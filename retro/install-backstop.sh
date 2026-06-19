#!/usr/bin/env bash
# Install the launchd daily backstop (macOS). Runs retro-run.sh once a day at 10:00 AM —
# covers long-running sessions where the Stop hook never fires. launchd doesn't inject
# Claude Code's env block, so retro-run.sh reads the token + flag directly from
# settings.local.json as a fallback. Reversible.
set -euo pipefail

LABEL="com.claudecode.retro"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
BASH="$(command -v bash || true)"
LOG="${HOME}/.claude/retro/retro.log"

if [[ -z "$BASH" ]]; then
  echo "bash not on PATH; cannot install backstop" >&2
  exit 1
fi
mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/.claude/retro"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BASH}</string>
    <string>${SCRIPT_DIR}/retro-run.sh</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_RETRO_LLM</key><string>1</string>
  </dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>${LOG}</string>
  <key>StandardErrorPath</key><string>${LOG}</string>
  <key>ProcessType</key><string>Background</string>
</dict>
</plist>
EOF

DOMAIN="gui/$(id -u)"
launchctl bootout "${DOMAIN}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "${DOMAIN}" "$PLIST"
echo "installed ${LABEL} — daily 10:00, run-on-wake."
echo "  test now:  launchctl kickstart -k ${DOMAIN}/${LABEL}"
echo "  remove:    launchctl bootout ${DOMAIN}/${LABEL} && rm '${PLIST}'"
