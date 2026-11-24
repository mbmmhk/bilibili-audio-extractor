#!/bin/bash
# Songline one-command installer for Apple Silicon Macs.
#
#   curl -fsSL https://raw.githubusercontent.com/mbmmhk/bilibili-audio-extractor/master/install.sh | bash
#
# Installs into ~/Songline (code + Python env), keeps recognition data in
# ~/.songline, and puts a "Songline.command" launcher on the Desktop.
# Running it again updates to the latest version. Nothing needs sudo.
set -euo pipefail

REPO="mbmmhk/bilibili-audio-extractor"
APP_HOME="${SONGLINE_HOME:-$HOME/Songline}"
SOURCE_URL="${SONGLINE_SOURCE_URL:-https://codeload.github.com/$REPO/tar.gz/refs/heads/master}"
WEB_URL="${SONGLINE_WEB_URL:-https://github.com/$REPO/releases/download/web-latest/web-dist.tgz}"
LAUNCHER_DIR="${SONGLINE_LAUNCHER_DIR:-$HOME/Desktop}"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误：\033[0m%s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] ||
  die "Songline 目前只支持 Apple Silicon（M 系列芯片）的 Mac。"

# 1. uv: installs and manages Python for us.
UV="$(command -v uv || true)"
if [ -z "$UV" ] && [ -x "$HOME/.local/bin/uv" ]; then
  UV="$HOME/.local/bin/uv"
fi
if [ -z "$UV" ]; then
  say "安装 uv（Python 环境管理工具）…"
  curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh >/dev/null
  UV="$HOME/.local/bin/uv"
fi

# 2. Code and the prebuilt web UI, swapped in only once both downloaded fine.
say "下载 Songline…"
mkdir -p "$APP_HOME"
NEW="$(mktemp -d "$APP_HOME/.new.XXXXXX")"
trap 'rm -rf "$NEW"' EXIT
trap 'printf "\033[1;31m安装没有完成\033[0m（多半是网络问题），已保留原来的版本，可以稍后重新运行。\n" >&2' ERR
# GitHub can be flaky from some networks: retry, and only unpack complete files.
fetch() { curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors -o "$2" "$1"; }
fetch "$SOURCE_URL" "$NEW/.src.tgz"
fetch "$WEB_URL" "$NEW/.web.tgz"
tar -xzf "$NEW/.src.tgz" -C "$NEW" --strip-components=1
mkdir -p "$NEW/frontend/dist"
tar -xzf "$NEW/.web.tgz" -C "$NEW/frontend/dist"
rm -f "$NEW/.src.tgz" "$NEW/.web.tgz"
[ -f "$NEW/frontend/dist/index.html" ] || die "网页界面下载不完整，请稍后重试。"
rm -rf "$APP_HOME/app.old"
[ -d "$APP_HOME/app" ] && mv "$APP_HOME/app" "$APP_HOME/app.old"
mv "$NEW" "$APP_HOME/app"
rm -rf "$APP_HOME/app.old"

# 3. Python 3.12 + dependencies (the env lives outside app/, so updates are quick).
say "安装依赖（第一次需要几分钟）…"
export UV_PROJECT_ENVIRONMENT="$APP_HOME/venv"
(cd "$APP_HOME/app/backend" && "$UV" sync --locked --no-dev --quiet)

# 4. The speech model (~1.6 GB) now, with progress, instead of silently on first use.
say "下载语音识别模型（约 1.6 GB，只需一次）…"
if ! (cd "$APP_HOME/app/backend" && "$UV" run --no-dev --no-sync songline setup); then
  echo "    模型这次没下载完，没关系：第一次识别时会接着下载，网页上会显示进度。"
fi

# 5. Double-click launcher.
LAUNCHER="$LAUNCHER_DIR/Songline.command"
mkdir -p "$LAUNCHER_DIR"
cat >"$LAUNCHER" <<EOF
#!/bin/bash
# Songline 启动器：双击打开。关掉这个终端窗口就会停止 Songline。
if curl -s -o /dev/null http://127.0.0.1:8765/api/jobs; then
  echo "Songline 已经在运行，正在打开网页…"
  open http://127.0.0.1:8765
  exit 0
fi
echo "正在启动 Songline，浏览器会自动打开 http://127.0.0.1:8765"
echo "用完关掉这个窗口即可。第一次识别会下载约 1.6 GB 的语音模型，请耐心等待。"
cd "$APP_HOME/app/backend"
UV_PROJECT_ENVIRONMENT="$APP_HOME/venv" exec "$UV" run --no-dev --no-sync songline serve
EOF
chmod +x "$LAUNCHER"

say "安装完成！"
echo "    以后双击桌面上的 Songline.command 就能打开。"
echo "    想更新到最新版，重新运行这条安装命令即可。"
if [ -z "${SONGLINE_NO_START:-}" ]; then
  say "现在启动…"
  open "$LAUNCHER"
fi
