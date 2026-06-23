#!/usr/bin/env bash
# One-command setup for claude-code-learning. Run once per machine — that's it.
# Interactive (terminal): full setup including notification permission + token paste.
# Non-interactive (Claude's Bash tool): installs everything except the token step.
#
# Usage: bash setup.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RETRO_SRC="$SCRIPT_DIR/retro"
RETRO_DST="$HOME/.claude/retro"
GLOBAL_SETTINGS="$HOME/.claude/settings.json"
GLOBAL_LOCAL="$HOME/.claude/settings.local.json"
COMMANDS_DST="$HOME/.claude/commands"
INTERACTIVE=0; [[ -t 0 ]] && INTERACTIVE=1
REPO_RAW="https://raw.githubusercontent.com/unify-apps/claude-code-learning/main"

echo "claude-code-learning setup"
echo

# ── 1. Scripts ──────────────────────────────────────────────────────────────
mkdir -p "$RETRO_DST" "$COMMANDS_DST"
echo "installing scripts → $RETRO_DST"
# When invoked via `bash <(curl ...)`, BASH_SOURCE[0] is /dev/fd/N — no sibling dirs exist.
# Detect this and download files directly from GitHub instead of copying locally.
if [[ "$SCRIPT_DIR" == /dev/fd* ]] || [[ ! -d "$RETRO_SRC" ]]; then
  for f in compact.py retro-run.sh retro-maybe.sh retro-notify.sh install-backstop.sh doctor.sh prompt.md WORKFLOW.md; do
    curl -fsSL "$REPO_RAW/retro/$f" -o "$RETRO_DST/$f" || { echo "  ✗ failed to download $f" >&2; exit 1; }
    [[ "$f" == *.sh ]] && chmod +x "$RETRO_DST/$f"
  done
  curl -fsSL "$REPO_RAW/commands/review-conversations.md" -o "$COMMANDS_DST/review-conversations.md" || { echo "  ✗ failed to download review-conversations.md" >&2; exit 1; }
else
  for f in compact.py retro-run.sh retro-maybe.sh retro-notify.sh install-backstop.sh doctor.sh prompt.md WORKFLOW.md; do
    [[ -f "$RETRO_SRC/$f" ]] || { echo "  ✗ missing: $RETRO_SRC/$f" >&2; exit 1; }
    cp "$RETRO_SRC/$f" "$RETRO_DST/$f"
    [[ "$f" == *.sh ]] && chmod +x "$RETRO_DST/$f"
  done
  cp "$SCRIPT_DIR/commands/review-conversations.md" "$COMMANDS_DST/review-conversations.md"
fi
echo "  ✓ all scripts installed"

# ── 2. Global env flag ──────────────────────────────────────────────────────
python3 - "$GLOBAL_LOCAL" <<'PY'
import json, os, sys
path = sys.argv[1]
try: data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError): data = {}
env = data.setdefault("env", {})
changed = env.get("CLAUDE_RETRO_LLM") != "1"
env["CLAUDE_RETRO_LLM"] = "1"
if changed or not os.path.exists(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh: json.dump(data, fh, indent=2); fh.write("\n")
    print("  ✓ CLAUDE_RETRO_LLM=1 written")
else: print("  ✓ CLAUDE_RETRO_LLM=1 already set")
PY

# ── 3. Global hooks ─────────────────────────────────────────────────────────
python3 - "$GLOBAL_SETTINGS" <<'PY'
import json, os, sys
path = sys.argv[1]
try: data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError): data = {}
hooks = data.setdefault("hooks", {})
STOP  = 'bash "${HOME}/.claude/retro/retro-maybe.sh"'
NOTIF = 'bash "${HOME}/.claude/retro/retro-notify.sh"'
def has(event, marker): return any(marker in json.dumps(g) for g in hooks.get(event, []))
added = []
if not has("Stop", "retro-maybe"):
    hooks.setdefault("Stop", []).append({"hooks": [{"type": "command", "command": STOP, "timeout": 10}]}); added.append("Stop")
if not has("UserPromptSubmit", "retro-notify"):
    hooks.setdefault("UserPromptSubmit", []).append({"hooks": [{"type": "command", "command": NOTIF, "timeout": 5}]}); added.append("UserPromptSubmit")
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w") as fh: json.dump(data, fh, indent=2); fh.write("\n")
print("  ✓ hooks registered: " + ", ".join(added) if added else "  ✓ hooks already registered")
PY

# ── 4. LaunchAgent (macOS daily backstop) ───────────────────────────────────
if command -v launchctl >/dev/null 2>&1; then
    bash "$RETRO_DST/install-backstop.sh" 2>&1 | grep -E "^installed|error" | sed 's/^/  ✓ /'
else
    echo "  • Linux: add to crontab for daily backstop:"
    echo "    @daily bash ~/.claude/retro/retro-run.sh >> ~/.claude/retro/retro.log 2>&1"
fi
if ! command -v terminal-notifier >/dev/null 2>&1; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "  installing Homebrew (needed for terminal-notifier)..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    if command -v brew >/dev/null 2>&1; then
        echo "  installing terminal-notifier (makes notifications clickable)..."
        brew install terminal-notifier >/dev/null 2>&1 \
            && echo "  ✓ terminal-notifier installed" \
            || echo "  • terminal-notifier install failed — notifications will still work, just not clickable"
    fi
else
    echo "  ✓ terminal-notifier already installed"
fi
echo

# ── 5. macOS notification permission (interactive only) ─────────────────────
if command -v terminal-notifier >/dev/null 2>&1 && (( INTERACTIVE )); then
    echo "── notification permission ──────────────────────────────────────────────────"
    echo "  Sending a test notification — you need to allow it in System Settings."
    terminal-notifier -title "Claude Code retro" -message "Setup complete — allow notifications to see daily reviews." -sound "Submarine" 2>/dev/null || true
    open "x-apple.systempreferences:com.apple.preference.notifications" 2>/dev/null || true
    echo "  System Settings just opened → scroll to terminal-notifier → Alert style: Banners"
    echo
    printf "  Press Enter once you've set it (or Enter to skip): "
    read -r _
    echo
fi

# ── 6. Token setup (interactive only) ───────────────────────────────────────
if (( INTERACTIVE )); then
    existing_tok=$(python3 - "$GLOBAL_LOCAL" <<'PY' 2>/dev/null
import json, sys
try: tok = json.load(open(sys.argv[1])).get("env", {}).get("CLAUDE_CODE_OAUTH_TOKEN", "")
except Exception: tok = ""
print(tok)
PY
)
    if [[ -n "$existing_tok" && "$existing_tok" != "REPLACE_THIS_WITH_YOUR_TOKEN" ]]; then
        echo "  ✓ token already configured — skipping"
    elif ! command -v claude >/dev/null 2>&1; then
        echo "── token setup — claude CLI not found ──────────────────────────────────────"
        echo "  The AI review needs the claude CLI to be installed."
        echo
        echo "  Install it:  npm install -g @anthropic-ai/claude-code"
        echo "  Then re-run: bash <(curl -fsSL https://raw.githubusercontent.com/unify-apps/claude-code-learning/main/setup.sh)"
        echo
    else
        echo "── token setup ─────────────────────────────────────────────────────────────"
        echo "  The background review calls claude headlessly (without the app open)."
        echo "  This needs a long-lived token — different from your normal Claude login."
        echo
        echo "  What happens next:"
        echo "  1. 'claude setup-token' runs below in this same terminal"
        echo "  2. It may open a browser to confirm your Claude account — do that, then"
        echo "     return to this terminal"
        echo "  3. A token starting with sk-ant-oat... will appear in the output"
        echo "  4. Copy that token and paste it at the prompt that follows"
        echo
        printf "  Press Enter to continue: "
        read -r _
        echo
        echo "  ── running claude setup-token ──────────────────────────────────────────"
        claude setup-token
        echo "  ── token output ends above ─────────────────────────────────────────────"
        echo
        printf "  Paste the sk-ant-oat... token here (hidden, won't echo): "
        IFS= read -r -s token; echo
        if [[ -z "$token" ]]; then
            echo "  • skipped — re-run this script any time to set the token."
        elif [[ "$token" != sk-ant-oat* ]]; then
            echo "  ✗ token should start with 'sk-ant-oat' — re-run this script to retry." >&2
        else
            python3 - "$GLOBAL_LOCAL" "$token" <<'PY'
import json, os, sys
path, token = sys.argv[1:]
try: data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError): data = {}
data.setdefault("env", {})["CLAUDE_CODE_OAUTH_TOKEN"] = token
with open(path, "w") as fh: json.dump(data, fh, indent=2); fh.write("\n")
print("  ✓ token written — automatic review is fully enabled")
PY
        fi
    fi
    echo
fi

# ── 7. Verify ───────────────────────────────────────────────────────────────
bash "$RETRO_DST/doctor.sh" --no-exec
