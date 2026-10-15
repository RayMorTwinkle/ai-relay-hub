# 架构

## 组件与端口

| 组件 | 镜像/来源 | 监听 | 对外 |
|------|-----------|------|------|
| wb-proxy | ghcr.io/ardeyouxipianyi/workbuddy2api-hub | 0.0.0.0:8788 | 面板（compose 绑回环） |
| qoder-proxy | 源码+npm（无官方镜像） | 127.0.0.1:3000 | 仅容器内 |
| oc-gate | ghcr.io/guji08233/opencode-free-gate → `/app/gate` | 0.0.0.0:13339 | 仅容器内 |
| new-api | GitHub Release 二进制 | 0.0.0.0:8080 | 唯一出口 :8080 |
| wirer | 本仓 Python | — | — |

## 进程编排

`supervisord` 管 5 个 program：3 上游 `priority=10 autorestart=true` → new-api `priority=20` → wirer `priority=30 autorestart=false`。PID 1 用 `tini` 做信号回收。

## 接线（wirer）

常驻循环：

1. 探活 `wb /health`、`qoder /health`、`oc /healthz`、`new-api /api/status`
2. 拉各上游 `/v1/models`（拿不到 = 空集，不阻塞）
3. 按来源前缀生成渠道（`wb/`、`wb-intl/`、`wb-cn/`、`qoder/`、`oc/`），`model_mapping` 把公开名映射回原名
4. 与已有渠道 diff，增量创建/更新 new-api channel（`POST/PUT /api/channel/`）

new-api 鉴权优先 `SYSTEM_ACCESS_TOKEN`；否则用 `AGG_ADMIN_USER/PASS`（默认 `root`/`123456`）登录取 session cookie + `New-Api-User` 头。

## 持久化

`/data` 一个卷收全部：wb `accounts/`+`usage/`、new-api SQLite、qoder `usage.json`、各进程日志 `logs/`。升级重建容器不丢账号。

## 已知取舍

- **qoder 仅 CN**：`qodercli login`（Global OAuth）需要交互浏览器，容器内做不了；CN 走 PAT env。
- **同名模型默认分前缀**，不是合并轮询——需要 wb 国际/国内合并时把 `wb-intl/`、`wb-cn/` 两个 Key 填上即可自动拆渠道。
- **wb 面板只绑回环**：要远程加账号，把 compose 里 `127.0.0.1:8788` 改成 `8788`。
- **new-api AGPL**：自用/团队内部署 OK；公开分发镜像需注意合规义务（见 README 合规说明）。
