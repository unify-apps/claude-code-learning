# claude-code-learning

Automatic conversation review for Claude Code — works for **any team** (frontend, backend, any repo).

After you code, this quietly compacts your recent Claude Code conversations and reviews them
automatically every 24h, saving a report you read. The same deep review is available on demand
as `/review-conversations`. Local, and free unless you opt into the AI review.

## What it does

A `Stop` hook fires after each turn, **at most once every 24h**, in the background:

1. **`compact.py`** (free, zero quota) — condenses every conversation since your last review into a
   small readable feed (~22–26× smaller). Nothing is skipped; a checkpoint watermark tracks what was
   already reviewed (capped at 14 days).
2. **AI review** (opt-in, needs a token) — feeds the compacted output to a headless `claude` and
   saves a report to `~/.claude/retro/conversation-review-<date>.md`. You read it; nothing is
   auto-applied. A macOS notification fires when the report lands, and your next prompt surfaces
   a one-line "review ready" note inside Claude.
3. **`/review-conversations`** — runs the same deep review interactively, any time you want.

The hooks are installed globally, so reviews cover **all projects** you work in, not just the repo
where you run the setup.

## Setup

**One command, ~2 minutes:**

```bash
git clone git@github.com:unifyapps/claude-code-learning.git /tmp/claude-learning
bash /tmp/claude-learning/setup.sh
```

Or if you received this as a zip / folder: `bash setup.sh` from inside it.

`setup.sh` does everything in one interactive flow:
1. Installs scripts → `~/.claude/retro/` (global; works in any repo)
2. Installs `/review-conversations` → `~/.claude/commands/`
3. Registers both hooks in `~/.claude/settings.json` (global)
4. Sets `CLAUDE_RETRO_LLM=1` in `~/.claude/settings.local.json`
5. Installs the macOS LaunchAgent daily backstop
6. Opens System Settings → Notifications, waits while you enable **Script Editor**
7. Runs `claude setup-token`, prompts for token paste, writes it
8. Runs `doctor.sh` to verify everything end-to-end

Open Claude Code in **any project** — `/review-conversations` works immediately.
Automatic review fires after the next session (24h debounce).

The token is needed only for the AI review. The free compaction runs without it.

## Verify the setup

```bash
bash ~/.claude/retro/doctor.sh
```

Prints PASS/FAIL per link in the enablement chain with the exact fix for anything broken.

## On Linux

The macOS launchd backstop is skipped automatically. The `Stop` hook still fires after every session.
For a daily backstop, add to crontab manually:

```bash
@daily bash ~/.claude/retro/retro-run.sh >> ~/.claude/retro/retro.log 2>&1
```

## Files

| File | What it does |
|------|-------------|
| `setup.sh` | One-command global install. Idempotent. |
| `configure-token.sh` | Interactive token setup. Run once per machine. |
| `retro/compact.py` | Compacts raw transcripts ~22–26× into the conversation feed. Free. |
| `retro/retro-maybe.sh` | Hook entrypoint: 24h debounce + lock + detach. Near-instant. |
| `retro/retro-run.sh` | Background worker: runs `compact.py`, then AI review if enabled. |
| `retro/retro-notify.sh` | `UserPromptSubmit` hook: surfaces "review ready" once per new report. |
| `retro/install-backstop.sh` | Registers the macOS launchd daily safety-net. |
| `retro/doctor.sh` | Verifies the full setup: env, scripts, hooks, claude CLI, auth probe. |
| `retro/prompt.md` | Instruction for the automatic headless AI review. |
| `commands/review-conversations.md` | The `/review-conversations` slash command. |

## Where reports go (all local, never committed)

```
~/.claude/retro/
  conversations-<date>.md          compacted feed (free pass)
  conversation-review-<date>.md    AI review report (token path)
  INDEX.md                         newest-first navigable index
  latest.md                        symlink to most recent report
  retro.log                        run log with timestamps and costs
```

## Turn it off

- **Stop hook:** remove the `Stop` entry from `~/.claude/settings.json`
- **Notify hook:** remove the `UserPromptSubmit` entry from `~/.claude/settings.json`
- **Daily backstop:** `launchctl bootout gui/$(id -u)/com.claudecode.retro` (macOS)
- **AI review only:** remove `CLAUDE_RETRO_LLM` from `~/.claude/settings.local.json` (free compaction still runs)

## Do / Don't

**Do:**
- Let it run — the compaction is silent and free.
- Open `~/.claude/retro/INDEX.md` to browse all reports (or `~/.claude/retro/latest.md` for the newest).
- Run `/review-conversations` any time for an on-demand deep review.
- Apply only the changeset items you agree with.
- Add a `retro` alias to `~/.zshrc` for quick access:
  ```bash
  retro() { open ~/.claude/retro/INDEX.md 2>/dev/null || open ~/.claude/retro 2>/dev/null || echo "no retro output yet"; }
  ```

**Don't:**
- Commit or share your token — treat it as a password.
- Put `[session]` changeset items in a committed repo `CLAUDE.md` — they describe your local harness.
- Expect web/desktop app sessions to be covered — only terminal Claude Code sessions appear in reviews.
