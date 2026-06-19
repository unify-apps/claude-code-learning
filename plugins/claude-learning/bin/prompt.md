You are doing an automated, unattended retrospective of a developer's recent Claude Code conversations.

The compacted conversation feed is provided below. It contains the real back-and-forth across repos, including lines such as:

* `USER:`
* `ASSISTANT:`
* `→ tool`
* `✗ ERROR`
* `⟳CORRECTION`

Review the feed thoroughly.

This review is not only about errors. It must improve how Claude Code collaborates with this developer.

Analyze six layers:

## 1. Execution/tooling problems

Find:

* failed commands;
* wrong cwd or repo root;
* unnecessary tool calls;
* repeated retries;
* edits before reading exact target text;
* avoidable environment mistakes;
* bad assumptions about git, gh, permissions, shell, setup, scripts, or repo structure.

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

Find:

* places where the user corrected Claude;
* `⟳CORRECTION` markers;
* repeated clarifications;
* cases where Claude answered the wrong question;
* cases where Claude overbuilt the answer;
* cases where Claude asked unnecessary questions;
* cases where Claude missed context already provided.

## 4. User working style

Infer the developer's working preferences from evidence only:

* preferred answer length;
* preferred structure;
* whether they want explanations, direct fixes, prompts, or plans;
* how they phrase rough instructions;
* how they react when Claude is too vague, too slow, too verbose, or too tool-heavy;
* what output formats they reuse.

Do not invent personality traits. Only include insights supported by the feed.

## 5. Future operating rules

Turn findings into concrete rules Claude should follow:

* default response style;
* coding/debugging behavior;
* prompt-refinement behavior;
* planning behavior;
* repo-navigation behavior;
* multi-repo behavior;
* when to ask vs when to proceed.

## 6. Proposed changes

Propose ready-to-apply changes only. Do not edit anything.

For each proposed change include:

* tag: `[session]`, `[repo:<name>]`, `[settings]`, or `[code]`;
* exact target file;
* exact line(s) to add or a short before → after diff;
* rationale tied to a finding ID.

Use this report format:

# Automated Conversation Review — <date>

## 1. Executive summary

3–6 bullets max.

## 2. Findings

### A. Execution/tooling findings

Use IDs `E1`, `E2`, etc.
Each finding must include:

* issue;
* example or quote from the feed;
* impact;
* suggested fix.

### B. Tool-use waste findings

Use IDs `W1`, `W2`, etc.
Each finding must include:

* what was wasted (tool name + what it returned);
* concrete example or quote from the feed;
* estimated cost (redundant calls or ~lines of unused output);
* leaner alternative.

### C. Misunderstanding/user-correction findings

Use IDs `M1`, `M2`, etc.
Each finding must include:

* misunderstanding;
* example or quote from the feed;
* better future behavior.

### D. User working-style findings

Use IDs `S1`, `S2`, etc.
Each finding must include:

* observed preference;
* supporting example or quote;
* future behavior rule.

## 3. Operating model for future sessions

### Default response style

Concise rules.

### Coding/debugging

Concrete repo/tool rules.

### Prompt refinement

Concrete rewriting rules.

### Planning

Concrete planning rules.

### Multi-repo work

Concrete cwd/repo/root rules.

## 4. Proposed changes

Numbered changeset only. Include exact targets and exact text/diffs.

## 5. What not to change

Mention patterns that are working and should not be over-optimized.

## 6. Coverage

State:

* sessions reviewed;
* time window;
* limitations.

Important constraints:

* Do not run tools.
* Do not apply edits.
* Do not praise.
* Do not create vague recommendations.
* Do not invent findings if the feed does not support them.
* If nothing notable appears, say so directly in one line.
* Prefer fewer, higher-quality findings over many weak findings.
