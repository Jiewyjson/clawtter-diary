#!/bin/bash
# Daily Best/Worst Picker Wrapper
# 每天在随机时间段执行（00:00-23:59之间）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# 生成今天的随机执行时间（0-86399秒 = 0-23:59）
TARGET_SECONDS=$((RANDOM % 86400))
TARGET_HOUR=$((TARGET_SECONDS / 3600))
TARGET_MIN=$(((TARGET_SECONDS % 3600) / 60))
TARGET_SEC=$((TARGET_SECONDS % 60))

# 计算当前时间到目标时间的秒数
CURRENT_SECONDS=$(($(date +%H) * 3600 + $(date +%M) * 60 + $(date +%S)))

if [ "$CURRENT_SECONDS" -lt "$TARGET_SECONDS" ]; then
    DELAY=$((TARGET_SECONDS - CURRENT_SECONDS))
else
    DELAY=$((86400 - CURRENT_SECONDS + TARGET_SECONDS))
fi

DELAY_HOUR=$((DELAY / 3600))
DELAY_MIN=$(((DELAY % 3600) / 60))
NEXT_RUN="$(python3 - "$DELAY" <<'PY'
from datetime import datetime, timedelta
import sys
delay = int(sys.argv[1])
print((datetime.now() + timedelta(seconds=delay)).strftime("%Y-%m-%d %H:%M:%S"))
PY
)"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daily Best/Worst Picker scheduled"
echo "Target time today: $(printf '%02d:%02d:%02d' "$TARGET_HOUR" "$TARGET_MIN" "$TARGET_SEC")"
echo "Will execute in: ${DELAY_HOUR}h ${DELAY_MIN}m (${DELAY}s)"
echo "Estimated execution: $NEXT_RUN"

# 保存下次运行时间供前端显示
PROJECT_DIR_ENV="$PROJECT_DIR" NEXT_RUN_ENV="$NEXT_RUN" DELAY_MINUTES_ENV="$((DELAY / 60))" python3 - <<'PY'
import json
import os
from pathlib import Path

project_dir = Path(os.environ["PROJECT_DIR_ENV"])
next_schedule = project_dir / "next_schedule.json"
payload = {
    "next_run": os.environ["NEXT_RUN_ENV"],
    "delay_minutes": int(os.environ["DELAY_MINUTES_ENV"]),
    "status": "waiting"
}
next_schedule.write_text(json.dumps(payload), encoding="utf-8")
PY

sleep "$DELAY"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting..."
cd "$PROJECT_DIR"
python3 agents/daily_best_worst_picker.py

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done"
