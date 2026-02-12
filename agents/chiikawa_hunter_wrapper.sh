#!/bin/bash
# Daily Chiikawa Hunter Wrapper
# 每天随机时间执行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# 生成今天的随机执行时间（0-86399秒 = 0-23:59）
TARGET_SECONDS=$((RANDOM % 86400))
TARGET_HOUR=$((TARGET_SECONDS / 3600))
TARGET_MIN=$(((TARGET_SECONDS % 3600) / 60))

# 计算当前时间到目标时间的秒数
CURRENT_SECONDS=$(($(date +%H) * 3600 + $(date +%M) * 60 + $(date +%S)))

if [ "$CURRENT_SECONDS" -lt "$TARGET_SECONDS" ]; then
    DELAY=$((TARGET_SECONDS - CURRENT_SECONDS))
else
    DELAY=$((86400 - CURRENT_SECONDS + TARGET_SECONDS))
fi

DELAY_HOUR=$((DELAY / 3600))
DELAY_MIN=$(((DELAY % 3600) / 60))
EST_EXEC="$(python3 - "$DELAY" <<'PY'
from datetime import datetime, timedelta
import sys
delay = int(sys.argv[1])
print((datetime.now() + timedelta(seconds=delay)).strftime("%Y-%m-%d %H:%M:%S"))
PY
)"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Chiikawa Hunter scheduled"
echo "Target time today: $(printf '%02d:%02d' "$TARGET_HOUR" "$TARGET_MIN")"
echo "Will execute in: ${DELAY_HOUR}h ${DELAY_MIN}m (${DELAY}s)"
echo "Estimated execution: $EST_EXEC"

sleep "$DELAY"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Chiikawa hunt..."
cd "$PROJECT_DIR"
python3 agents/daily_chiikawa_hunter.py

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done"
