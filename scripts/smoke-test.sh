#!/usr/bin/env bash
# 冒烟：验证 4 服务 RUNNING + 3 上游健康 + new-api 渠道写入 + 出口 /v1/models
set -uo pipefail
AGG="${AGG_PORT:-8080}"
echo "== docker ps =="
docker ps --filter name=ai-relay-hub --format '{{.Status}}'
echo
echo "== supervisord =="
docker exec ai-relay-hub supervisorctl status 2>&1 || true
echo
echo "== 上游探活 =="
for p in "wb:8788/health" "qoder:3000/health" "oc:13339/healthz" "agg:${AGG}/api/status"; do
  name="${p%%:*}"; rest="${p#*:}"; port="${rest%%/*}"
  code=$(docker exec ai-relay-hub curl -s -o /dev/null -m 5 -w '%{http_code}' "http://127.0.0.1:${rest}" 2>/dev/null || echo 000)
  printf '  %-8s :%s -> HTTP %s\n' "$name" "$port" "$code"
done
echo
echo "== new-api 渠道 =="
docker exec ai-relay-hub curl -s "http://127.0.0.1:${AGG}/api/channel/?p=0&page_size=50" 2>/dev/null | python3 -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps(d,ensure_ascii=False)[:800])' 2>/dev/null || echo "(需先登录，见 wirer 日志)"
echo
echo "== 出口模型数 =="
docker exec ai-relay-hub curl -s "http://127.0.0.1:${AGG}/v1/models" 2>/dev/null | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d.get("data",[])),"models")' 2>/dev/null || echo 0
