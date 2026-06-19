#!/usr/bin/env bash
# Stop-hook entrypoint. Runs on every turn, so it MUST be near-instant:
#   1. debounce — if the last SUCCESSFUL retro was <24h ago, exit (a stat()).
#   2. single-flight — if a run is already in progress, exit (atomic mkdir lock;
#      no flock on macOS). Stale locks (>1h, i.e. a dead run) are reclaimed.
#   3. otherwise launch retro-run.sh DETACHED. It stamps .last only on success and
#      removes the lock, so a failed/killed run retries next turn instead of
#      silently burning the 24h window.
set -euo pipefail

RETRO_DIR="${HOME}/.claude/retro"
STAMP="${RETRO_DIR}/.last"
LOCK="${RETRO_DIR}/.lock"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$RETRO_DIR"

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

if [[ -f "$STAMP" ]]; then
  if (( $(date +%s) - $(mtime "$STAMP") < 86400 )); then
    exit 0
  fi
fi

# Atomic lock. If it exists and is fresh, a run is live → bail. If stale, reclaim it.
if ! mkdir "$LOCK" 2>/dev/null; then
  if (( $(date +%s) - $(mtime "$LOCK") < 3600 )); then
    exit 0
  fi
  rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || exit 0
fi

# nohup + & detaches from the controlling terminal so closing it can't kill the run.
nohup bash "$SCRIPT_DIR/retro-run.sh" >>"$RETRO_DIR/retro.log" 2>&1 &
exit 0
