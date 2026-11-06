#!/bin/bash
# 等待 GitHub API 恢复可达，恢复后立刻检查/重跑构建。
set -uo pipefail
TOKEN="$GITHUB_TOKEN"
REPO="17xtreme77/netpilot"
API="https://api.github.com"

net_ok() {
    curl -sS --max-time 12 -o /dev/null -w "%{http_code}" "$API/rate_limit" 2>/dev/null | grep -q 200
}

echo "[$(date +%H:%M:%S)] 开始等待 GitHub 可达…"
for i in $(seq 1 120); do
    if net_ok; then
        echo "[$(date +%H:%M:%S)] 网络已恢复"
        break
    fi
    [ $((i % 6)) -eq 0 ] && echo "[$(date +%H:%M:%S)] 仍不可达（第 ${i} 次）"
    sleep 15
    if [ "$i" -eq 120 ]; then echo "NETWORK-TIMEOUT"; exit 2; fi
done

echo "[$(date +%H:%M:%S)] 查询最新运行…"
RUN=$(curl -sS --max-time 30 -H "Authorization: Bearer $TOKEN" "$API/repos/$REPO/actions/runs?per_page=1")
python3 - "$RUN" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
r = d["workflow_runs"][0]
print(f"#{r['run_number']} {r['status']} {r['conclusion']}")
PY
echo "NETWORK-OK"
