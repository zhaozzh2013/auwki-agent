#!/usr/bin/env bash
# AUWKI Agent 数据迁移脚本（Linux）
# 将 U 盘备份的 AppData-backup 迁移到本机应用数据目录。
# 用法：在真实终端（非沙箱）运行：bash tool/migrate_data_linux.sh [备份目录]
set -euo pipefail

BACKUP="${1:-/home/zzh/项目/AUWKI-AGENT/AppData-backup}"
if [ ! -d "$BACKUP" ]; then
  echo "错误：找不到备份目录 $BACKUP" >&2
  exit 1
fi

# 应用数据目录（path_provider ApplicationSupport，按可执行文件名）
DEST="$HOME/.local/share/auwki_agent"
mkdir -p "$DEST"
echo "==> 迁移到 $DEST"

cp -v "$BACKUP/chats.db" "$BACKUP/chats.db-wal" "$BACKUP/chats.db-shm" \
      "$BACKUP/settings.json" "$BACKUP/memory.json" \
      "$BACKUP/tasks.json" "$BACKUP/audit.jsonl" "$DEST/" 2>&1 || true

echo
echo "==> 完成。注意："
echo "  - chats.db-wal 必须与 chats.db 同目录（含未合并写入）"
echo "  - 若应用已启动过，先退出后用本脚本覆盖（避免单实例锁 app.lock 冲突）"
echo "  - 验证：启动应用后检查对话是否完整"