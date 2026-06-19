# claude-code-learning

Claude Code gets better at working with you over time. This tool reviews your recent conversations daily, surfaces what's going wrong, and proposes fixes. Everything stays local — nothing is auto-applied.

## How it works

Three triggers, all pointing at the same pipeline:

1. **Stop hook** — fires when you close a Claude Code session. Runs at most once per 24h.
2. **LaunchAgent (macOS)** — fires daily at 10am regardless of whether you ever close Claude Code. Catches long-running sessions.
3. **`/claude-learning:review-conversations`** — on-demand, any time you want.

The pipeline:

```
compact.py (free)  →  claude -p review  →  ~/.claude/retro/conversation-review-<date>.md
                                        →  macOS notification + in-Claude banner
```

`compact.py` condenses raw transcripts ~22–26× so the full review fits in one pass. A checkpoint watermark ensures nothing is reviewed twice (capped at 14 days backlog).

## Install

### Option 1 — Claude Code plugin (recommended)

Add the Unifyapps marketplace once inside Claude Code:

```
/plugin marketplace add github:unify-apps/claude-code-learning
/plugin install claude-learning@unifyapps
```

`/claude-learning:review-conversations` is available immediately. Hooks are registered automatically.

Then run this once in terminal to enable the daily background review and token setup (~2 min):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/unify-apps/claude-code-learning/main/setup.sh)
```

### Option 2 — setup.sh only (no plugin)

```bash
git clone https://github.com/unify-apps/claude-code-learning.git /tmp/cl
bash /tmp/cl/setup.sh
```

`setup.sh` handles everything in one interactive flow — scripts, hooks, LaunchAgent, token, and a self-check at the end.

## Verify

```bash
bash ~/.claude/retro/doctor.sh
```

Prints PASS/FAIL per step with the exact fix for anything broken.

## Platform support

| | macOS | Linux | Windows |
|---|---|---|---|
| Stop hook | ✓ | ✓ | ✓ (WSL) |
| On-demand skill | ✓ | ✓ | ✓ (WSL) |
| LaunchAgent backstop | ✓ | — | — |
| System notification | ✓ | — | — |

On Linux, add a cron backstop manually:
```bash
@daily bash ~/.claude/retro/retro-run.sh >> ~/.claude/retro/retro.log 2>&1
```

## Files

| File | What it does |
|------|-------------|
| `setup.sh` | One-command global install. Idempotent. |
| `retro/compact.py` | Compacts raw transcripts ~22–26× into a feed. Free, zero API quota. |
| `retro/retro-maybe.sh` | Stop hook entrypoint: 24h debounce + lock + detach. ~165ms overhead. |
| `retro/retro-run.sh` | Background worker: compact + AI review + notify. |
| `retro/retro-notify.sh` | UserPromptSubmit hook: in-Claude "review ready" banner. |
| `retro/install-backstop.sh` | Registers the macOS LaunchAgent. |
| `retro/doctor.sh` | Full setup verification with actionable fixes. |
| `retro/prompt.md` | System prompt for the headless AI review. |
| `plugins/claude-learning/` | Claude Code plugin (skill + hooks + marketplace manifest). |

## Reports (all local, never committed)

```
~/.claude/retro/
  conversations-<date>.md          compacted feed
  conversation-review-<date>.md    AI review report
  INDEX.md                         newest-first navigable index
  latest.md                        symlink to most recent report
  retro.log                        run log with timestamps and costs
```

## Turn it off

| What | How |
|---|---|
| Stop hook | Remove `Stop` entry from `~/.claude/settings.json` |
| Notify hook | Remove `UserPromptSubmit` entry from `~/.claude/settings.json` |
| LaunchAgent | `launchctl bootout gui/$(id -u)/com.claudecode.retro` |
| AI review only | Remove `CLAUDE_RETRO_LLM` from `~/.claude/settings.local.json` |
| Plugin | `/plugin uninstall claude-learning` |

## Do / Don't

**Do:**
- Open `~/.claude/retro/INDEX.md` to browse all reports.
- Run `/claude-learning:review-conversations` any time for an on-demand deep review.
- Apply only the changeset items you agree with — nothing is auto-applied.
- Add a quick alias:
  ```bash
  alias retro='open ~/.claude/retro/INDEX.md 2>/dev/null || open ~/.claude/retro'
  ```

**Don't:**
- Commit or share your token — treat it as a password.
- Put `[session]` items in a committed repo `CLAUDE.md` — they're local only.
- Expect web/desktop Claude sessions to appear — only terminal Claude Code sessions are reviewed.
