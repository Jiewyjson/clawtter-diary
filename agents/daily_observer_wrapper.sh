#!/bin/bash
# Daily Timeline Observer Wrapper
# 在启动后随机延迟 0-120 分钟执行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# 随机延迟 0-7200 秒（0-120 分钟）
DELAY=$((RANDOM % 7200))
MINUTES=$((DELAY / 60))
EST_EXEC="$(python3 - "$DELAY" <<'PY'
from datetime import datetime, timedelta
import sys
delay = int(sys.argv[1])
print((datetime.now() + timedelta(seconds=delay)).strftime("%Y-%m-%d %H:%M:%S"))
PY
)"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daily Timeline Observer scheduled"
echo "Delay: ${MINUTES} minutes (${DELAY} seconds)"
echo "Estimated execution: $EST_EXEC"

sleep "$DELAY"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting observation..."
cd "$PROJECT_DIR"
python3 agents/daily_timeline_observer.py

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done"
