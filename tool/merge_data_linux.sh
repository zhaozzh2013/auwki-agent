#!/usr/bin/env bash
# AUWKI Agent 数据合并脚本（合并式迁移，不会覆盖现有对话）
# 作用：把备份库（U盘 21 个旧对话）按 id 去重合并进当前库
#       （当前 4 个新对话保留；id 冲突时保留当前版本）。
# 用法：bash tool/merge_data_linux.sh [备份库路径]
# 注意：先退出 AUWKI Agent 再运行！
set -euo pipefail

BACKUP_DB="${1:-/home/zzh/项目/AUWKI-AGENT/AppData-backup/chats.db}"
# 数据目录可用 AUWKI_DATA_DIR 覆盖（测试/自定义用）
DEST_DIR="${AUWKI_DATA_DIR:-$HOME/.local/share/com.auwki.auwki_agent}"
DEST_DB="$DEST_DIR/chats.db"

if [ ! -f "$BACKUP_DB" ]; then
  echo "错误：找不到备份库 $BACKUP_DB" >&2
  exit 1
fi
if [ ! -f "$DEST_DB" ]; then
  echo "错误：找不到当前库 $DEST_DB（先启动一次应用再跑）" >&2
  exit 1
fi

# 合并前备份当前库（双保险）
stamp="$(date +%Y%m%d-%H%M%S)"
cp "$DEST_DB" "$DEST_DB.bak-$stamp"
echo "==> 已备份当前库 -> chats.db.bak-$stamp"

python3 - "$BACKUP_DB" "$DEST_DB" <<'PY'
import sqlite3, sys, json

src, dst = sys.argv[1], sys.argv[2]
a = sqlite3.connect(src)
b = sqlite3.connect(dst)

backup_rows = a.execute("SELECT id, data FROM conversations").fetchall()
cur_ids = {r[0] for r in b.execute("SELECT id FROM conversations")}

added, skipped = 0, 0
with b:
    for cid, data in backup_rows:
        if cid in cur_ids:
            skipped += 1
            continue
        b.execute("INSERT INTO conversations (id, data) VALUES (?, ?)", (cid, data))
        added += 1
b.commit()

# WAL 合并（若有未合并写入）
try:
    b.execute("PRAGMA wal_checkpoint(TRUNCATE)")
except Exception:
    pass

print(f"==> 备份库 {len(backup_rows)} 个对话：新增 {added}，冲突跳过 {skipped}")
print(f"==> 合并后当前库共 {b.execute('SELECT COUNT(*) FROM conversations').fetchone()[0]} 个对话")
a.close(); b.close()
PY
echo "==> 完成。启动应用检查对话列表。"