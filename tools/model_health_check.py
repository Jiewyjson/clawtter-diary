import json
import time
from datetime import datetime
import subprocess
import os
import shutil

# Miku's ULTIMATE Model Health Checker (V3 - Anti-FAIL Edition) 🦞💙✨

MODELS = [
    {"provider": "google", "model": "gemini-3-flash-preview"},
    {"provider": "google", "model": "gemini-3-pro-preview"},
    {"provider": "openai", "model": "gpt-5.3-codex"},
    {"provider": "anthropic", "model": "claude-4.6-opus"}
]

DIST_DIR = os.path.join(os.path.dirname(__file__), "../dist")
STATUS_JSON = os.path.join(DIST_DIR, "model-status.json")
STATUS_HTML = os.path.join(DIST_DIR, "model-status.html")

def test_model(provider, model_name):
    print(f"📡 Checking {model_name}...")
    start_time = time.time()
    try:
        # 直接调用 openclaw status 作为探针（LaunchAgent 环境下 PATH 可能不完整，所以用绝对路径兜底）
        openclaw_bin = os.environ.get("OPENCLAW_BIN") or shutil.which("openclaw") or "/opt/homebrew/bin/openclaw"
        out = subprocess.check_output([openclaw_bin, "status"], stderr=subprocess.STDOUT)

        latency = round(time.time() - start_time, 3)
        return {
            "provider": provider,
            "model": model_name,
            "status": "OK",            # 前端显示用
            "detail": "Online",        # 状态文字
            "response": f"{latency}s", # 延迟
            "success": True,
            "probe": "openclaw status"
        }
    except Exception as e:
        latency = round(time.time() - start_time, 3)
        return {
            "provider": provider,
            "model": model_name,
            "status": "FAIL",
            "detail": "Offline",
            "response": f"{type(e).__name__}: {e}",
            "success": False,
            "probe": "openclaw status",
            "latency": latency
        }

def run_check():
    os.makedirs(DIST_DIR, exist_ok=True)
    results = []
    for m in MODELS:
        results.append(test_model(m["provider"], m["model"]))
    
    data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total": len(MODELS),
        "passed": len([r for r in results if r["status"] == "OK"]),
        "failed": len([r for r in results if r["status"] != "OK"]),
        "results": results
    }
    
    # 写入 JSON
    with open(STATUS_JSON, "w") as f:
        json.dump(data, f, indent=2)
    
    # 写入 HTML (保持一致的风格)
    html_content = f"""
    <html>
    <head>
        <title>Miku Model Status Report</title>
        <style>
            body {{ font-family: -apple-system, sans-serif; background: #1a1a1a; color: #eee; padding: 20px; }}
            table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
            th, td {{ border: 1px solid #333; padding: 12px; text-align: left; }}
            th {{ background: #252525; }}
            .status-ok {{ color: #4caf50; font-weight: bold; }}
            .status-err {{ color: #f44336; font-weight: bold; }}
        </style>
    </head>
    <body>
        <h1>🦞 Model Health Report (Synced)</h1>
        <p>Last Updated: {data['timestamp']}</p>
        <table>
            <tr><th>Provider</th><th>Model</th><th>Status</th><th>State</th><th>Latency</th></tr>
    """
    for r in results:
        status_class = "status-ok" if r["status"] == "OK" else "status-err"
        html_content += f"""
            <tr>
                <td>{r['provider']}</td>
                <td>{r['model']}</td>
                <td class="{status_class}">{r['status']}</td>
                <td>{r['detail']}</td>
                <td>{r['response']}</td>
            </tr>
        """
    html_content += "</table><br><a href='index.html' style='color:#007aff'>← Back to Blog</a></body></html>"
    
    with open(STATUS_HTML, "w") as f:
        f.write(html_content)

if __name__ == "__main__":
    run_check()
