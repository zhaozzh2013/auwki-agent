#!/usr/bin/env bash
# AUWKI Agent 开发环境 PATH 持久化安装脚本
# 让 flutter / cmake / ninja 在新终端、IDE、AI 工具中都可检测到。
# 用法：bash ~/项目/auwki-agent/tool/setup_dev_path.sh
set -euo pipefail

FLUTTER_BIN="/home/zzh/项目/flutter-sdk/flutter/bin"
TOOLCHAIN_BIN="/home/zzh/项目/toolchain/cmake/bin:/home/zzh/项目/toolchain/ninja-bin"

# 1. GUI / systemd 用户会话（桌面启动的 IDE/AI 工具也生效）
ENVD="$HOME/.config/environment.d"
mkdir -p "$ENVD"
cat > "$ENVD/100-auwki.conf" <<EOF
PATH=$FLUTTER_BIN:$TOOLCHAIN_BIN:\$PATH
EOF
echo "✔ systemd 用户环境: $ENVD/100-auwki.conf"

# 2. bash / zsh（子 shell / 脚本）
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && ! grep -q "项目/flutter-sdk/flutter/bin" "$rc"; then
    printf '\nexport PATH="%s:%s:$PATH"\n' "$FLUTTER_BIN" "$TOOLCHAIN_BIN" >> "$rc"
    echo "✔ 已追加 $rc"
  fi
done

# 3. fish（用户主 shell；fish_add_path 持久化到 fish_user_paths）
if command -v fish >/dev/null 2>&1; then
  fish -c 'fish_add_path "/home/zzh/项目/flutter-sdk/flutter/bin" "/home/zzh/项目/toolchain/cmake/bin" "/home/zzh/项目/toolchain/ninja-bin"'
  echo "✔ fish_user_paths 已更新（当前及以后所有 fish 会话生效）"
fi

echo
echo "==> 验证（重新打开的终端中）:"
echo "    flutter --version"
echo "    which cmake ninja"
echo "==> 注意：已在运行的终端需重开；GUI 应用需注销重登后继承新环境。"