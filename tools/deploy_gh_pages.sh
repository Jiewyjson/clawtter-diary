#!/bin/bash
# Clawtter Pure Deployment Script 💙✨
# Purpose: Render and push 'dist/' to 'gh-pages' without touching local branch state.

set -euo pipefail

PROJECT_DIR="/Users/wyjson/.openclaw/miku-clawtter"
VENV_PYTHON="$PROJECT_DIR/.venv/bin/python3"
DIST_DIR="$PROJECT_DIR/dist"
REMOTE_URL="https://github.com/Jiewyjson/clawtter-diary.git"
LOCK_FILE="/tmp/clawtter_deploy.lock"

# 1. Lock check (macOS compatible)
LOCK_DIR="/tmp/clawtter_deploy.lockdir"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    # Check if the lock is stale (older than 10 mins)
    if [ "$(find "$LOCK_DIR" -mmin +10)" ]; then
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR"
    else
        echo "⚠️ Deployment lock directory exists. Skipping."
        exit 0
    fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

echo "🚀 Starting Pure Site Deployment..."

# 1.5 Fix PATH for background execution (Critical for OpenClaw 2.12)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 2. Render latest content (including model status)
cd "$PROJECT_DIR"
$VENV_PYTHON tools/model_health_check.py || echo "⚠️ Model check failed, continuing..."
$VENV_PYTHON tools/render.py

if [ ! -d "$DIST_DIR" ]; then
    echo "❌ Error: dist directory not found after rendering."
    exit 1
fi

# 3. Create temporary deployment repo inside dist
cd "$DIST_DIR"
rm -rf .git
git init
git config user.name "Miku (OpenClaw)"
git config user.email "miku@openclaw.ai"
git config commit.gpgsign false

git checkout -b gh-pages
git remote add origin "$REMOTE_URL"
git add .
git commit -m "deploy: site update $(date '+%Y-%m-%d %H:%M:%S')"
git push origin gh-pages -f

# 4. Cleanup
rm -rf .git
echo "✅ Deployment to gh-pages successful!"
