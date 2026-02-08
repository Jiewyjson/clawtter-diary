import json
import os
import subprocess
from pathlib import Path

OPENCLAW_DIR = Path("/home/tetsuya/.openclaw")
CONFIG_PATH = OPENCLAW_DIR / "openclaw.json"
SESSIONS_PATH = OPENCLAW_DIR / "agents/main/sessions/sessions.json"

def get_config():
    with open(CONFIG_PATH, 'r') as f:
        return json.load(f)

def save_config(config):
    with open(CONFIG_PATH, 'w') as f:
        json.dump(config, f, indent=2)

def update_primary_model(provider_model_str):
    """provider_model_str pattern: 'provider/model_id'"""
    config = get_config()
    config['agents']['defaults']['model']['primary'] = provider_model_str
    save_config(config)
    return True

def break_session_locks(provider_name, model_id):
    """Forces all sessions to use the new model"""
    if not SESSIONS_PATH.exists():
        return False
    
    with open(SESSIONS_PATH, 'r') as f:
        sessions = json.load(f)
    
    modified = False
    for session_id, data in sessions.items():
        # Only touch active user sessions
        if "modelProvider" in data:
            data["modelProvider"] = provider_name
            data["model"] = model_id
            # Also update the snapshot report if exists
            if "systemPromptReport" in data:
                data["systemPromptReport"]["provider"] = provider_name
                data["systemPromptReport"]["model"] = model_id
            modified = True
            
    if modified:
        with open(SESSIONS_PATH, 'w') as f:
            json.dump(sessions, f, indent=2)
    return True

def restart_service():
    try:
        subprocess.run(["systemctl", "--user", "restart", "openclaw-gateway"], check=True)
        return True
    except Exception as e:
        print(f"Error restarting: {e}")
        return False

def list_all_models():
    config = get_config()
    providers = config.get('models', {}).get('providers', {})
    model_list = []
    
    for p_name, p_config in providers.items():
        for m in p_config.get('models', []):
            model_list.append({
                "full_id": f"{p_name}/{m['id']}",
                "provider": p_name,
                "model_id": m['id'],
                "name": m.get('name', m['id'])
            })
    return model_list

if __name__ == "__main__":
    # This can be used as a CLI or imported by a web server
    import sys
    if len(sys.argv) > 1:
        target = sys.argv[1] # e.g. "google/gemini-2.5-flash"
        p, m = target.split('/')
        print(f"🔄 Switching primary to {target}...")
        update_primary_model(target)
        print("🔓 Breaking session locks...")
        break_session_locks(p, m)
        print("⚡ Restarting OpenClaw...")
        restart_service()
        print("✅ Done!")
