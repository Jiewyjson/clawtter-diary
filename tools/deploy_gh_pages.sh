#!/bin/bash
# Clawtter Pure Deployment Script 💙✨
# Purpose: Render and push dist/ to gh-pages with branch-safety fuse.

set -euo pipefail

PROJECT_DIR="/Users/wyjson/.openclaw/miku-clawtter"
VENV_PYTHON="$PROJECT_DIR/.venv/bin/python3"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE_URL="https://github.com/Jiewyjson/clawtter-diary.git"
LOCK_DIR="/tmp/clawtter_deploy.lockdir"
LOCK_META="$LOCK_DIR/meta"

run_with_timeout() {
  local seconds="$1"
  shift
  perl -e 'my $t=shift; alarm $t; exec @ARGV' "$seconds" "$@"
}

acquire_lock() {
  local now_ts
  now_ts="$(date +%s)"

  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf "%s %s\n" "$$" "$now_ts" > "$LOCK_META"
    return 0
  fi

  # Lock exists: try stale lock recovery
  if [ -f "$LOCK_META" ]; then
    local lock_pid lock_ts age
    lock_pid="$(awk '{print $1}' "$LOCK_META" 2>/dev/null || echo "")"
    lock_ts="$(awk '{print $2}' "$LOCK_META" 2>/dev/null || echo "0")"
    age=$((now_ts - lock_ts))

    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
      echo "⚠️ Stale lock detected (dead pid=$lock_pid). Recovering..."
      rm -rf "$LOCK_DIR"
      mkdir "$LOCK_DIR"
      printf "%s %s\n" "$$" "$now_ts" > "$LOCK_META"
      return 0
    fi

    if [ "$age" -gt 1800 ]; then
      echo "⚠️ Stale lock detected (age=${age}s). Recovering..."
      rm -rf "$LOCK_DIR"
      mkdir "$LOCK_DIR"
      printf "%s %s\n" "$$" "$now_ts" > "$LOCK_META"
      return 0
    fi
  fi

  echo "⚠️ Deployment lock exists. Skipping."
  return 1
}

release_lock() {
  rm -rf "$LOCK_DIR" 2>/dev/null || true
}

if ! acquire_lock; then
  exit 0
fi
trap release_lock EXIT

echo "🚀 Starting Pure Site Deployment..."

# 1) PATH fix for LaunchAgent/background execution
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 2) Render latest content
cd "$PROJECT_DIR"
"$VENV_PYTHON" tools/render.py

if [ ! -d "$DIST_DIR" ]; then
  echo "❌ dist directory not found after rendering."
  exit 1
fi

# 3) Safety fuse: dist content sanity check
if [ ! -f "$DIST_DIR/index.html" ] || [ ! -d "$DIST_DIR/post" ] || [ ! -d "$DIST_DIR/static" ]; then
  echo "❌ Safety fuse: dist is missing required static-site outputs. Abort."
  exit 1
fi

if find "$DIST_DIR" -maxdepth 2 \( -name "*.py" -o -name "*.md" -o -name "AGENTS.md" -o -name "SOUL.md" \) | grep -q .; then
  echo "❌ Safety fuse: detected source-like files in dist (py/md). Abort to prevent branch pollution."
  exit 1
fi

# 4) Build temporary gh-pages repo in dist
cd "$DIST_DIR"
rm -rf .git
git init
git config user.name "Miku (OpenClaw)"
git config user.email "miku@openclaw.ai"
git config commit.gpgsign false
git checkout -b gh-pages
find . -name ".DS_Store" -delete || true
git add .
git commit -m "deploy: site update $(date '+%Y-%m-%d %H:%M:%S')"

# 5) Safety fuse: remote main-vs-payload commit check
local_sha="$(git rev-parse HEAD)"
remote_main_raw="$(run_with_timeout 20 git ls-remote "$REMOTE_URL" refs/heads/main 2>/dev/null || true)"
remote_main_sha="$(echo "$remote_main_raw" | awk '{print $1}')"
if [ -n "$remote_main_sha" ] && [ "$local_sha" = "$remote_main_sha" ] && [ "${ALLOW_SAME_MAIN_SHA:-0}" != "1" ]; then
  echo "❌ Safety fuse: deploy payload SHA equals remote main SHA. Abort."
  echo "   If intentional, rerun with ALLOW_SAME_MAIN_SHA=1"
  exit 1
fi

# 6) Push gh-pages only with health check
git remote add origin "$REMOTE_URL"
if run_with_timeout 180 git push origin gh-pages -f; then
  echo "📡 Verifying remote deployment..."
  sleep 2
  remote_gh_pages_raw="$(run_with_timeout 20 git ls-remote "$REMOTE_URL" refs/heads/gh-pages 2>/dev/null || true)"
  remote_gh_pages_sha="$(echo "$remote_gh_pages_raw" | awk '{print $1}')"
  if [ "$local_sha" != "$remote_gh_pages_sha" ]; then
    echo "❌ Health check failed: Remote gh-pages SHA mismatch! (Remote: $remote_gh_pages_sha)"
    exit 1
  fi
  echo "✅ Remote health check passed."
else
  echo "❌ Git push failed or timed out."
  exit 1
fi

# 7) Cleanup
rm -rf .git

echo "📡 Scheduling async model health update (non-blocking)..."
(
  cd "$PROJECT_DIR"
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  nohup "$VENV_PYTHON" tools/model_health_check.py > /tmp/clawtter_model_health.log 2>&1 || true
) >/dev/null 2>&1 &

echo "✅ Deployment to gh-pages successful!"
