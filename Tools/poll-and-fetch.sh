#!/bin/bash
# 轮询 CI 运行直到结束，成功则下载 IPA，失败则下载日志。
# 用法：GITHUB_TOKEN=xxx ./Tools/poll-and-fetch.sh [最多轮询次数]
set -uo pipefail

REPO="17xtreme77/netpilot"
MAX="${1:-80}"
API="https://api.github.com/repos/$REPO"
DIST="$(cd "$(dirname "$0")/.." && pwd)/dist"
mkdir -p "$DIST"

api() { curl -sS --retry 4 --retry-delay 3 --max-time 40 -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

for i in $(seq 1 "$MAX"); do
    RUN_JSON=$(api "$API/actions/runs?per_page=1") || { sleep 20; continue; }
    STATUS=$(echo "$RUN_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['status'])" 2>/dev/null) || { sleep 20; continue; }
    RUN_ID=$(echo "$RUN_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['id'])" 2>/dev/null)
    RUN_NO=$(echo "$RUN_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['run_number'])" 2>/dev/null)

    echo "[$(date +%H:%M:%S)] 第 $i 次轮询：run #$RUN_NO status=$STATUS"

    if [ "$STATUS" = "completed" ]; then
        CONCLUSION=$(echo "$RUN_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['workflow_runs'][0]['conclusion'])")
        echo "=== 构建结束：$CONCLUSION ==="

        if [ "$CONCLUSION" = "success" ]; then
            ART=$(api "$API/actions/runs/$RUN_ID/artifacts")
            AID=$(echo "$ART" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for a in d.get('artifacts',[]):
    if a['name']=='NetPilot-ipa': print(a['id']); break
")
            if [ -z "$AID" ]; then echo "未找到 IPA 产物"; exit 1; fi
            echo "下载产物 artifact $AID"
            curl -sS -L --retry 4 --max-time 300 -H "Authorization: Bearer $GITHUB_TOKEN" \
                 -o "$DIST/ipa.zip" "$API/actions/artifacts/$AID/zip"
            ls -lh "$DIST/ipa.zip"
            rm -rf "$DIST/extract" && mkdir -p "$DIST/extract"
            unzip -o -q "$DIST/ipa.zip" -d "$DIST/extract" && find "$DIST/extract" -name "*.ipa" -exec cp {} "$DIST/" \;
            ls -lh "$DIST"/*.ipa 2>/dev/null && echo "IPA-READY"
        else
            echo "下载失败日志"
            curl -sS -L --retry 3 --max-time 120 -H "Authorization: Bearer $GITHUB_TOKEN" \
                 -o "$DIST/logs.zip" "$API/actions/runs/$RUN_ID/logs"
            rm -rf "$DIST/logs" && mkdir -p "$DIST/logs"
            unzip -o -q "$DIST/logs.zip" -d "$DIST/logs" 2>/dev/null
            find "$DIST/logs" -type f | head -20
            echo "LOG-READY"
        fi
        exit 0
    fi
    sleep 25
done
echo "轮询超时，任务仍在排队或运行"
