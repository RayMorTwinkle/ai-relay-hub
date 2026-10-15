# 排障

## 容器起不来 / 某服务反复重启

```bash
docker exec ai-relay-hub supervisorctl status        # 谁在 crash-loop
docker exec ai-relay-hub tail -100 /data/logs/<服务>.log
```

- `wb-proxy`：看 `/data/logs/wb-proxy.log`，多半是 accounts/usage 卷权限（默认 root 运行 OK；自定义 PUID 要配 PUID/PGID）。
- `qoder-proxy`：没填 `QODERCN_PERSONAL_ACCESS_TOKEN` 时它照常起，但 `/v1/models` 会空 → wirer 跳过渠道创建，属正常。
- `oc-gate`：出口依赖公共代理池，没网/被墙时 429/超时；配 `CUSTOM_PROXIES` 或 `ZENPROXY_KEY` 改善。

## 出口 /v1/models 空

wirer 每 30s 重拉一次。先确认：
1. `supervisorctl status` 里 new-api 是 RUNNING；
2. `docker exec ai-relay-hub tail -50 /data/logs/wirer.log` 看最后是不是“渠道已创建”；
3. 上游 `/v1/models` 在各自日志里是不是 401（没配 key）/空目录（上游没账号）。

## qoder /v1/models 空

最常见：没填 `QODERCN_PERSONAL_ACCESS_TOKEN`。`.env` 填上后 `docker compose up -d` 重启即可。

## new-api 登录不进 / wirer 401

默认凭据 `root`/`123456`。若上游改了默认口令，改 `.env` 的 `AGG_ADMIN_PASS`；或改走 `SYSTEM_ACCESS_TOKEN`（new-api 面板生成后填进 `.env`）。

## GitHub 拉不动

构建期 GitHub 直连受限时：

```bash
export GH_PROXY_PREFIX=https://gh-proxy.com/
docker compose up -d --build
```

## 想对外暴露 wb 面板（远程加账号）

compose 默认把 `8788` 绑到 `127.0.0.1`。改成 `"8788:8788"` 再 `docker compose up -d`。**注意 wb 面板密码默认 admin，公网暴露前先改密。**
