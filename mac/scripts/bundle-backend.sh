#!/bin/sh
# Xcode 构建阶段调用：把 Python 后端代码和 uv 复制进 Songline.app/Contents/Resources。
# 依赖本身不打包，App 首次打开时用 uv 安装（见 ARCHITECTURE.md 5.1）。
set -eu

REPO="${SRCROOT}/.."
DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
mkdir -p "$DEST/backend" "$DEST/bin"

rsync -a --delete \
  --exclude .venv --exclude __pycache__ --exclude .pytest_cache --exclude tests --exclude eval \
  "$REPO/backend/" "$DEST/backend/"

# uv：优先用环境变量指定的，其次是常见安装位置。
for uv in "${SONGLINE_UV:-}" "$(command -v uv 2>/dev/null || true)" \
          "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
  if [ -n "$uv" ] && [ -x "$uv" ]; then
    cp -f "$uv" "$DEST/bin/uv"
    echo "bundled uv from $uv"
    exit 0
  fi
done
echo "warning: 没找到 uv，App 运行时会去常见位置找。安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
