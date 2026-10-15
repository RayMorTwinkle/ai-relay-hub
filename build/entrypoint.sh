#!/usr/bin/env bash
# ============================================================================
# ai-relay-hub entrypoint（幂等，可反复重启/重建容器）
# 职责：补齐缺省密钥与环境 → 交棒 supervisord 拉活 4 服务 + wirer
# ============================================================================
set -euo pipefail

export TZ="${TZ:-Asia/Shanghai}"
mkdir -p /data/logs

# 生成一个高熵密钥（仅当未显式注入时）；复用同一张表便于排障
gen_key() { python3 -c 'import secrets;print("sk-"+secrets.token_hex(20))'; }

# ---- 默认值（用户 -e 注入覆盖这些）----
export WB_PORT="${WB_PORT:-8788}"
export QODER_PORT="${QODER_PORT:-3000}"
export OC_PORT="${OC_PORT:-13339}"
export AGG_PORT="${AGG_PORT:-8080}"

# 三个上游/聚合层各自的内网密钥（对话只发生在容器回环内）
export WB_API_KEY="${WB_API_KEY:-$(gen_key)}"
export QODER_API_KEY="${QODER_API_KEY:-$(gen_key)}"
export SESSION_SECRET="${SESSION_SECRET:-$(python3 -c 'import secrets;print(secrets.token_hex(32))')}"

# qoder：仅 CN 后端，PAT 由环境变量注入（容器内无交互登录）
export QODERCN_PAT="${QODERCN_PERSONAL_ACCESS_TOKEN:-${QODERCN_PAT:-}}"
# oc-gate：默认公共代理池回退链
export OC_PROXY_MODE="${OC_PROXY_MODE:-auto}"

# new-api 初始管理员（首启创建；若上游改了默认口令，wirer 会在日志报 401）
export AGG_ADMIN_USER="${AGG_ADMIN_USER:-root}"
export AGG_ADMIN_PASS="${AGG_ADMIN_PASS:-123456}"

cat <<EOF
============================================================
 ai-relay-hub 启动中
  唯一出口      : http://127.0.0.1:${AGG_PORT}/v1
  wb 看板(加账号): http://127.0.0.1:${WB_PORT}
  数据目录      : /data
  密钥(未注入时自动生成)：
    WB_API_KEY=${WB_API_KEY}
    QODER_API_KEY=${QODER_API_KEY}
============================================================
EOF

exec /usr/bin/supervisord -n -c /etc/supervisord.conf
