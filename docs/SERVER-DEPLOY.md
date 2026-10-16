# SERVER-DEPLOY —— 服务器部署手册（ServerX 口径）

> 目标机：腾讯云 SM（122.51.139.252 · 4C4G · Ubuntu 24.04 · x86_64）
> 宿主端口：**4001**（ServerX 预留「项目C」，已随 D027 转正）
> 部署模式：公开仓源码浅克隆 → 服务器本地 `docker build`（`docker-compose.pull.yml` 的 ghcr 预构建路径作为备选）

## 前置

1. 仓库已 push 到 `RayMorTwinkle/ai-relay-hub`（public）
2. `~/app-configs` 是 `RayMorTwinkle/ServerX` 的工作树，`git pull` 后 `ai-relay-hub/` 自动出现
3. 凭据：`敏感/ai-relay-hub.env` → `ai-relay-hub/.env`（cp + chmod 600）

## 一键部署 / 更新

```bash
cd ~/app-configs/ai-relay-hub && bash setup.sh
```

setup.sh 决策链：

```
docker pull ghcr.io/raymortwinkle/ai-relay-hub:latest
  ├─ 成功 → IMAGE=ghcr 预构建，直接 compose up
  └─ 失败 → git clone（SSH，SM 直连 GitHub HTTPS 会断）
            → docker build（GH_PROXY_PREFIX 走 gh-proxy 加速 GitHub 下载）
            → IMAGE=ai-relay-hub:local，compose up
```

## 首次验证

```bash
bash scripts/smoke-test.sh ai-relay-hub    # 4 服务 RUNNING + 3 上游健康 + :4001/v1/models
docker exec ai-relay-hub supervisorctl status
docker exec ai-relay-hub tail -30 /data/logs/wirer.log
```

期望出口聚合（前缀路由）：

| 前缀 | 来源 | 模型示例 |
|---|---|---|
| `wb/` | WorkBuddy 反代 | `wb/claude-sonnet-4-5` |
| `wb-intl/` + `wb-cn/` | wb 双区域（可选） | 同目录两前缀 |
| `qoder/` | Qoder CN 反代 | `qoder/...` |
| `oc/` | OpenCode free-gate | `oc/gpt-4o` 等 |

## 凭据要填什么

| env | 必填 | 说明 |
|---|---|---|
| `QODERCN_PERSONAL_ACCESS_TOKEN` | 是 | qoder CN PAT（唯一必填上游凭据） |
| `AGG_ADMIN_PASS` | 建议改 | new-api 面板密码（默认 `123456`） |
| `WB_API_KEY` | 留空自动生成 | wb 网关自身鉴权 key（面板可加真实 OAuth 账号） |
| `WB_API_KEY_INTL`/`WB_API_KEY_CN` | 可选 | 双区域拆分前缀 |
| `SYSTEM_ACCESS_TOKEN` | 可选 | 绕过 cookie 的 wirer 鉴权（面板建 PAT） |

## 网络注意

- SM 直连 `https://github.com` HTTPS 会断 → 克隆走 SSH（`git@github.com:...`）
- `ghcr.io` 可通 → 镜像优先 pull；不可用时 `GH_PROXY_PREFIX=https://gh-proxy.com/` 已在 `.env` 默认开启
- docker.io 被墙，但本项目 base image 全在 ghcr，无依赖

## 运维入口

| 位置 | 用途 |
|---|---|
| `http://<host>:4001` | new-api 面板 + 统一 API 出口 |
| `http://127.0.0.1:8788` | wb 看板（仅绑回环，ssh -L 或容器内 curl） |
| `~/app-configs/ai-relay-hub/data/` | SQLite + 账号目录 + 日志（备份 = tar 打包） |
| `docker exec ai-relay-hub supervisorctl status` | 4 服务编排状态 |
| `docker exec ai-relay-hub tail -f /data/logs/wirer.log` | 渠道接线日志 |

## 重建 / 迁移

```bash
tar -czf /root/backups/airelay-$(date +%F).tar.gz -C ~/app-configs/ai-relay-hub data/
# 迁移：data/ 整体复制即可（SQLite + wb 账号 + 用量）
```
