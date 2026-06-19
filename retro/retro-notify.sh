#!/usr/bin/env bash
# UserPromptSubmit hook. Fires on EVERY prompt (so it works even in a session left open for days,
# which SessionStart wouldn't). If a NEW conversation-review report exists that hasn't been
# surfaced yet, it prints a short note — UserPromptSubmit adds stdout to the session as context,
# so Claude sees it and can tell the user. Quiet (exit 0, no output) the rest of the time.
# A "seen" marker means it surfaces each report at most once.
set -euo pipefail

RD="${HOME}/.claude/retro"
SEEN="${RD}/.review-seen"

latest="$(ls -1t "$RD"/conversation-review-*.md 2>/dev/null | head -1 || true)"
[ -n "$latest" ] || exit 0

# Already surfaced this (or an even newer) report? stay quiet.
if [ -f "$SEEN" ] && [ ! "$latest" -nt "$SEEN" ]; then
  exit 0
fi
touch "$SEEN"

echo "[retro] A new Claude Code conversation-review report is ready: ${latest}"
echo "[retro] Briefly let the user know it's available and offer to open or summarize it, then continue with their request."
