# claude-learning plugin

Automatic daily review of your Claude Code conversations. Surfaces patterns, mistakes, and improvements so Claude gets better at working with you over time.

## Install

Add the Unifyapps marketplace once:
```
/plugin marketplace add github:unifyapps/claude-code-learning
```

Install the plugin:
```
/plugin install claude-learning@unifyapps
```

## Use

On-demand review (works immediately after install):
```
/claude-learning:review-conversations
```

## Full automation (daily background review)

The plugin registers hooks automatically. To also enable the daily background review and macOS notifications, run once in terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/unifyapps/claude-code-learning/main/setup.sh)
```

This installs the background scripts and LaunchAgent. Never needed again after that.

## What it does

- **On session end (Stop hook):** compacts your conversations and triggers an AI review once per 24h
- **On next prompt (UserPromptSubmit hook):** surfaces a one-line "review ready" banner inside Claude
- **Daily at 10am (LaunchAgent):** backup trigger for long-running sessions that never close
- **`/claude-learning:review-conversations`:** on-demand deep review, any time

All reports are saved locally to `~/.claude/retro/`. Nothing is auto-applied.
