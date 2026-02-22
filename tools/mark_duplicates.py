#!/usr/bin/env python3
"""Non-destructive post dedupe.

Marks near-duplicate posts as hidden by adding `hidden: true` to YAML front matter.
Does NOT delete files (deletions require triple confirmation).

Algorithm:
- For each post in reverse-chronological order, compare to earlier "kept" posts.
- Similarity: Jaccard over tokens:
  - English: [a-z0-9]+ words
  - Chinese: 2-gram over Han characters
- Ignores markdown quote lines starting with '>' to avoid Perspective Evolution quote blocks.

Usage:
  python3 tools/mark_duplicates.py --threshold 0.90 --window 80
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
POSTS_DIR = PROJECT_ROOT / "posts"


def _split_frontmatter(md: str):
    if md.startswith('---\n'):
        parts = md.split('---', 2)
        if len(parts) >= 3:
            # parts[0] is empty before first ---
            fm = parts[1].strip('\n')
            body = parts[2].lstrip('\n')
            return fm, body
    return "", md


def _parse_frontmatter(fm: str) -> dict:
    meta = {}
    for line in fm.splitlines():
        if ':' not in line:
            continue
        k, v = line.split(':', 1)
        meta[k.strip()] = v.strip()
    return meta


def _render_frontmatter(meta: dict, original_fm: str) -> str:
    # preserve original key order if possible
    original_keys = []
    for line in original_fm.splitlines():
        if ':' in line:
            original_keys.append(line.split(':', 1)[0].strip())

    keys = []
    for k in original_keys:
        if k in meta and k not in keys:
            keys.append(k)
    for k in meta.keys():
        if k not in keys:
            keys.append(k)

    lines = []
    for k in keys:
        lines.append(f"{k}: {meta[k]}")
    return "\n".join(lines)


def _clean_text(body: str) -> str:
    # remove quoted blocks
    body = re.sub(r'(?m)^>.*$', '', body)
    # remove links
    body = re.sub(r'https?://\S+', '', body)
    # remove markdown punctuation
    body = re.sub(r'[*_`#\[\]\(\)!-]', ' ', body.lower())
    return body


def _tokens(text: str) -> set[str]:
    words = re.findall(r'[a-z0-9]+', text)
    hanzi = re.findall(r'[\u4e00-\u9fa5]', text)
    bigrams = ["".join(hanzi[i:i+2]) for i in range(len(hanzi) - 1)]
    return set(words) | set(bigrams)


def jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return inter / union


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--threshold', type=float, default=0.90)
    ap.add_argument('--window', type=int, default=80, help='Compare against the last N kept posts')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    files = sorted(POSTS_DIR.rglob('*.md'), key=lambda p: p.stat().st_mtime, reverse=True)
    kept: list[tuple[Path, set[str]]] = []
    marked = []

    for f in files:
        md = f.read_text(encoding='utf-8')
        fm, body = _split_frontmatter(md)
        meta = _parse_frontmatter(fm)
        if meta.get('hidden', '').lower() in {'true', '1', 'yes'}:
            continue

        t = _tokens(_clean_text(body))
        is_dup = False
        for prev_path, prev_toks in kept[: args.window]:
            sim = jaccard(t, prev_toks)
            if sim >= args.threshold:
                is_dup = True
                print(f"DUP {sim:.2f} {f.relative_to(PROJECT_ROOT)} ~= {prev_path.relative_to(PROJECT_ROOT)}")
                break

        if not is_dup:
            kept.insert(0, (f, t))
            continue

        # mark hidden
        meta['hidden'] = 'true'
        new_fm = _render_frontmatter(meta, fm)
        new_md = f"---\n{new_fm}\n---\n\n{body}" if fm else f"---\n{new_fm}\n---\n\n{body}"
        marked.append(f)
        if not args.dry_run:
            f.write_text(new_md, encoding='utf-8')

    print(f"\nMarked hidden: {len(marked)}")


if __name__ == '__main__':
    main()
