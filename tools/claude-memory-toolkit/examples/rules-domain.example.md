---
paths:
  - "payments/**"
  - "**/*payment*"
  - "services/checkout/**"
---
# Payments — file-anchored rules (loads only when Claude reads a matching file)

> Place this at `.claude/rules/payments.md` in your repo (or `~/.claude/rules/` for all repos).
> Claude Code loads this block **on-demand, deterministically, when it reads a file matching the
> `paths` globs above** — a hard trigger. It does NOT load for unrelated work. This is the reliable
> way to scope domain knowledge that only matters when you're touching those files — more reliable
> than a memory-index entry (subject to truncation) or a "read this when relevant" pointer (a
> judgment call that misses silently).

## Idempotency keys are mandatory on every write
Every payment write carries a client-generated idempotency key; retries reuse the SAME key or you
double-charge. Derive it from the order id + attempt-invariant fields — never a per-attempt uuid
or timestamp.

## Never log full PANs / CVV
Card numbers are truncated to last-4 before any log/trace/metric. The linter allows-lists the
`redact_card()` helper; raw card fields must not reach `logger.*`.

## Verify the side effect, don't trust the 200
The gateway returns `200` on accepted-but-async captures. Confirm the capture landed
(`GET /charges/{id}` state == `captured`) before marking the order paid — a `200` alone is not
settlement.

<!--
  Use path rules (not memory) for knowledge that is only relevant while editing specific files.
  Reliability ladder (most -> least deterministic):
    global MEMORY.md entry  > path rule (file-anchored)  > skill-bundled ref (fires with the skill)
      > "read this pack when relevant" pointer (unreliable — silent misses)
-->
