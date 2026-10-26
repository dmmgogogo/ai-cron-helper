#!/bin/bash
# 发布新版本：打包 DMG → EdDSA 签名 → 发布 GitHub Release → 把新版本写进 appcast.xml 并推送
# 用法：scripts/release.sh 0.2.0 docs/release-notes/0.2.0.md
#   更新说明（Markdown）只写这次改了什么：它会显示在 App 的更新窗口里；
#   GitHub Release 页面会在后面自动补上安装说明和 SHA-256。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

die() { echo "错误：$*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "用法：scripts/release.sh <版本号> <更新说明.md>"
VERSION="$1"
NOTES="$2"
REPO="dmmgogogo/ai-cron-helper"
TAG="v$VERSION"
# 私钥路径属于本机私有信息，不写进仓库：放在仓库根目录的 .release.env（已在 .gitignore 里），
# 内容形如 SPARKLE_KEY_FILE=/path/to/private.key；也可以直接用同名环境变量
# 只读取 SPARKLE_KEY_FILE 这一项，不 source 整个文件，避免误覆盖脚本里的其它变量
KEY_FILE="${SPARKLE_KEY_FILE:-}"
if [[ -z "$KEY_FILE" && -f "$ROOT/.release.env" ]]; then
    KEY_FILE="$(sed -n 's/^SPARKLE_KEY_FILE=//p' "$ROOT/.release.env" | tail -1)"
fi
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

echo "==> 发布前检查"
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "版本号格式不对：$VERSION"
[[ -s "$NOTES" ]] || die "更新说明不存在或为空：$NOTES"
[[ -n "$KEY_FILE" ]] || die "没有配置签名私钥：在仓库根目录 .release.env 写入 SPARKLE_KEY_FILE=<私钥文件路径>（该文件不提交）"
[[ -f "$KEY_FILE" ]] || die "找不到签名私钥：$KEY_FILE"
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || die "请在 main 分支发布"
[[ -z "$(git status --porcelain)" ]] || die "工作区有未提交的改动，先提交（更新说明也要提交）"
git fetch -q origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "本地 main 与 origin/main 不一致，先同步"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then die "$TAG 已经存在"; fi

BUILD_NUMBER="$(date +%Y%m%d%H%M)"
VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" scripts/build.sh
DMG="dist/AICronHelper-$VERSION.dmg"

echo "==> EdDSA 签名"
SIGN_OUTPUT="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"
SHA256="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"

DMG_URL="https://github.com/$REPO/releases/download/$TAG/AICronHelper-$VERSION.dmg"
RELEASE_BODY="$(mktemp)"
APPCAST_CHECK="$(mktemp)"
trap 'rm -f "$RELEASE_BODY" "$APPCAST_CHECK"' EXIT

echo "==> 预检 appcast"
# 建 Release 之前先在副本上试写一遍：构建号、重复版本、签名格式有问题就在这里停下，不留半截的 Release
if [[ -f appcast.xml ]]; then cp appcast.xml "$APPCAST_CHECK"; fi
python3 scripts/update_appcast.py --appcast "$APPCAST_CHECK" --version "$VERSION" --build "$BUILD_NUMBER" \
    --url "$DMG_URL" --sign-output "$SIGN_OUTPUT" --notes "$NOTES" >/dev/null

echo "==> 发布 GitHub Release $TAG"
# 先发 Release 再推 appcast：避免用户拿到指向还不存在的安装包的更新
{
    cat "$NOTES"
    cat <<EOF

## 安装
已安装 v0.2.0 及以上版本的，在菜单栏面板点「检查更新」即可自动更新。

首次安装：下载 \`AICronHelper-$VERSION.dmg\`，把 \`AICronHelper.app\` 拖进「应用程序」。App 为 ad-hoc 签名、未经 Apple 公证，首次打开会被系统拦截，二选一：
- 「系统设置 → 隐私与安全性」里点「仍要打开」
- 或在终端执行：\`xattr -dr com.apple.quarantine /Applications/AICronHelper.app\`

要求 macOS 14 及以上、Apple 芯片（arm64）。

## 校验
SHA-256：\`$SHA256\`
EOF
} > "$RELEASE_BODY"
gh release create "$TAG" "$DMG" --repo "$REPO" --target main --title "$TAG" --notes-file "$RELEASE_BODY" --latest
# Release 已公开：之后的步骤失败时不能直接重跑（会撞「已存在」），提示怎么补完
trap 'rm -f "$RELEASE_BODY" "$APPCAST_CHECK"; echo "错误：$TAG 的 Release 已发布，但 appcast 没有推送成功。检查 appcast.xml 与 git 状态后手动完成：git add -- appcast.xml && git commit -m \"release: $TAG\" && git push origin main（已提交过就只需 git push origin main）" >&2' ERR

echo "==> 更新 appcast.xml"
python3 scripts/update_appcast.py --appcast appcast.xml --version "$VERSION" --build "$BUILD_NUMBER" \
    --url "$DMG_URL" --sign-output "$SIGN_OUTPUT" --notes "$NOTES"
git add -- appcast.xml
git commit -q -m "release: $TAG"
git push -q origin main

echo "==> 完成：$TAG（构建号 $BUILD_NUMBER）"
echo "    Release：https://github.com/$REPO/releases/tag/$TAG"
