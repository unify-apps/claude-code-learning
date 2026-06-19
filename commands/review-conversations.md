---
description: Review my recent Claude Code conversations, learn my working style, and propose concrete improvements
---

Review my **unreviewed** Claude Code conversations and improve how Claude Code works with me going forward.

This is not only a tooling/error review. It should also learn my conversation style, working preferences, recurring frustrations, and the ways Claude misunderstands me.

Default behavior:

* Run `python3 ~/.claude/retro/compact.py`
* If that path is missing, fall back to `python3 compact.py` (available on PATH via the plugin's bin/).
* This reads every conversation since the last reviewed checkpoint, capped at 14 days.
* It writes `~/.claude/retro/conversations-<date>.md`.
* Read the generated file in full. Do not sample.
* If the file is too large, read it in chunks and synthesize across all chunks.
* If I ask for a specific window, such as "review the last 7 days", run:
  `python3 ~/.claude/retro/compact.py --days N`
  This is an ad-hoc review and must not move the checkpoint.
* Fallback only if needed: read raw `~/.claude/projects/**/*.jsonl`, largest-first, and clearly state what was covered.

Review the conversations for these layers:

## 1. Execution problems

Find concrete issues in how Claude Code worked:

* failed commands;
* wrong working directory;
* unnecessary tool calls;
* repeated retries;
* edits attempted without reading exact file contents;
* wrong assumptions about repo layout, setup, environment, permissions, or tools;
* slow or overcomplicated workflows.

## 2. Tool-use waste

Find cases where tool calls consumed context or time without earning their keep:

* files read but never referenced in the response (unused reads);
* same file read more than once in a session when the content hadn't changed;
* oversized reads where only a small portion of the result was used (e.g. reading 200 lines when 5 were needed);
* `find`/`ls`/`grep` fan-outs to locate something that had a direct known path;
* speculative tool calls made "just in case" with no resulting action;
* large Bash output returned and ignored;
* parallel or sequential reads of multiple files when only one was consulted;
* searches returning large result sets where only 1–2 items were relevant.

For each waste finding, estimate rough cost: number of redundant calls or approximate lines of unused output.

## 3. Misunderstanding patterns

Find where Claude misunderstood me:

* places where I corrected Claude;
* `⟳CORRECTION` markers;
* repeated clarifications from me;
* places where Claude answered a different question than I asked;
* places where Claude made the task bigger than needed;
* places where Claude asked instead of making a reasonable best-effort assumption;
* places where Claude missed context from earlier in the same conversation.

## 4. My working style

Infer how I prefer to work, based only on evidence from the conversations:

* whether I prefer short answers, full explanations, direct code, staged plans, or exact prompts;
* how I phrase tasks;
* when I want refinement vs implementation;
* when I want Claude to stop and wait;
* when I want Claude to continue and make progress;
* what kind of summaries help me;
* what kind of output format I reuse most often.

Do not invent personality claims. Only include style insights supported by examples.

## 5. Better future behavior

Convert the review into practical operating rules:

* how Claude should respond to me by default;
* when Claude should be concise;
* when Claude should explain deeply;
* when Claude should ask a question;
* when Claude should avoid asking and proceed;
* how Claude should handle repo work;
* how Claude should handle prompt-refinement tasks;
* how Claude should handle debugging tasks;
* how Claude should handle planning tasks.

## 6. Memory candidates

Identify what should be remembered going forward, split into:

* `[session]` local Claude behavior rules for `~/.claude/CLAUDE.md`;
* `[repo:<name>]` repo-specific conventions that belong in a committed repo `CLAUDE.md`;
* `[settings]` Claude Code settings or hook changes;
* `[code]` script/tooling changes.

Only propose memory/rule changes that are genuinely useful and supported by the review.

Output the full review directly in chat with these sections:

# Conversation Review — <date>

## 1. Executive summary

3–6 bullets max:

* what went wrong most often;
* what Claude should change immediately;
* what user-style insight matters most.

## 2. Findings

Group findings into these categories:

### A. Execution/tooling findings

Each finding must include:

* ID, like `E1`;
* issue;
* concrete example or quote;
* impact;
* suggested fix.

### B. Tool-use waste findings

Each finding must include:

* ID, like `W1`;
* what was wasted (tool name + what it returned);
* concrete example or quote;
* estimated cost (redundant calls or ~lines of unused output);
* leaner alternative.

### C. Misunderstanding/user-correction findings

Each finding must include:

* ID, like `M1`;
* what Claude misunderstood;
* concrete example or quote;
* what Claude should do differently next time.

### D. User working-style findings

Each finding must include:

* ID, like `S1`;
* observed preference;
* supporting example or quote;
* future behavior rule.

## 3. Operating model for future Claude sessions

Write concise rules split into:

### Default response style

How Claude should answer me by default.

### For coding/debugging

Rules for repo inspection, edits, tests, git/gh usage, and avoiding wasted commands.

### For prompt refinement

Rules for rewriting my rough notes into polished prompts/messages.

### For planning

Rules for making implementation plans without overcomplicating them.

### For multi-repo work

What to re-check when cwd changes or multiple repos are involved.

## 4. Proposed changes pending my review

Give a numbered changeset. For each item include:

* tag: `[session]`, `[repo:<name>]`, `[settings]`, or `[code]`;
* exact target file;
* exact change to add or a short before → after diff;
* rationale tied to a finding ID.

Do not apply changes yet.

Rules:

* `[session]` items go only in `~/.claude/CLAUDE.md`.
* `[repo:*]` items go only in committed repo docs and need human review.
* Do not auto-commit repo changes.
* Do not apply anything until I approve specific item numbers.

## 5. What not to change

List any patterns that looked okay and do not need action.

## 6. Review coverage

State:

* number of sessions reviewed;
* time window;
* whether this was default checkpoint mode or ad-hoc `--days`;
* any sessions/files skipped and why.

After producing the chat review:

## Mark reviewed only for default mode

If this was the default review, run:
`cp ~/.claude/retro/.feed-max-ts ~/.claude/retro/.checkpoint`

If this was an ad-hoc `--days` review, do not move the checkpoint.

## Save review to disk

Always save the complete review to:
`~/.claude/retro/conversation-review-${DATE}.md`

Where:
`DATE=$(date +%F)`

Then update:
`~/.claude/retro/latest.md`

By running:
`ln -sf "conversation-review-${DATE}.md" ~/.claude/retro/latest.md`

Then update `~/.claude/retro/INDEX.md` so this review appears newest-first, with session count and finding count when available.
