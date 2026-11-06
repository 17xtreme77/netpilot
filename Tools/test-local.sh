#!/bin/bash
#
# 在本机（macOS）编译并运行纯逻辑测试。
# 不含 UIKit / NetworkExtension 依赖，所以能在没有 iOS SDK 的环境下验证算法。
#
set -euo pipefail

cd "$(dirname "$0")/.."

OUT="$PWD/build/local-tests"
mkdir -p "$OUT"

echo "编译纯逻辑模块 ..."
swiftc -swift-version 5 -Onone -g \
  -o "$OUT/logic-tests" \
  Sources/Core/InterfaceReader.swift \
  Sources/Core/UsageStore.swift \
  Sources/Core/HotspotClients.swift \
  Sources/Core/Shell.swift \
  Sources/Core/ClientBlocker.swift \
  Tools/LocalTests/main.swift \
  2>&1 | sed 's/^/  /'

echo ""
"$OUT/logic-tests"
