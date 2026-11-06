#!/bin/bash
#
# 一键：建私有仓库 → 推代码 → 等 CI 编译 → 下载 IPA
#
# 用法：
#   GITHUB_TOKEN=ghp_xxx ./Tools/ci-build.sh
#
# 令牌要求：classic PAT，只勾 repo 权限即可。
# 脚本不会把令牌写进 .git/config，也不会打印到日志。
#
set -euo pipefail

cd "$(dirname "$0")/.."

TOKEN="${GITHUB_TOKEN:-}"
REPO_NAME="${REPO_NAME:-netpilot}"
API="https://api.github.com"

if [ -z "$TOKEN" ]; then
  echo "缺少 GITHUB_TOKEN 环境变量"
  echo "用法：GITHUB_TOKEN=ghp_xxx $0"
  exit 1
fi

api() {
  local method="$1"; shift
  local path="$1"; shift
  curl -sS -X "$method" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$API$path" "$@"
}

echo "==> 1/6 校验令牌"
USER_JSON="$(api GET /user)"
ACCOUNT="$(printf '%s' "$USER_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("login",""))')"
if [ -z "$ACCOUNT" ]; then
  echo "令牌无效：$(printf '%s' "$USER_JSON" | head -c 300)"
  exit 1
fi
echo "    账号：$ACCOUNT"

echo "==> 2/6 创建私有仓库 $ACCOUNT/$REPO_NAME"
api POST /user/repos -d "{\"name\":\"$REPO_NAME\",\"private\":true,\"description\":\"iOS 网络助手：流量统计 / 热点管控 / 代理\"}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print("    仓库地址：", d.get("html_url") or d.get("message","已存在"))'

echo "==> 3/6 推送代码"
git remote remove origin 2>/dev/null || true
git push -q "https://x-access-token:$TOKEN@github.com/$ACCOUNT/$REPO_NAME.git" HEAD:main --force
echo "    推送完成"

echo "==> 4/6 等待 CI 启动"
RUN_ID=""
for i in $(seq 1 20); do
  sleep 6
  RUN_ID="$(api GET "/repos/$ACCOUNT/$REPO_NAME/actions/runs?per_page=1" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
runs=d.get("workflow_runs",[])
print(runs[0]["id"] if runs else "")')"
  [ -n "$RUN_ID" ] && break
done

if [ -z "$RUN_ID" ]; then
  echo "    等不到 CI 运行，去 Actions 页面看看："
  echo "    https://github.com/$ACCOUNT/$REPO_NAME/actions"
  exit 1
fi
echo "    Run ID: $RUN_ID"
echo "    页面：https://github.com/$ACCOUNT/$REPO_NAME/actions/runs/$RUN_ID"

echo "==> 5/6 等待编译（最长 20 分钟）"
CONCLUSION=""
for i in $(seq 1 120); do
  sleep 10
  STATUS_JSON="$(api GET "/repos/$ACCOUNT/$REPO_NAME/actions/runs/$RUN_ID")"
  READ_STATE="$(printf '%s' "$STATUS_JSON" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("status",""), d.get("conclusion","") or "-")')"
  STATUS_V="${READ_STATE% *}"
  CONCLUSION="${READ_STATE#* }"
  printf "\r    状态：%s %s   " "$STATUS_V" "$CONCLUSION"
  if [ "$STATUS_V" = "completed" ]; then
    echo
    break
  fi
done

if [ "$CONCLUSION" != "success" ]; then
  echo
  echo "    编译失败，结论：$CONCLUSION"
  echo "    查看日志：https://github.com/$ACCOUNT/$REPO_NAME/actions/runs/$RUN_ID"
  exit 1
fi

echo "==> 6/6 下载 IPA"
ARTIFACT_ID="$(api GET "/repos/$ACCOUNT/$REPO_NAME/actions/runs/$RUN_ID/artifacts" \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
arts=d.get("artifacts",[])
print(arts[0]["id"] if arts else "")')"

if [ -z "$ARTIFACT_ID" ]; then
  echo "    没找到产物"
  exit 1
fi

mkdir -p dist
curl -sSL -H "Authorization: Bearer $TOKEN" \
  -o dist/artifact.zip \
  "$API/repos/$ACCOUNT/$REPO_NAME/actions/artifacts/$ARTIFACT_ID/zip"

cd dist
unzip -oq artifact.zip
rm -f artifact.zip
IPA="$(find . -name '*.ipa' -maxdepth 2 | head -1)"
if [ -z "$IPA" ]; then
  echo "压缩包里没有 ipa"
  ls -la
  exit 1
fi
mv "$IPA" ./NetPilot.ipa
echo ""
echo "完成：$(cd .. && pwd)/dist/NetPilot.ipa  ($(du -h NetPilot.ipa | cut -f1))"
echo "传到手机，用 TrollStore 安装。"
