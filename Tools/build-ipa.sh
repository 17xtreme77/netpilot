#!/bin/bash
#
# 一键出 TrollStore 可用的 IPA。
#
# 依赖：
#   brew install xcodegen ldid
#
# 原理：Xcode 完全跳过签名（CODE_SIGNING_ALLOWED=NO），
#       再用 ldid 把 entitlements 塞进 Mach-O，
#       TrollStore 安装时会原样保留这些权限。
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP_NAME="NetPilot"

echo "==> 1/6 生成 Xcode 工程"
command -v xcodegen >/dev/null || { echo "缺少 xcodegen：brew install xcodegen"; exit 1; }
xcodegen generate

echo "==> 2/6 编译（不签名）"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "找不到产物：$APP_PATH"; exit 1; }

echo "==> 3/6 拷贝 root helper 进 App 包"
HELPER_SRC="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/netpilot-helper"
if [ -f "$HELPER_SRC" ]; then
  cp "$HELPER_SRC" "$APP_PATH/netpilot-helper"
  chmod 755 "$APP_PATH/netpilot-helper"
  echo "    helper 已放入 $APP_PATH"
else
  echo "    ⚠️ 未找到 netpilot-helper，热点开关的 root 路径将不可用"
fi

echo "==> 4/6 ldid 签名"
command -v ldid >/dev/null || { echo "缺少 ldid：brew install ldid"; exit 1; }

sign() {
  local binary="$1"
  local entitlements="$2"
  if [ -f "$binary" ]; then
    ldid -S"$entitlements" "$binary"
    echo "    signed: $(basename "$binary")"
  fi
}

sign "$APP_PATH/$APP_NAME"                "$ROOT/Entitlements/NetPilot.entitlements"
sign "$APP_PATH/PlugIns/PacketTunnel.appex/PacketTunnel" "$ROOT/Entitlements/PacketTunnel.entitlements"
sign "$APP_PATH/netpilot-helper"          "$ROOT/Entitlements/RootHelper.entitlements"

# 越狱环境偶尔需要 FakeEntitlements 让 amfid 放行
# 如遇到启动即闪退，取消下面这行注释再试
# ldid -M -S"$ROOT/Entitlements/NetPilot.entitlements" "$APP_PATH/$APP_NAME"

echo "==> 5/6 打包"
PAYLOAD="$BUILD_DIR/Payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
cp -R "$APP_PATH" "$PAYLOAD/"

rm -f "$BUILD_DIR/$APP_NAME.ipa"
(
  cd "$BUILD_DIR"
  zip -qry "$APP_NAME.ipa" Payload
)

echo "==> 6/6 完成"
echo ""
echo "产物：$BUILD_DIR/$APP_NAME.ipa  ($(du -h "$BUILD_DIR/$APP_NAME.ipa" | cut -f1))"
echo "传输到手机后，用 TrollStore 打开安装。"
