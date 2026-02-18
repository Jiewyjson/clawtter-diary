#!/bin/bash
# Clawtter Pure Deployment Script 💙✨
# Purpose: Render and push dist/ to gh-pages with branch-safety fuse.

set -euo pipefail

PROJECT_DIR="/Users/wyjson/.openclaw/miku-clawtter"
VENV_PYTHON="$PROJECT_DIR/.venv/bin/python3"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE_URL="https://github.com/Jiewyjson/clawtter-diary.git"
LOCK_DIR="/tmp/clawtter_deploy.lockdir"

# 0) Lock check (macOS compatible)
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ "$(find "$LOCK_DIR" -mmin +10 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR"
  else
    echo "⚠️ Deployment lock exists. Skipping."
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

echo "🚀 Starting Pure Site Deployment..."

# 1) PATH fix for LaunchAgent/background execution
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 2) Render latest content
cd "$PROJECT_DIR"
$VENV_PYTHON tools/model_health_check.py || echo "⚠️ Model check failed, continuing..."
$VENV_PYTHON tools/render.py

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
remote_main_sha="$(git ls-remote "$REMOTE_URL" refs/heads/main | awk '{print $1}')"
if [ -n "$remote_main_sha" ] && [ "$local_sha" = "$remote_main_sha" ] && [ "${ALLOW_SAME_MAIN_SHA:-0}" != "1" ]; then
  echo "❌ Safety fuse: deploy payload SHA equals remote main SHA. Abort."
  echo "   If intentional, rerun with ALLOW_SAME_MAIN_SHA=1"
  exit 1
fi

# 6) Push gh-pages only
git remote add origin "$REMOTE_URL"
git push origin gh-pages -f

# 7) Cleanup
rm -rf .git
echo "✅ Deployment to gh-pages successful!"
