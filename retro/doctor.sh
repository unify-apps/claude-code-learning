#!/usr/bin/env bash
# doctor.sh — self-verifying check for the retro automatic-review setup.
# Checks the global ~/.claude/ installation (not tied to any specific repo).
# Prints PASS / FAIL per link in the enablement chain, with the exact fix.
#
# Usage: bash ~/.claude/retro/doctor.sh [--no-exec]
#   --no-exec  skip the final headless probe (which makes one tiny billable `claude` call).
set -uo pipefail

LOCAL="$HOME/.claude/settings.local.json"
SETTINGS="$HOME/.claude/settings.json"
RUN_EXEC=1
[[ "${1:-}" == "--no-exec" ]] && RUN_EXEC=0

pass=0; fail=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n       fix: %s\n' "$1" "$2"; fail=$((fail+1)); }
note() { printf '  \033[33m•\033[0m %s\n' "$1"; }

echo "retro doctor — verifying automatic-review setup"
echo

# 1. ~/.claude/settings.local.json has both env vars.
flag="NONE"; tokstate="NONE"
if [[ -f "$LOCAL" ]]; then
  read -r flag tokstate < <(python3 - "$LOCAL" <<'PY'
import json, sys
try: env = json.load(open(sys.argv[1])).get("env", {})
except Exception: env = {}
print(env.get("CLAUDE_RETRO_LLM") or "NONE", "SET" if env.get("CLAUDE_CODE_OAUTH_TOKEN") else "NONE")
PY
)
else
  bad "no ~/.claude/settings.local.json" "run bash setup.sh"
fi
[[ "$flag" == "1" ]] && ok "CLAUDE_RETRO_LLM=1 in ~/.claude/settings.local.json" \
  || bad "CLAUDE_RETRO_LLM not set to 1 in ~/.claude/settings.local.json" \
         "run bash setup.sh to write it"
[[ "$tokstate" == "SET" ]] && ok "CLAUDE_CODE_OAUTH_TOKEN present in ~/.claude/settings.local.json" \
  || bad "CLAUDE_CODE_OAUTH_TOKEN missing in ~/.claude/settings.local.json" \
         "re-run bash setup.sh and complete the token step"

# 2. Scripts are installed to ~/.claude/retro/.
RETRO_DIR="$HOME/.claude/retro"
for f in compact.py retro-run.sh retro-maybe.sh retro-notify.sh; do
  if [[ -f "$RETRO_DIR/$f" ]]; then
    ok "~/.claude/retro/$f installed"
  else
    bad "~/.claude/retro/$f not found" "run bash setup.sh to reinstall"
  fi
done

# 3. Both hooks registered in ~/.claude/settings.json (global, fires for any project).
stop_ok=0; notify_ok=0
read -r stop_ok notify_ok < <(python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    stop   = "retro-maybe"  in json.dumps(data.get("hooks", {}).get("Stop", []))
    notify = "retro-notify" in json.dumps(data.get("hooks", {}).get("UserPromptSubmit", []))
    print("1" if stop else "0", "1" if notify else "0")
except Exception:
    print("0 0")
PY
)
[[ "$stop_ok" == "1" ]] \
  && ok "Stop hook registered in ~/.claude/settings.json (automatic review)" \
  || bad "Stop hook missing from ~/.claude/settings.json" "run bash setup.sh to register it"
[[ "$notify_ok" == "1" ]] \
  && ok "UserPromptSubmit hook registered (in-Claude report notification)" \
  || bad "UserPromptSubmit hook missing from ~/.claude/settings.json" \
         "run bash setup.sh — this hook is why in-Claude notifications don't appear"

# 4. LaunchAgent (macOS daily backstop).
if command -v launchctl >/dev/null 2>&1; then
  PLIST="$HOME/Library/LaunchAgents/com.claudecode.retro.plist"
  if [[ -f "$PLIST" ]]; then
    if launchctl list com.claudecode.retro >/dev/null 2>&1; then
      ok "LaunchAgent com.claudecode.retro loaded (daily 10:00 backstop active)"
    else
      bad "LaunchAgent plist exists but is not loaded" "run: launchctl bootstrap gui/$(id -u) '$PLIST'"
    fi
  else
    bad "LaunchAgent not installed (daily backstop missing)" "re-run bash setup.sh to install it"
  fi
else
  note "non-macOS — LaunchAgent check skipped"
fi

# 5. claude CLI reachable.
if command -v claude >/dev/null 2>&1; then ok "claude on PATH ($(command -v claude))"
else bad "claude not on PATH" "install the Claude Code CLI and ensure it's on PATH"; fi

# 6. Live injection check (informational — only meaningful when running inside Claude Code).
if [[ -n "${CLAUDE_RETRO_LLM:-}" ]]; then
  ok "live injection confirmed — CLAUDE_RETRO_LLM is in this subprocess (running inside Claude Code)"
else
  note "not running inside Claude Code — live env injection isn't active here; that's expected."
  note "  Check 1 (the file) is the launch-independent source of truth."
fi

# 7. End-to-end headless auth probe.
if (( RUN_EXEC )) && [[ "$tokstate" == "SET" ]]; then
  echo; note "running headless auth probe (one tiny billable claude call)…"
  realtok=$(python3 -c "import json;print(json.load(open('$LOCAL'))['env']['CLAUDE_CODE_OAUTH_TOKEN'])" 2>/dev/null)
  out=$(printf 'reply with exactly: OK' | CLAUDE_CODE_OAUTH_TOKEN="$realtok" claude -p --output-format json 2>/dev/null)
  if echo "$out" | python3 -c "import json,sys; sys.exit(0 if not json.load(sys.stdin).get('is_error') else 1)" 2>/dev/null; then
    ok "headless claude authenticates with the token — the review path works end-to-end"
  else
    err=$(echo "$out" | python3 -c "import json,sys; print((json.load(sys.stdin).get('result') or '')[:90])" 2>/dev/null)
    bad "headless claude FAILED to authenticate (${err:-no/blank response})" \
        "re-run bash setup.sh and complete the token step — the in-app login does NOT authenticate headless claude"
  fi
elif (( RUN_EXEC )); then
  note "skipped execution probe — fix the token check above first"
else
  note "execution probe skipped (--no-exec)"
fi

# 8. macOS notification permission — fire test notifications, user verifies visually.
# TCC database requires Full Disk Access to query — not available to normal processes.
# Best we can do: fire test notifications and tell the user what to look for.
if command -v osascript >/dev/null 2>&1; then
  _macos_major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1 || echo "0")
  osascript -e 'display notification "If you see this banner, Script Editor notifications are working." with title "retro doctor ✓" sound name "Submarine"' >/dev/null 2>&1 || true
  note "macOS: a Script Editor test notification was just fired."
  note "  ✓ saw a banner → notifications working."
  note "  ✗ no banner → System Settings → Notifications → Script Editor → Alert style: Banners/Temporary"
  # terminal-notifier 2.0.0 is broken on macOS 26 (Tahoe) and later — skip on those versions.
  if command -v terminal-notifier >/dev/null 2>&1 && (( _macos_major > 0 && _macos_major < 26 )); then
    terminal-notifier -title "retro doctor ✓" -message "If you see this, terminal-notifier notifications are working." -sound "Submarine" >/dev/null 2>&1 || true
    note "macOS: a terminal-notifier test notification was also fired (clickable review notifications)."
    note "  ✓ saw a banner → terminal-notifier working — click action will open review in Finder."
    note "  ✗ no banner → System Settings → Notifications → terminal-notifier → Alert style: Banners"
  fi
  note "  shortcut to open Notifications settings: open 'x-apple.systempreferences:com.apple.preference.notifications'"
  unset _macos_major
else
  note "non-macOS — system notifications skipped; in-Claude notification still works."
fi

echo
printf 'result: %d passed, %d failed\n' "$pass" "$fail"
if (( fail == 0 )); then
  echo "✅ automatic review is correctly wired."
  exit 0
fi
echo "❌ automatic review will NOT run until the ✗ items above are fixed."
exit 1
