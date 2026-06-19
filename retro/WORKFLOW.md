# Claude Code Retro — Workflow (for reviewers)

A reviewer/manager-facing explainer. For setup steps see [README.md](./README.md).

## In one line

A **self-improvement loop for Claude Code**: it reviews how a developer actually used Claude Code
recently — from their own session history — and surfaces what to do better next time. Free and
automatic by default; the AI-powered deep review is opt-in.

## The problem it solves

Developers using Claude Code repeat the same inefficiencies and mistakes, and there's no feedback
loop to catch them. This builds one, grounded in the *real* conversations — not guesswork.

## The workflow, end to end

**1. Capture & compact — free, automatic, every 24h.**
After a developer works, a `Stop` hook fires (debounced to once per 24h, runs in the background). It
condenses **every conversation since the last review** — tracked by a checkpoint watermark, capped at
14 days so a few days of inactivity never drops anything and the backlog stays bounded — into a small,
readable **conversation feed** (~22–26× smaller, from ~1M+ raw tokens) that fits in one pass. A
successful review advances the checkpoint, so each conversation is reviewed exactly once. Pure Python,
no AI, no cost.

**2. Review — two ways.**
- **On demand (free):** the developer runs **`/review-conversations`** anytime. Claude reads the
  compacted feed and produces findings (problems, inefficiencies, mistakes), a plan (per-repo +
  cross-repo), and a **proposed changeset**.
- **Automatic (opt-in, needs a token):** with a token, the same 24h hook also runs that review
  headlessly and saves a **report** to a file.

**3. Notify — so it's not silent.**
When the automatic report lands, the developer gets a **macOS notification** and — on their next
prompt — an in-Claude "review ready" note (works even in a session left open for days).

**4. Human approves — nothing auto-applies.**
The developer reads the findings and applies **only** the changes they agree with. The system never
edits code or any shared file on its own.

```
work → 24h hook → compact (free) → [token] AI review → report → notify you
                                  → /review-conversations any time (free)
            you read it → approve the changes you want → done
```

## Reassurances

- **Privacy:** everything stays **local** on the developer's machine. Nothing is uploaded, committed,
  or sent anywhere (transcripts can contain secrets).
- **Cost:** **free by default** — no tokens, no quota. The AI review is opt-in, per developer, with
  their own token.
- **Safety:** **nothing is applied automatically.** No auto-edits to code, and nothing writes to a
  shared `CLAUDE.md`. Every change is human-approved.
- **Blast radius:** only adds files under `.claude/retro/` + two hooks + one command. It does **not**
  touch product code, CI, or builds.
- **Reversible:** it's a hook + scripts — remove the hook to turn it off instantly.
- **Reviewed:** went through a fresh-eyes bug review (found + fixed real issues: the 24h window,
  over-counted signals, atomic writes, a backstop race) and end-to-end testing.

## Deployment

- Ships **in the repo** (committed). After merge, every developer who pulls gets it.
- Per-developer one-time setup: run the backstop installer + start a new session (~2 steps). For the
  AI review: generate a token once (`claude setup-token`).

## Honest limitations

- **macOS** for the daily backstop + the desktop notification; on Linux the hook still works
  (cron/systemd for the backstop).
- Covers **terminal/CLI** Claude Code only — not the web app or desktop app.
- The **automatic** AI review needs a per-developer token (headless auth is separate from the
  interactive login).

## Status / the ask

Draft PR, not merged — built, reviewed, and tested locally, now ready for **team review + a small
real-world trial**. Suggested test: pull the branch, run `/review-conversations`, see the output;
optionally enable a token to see the automatic review + notification.

> **30-second version:** a free, local, opt-in feedback loop that reviews how we use Claude Code and
> suggests improvements — nothing auto-applies, nothing leaves the machine, it doesn't touch product
> code, and it's fully reversible. Built and tested; ready for team review and a small trial.
