#!/usr/bin/env bash
# 一键启动：复制 .env → build → up → 等健康 → 打印接入说明
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f .env ] || { cp .env.example .env; echo "已生成 .env（按需编辑后重跑）"; }
export GH_PROXY_PREFIX="${GH_PROXY_PREFIX:-}"

docker compose up -d --build
echo "等待聚合层健康…"
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${AGG_PORT:-8080}/api/status" 2>/dev/null || true)
  [ "${code}" != "000" ] && break
  sleep 2
done
echo "=================================================="
echo "  出口   : http://127.0.0.1:${AGG_PORT:-8080}/v1"
echo "  面板   : http://127.0.0.1:${AGG_PORT:-8080}  (root / 123456)"
echo "  wb看板 : http://127.0.0.1:${WB_PORT:-8788}"
echo "=================================================="
