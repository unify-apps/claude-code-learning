#!/usr/bin/env python3
"""
Compact recent Claude Code transcripts into a small, readable review feed.

Window selection (so nothing is skipped after days of inactivity):
  - DEFAULT: every event since the last reviewed CHECKPOINT (a watermark in .checkpoint),
    capped at MAX_LOOKBACK days so the backlog can never grow unbounded.
  - `--days N`: a fixed N-day window (ad-hoc; ignores the checkpoint, doesn't advance it).
  - First run (no checkpoint): defaults to the last 1 day.

The newest event included is recorded in .feed-max-ts as "<epoch> <uuid>"; a *successful review*
advances .checkpoint to it (the caller does the advance, so unreviewed events stay queued). The uuid
makes the checkpoint exclusive without skipping siblings: the next run drops the single event the
checkpoint points at, but keeps any *other* events that merely share its timestamp. Strips JSONL
bloat ~22-26x. Stdlib only, zero quota.

Usage: python3 compact.py [--days N] [--since EPOCH] [--out <path>]
"""
from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import re
import time
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
RETRO = Path.home() / ".claude" / "retro"
CHECKPOINT = RETRO / ".checkpoint"
FEED_MAX_TS = RETRO / ".feed-max-ts"
MAX_LOOKBACK_DAYS = int(os.environ.get("CLAUDE_RETRO_MAX_LOOKBACK_DAYS", "14"))
RETENTION_DAYS = int(os.environ.get("CLAUDE_RETRO_RETENTION_DAYS", "14"))
CORRECTION = re.compile(r"\b(no|nope|don'?t|do not|actually|wrong|that'?s not|undo|revert|stop|not what)\b", re.I)


def event_ts(obj: dict) -> float | None:
    ts = obj.get("timestamp")
    if not isinstance(ts, str):
        return None
    try:
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def read_checkpoint() -> tuple[float | None, str | None]:
    """(timestamp, uuid) of the last reviewed event. uuid is None for a legacy/integer checkpoint."""
    try:
        raw = CHECKPOINT.read_text().strip()
    except OSError:
        return None, None
    if not raw:
        return None, None
    parts = raw.split()
    try:
        ts = float(parts[0])
    except ValueError:
        return None, None
    return ts, (parts[1] if len(parts) > 1 else None)


def resolve_cutoff(now: float, days: int | None, since: float | None) -> tuple[float, str, str | None]:
    """The lower time bound for events to include, a human label, and the checkpoint event's uuid —
    the exact boundary event to exclude next run. The uuid is set ONLY on the un-capped checkpoint
    path (the ad-hoc --days/--since and capped paths have no event sitting on the cutoff edge)."""
    if days is not None:                                   # explicit ad-hoc fixed window
        return now - days * 86400, f"fixed {days}d window", None
    floor = now - MAX_LOOKBACK_DAYS * 86400                # the bound that keeps the backlog finite
    if since is not None:
        checkpoint_ts, checkpoint_uuid = since, None
    else:
        checkpoint_ts, checkpoint_uuid = read_checkpoint()
    if checkpoint_ts is None:
        return now - 86400, "first run (last 1d)", None
    if checkpoint_ts < floor:                              # cutoff != checkpoint → no boundary event on the edge
        return floor, f"since checkpoint, capped at {MAX_LOOKBACK_DAYS}d", None
    return checkpoint_ts, "since checkpoint", checkpoint_uuid


def clip(text: str | None, limit: int) -> str:
    collapsed = " ".join((text or "").split())
    return collapsed if len(collapsed) <= limit else collapsed[:limit] + "…"


def tool_summary(name: str, inp: dict | None) -> str:
    inp = inp or {}
    if name == "Bash":
        return clip(inp.get("command", ""), 160)
    if name in ("Read", "Edit", "Write", "NotebookEdit"):
        return inp.get("file_path") or inp.get("notebook_path") or ""
    if name in ("Task", "Agent"):
        return clip(inp.get("description") or inp.get("prompt", ""), 120)
    return clip(", ".join(f"{k}={clip(str(v), 40)}" for k, v in inp.items()
                          if k not in ("content", "new_string", "old_string")), 160)


def compact_session(path: str, cutoff: float,
                    boundary_uuid: str | None = None) -> tuple[str | None, float | None, str | None]:
    """Return (compacted chunk or None, newest included event ts or None, that event's uuid or None)."""
    try:
        repo = Path(path).relative_to(PROJECTS).parts[0]
    except ValueError:
        repo = Path(path).parent.name
    sid = Path(path).stem[:8]
    out: list[str] = []
    turns = 0
    max_ts: float | None = None
    max_uuid: str | None = None
    with open(path, errors="ignore") as fh:
        lines = fh.readlines()
    for raw in lines:
        try:
            obj = json.loads(raw)
        except ValueError:
            continue
        ts = event_ts(obj)
        if ts is not None and ts < cutoff:
            continue                                       # before the watermark → already reviewed
        # Checkpoint path only: drop the single event the checkpoint points at (reviewed last run).
        # Matched by uuid, not by ts alone — so other events sharing that exact timestamp are kept.
        if boundary_uuid is not None and ts == cutoff and obj.get("uuid") == boundary_uuid:
            continue
        if ts is not None and (max_ts is None or ts > max_ts):
            max_ts = ts
            max_uuid = obj.get("uuid")
        kind = obj.get("type")
        content = (obj.get("message") or {}).get("content")
        if kind == "user":
            text = content if isinstance(content, str) else None
            if isinstance(content, list):
                texts = [b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text"]
                text = " ".join(texts) if texts else None
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_result" and block.get("is_error"):
                        body = block.get("content")
                        if isinstance(body, list):
                            body = " ".join(x.get("text", "") for x in body if isinstance(x, dict))
                        out.append(f"  ✗ ERROR: {clip(str(body), 200)}")
            if text and not obj.get("isMeta"):
                flag = "  ⟳CORRECTION" if CORRECTION.search(text[:80]) else ""
                out.append(f"USER: {clip(text, 1500)}{flag}")
                turns += 1
        elif kind == "assistant" and isinstance(content, list):
            for block in content:
                if not isinstance(block, dict):
                    continue
                bt = block.get("type")
                if bt == "text" and block.get("text", "").strip():
                    out.append(f"ASSISTANT: {clip(block['text'], 1200)}")
                elif bt == "thinking" and block.get("thinking", "").strip():
                    out.append(f"  [thinks: {clip(block['thinking'], 240)}]")
                elif bt == "tool_use":
                    out.append(f"  → {block.get('name')}: {tool_summary(block.get('name'), block.get('input'))}")
    if not out:
        return None, max_ts, max_uuid
    return f"\n## session {sid} · {repo} · {turns} user-turns\n" + "\n".join(out), max_ts, max_uuid


def prune(out_dir: Path) -> None:
    """Delete dated outputs older than RETENTION_DAYS so nothing accumulates unbounded."""
    horizon = time.time() - RETENTION_DAYS * 86400
    for pattern in ("conversations-*.md", "conversation-review-*.md", ".review-*.json"):
        for f in out_dir.glob(pattern):
            try:
                if os.path.getmtime(f) < horizon:
                    f.unlink()
            except OSError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=None, help="fixed N-day window (ignores checkpoint)")
    parser.add_argument("--since", type=float, default=None, help="explicit epoch lower bound")
    parser.add_argument("--out", default=str(RETRO / ("conversations-" + datetime.date.today().isoformat() + ".md")))
    args = parser.parse_args()

    now = time.time()
    cutoff, mode, boundary_uuid = resolve_cutoff(now, args.days, args.since)
    files = sorted((f for f in glob.glob(str(PROJECTS / "**" / "*.jsonl"), recursive=True)
                    if os.path.getmtime(f) >= cutoff),
                   key=lambda f: -os.path.getsize(f))
    out_path = Path(os.path.expanduser(args.out))
    out_path.parent.mkdir(parents=True, exist_ok=True)
    RETRO.mkdir(parents=True, exist_ok=True)

    results = [compact_session(f, cutoff, boundary_uuid) for f in files]
    chunks = [chunk for chunk, _, _ in results if chunk]
    stamps = [(ts, uuid) for _, ts, uuid in results if ts is not None]
    body = (f"# Compacted Claude Code conversations — {mode} — {len(chunks)} sessions\n"
            + "\n".join(chunks))
    tmp = out_path.with_name(out_path.name + ".tmp")
    tmp.write_text(body, encoding="utf-8")
    os.replace(tmp, out_path)

    # Record the newest included event as "<epoch> <uuid>"; a successful review advances .checkpoint
    # to this. Full-precision epoch (not :.0f) so next run's `ts == cutoff` identity check can match.
    best_ts, best_uuid = max(stamps, key=lambda pair: pair[0]) if stamps else (cutoff, None)
    FEED_MAX_TS.write_text(f"{best_ts!r}" + (f" {best_uuid}" if best_uuid else "") + "\n")
    prune(out_path.parent)

    raw_kb = sum(os.path.getsize(f) for f in files) // 1024
    out_kb = len(body.encode()) // 1024
    since_str = datetime.datetime.fromtimestamp(cutoff).strftime("%Y-%m-%d %H:%M")
    print(f"compacted {len(chunks)} sessions ({mode}, since {since_str}): {raw_kb}KB raw → {out_kb}KB")
    print(f"~{len(body) // 4} tokens — {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
