#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
wirer.py — ai-relay-hub 常驻接线器

职责：把三个反代上游聚合成 new-api 单一出口。
每轮循环（默认 30s）：
  1. 探活：三个上游 /health 与 new-api /api/status
  2. 拉取各上游 /v1/models（拿不到就当空集，不阻塞）
  3. 按「来源前缀」生成渠道模型表 + model_mapping（wb/、qoder/、oc/；
     wb 可再细分 wb-intl/、wb-cn/：见 WB_API_KEY_INTL / WB_API_KEY_CN）
  4. diff 后创建/更新 new-api 渠道（渠道幂等：同名复用，内容不同才 PUT）

纯标准库实现（urllib），不引入 pip 依赖——镜像内不需要额外装 requests。
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
import http.cookiejar

# ---------- 环境 ----------
WB_BASE      = os.environ.get("WB_BASE", "http://127.0.0.1:8788")
QODER_BASE   = os.environ.get("QODER_BASE", "http://127.0.0.1:3000")
OC_BASE      = os.environ.get("OC_BASE", "http://127.0.0.1:13339")
AGG_BASE     = os.environ.get("AGG_BASE", "http://127.0.0.1:8080")

WB_API_KEY   = os.environ.get("WB_API_KEY", "")
QODER_APIKEY = os.environ.get("QODER_API_KEY", "")
# 可选：双区域拆分（wb 面板里给两个 Key 分别绑国际版/国内版）
WB_KEY_INTL  = os.environ.get("WB_API_KEY_INTL", "")
WB_KEY_CN    = os.environ.get("WB_API_KEY_CN", "")

ADMIN_USER   = os.environ.get("AGG_ADMIN_USER", "root")
ADMIN_PASS   = os.environ.get("AGG_ADMIN_PASS", "123456")
SYS_TOKEN    = os.environ.get("SYSTEM_ACCESS_TOKEN", "")

INTERVAL     = int(os.environ.get("WIRER_INTERVAL", "30"))
BOOT_WAIT    = int(os.environ.get("WIRER_BOOT_WAIT", "5"))

LOG = sys.stdout


def log(msg):
    print(f"[wirer {time.strftime('%H:%M:%S')}] {msg}", file=LOG, flush=True)


# ---------- HTTP 工具（urllib，零依赖）----------
def http_json(url, method="GET", data=None, headers=None, timeout=8, cookie_jar=None):
    hdrs = {"Content-Type": "application/json"}
    if headers:
        hdrs.update(headers)
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    if cookie_jar is not None:
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
        resp = opener.open(req, timeout=timeout)
    else:
        resp = urllib.request.urlopen(req, timeout=timeout)
    raw = resp.read().decode("utf-8", "replace")
    try:
        return json.loads(raw)
    except Exception:
        return {"_raw": raw}


def health_ok(url):
    try:
        urllib.request.urlopen(url, timeout=5)
        return True
    except urllib.error.HTTPError as e:
        return 200 <= e.code < 500
    except Exception:
        return False


def fetch_models(base, path, key=""):
    """GET <base><path> -> [model_id,...]，任何失败返回 []。"""
    headers = {}
    if key:
        headers["Authorization"] = f"Bearer {key}"
    try:
        r = http_json(base + path, headers=headers)
        data = r.get("data") or r.get("models") or []
        out = []
        for m in data:
            if isinstance(m, str):
                out.append(m)
            elif isinstance(m, dict) and m.get("id"):
                out.append(m["id"])
        return sorted(set(out))
    except Exception as e:
        log(f"warn: fetch models {base}{path} -> {e}")
        return []


# ---------- new-api 管理客户端 ----------
class NewAPI:
    def __init__(self):
        self.base = AGG_BASE
        self.jar = http.cookiejar.CookieJar()
        self.user_id = "1"
        self.sys_token = SYS_TOKEN

    def _headers(self):
        if self.sys_token:
            return {"Authorization": f"Bearer {self.sys_token}", "New-Api-User": self.user_id}
        return {"New-Api-User": self.user_id}

    def setup(self):
        """new-api 未初始化时走 /api/setup 建 root（无鉴权，官方入口）。"""
        try:
            r = http_json(f"{self.base}/api/setup", method="POST",
                          data={"username": ADMIN_USER, "password": ADMIN_PASS,
                                "confirmPassword": ADMIN_PASS},
                          cookie_jar=self.jar)
            if r.get("success"):
                log("new-api 已初始化 root")
                return True
            log(f"warn: setup failed: {r.get('message') or r}")
            return False
        except Exception as e:
            log(f"warn: setup exception: {e}")
            return False

    def login(self):
        if self.sys_token:
            return True
        try:
            r = http_json(f"{self.base}/api/user/login",
                          method="POST",
                          data={"username": ADMIN_USER, "password": ADMIN_PASS},
                          cookie_jar=self.jar)
            if r.get("success"):
                uid = (r.get("data") or {}).get("id")
                if uid:
                    self.user_id = str(uid)
                return True
            msg = str(r.get("message") or r)
            log(f"warn: new-api login failed: {msg}")
            # 未初始化 / root 不存在 → 尝试自动 setup 后再登录一次
            if "initialized" in msg or "not exist" in msg or "incorrect" in msg:
                if self.setup():
                    r2 = http_json(f"{self.base}/api/user/login",
                                   method="POST",
                                   data={"username": ADMIN_USER, "password": ADMIN_PASS},
                                   cookie_jar=self.jar)
                    if r2.get("success"):
                        uid = (r2.get("data") or {}).get("id")
                        if uid:
                            self.user_id = str(uid)
                        return True
            return False
        except Exception as e:
            log(f"warn: new-api login exception: {e}")
            return False

    def channels(self):
        try:
            r = http_json(f"{self.base}/api/channel/?p=0&page_size=100",
                          headers=self._headers(), cookie_jar=self.jar)
            data = (r.get("data") or {})
            items = data.get("items") or data.get("data") or []
            return items if isinstance(items, list) else []
        except Exception as e:
            log(f"warn: list channels -> {e}")
            return []

    def create(self, ch):
        for payload in ({"mode": "single", "channel": ch}, ch):
            try:
                r = http_json(f"{self.base}/api/channel/", method="POST",
                              data=payload, headers=self._headers(), cookie_jar=self.jar)
                if r.get("success"):
                    return True
            except urllib.error.HTTPError as e:
                body = e.read().decode("utf-8", "replace")[:200]
                log(f"warn: create channel http {e.code}: {body}")
            except Exception as e:
                log(f"warn: create channel exception: {e}")
        return False

    def update(self, ch):
        for payload in ({"channel": ch}, ch):
            try:
                r = http_json(f"{self.base}/api/channel/", method="PUT",
                              data=payload, headers=self._headers(), cookie_jar=self.jar)
                if r.get("success"):
                    return True
            except Exception as e:
                log(f"warn: update channel exception: {e}")
        return False


def build_channel(name, base_url, key, upstream_models, prefix):
    """生成 new-api 渠道对象：公开模型名 = prefix + 原名；上游收到原名。"""
    public = [f"{prefix}{m}" for m in upstream_models]
    mapping = {f"{prefix}{m}": m for m in upstream_models}
    return {
        "name": name,
        "type": 1,                      # OpenAI 兼容渠道
        "base_url": base_url,
        "key": key or "sk-placeholder",
        "models": ",".join(public),
        "model_mapping": json.dumps(mapping, ensure_ascii=False),
        "group": "default",             # new-api 是逗号分隔字符串，不是数组
        "priority": 0,
        "weight": 1,
        "status": 1,
    }


def desired_channels():
    """从当前上游模型表计算期望渠道集合。"""
    chans = []

    wb_models = fetch_models(WB_BASE, "/v1/models", WB_API_KEY)
    if WB_KEY_INTL or WB_KEY_CN:
        # 双 Key 双区域：目录交集不可分，按同一目录分两个前缀暴露，
        # 由 wb 面板里各 Key 绑定的出口决定实际落点。
        if WB_KEY_INTL:
            chans.append(build_channel("wb-intl", WB_BASE, WB_KEY_INTL, wb_models, "wb-intl/"))
        if WB_KEY_CN:
            chans.append(build_channel("wb-cn", WB_BASE, WB_KEY_CN, wb_models, "wb-cn/"))
    elif wb_models:
        chans.append(build_channel("wb", WB_BASE, WB_API_KEY, wb_models, "wb/"))

    qoder_models = fetch_models(QODER_BASE, "/v1/models", QODER_APIKEY)
    if qoder_models:
        chans.append(build_channel("qoder", QODER_BASE, QODER_APIKEY, qoder_models, "qoder/"))

    oc_models = fetch_models(OC_BASE, "/openai/v1/models", "")
    if oc_models:
        chans.append(build_channel("oc", OC_BASE + "/openai", "", oc_models, "oc/"))

    return chans


def main():
    log("wirer 启动：等待上游与聚合层就绪")
    time.sleep(BOOT_WAIT)

    agg = NewAPI()
    logged_in = False
    applied = {}

    # 先等 new-api 就绪（最多 120s）
    for _ in range(120):
        if health_ok(f"{AGG_BASE}/api/status") or health_ok(f"{AGG_BASE}/"):
            break
        time.sleep(1)
    log("new-api 就绪")

    while True:
        upstreams_up = {
            "wb": health_ok(f"{WB_BASE}/health") or health_ok(f"{WB_BASE}/"),
            "qoder": health_ok(f"{QODER_BASE}/health"),
            "oc": health_ok(f"{OC_BASE}/healthz"),
        }
        log(f"上游状态: {upstreams_up}")

        if not logged_in:
            logged_in = agg.login()
            if not logged_in:
                log("尚未登录 new-api（可能首次初始化中），下轮重试")
                time.sleep(INTERVAL)
                continue

        existing = {c.get("name"): c for c in agg.channels()}

        for ch in desired_channels():
            name = ch["name"]
            cur = existing.get(name)
            sig = json.dumps({k: ch[k] for k in ("base_url", "models", "model_mapping")}, sort_keys=True)
            if cur and applied.get(name) == sig:
                continue
            if cur is None:
                if agg.create(ch):
                    log(f"渠道已创建: {name}（{ch['models'].count(',')+1} 个模型）")
                    applied[name] = sig
            else:
                ch["id"] = cur.get("id")
                if applied.get(name) != sig and agg.update(ch):
                    log(f"渠道已更新: {name}")
                    applied[name] = sig

        time.sleep(INTERVAL)


if __name__ == "__main__":
    main()
