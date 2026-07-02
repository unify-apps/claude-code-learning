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

# Weekly self-update: pull latest scripts from GitHub so existing installs stay current.
# Downloads everything to a temp dir first — nothing is replaced unless all files land cleanly.
# Stamp is only touched on success, so a network outage retries on the next run (not next week).
_update_stamp="$RETRO_DIR/.update-last"
_repo_raw="https://raw.githubusercontent.com/unify-apps/claude-code-learning/main/retro"
if [[ ! -f "$_update_stamp" ]] || find "$_update_stamp" -mtime +6 -print -quit 2>/dev/null | grep -q .; then
  _tmp=$(mktemp -d)
  _ok=1
  for _f in compact.py retro-run.sh retro-maybe.sh retro-notify.sh install-backstop.sh doctor.sh prompt.md WORKFLOW.md; do
    curl -fsSL "$_repo_raw/$_f" -o "$_tmp/$_f" 2>/dev/null || { _ok=0; break; }
  done
  if (( _ok )); then
    for _f in compact.py retro-run.sh retro-maybe.sh retro-notify.sh install-backstop.sh doctor.sh prompt.md WORKFLOW.md; do
      mv "$_tmp/$_f" "$RETRO_DIR/$_f"
      [[ "$_f" == *.sh ]] && chmod +x "$RETRO_DIR/$_f"
    done
    touch "$_update_stamp"
    log "weekly update: scripts refreshed from GitHub"
  else
    log "weekly update: GitHub unreachable — will retry next run"
  fi
  rm -rf "$_tmp"
  unset _ok _f _tmp
fi
unset _update_stamp _repo_raw

# Compact the unreviewed conversations since the last checkpoint (deterministic, free).
# Stamp the 24h debounce only after the review is written — if the AI call fails (e.g. network
# not ready at 10am after wake-from-sleep), the Stop hook retries on the next session close.
# Re-running compact on retry is harmless: it's free, deterministic, and reads the same files.
COMPACT_OUT=$(python3 "$SCRIPT_DIR/compact.py" 2>>"$RETRO_DIR/retro.log")
COMPACT_EXIT=$?
echo "$COMPACT_OUT" >> "$RETRO_DIR/retro.log"
if [[ $COMPACT_EXIT -eq 0 ]]; then
  FEED=$(echo "$COMPACT_OUT" | grep -oE '[^ ]+conversations-[0-9-]+\.md' | tail -1 || true)
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

ENVELOPE="$RETRO_DIR/.review-${DATE_TAG}.json"
MD="$RETRO_DIR/conversation-review-${DATE_TAG}.md"
[[ -n "$FEED" && -s "$FEED" ]] || { log "AI review skipped: no compacted feed found (compact output: $(echo "$COMPACT_OUT" | tail -1))"; exit 0; }

# Whole prompt (instruction + the compacted feed) via STDIN — the feed is far too big for an argv arg.
# Runs from $HOME so no project CLAUDE.md or hooks are loaded — prevents the Stop hook re-firing.
# Retries up to 3 times on connectivity errors (handles LaunchAgent firing before network is ready
# after wake-from-sleep — network typically comes up within 30-60s).
_retries=3
for _attempt in 1 2 3; do
  { cat "$SCRIPT_DIR/prompt.md"; printf '\n\n--- CONVERSATION FEED (last 24h) ---\n'; cat "$FEED"; } \
    | (cd "$HOME" && claude -p --output-format json) > "$ENVELOPE" 2>>"$RETRO_DIR/retro.log" || true
  _conn_err=$(python3 -c "
import json, sys
try:
    d = json.load(open('$ENVELOPE'))
    r = d.get('result', '')
    print('1' if d.get('is_error') and any(x in r for x in ['ConnectionRefused','Unable to connect','Connection closed']) else '0')
except: print('0')
" 2>/dev/null || echo "0")
  [[ "$_conn_err" == "1" ]] && (( _attempt < _retries )) || break
  log "AI review attempt $_attempt/$_retries failed (network not ready) — retrying in 30s"
  sleep 30
done
unset _retries _attempt _conn_err

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

# Report written → stamp the 24h debounce, advance the watermark, refresh navigable entry points,
# and notify. All independent of any session hook, so they surface even in a long-open session.
if [[ -f "$MD" ]]; then
  touch "$STAMP"
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

  # osascript fires on all macOS — guaranteed delivery regardless of terminal-notifier health.
  # terminal-notifier adds a clickable "open in Finder" action on top when installed; it exits 0
  # even when it delivers nothing (broken on some macOS versions), so we can't use it as the
  # sole notifier without risking silent failure.
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"Open ~/.claude/retro/INDEX.md to read it.\" with title \"Claude Code retro\" subtitle \"Conversation review for ${DATE_TAG} ready\" sound name \"Submarine\"" >/dev/null 2>&1 || true
    log "macOS notification sent via osascript — if no banner: System Settings → Notifications → Script Editor → Alert style: Banners/Temporary"
  fi
  if command -v terminal-notifier >/dev/null 2>&1; then
    terminal-notifier \
      -title "Claude Code retro" \
      -subtitle "Conversation review for ${DATE_TAG} ready" \
      -message "Click to open in Finder" \
      -execute "open -R \"${MD}\"" \
      -sound "Submarine" >/dev/null 2>&1 || true
    log "macOS notification sent via terminal-notifier (clickable) — if no banner: System Settings → Notifications → terminal-notifier → Alert style: Banners"
  fi
fi
