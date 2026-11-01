#!/bin/bash
# Build kbled, add the Claude Code hooks and (optionally) the reconnect watcher.
#   ./install.sh              hooks + watcher
#   ./install.sh --no-agent   hooks only
set -euo pipefail

HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
AGENT_LABEL="local.claude-light.watch"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
KEYBOARD="${CLAUDE_LIGHT_KEYBOARD:-Air60 V2}"

echo "==> building kbled"
clang -O2 -o "$HOST_DIR/kbled" "$HOST_DIR/kbled.c" -framework IOKit -framework CoreFoundation
chmod +x "$HOST_DIR/claude-light"

echo "==> adding hooks to $SETTINGS"
mkdir -p "$HOME/.claude"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak-claude-light-$(date +%Y%m%d%H%M%S)"
python3 - "$SETTINGS" "$HOST_DIR/claude-light" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})

def add(event, arg, matcher=None):
    entries = hooks.setdefault(event, [])
    # drop an earlier claude-light entry so re-running install stays idempotent
    entries[:] = [e for e in entries
                  if not any("claude-light" in h.get("command", "") for h in e.get("hooks", []))]
    entry = {"hooks": [{"type": "command", "command": f"{cmd} {arg}", "timeout": 5}]}
    if matcher:
        entry["matcher"] = matcher
    entries.append(entry)

add("UserPromptSubmit", "working")
add("PostToolUse", "working", "*")
add("PreToolUse", "attention", "AskUserQuestion")
add("Notification", "attention", "permission_prompt")
add("Stop", "done")
add("SessionEnd", "end")

with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
PY

if [ "${1:-}" = "--no-agent" ]; then
    echo "==> skipping the reconnect watcher (--no-agent)"
else
    echo "==> installing reconnect watcher ($AGENT_PLIST)"
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.claude/claude-light"
    cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOST_DIR/kbled</string>
        <string>watch</string>
        <string>$KEYBOARD</string>
        <string>$HOST_DIR/claude-light show &lt;/dev/null</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$HOME/.claude/claude-light/watch.log</string>
</dict>
</plist>
EOF
    launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    launchctl load "$AGENT_PLIST"
fi

echo "==> done. Keyboards seen:"
"$HOST_DIR/kbled" list | grep '^\['
