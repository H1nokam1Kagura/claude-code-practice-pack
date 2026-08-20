---
name: payments-idempotency-key
description: Every payment write must carry an idempotency key; retries reuse it or you double-charge
metadata:
  type: feedback
  # index: false     # uncomment to keep this file on disk but drop it from MEMORY.md
  # pin: true        # uncomment to force this entry to the top of its section (always loaded)
---

Every write to the payments API MUST include a client-generated idempotency key; the gateway
dedupes on it for 24h. Retries (network, 5xx, timeout) MUST reuse the SAME key — generating a
new one on retry double-charges.

**Why:** 2026-01-14, a retry-on-timeout in the checkout worker minted a fresh key and charged a
customer twice; the gateway had already committed the first attempt.

**How to apply:** derive the key from the order id + attempt-invariant fields (never from a
timestamp or a fresh uuid per attempt). Related: [[payments-webhook-ordering]], [[retry-budget]].

<!--
  Notes on the schema (delete in real files):
  - `name`   : kebab-case; this is what other memories reference as [[payments-idempotency-key]].
               Inbound [[links]] from other memories drive the priority ordering.
  - `type`   : feedback (a durable rule/lesson) | project (ongoing work/state) | reference (a pointer/map).
               `feedback` always floats — rules never get sunk to the truncation tail.
  - Filename : feedback_payments_idempotency_key.md  (type prefix + slug with underscores).
-->
