# ai-relay-hub

**三个反代项目 + 一个聚合平台，打包进同一个 Docker 镜像，一键部署，统一成一个 API 出口。**

```
                         ┌───────────────── 一个容器 ──────────────────┐
                         │                                            │
  客户端 ──:8080────────▶  │   new-api（聚合层 / 唯一出口）               │
                         │   /v1/chat/completions · /v1/messages ·     │
                         │   /v1/responses · /v1/models               │
                         └───────┬──────────┬──────────┬───────────────┘
                                 │ 127.0.0.1│          │
                       ┌─────────┴───┐ ┌────┴─────┐ ┌───┴──────────┐
                       │ wb-proxy    │ │ qoder    │ │ oc-gate      │
                       │ :8788 /v1   │ │ :3000 /v1│ │ :13339       │
                       │ (WorkBuddy) │ │ (Qoder)  │ │ /openai/v1   │
                       └─────────────┘ └──────────┘ └──────────────┘
   由 supervisord 编排；wirer 常驻把三个上游模型自动写成 new-api 渠道
```

## 三个反代 + 一个聚合层

| 上游 | 来源 | 端口 | 账号方式 | 协议 |
|------|------|------|----------|------|
| **wb-proxy** | [ardeyouxipianyi/workbuddy2api-hub](https://github.com/ardeyouxipianyi/workbuddy2api-hub) | :8788 | 面板 OAuth / 桌面客户端导入 | OpenAI `/v1` + Anthropic + Responses |
| **qoder-proxy** | [avaritiachaos/qoder-proxy](https://github.com/avaritiachaos/qoder-proxy) | :3000 | **仅 CN 后端**，`QODERCN_PERSONAL_ACCESS_TOKEN` | OpenAI `/v1` + Anthropic `/v1/messages` |
| **oc-gate** | [GuJi08233/opencode-free-gate](https://github.com/GuJi08233/opencode-free-gate) | :13339 | 免账号，公共代理池 | `/openai/v1` + `/anthropic` + `/codex` |
| **new-api** | [QuantumNous/new-api](https://github.com/QuantumNous/new-api) | :8080 | 管理员/令牌 | 聚合层唯一出口 |

## 一键部署

```bash
cp .env.example .env          # 按需填 qoder PAT / 自定义密钥
docker compose up -d --build
```

启动完成后：

- **统一出口**：`http://<host>:8080/v1`（OpenAI 兼容；Anthropic 用 `:8080` + `/v1/messages`；Codex 用 `:8080` + `/v1/responses`）
- **new-api 面板**：`http://<host>:8080`（默认 `root` / `123456`，**立即改**）
- **wb 看板（加账号用）**：`http://<host>:8788`（compose 默认只绑 `127.0.0.1`，要远程加账号就改 compose 里的端口绑定）

## 给三个反代"加账号"

你只用在各自反代项目里配账号，wirer 会自动把它们接进 new-api：

| 上游 | 怎么加账号 |
|------|-----------|
| wb-proxy | 打开 `:8788` 看板 → 「+ 添加账号 (OAuth)」选国际版/国内版 |
| qoder-proxy | `.env` 填 `QODERCN_PERSONAL_ACCESS_TOKEN`（容器内**只支持 CN**） |
| oc-gate | 无需账号，开箱即用 |

## 模型命名（按来源前缀）

为避免同名模型（如 `deepseek-v4.1-flash` 在 wb 国际/国内、qoder 都存在）撞车，wirer 给每个渠道的公开模型名加来源前缀：

- `wb/deepseek-v4.1-flash`、`wb/hy3`（wb 单 Key 时）
- `wb-intl/…`、`wb-cn/…`（在 wb 面板给两个 Key 分别绑出口时）
- `qoder/deepseek-v4-pro`、`qoder/glm-5.3`
- `oc/grok-4-fast-free`、`oc/big-pickle`

上游收到的是**原名**（由 `model_mapping` 剥离前缀），所以在 new-api 面板里你看清模型来自哪个号池。

## 架构决策摘要

- **单镜像而非 compose**：qoder-proxy 强制 `127.0.0.1`，跨容器无法访问；同容器共享 loopback 反而成了天然要求。
- **`COPY --from` 拿上游成品**：不重编译 wb/oc，镜像小、上游升级只改 tag。
- **new-api 走 GitHub Release 二进制**（gh-proxy 可绕 Docker Hub）。
- **wirer 常驻节流**：后加账号不用重启，30s 内自动补登渠道。
- 更多细节见 `docs/`。

## 合规说明

- 本项目是**面向个人/团队自用**的部署模板，不内置任何账号、Token 或额度。
- 内嵌组件各自带自己的许可与限制：new-api（AGPL-3.0）、workbuddy2api-hub（MIT）、qoder-proxy（MIT，且明确**禁止公网部署/多人共享/转售**）、opencode-free-gate（见其 README）。
- 在容器内把 qoder-proxy 暴露给公网或做成中转站，可能违反其使用条款与对应平台的 ToS，有封号风险。请自行评估。
