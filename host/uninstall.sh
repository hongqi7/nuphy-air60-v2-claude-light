#!/bin/bash
# Remove the Claude Code hooks and the reconnect watcher, and turn the status lights off.
set -euo pipefail

HOST_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
AGENT_PLIST="$HOME/Library/LaunchAgents/local.claude-light.watch.plist"

if [ -f "$AGENT_PLIST" ]; then
    echo "==> removing reconnect watcher"
    launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
fi

if [ -f "$SETTINGS" ]; then
    echo "==> removing hooks from $SETTINGS"
    cp "$SETTINGS" "$SETTINGS.bak-claude-light-$(date +%Y%m%d%H%M%S)"
    python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    s = json.load(f)
hooks = s.get("hooks", {})
for event in list(hooks):
    hooks[event] = [e for e in hooks[event]
                    if not any("claude-light" in h.get("command", "") for h in e.get("hooks", []))]
    if not hooks[event]:
        del hooks[event]
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
PY
fi

"$HOST_DIR/claude-light" off </dev/null || true
echo "==> done. The firmware stays on the keyboard; with no signal it behaves like stock."
