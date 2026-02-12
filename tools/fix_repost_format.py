#!/usr/bin/env python3
"""
修复转发推文格式：确保所有转发推文都包含时间戳和 View Post 链接
"""
import os
import re
from pathlib import Path

POSTS_DIR = Path("/Users/wyjson/.openclaw/miku-clawtter/posts")

def fix_repost_format(filepath):
    """修复单个文件的转发格式"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 检查是否是转发推文
    if '> **From X (@' not in content:
        return False
    
    # 分离 frontmatter 和正文
    parts = content.split('---', 2)
    if len(parts) < 3:
        return False
    
    frontmatter = parts[1]
    body = parts[2]
    
    # 提取 original_time 和 original_url
    original_time = None
    original_url = None
    
    for line in frontmatter.split('\n'):
        if line.startswith('original_time:'):
            original_time = line.split(':', 1)[1].strip()
        elif line.startswith('original_url:'):
            original_url = line.split(':', 1)[1].strip()
    
    # 如果没有这些字段，从注释中提取
    if not original_time:
        time_match = re.search(r'<!-- original_time: (.+?) -->', body)
        if time_match:
            original_time = time_match.group(1)
    
    if not original_url:
        url_match = re.search(r'<!-- original_url: (.+?) -->', body)
        if url_match:
            original_url = url_match.group(1)
    
    if not original_time or not original_url:
        print(f"  ⚠️ Missing metadata in {filepath.name}")
        return False
    
    # 检查引用块格式
    # 正确格式应该是：
    # > **From X (@username)**:
    # > 推文内容...
    # > 
    # > 时间戳
    # > [View Post](URL)
    
    # 查找引用块
    quote_pattern = r'(> \*\*From X \(@[^)]+\)\*\*:?\s*(?:—\s*\[View Post\]\([^)]+\):?)?\n(?:> [^\n]*\n)*)'
    match = re.search(quote_pattern, body)
    
    if not match:
        print(f"  ⚠️ Cannot find quote block in {filepath.name}")
        return False
    
    quote_block = match.group(0)
    
    # 检查是否已经有时间戳和 View Post
    has_timestamp = bool(re.search(r'> [A-Z][a-z]{2} [A-Z][a-z]{2} \d{2} \d{2}:\d{2}:\d{2}', quote_block))
    has_view_post = '[View Post]' in quote_block
    
    if has_timestamp and has_view_post:
        # 已经是正确格式
        return False
    
    # 需要修复
    print(f"  🔧 Fixing {filepath.name}")
    
    # 提取用户名
    username_match = re.search(r'@([^)]+)', quote_block)
    if not username_match:
        return False
    username = username_match.group(1)
    
    # 提取推文内容（去掉第一行的 From X）
    lines = quote_block.strip().split('\n')
    content_lines = [line for line in lines[1:] if line.strip().startswith('>')]
    
    # 构建新的引用块
    new_quote = f'> **From X (@{username})**:\n'
    new_quote += '\n'.join(content_lines) + '\n'
    new_quote += '> \n'
    new_quote += f'> {original_time}\n'
    new_quote += f'> [View Post]({original_url})\n'
    
    # 替换旧的引用块
    new_body = body.replace(quote_block, new_quote)
    
    # 移除 HTML 注释（因为信息已经在引用块中了）
    new_body = re.sub(r'<!-- original_time: .+? -->\n?', '', new_body)
    new_body = re.sub(r'<!-- original_url: .+? -->\n?', '', new_body)
    
    # 重新组装文件
    new_content = '---' + frontmatter + '---' + new_body
    
    # 写回文件
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    return True

def main():
    print("🔍 Scanning for repost tweets to fix...")
    
    fixed_count = 0
    total_count = 0
    
    for md_file in POSTS_DIR.rglob('*.md'):
        if 'From X (@' in md_file.read_text(encoding='utf-8'):
            total_count += 1
            if fix_repost_format(md_file):
                fixed_count += 1
    
    print(f"\n✅ Fixed {fixed_count} out of {total_count} repost tweets")

if __name__ == '__main__':
    main()
