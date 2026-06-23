#!/usr/bin/env bash
# The actual (detached) retro work. Releases the lock on ANY exit, and stamps the 24h
# debounce ONLY after compact.py succeeds — so a crash/sleep/kill mid-run retries next turn.
#   1. compact.py — condense the recent conversations into a small feed. Deterministic, ZERO quota.
#   2. AI conversation review — only if CLAUDE_RETRO_LLM=1 + a token. Feeds the compacted feed
#      to a headless `claude -p` and SAVES the report (no auto-apply, a human reads it). Runs from
#      $HOME so the project's hooks/skills/CLAUDE.md aren't loaded (no recursion + minimal context).
#      NOTE: do NOT add `--bare` — on the CLI it disables CLAUDE_CODE_OAUTH_TOKEN auth ("Not logged in").
# Every skip/failure is LOGGED to retro.log with the fix — no silent dead ends.
set -uo pipefail

RETRO_DIR="${HOME}/.claude/retro"
LOCK="${RETRO_DIR}/.lock"
STAMP="${RETRO_DIR}/.last"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATE_TAG="$(date +%F)"
log() { echo "$(date '+%F %T') retro: $*" >> "$RETRO_DIR/retro.log"; }

trap 'rm -rf "$LOCK"' EXIT   # always release the lock, however we exit

# Compact the unreviewed conversations since the last checkpoint (deterministic, free). Stamp the
# 24h debounce only on success, so a crash/kill mid-run retries next turn instead of skipping.
if python3 "$SCRIPT_DIR/compact.py" >>"$RETRO_DIR/retro.log" 2>&1; then
  touch "$STAMP"
else
  log "compact pass failed; will retry next turn"
  exit 0
fi

# When running from launchd (LaunchAgent backstop), Claude Code's env block is not injected.
# Fall back to reading both values directly from settings.local.json.
LOCAL="${HOME}/.claude/settings.local.json"
if [[ "${CLAUDE_RETRO_LLM:-0}" != "1" && -f "$LOCAL" ]]; then
  CLAUDE_RETRO_LLM=$(python3 -c "import json;print(json.load(open('$LOCAL')).get('env',{}).get('CLAUDE_RETRO_LLM','0'))" 2>/dev/null || echo "0")
fi
if [[ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" && -f "$LOCAL" ]]; then
  CLAUDE_CODE_OAUTH_TOKEN=$(python3 -c "import json;print(json.load(open('$LOCAL')).get('env',{}).get('CLAUDE_CODE_OAUTH_TOKEN',''))" 2>/dev/null || echo "")
  [[ -n "$CLAUDE_CODE_OAUTH_TOKEN" ]] && export CLAUDE_CODE_OAUTH_TOKEN
fi

[[ "${CLAUDE_RETRO_LLM:-0}" == "1" ]] || { log "AI review off (set CLAUDE_RETRO_LLM=1 + a token to enable)"; exit 0; }

# launchd runs with a stripped PATH — expand it with common install locations before checking for claude.
for _d in /usr/local/bin /opt/homebrew/bin "$HOME/.npm-global/bin" "$HOME/.local/bin" "$HOME/bin" /usr/bin; do
  [[ -d "$_d" ]] && export PATH="$_d:$PATH"
done
unset _d

command -v claude >/dev/null 2>&1 || { log "AI review skipped: 'claude' not on PATH (checked /usr/local/bin, /opt/homebrew/bin, ~/.npm-global/bin, ~/.local/bin)"; exit 0; }

FEED="$RETRO_DIR/conversations-${DATE_TAG}.md"
ENVELOPE="$RETRO_DIR/.review-${DATE_TAG}.json"
MD="$RETRO_DIR/conversation-review-${DATE_TAG}.md"
[[ -s "$FEED" ]] || { log "AI review skipped: no compacted feed at $FEED"; exit 0; }

# Whole prompt (instruction + the compacted feed) via STDIN — the feed is far too big for an argv
# arg. --bare skips hooks/skills/CLAUDE.md so this headless run can't re-fire the Stop hook.
{ cat "$SCRIPT_DIR/prompt.md"; printf '\n\n--- CONVERSATION FEED (last 24h) ---\n'; cat "$FEED"; } \
  | (cd "$HOME" && claude -p --output-format json) > "$ENVELOPE" 2>>"$RETRO_DIR/retro.log" || true

# Write the report on success, or log an actionable error and clean up the half-files.
python3 - "$ENVELOPE" "$MD" "$RETRO_DIR/retro.log" <<'PY'
import json, os, sys
env_path, md_path, log_path = sys.argv[1:4]
def log(msg): open(log_path, "a").write(msg + "\n")
try:
    data = json.load(open(env_path))
except Exception as exc:
    log(f"{__import__('datetime').date.today()} retro: unreadable claude envelope ({exc})")
    sys.exit(0)
result = data.get("result", "")
if data.get("is_error"):
    log(f"retro: AI review failed — {result!r}")
    if "logged in" in result.lower():
        log("retro: headless `claude -p` is NOT authenticated by the interactive login. "
            "Run `claude setup-token`, then `export CLAUDE_CODE_OAUTH_TOKEN=<token>` in the shell "
            "that launches Claude Code. Creating the token alone is not enough.")
    for path in (env_path, md_path):
        try: os.remove(path)
        except OSError: pass
    sys.exit(0)
open(md_path, "w").write(result)
try: os.remove(env_path)
except OSError: pass
log(f"retro: wrote {md_path} (cost ${data.get('total_cost_usd')})")
PY

# Report written → advance the watermark (so these conversations aren't re-reviewed), refresh the
# navigable entry points, and notify. All independent of any session hook, so they surface even in
# a long-open session.
if [[ -f "$MD" ]]; then
  cp -f "$RETRO_DIR/.feed-max-ts" "$RETRO_DIR/.checkpoint" 2>/dev/null || true

  # Navigable entry points so reports aren't just buried date-stamped files in a hidden folder:
  #   latest.md — stable symlink to the newest review (relative target → survives a dir move).
  #   INDEX.md  — newest-first list, one upserted row per date; open once and click through history.
  ln -sf "conversation-review-${DATE_TAG}.md" "$RETRO_DIR/latest.md"
  python3 - "$RETRO_DIR/INDEX.md" "$DATE_TAG" "conversation-review-${DATE_TAG}.md" "$FEED" "$MD" <<'PY'
import re, sys
index_path, date_tag, review_name, feed_path, md_path = sys.argv[1:6]

def read(path):
    try:
        with open(path) as fh: return fh.read()
    except OSError: return ""

# Session count is always in the feed header ("… — N sessions"). Finding count is best-effort from
# F<n> markers (e.g. "F1", "### F2") — omitted when the review doesn't use that style, never guessed.
sessions = re.search(r"(\d+)\s+sessions", read(feed_path).split("\n", 1)[0])
findings = len(set(re.findall(r"(?im)^\s*(?:[-*]\s+|#{2,4}\s+)?\**[EFMS](\d+)\b", read(md_path))))
parts = ([f"{sessions.group(1)} sessions"] if sessions else []) + ([f"{findings} findings"] if findings else [])
row = f"- [{date_tag}]({review_name})" + (" — " + ", ".join(parts) if parts else "")

HEADER = ("# Retro reviews\n\n"
          "Newest first — open this file and click a date to read that day's review. "
          "`latest.md` always points at the most recent.\n")

# Upsert by date: one row per date (same-day re-run replaces its row), sorted newest-first.
rows = {}
for line in read(index_path).splitlines():
    match = re.match(r"^- \[(\d{4}-\d{2}-\d{2})\]", line)
    if match: rows[match.group(1)] = line
rows[date_tag] = row
ordered = "\n".join(rows[date] for date in sorted(rows, reverse=True))
with open(index_path, "w") as fh:
    fh.write(HEADER + "\n" + ordered + "\n")
PY

  if command -v terminal-notifier >/dev/null 2>&1; then
    # terminal-notifier supports --open so clicking the notification opens the review file directly.
    terminal-notifier \
      -title "Claude Code retro" \
      -subtitle "Conversation review for ${DATE_TAG} ready" \
      -message "Click to open" \
      -open "file://${MD}" \
      -sound "Submarine" >/dev/null 2>&1 || true
    log "macOS notification fired via terminal-notifier (click opens review file)"
  elif command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"Open ~/.claude/retro/INDEX.md to read it.\" with title \"Claude Code retro\" subtitle \"Conversation review for ${DATE_TAG} ready\" sound name \"Submarine\"" >/dev/null 2>&1 || true
    log "macOS notification fired (requires terminal app notification permission — see doctor.sh if silent)"
  fi
fi
