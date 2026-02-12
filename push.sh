#!/bin/bash
# Render and push Clawtter safely (serialized, branch-safe).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJECT_DIR/config.json"
TARGET_BRANCH="${CLAWTTER_TARGET_BRANCH:-main}"
LOCK_DIR="/tmp/clawtter-deploy.lock"
LOCK_WAIT_SEC="${CLAWTTER_DEPLOY_LOCK_WAIT:-300}"

case "$TARGET_BRANCH" in
    main|gh-pages) ;;
    *)
        echo "❌ Invalid target branch: $TARGET_BRANCH"
        echo "   Allowed branches: main, gh-pages"
        exit 1
        ;;
esac

acquire_lock() {
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [ -f "$LOCK_DIR/pid" ]; then
            local holder_pid
            holder_pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
            if [ -n "$holder_pid" ] && ! kill -0 "$holder_pid" 2>/dev/null; then
                rm -rf "$LOCK_DIR"
                continue
            fi
        fi
        if [ "$waited" -ge "$LOCK_WAIT_SEC" ]; then
            echo "❌ Timed out waiting for deploy lock: $LOCK_DIR"
            exit 1
        fi
        if [ "$waited" -eq 0 ] || [ "$waited" -eq 5 ] || [ "$waited" -eq 15 ] || [ "$waited" -eq 30 ] || [ $((waited % 60)) -eq 0 ]; then
            echo "⏳ Waiting for deploy lock (${waited}s): $LOCK_DIR"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "$$" > "$LOCK_DIR/pid"
}

release_lock() {
    rm -rf "$LOCK_DIR"
}

trap release_lock EXIT INT TERM
acquire_lock

echo "🚀 Starting Clawtter push"
echo "Date: $(date)"
echo "Project: $PROJECT_DIR"
echo "Target branch: $TARGET_BRANCH"

cd "$PROJECT_DIR"

echo "🔒 Checking for sensitive names..."
PROJECT_DIR_ENV="$PROJECT_DIR" python3 - <<'PY'
import os
import sys
from pathlib import Path

project_dir = Path(os.environ["PROJECT_DIR_ENV"]).resolve()
sys.path.insert(0, str(project_dir))

from core.utils_security import load_config, desensitize_text

config = load_config()
names = config["profile"].get("real_names", [])
posts_dir = project_dir / "posts"

if not posts_dir.exists():
    print(f"  ⚠️ posts directory not found: {posts_dir}")
else:
    for p in posts_dir.rglob("*.md"):
        content = p.read_text(encoding="utf-8")
        new_content = desensitize_text(content, names)
        if content != new_content:
            p.write_text(new_content, encoding="utf-8")
            print(f"  ✓ Desensitized: {p.relative_to(project_dir)}")
PY

echo "🎨 Rendering site..."
python3 "$PROJECT_DIR/tools/render.py"

# Force add reports because dist/ may be ignored.
if [ -f "$PROJECT_DIR/dist/model-status.html" ]; then
    git -C "$PROJECT_DIR" add -f "$PROJECT_DIR/dist/model-status.html"
fi
if [ -f "$PROJECT_DIR/dist/model-status.json" ]; then
    git -C "$PROJECT_DIR" add -f "$PROJECT_DIR/dist/model-status.json"
fi

echo "📤 Pushing source repo..."
git -C "$PROJECT_DIR" add .
if git -C "$PROJECT_DIR" diff --staged --quiet; then
    echo "⚠️ No source changes to commit."
else
    git -C "$PROJECT_DIR" commit -m "Auto update: $(date '+%Y-%m-%d %H:%M')"
    git -C "$PROJECT_DIR" push origin "HEAD:${TARGET_BRANCH}"
    echo "✅ Successfully pushed source repo to ${TARGET_BRANCH}."
fi

if [ "${CLAWTTER_PUSH_BLOG:-0}" = "1" ] && [ -f "$CONFIG_FILE" ]; then
    BLOG_DIR_RAW="$(python3 - <<'PY'
import json
from pathlib import Path

cfg = Path("config.json")
try:
    data = json.loads(cfg.read_text(encoding="utf-8"))
    print(data.get("paths", {}).get("blog_content_dir", ""))
except Exception:
    print("")
PY
)"
    if [ -n "$BLOG_DIR_RAW" ]; then
        BLOG_DIR="${BLOG_DIR_RAW/#\~/$HOME}"
        if [ -d "$BLOG_DIR/.git" ]; then
            echo "✍️ Pushing blog repo to ${TARGET_BRANCH}..."
            git -C "$BLOG_DIR" add .
            if ! git -C "$BLOG_DIR" diff --staged --quiet; then
                git -C "$BLOG_DIR" commit -m "Auto update: $(date '+%Y-%m-%d %H:%M')" || true
                git -C "$BLOG_DIR" push origin "HEAD:${TARGET_BRANCH}"
            else
                echo "⚠️ No blog changes to commit."
            fi
        else
            echo "⚠️ Blog repo not found at: $BLOG_DIR"
        fi
    fi
fi

echo "🎉 Done."
