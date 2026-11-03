#!/bin/bash
# Build kbled, add the agent hooks and (optionally) the reconnect watcher.
# Claude Code always gets hooks; WorkBuddy and Devin get them too when their config folders exist.
#   ./install.sh              hooks + watcher
#   ./install.sh --no-agent   hooks only
set -euo pipefail

HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LABEL="local.claude-light.watch"
AGENT_PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
KEYBOARD="${CLAUDE_LIGHT_KEYBOARD:-NuPhy}"
STAMP="$(date +%Y%m%d%H%M%S)"

echo "==> building kbled"
clang -O2 -o "$HOST_DIR/kbled" "$HOST_DIR/kbled.c" -framework IOKit -framework CoreFoundation
chmod +x "$HOST_DIR/claude-light"

# add_hooks <settings file> <agent name or ""> <event:state[:matcher]>...
add_hooks() {
    local path="$1" agent="$2"
    shift 2
    echo "==> adding hooks to $path"
    mkdir -p "$(dirname "$path")"
    [ -f "$path" ] || echo '{}' > "$path"
    cp -p "$path" "$path.bak-claude-light-$STAMP"
    python3 - "$path" "$HOST_DIR/claude-light" "$agent" "$@" <<'PY'
import json, sys
path, cmd, agent, specs = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
with open(path) as f:
    s = json.load(f)
hooks = s.setdefault("hooks", {})
for spec in specs:
    event, state, *matcher = spec.split(":", 2)
    entries = hooks.setdefault(event, [])
    # drop an earlier claude-light entry so re-running install stays idempotent
    entries[:] = [e for e in entries
                  if not any("claude-light" in h.get("command", "") for h in e.get("hooks", []))]
    command = f"{cmd} {state} {agent}".rstrip()
    entry = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
    if matcher:
        entry["matcher"] = matcher[0]
    # go first, ahead of slow hooks on the same event (e.g. one that waits for an approval)
    entries.insert(0, entry)
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
PY
}

add_hooks "$HOME/.claude/settings.json" "" \
    UserPromptSubmit:working 'PostToolUse:working:*' PreToolUse:attention:AskUserQuestion \
    Notification:attention:permission_prompt Stop:done SessionEnd:end

# WorkBuddy uses Claude Code's hook format and events
if [ -d "$HOME/.workbuddy" ]; then
    add_hooks "$HOME/.workbuddy/settings.json" workbuddy \
        UserPromptSubmit:working PostToolUse:working PermissionRequest:attention \
        Notification:attention:permission_prompt Stop:done StopFailure:done SessionEnd:end
fi

# Devin drops the whole hooks object if it names an event it doesn't know (Notification, StopFailure...)
if [ -d "$HOME/.config/devin" ]; then
    add_hooks "$HOME/.config/devin/config.json" devin \
        UserPromptSubmit:working PostToolUse:working PermissionRequest:attention Stop:done SessionEnd:end
fi

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
