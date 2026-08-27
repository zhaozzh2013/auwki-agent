#!/usr/bin/env bash
# AUWKI Agent Linux 桌面集成安装脚本
# 作用：安装应用图标 + .desktop 启动器，可在应用菜单/启动器中双击启动。
# 用法：bash tool/install_desktop_linux.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_SRC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png"
DESKTOP_NAME="auwki-agent.desktop"
ICON_DIR="$HOME/.local/share/icons"
APP_DIR="$HOME/.local/share/applications"

if [ ! -f "$ICON_SRC" ]; then
  echo "错误：找不到图标源 $ICON_SRC" >&2
  exit 1
fi

mkdir -p "$ICON_DIR" "$APP_DIR"

# 图标（256px 与 512px 各一份）
install -m 644 "$ICON_SRC" "$ICON_DIR/auwki-agent.png"
echo "==> 图标已安装 -> $ICON_DIR/auwki-agent.png"

cat > "$APP_DIR/$DESKTOP_NAME" <<EOF
[Desktop Entry]
Type=Application
Name=AUWKI Agent
Comment=Local multi-provider AI chat desktop app
Exec=$ROOT/run_auwki_linux.sh
Icon=auwki-agent
Terminal=true
Categories=Utility;Office;
Keywords=AI;chat;agent;
StartupWMClass=com.auwki.auwki_agent
EOF
chmod +x "$APP_DIR/$DESKTOP_NAME"
echo "==> 启动器已安装 -> $APP_DIR/$DESKTOP_NAME"
echo "    Exec=$ROOT/run_auwki_linux.sh（Terminal=true 保持滚屏日志）"

# 刷新应用数据库（可选）
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" 2>/dev/null || true
fi
echo "==> 完成。在应用菜单中搜索 “AUWKI Agent” 即可启动。"