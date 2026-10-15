# 接入账号（三个反代分别怎么配）

聚合层 new-api 不接触任何上游账号——账号只在三个反代项目里维护，wirer 自动把它们的模型接进来。

## 1. wb-proxy（WorkBuddy 国际/国内）

打开面板（默认 `http://127.0.0.1:8788`，compose 已绑回环）：

1. 点「+ 添加账号 (OAuth)」
2. 选区域（国际版 www.workbuddy.ai / 国内版 codebuddy.cn）
3. 浏览器完成官方授权，账号自动入池

可选进阶：在 wb「设置」里给两个 Key 分别绑定国际版/国内版，把这两个 Key 填到 `.env` 的 `WB_API_KEY_INTL` / `WB_API_KEY_CN`，wirer 会拆出 `wb-intl/` 和 `wb-cn/` 两个独立渠道。

## 2. qoder-proxy（Qoder，仅 CN 后端）

> ⚠️ 容器内**只支持 CN**。Global 后端的 `qodercli login` 是交互式浏览器 OAuth，容器里做不了。

1. 到 https://qoder.com.cn/account/integrations 创建 Personal Access Token
2. `.env` 填 `QODERCN_PERSONAL_ACCESS_TOKEN=...`
3. `docker compose up -d --build`（或重启容器）

## 3. oc-gate（OpenCode 免费模型）

无需账号，直接走公共代理池/ZenProxy。如已有自有代理：`CUSTOM_PROXIES=...` / `ZENPROXY_KEY=...` 填进 `.env`。

## 4. new-api 面板（聚合层管理）

`http://<host>:8080`，默认 `root`/`123456`（**登录后立即改密码**）。渠道由 wirer 自动写入，你只需管令牌/分组/额度。
