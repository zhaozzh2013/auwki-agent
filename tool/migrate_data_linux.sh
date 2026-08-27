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

# 应用数据目录（path_provider ApplicationSupport，由 APPLICATION_ID
# com.auwki.auwki_agent 决定；注意不是 auwki_agent）
DEST="$HOME/.local/share/com.auwki.auwki_agent"
mkdir -p "$DEST"
echo "==> 迁移到 $DEST"

# 单实例锁残留（app.lock 中 PID 曾错判存活实例）会导致启动即退出
rm -f "$DEST/app.lock"
cp -v "$BACKUP/chats.db" "$BACKUP/settings.json" "$BACKUP/memory.json" \
      "$BACKUP/tasks.json" "$BACKUP/audit.jsonl" "$DEST/" 2>&1 || true

echo
echo "==> 完成。注意："
echo "  - 若备份含 chats.db-wal/-shm 且 chats.db 未合并，须连同拷贝并先退出应用"
echo "  - 若应用已启动过，先退出后用本脚本覆盖（避免单实例锁 app.lock 冲突）"
echo "  - 验证：启动应用后检查对话是否完整"