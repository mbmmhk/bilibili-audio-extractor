#!/bin/bash
# 打包 Songline：编译 Release 版 App，生成可以拖进「应用程序」安装的 .dmg。
#
#   mac/scripts/package.sh 0.1.0
#
# 输出：mac/dist/Songline-<版本号>.dmg
# 需要：Xcode、uv（会被打进 App，朋友的电脑上不用另外装）。
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/mac/build"
DIST="$ROOT/mac/dist"
APP="$BUILD/Build/Products/Release/Songline.app"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误：\033[0m%s\n' "$*" >&2; exit 1; }

# uv 必须打进 App：没有它，没装 uv 的朋友第一次打开时装不了 Python 环境。
UV="${SONGLINE_UV:-$(command -v uv || true)}"
[ -n "$UV" ] && [ -x "$UV" ] || die "找不到 uv。安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
[ "$(lipo -archs "$UV" 2>/dev/null)" = arm64 ] || die "uv 不是 Apple Silicon（arm64）版本：$UV"

say "编译 Songline ${VERSION}（Release）…"
rm -rf "$BUILD/Build/Products/Release"
SONGLINE_UV="$UV" xcodebuild \
  -project "$ROOT/mac/Songline.xcodeproj" -scheme Songline -configuration Release \
  -derivedDataPath "$BUILD" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  build >"$BUILD.log" 2>&1 || { tail -40 "$BUILD.log"; die "编译失败，完整日志：$BUILD.log"; }

say "检查 App…"
[ -x "$APP/Contents/Resources/bin/uv" ] || die "App 里没有 uv"
[ -f "$APP/Contents/Resources/backend/uv.lock" ] || die "App 里没有后端代码"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || die "App 版本号不对"
codesign --verify --strict "$APP" || die "App 签名校验失败"

say "生成 .dmg…"
mkdir -p "$DIST"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/应用程序"
DMG="$DIST/Songline-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Songline $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

say "完成：${DMG}（$(du -h "$DMG" | cut -f1)）"
