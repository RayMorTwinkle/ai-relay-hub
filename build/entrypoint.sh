#!/usr/bin/env bash
# ============================================================================
# ai-relay-hub entrypoint（幂等，可反复重启/重建容器）
# 职责：补齐缺省密钥与环境 → 交棒 supervisord 拉活 4 服务 + wirer
# ============================================================================
set -euo pipefail

export TZ="${TZ:-Asia/Shanghai}"
mkdir -p /data/logs /data/accounts /data/usage

# 生成一个高熵密钥（仅当未显式注入时）
gen_key() { python3 -c 'import secrets;print("sk-"+secrets.token_hex(20))'; }

# ---- 端口 ----
export WB_PORT="${WB_PORT:-8788}"
export QODER_PORT="${QODER_PORT:-3000}"
export OC_PORT="${OC_PORT:-13339}"
export AGG_PORT="${AGG_PORT:-8080}"

# ---- 上游/聚合层各自的内网密钥（只发生在容器回环内）----
export WB_API_KEY="${WB_API_KEY:-$(gen_key)}"
export QODER_API_KEY="${QODER_API_KEY:-$(gen_key)}"
export SESSION_SECRET="${SESSION_SECRET:-$(python3 -c 'import secrets;print(secrets.token_hex(32))')}"

# ---- wb 可选双区域拆分（在 wb 面板给两个 Key 分别绑国际版/国内版后填这两个）----
export WB_API_KEY_INTL="${WB_API_KEY_INTL:-}"
export WB_API_KEY_CN="${WB_API_KEY_CN:-}"

# ---- qoder：仅 CN 后端，PAT 由环境变量注入 ----
export QODERCN_PAT="${QODERCN_PERSONAL_ACCESS_TOKEN:-${QODERCN_PAT:-}}"

# ---- oc-gate ----
export OC_PROXY_MODE="${OC_PROXY_MODE:-auto}"

# ---- new-api 管理员（首启创建；若上游改了默认口令，wirer 会报 401 并提示）----
export AGG_ADMIN_USER="${AGG_ADMIN_USER:-root}"
export AGG_ADMIN_PASS="${AGG_ADMIN_PASS:-Relay@4001}"
export SYSTEM_ACCESS_TOKEN="${SYSTEM_ACCESS_TOKEN:-}"

# ---- wirer ----
export WIRER_INTERVAL="${WIRER_INTERVAL:-30}"
export WIRER_BOOT_WAIT="${WIRER_BOOT_WAIT:-5}"

cat <<EOF
============================================================
 ai-relay-hub 启动中
  唯一出口      : http://127.0.0.1:${AGG_PORT}/v1
  new-api 面板  : http://<host>:${AGG_PORT}   (root / 123456 — 立即改)
  wb 看板(加账号): http://<host>:${WB_PORT}
  数据目录      : /data
============================================================
EOF

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
