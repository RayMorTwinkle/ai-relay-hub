#!/usr/bin/env bash
# 冒烟：验证 4 服务 RUNNING + 3 上游健康 + 出口 /v1/models
# 用法：bash scripts/smoke-test.sh [容器名]
set -uo pipefail
C="${1:-ai-relay-hub}"
AGG="${AGG_PORT:-8080}"

echo "== docker ps =="
docker ps --filter "name=$C" --format '{{.Names}} {{.Status}}'
echo
echo "== supervisord =="
docker exec "$C" supervisorctl status 2>&1 || true
echo
echo "== 上游探活（容器内回环）=="
for p in "wb:8788/health" "qoder:3000/health" "oc:13339/healthz" "agg:${AGG}/api/status"; do
  name="${p%%:*}"; rest="${p#*:}"
  code=$(docker exec "$C" curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${rest}" 2>/dev/null || echo 000)
  printf '  %-8s %s -> HTTP %s\n' "$name" "$rest" "$code"
done
echo
echo "== 出口 /v1/models =="
docker exec "$C" curl -s -m 10 "http://127.0.0.1:${AGG}/v1/models" 2>/dev/null | head -c 400
echo
echo "== wirer 日志尾部 =="
docker exec "$C" tail -15 /data/logs/wirer.log 2>/dev/null || echo "(no wirer log)"
