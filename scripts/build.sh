#!/bin/bash
# 构建「AI 定时任务」菜单栏 App 并打包成 DMG
# 用法：scripts/build.sh            产物在 dist/AICronHelper-<版本>.dmg
#      VERSION=0.2.0 scripts/build.sh
# 可选环境变量：
#   BUILD_NUMBER  CFBundleVersion，Sparkle 用它比较新旧，必须递增（默认取当前时间）
#   FEED_URL      更新源 appcast 地址（本地测试时指向 127.0.0.1）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AICronHelper"
DISPLAY_NAME="AI 定时任务"
BUNDLE_ID="xyz.iamxmm.aicronhelper"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/dmmgogogo/ai-cron-helper/main/appcast.xml}"
# 公钥用于校验更新包签名；对应的私钥不进仓库，只保存在发布者本机
SPARKLE_PUBLIC_KEY="nN+zPi37gJ0HqSMZVNMNRPC/aJE9emWnY8BOg/RIJL4="
SPARKLE_FRAMEWORK="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
APP="$BUILD/$APP_NAME.app"

echo "==> 编译 release"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"

echo "==> 生成图标"
ICONSET="$BUILD/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/scripts/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"

echo "==> 组装 $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# 让 Sparkle 的更新窗口使用中文
mkdir -p "$APP/Contents/Resources/zh-Hans.lproj"

# 嵌入 Sparkle：ditto 保留框架内的符号链接；非沙盒 App 用不到 XPC 服务，去掉
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"
if ! otool -l "$APP/Contents/MacOS/$APP_NAME" | grep -q "path @executable_path/../Frameworks "; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# 不开 App Sandbox：需要读 ~/.codex 和 ~/Library/Application Support/Claude
echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> 打包 DMG"
STAGE="$BUILD/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$DISPLAY_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

echo "==> 完成：$DMG ($(du -h "$DMG" | cut -f1))"
