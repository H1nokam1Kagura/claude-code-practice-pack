# `tools/ci/` — how a recipient actually runs any of this

Every toolkit in this pack tells you to run its checks in CI. Until this directory existed, the
pack shipped no CI: the workflows lived in the source repository's GitHub Actions directory, which
is not part of any toolkit, so a recipient got the gate scripts and nothing to run them with. This
directory is that missing half.

It sits under `tools/` rather than at the repository root on purpose. The practice claim gate
sweeps `tools/`, and its pin sweep is opt-out, so a document placed here is gated from the moment
it exists — whereas at the root it would have been one more shipped directory that no check reads.
In the share pack, where the toolkits are themselves top-level, this directory lifts with them.

Two groups of files: the workflow and the runner that drives it, then the gate that keeps the
workflow honest about what it leaves out.

| File | What it is |
|------|------------|
| [`verify.yml`](verify.yml) | A GitHub Actions workflow over the shipped checks. Copy it into your own workflows directory and it runs. |
| [`Invoke-LocalCI.ps1`](Invoke-LocalCI.ps1) | Runs the same job on your machine by **parsing `verify.yml`**, never by duplicating it. |
| [`Invoke-LocalCI.SelfTest.ps1`](Invoke-LocalCI.SelfTest.ps1) | The negative controls. Proves the runner can fail. |
| [`check_workflow_parity.py`](check_workflow_parity.py) | Gates `verify.yml` against the source repository's fuller hosted workflow, step for step. |
| [`workflow-parity-exceptions.json`](workflow-parity-exceptions.json) | Every step one of the two runs and the other does not, with the reason. |

```powershell
pwsh -NoProfile -File tools/ci/Invoke-LocalCI.SelfTest.ps1   # prove the runner can fail
pwsh -NoProfile -File tools/ci/Invoke-LocalCI.ps1            # run every gate verify.yml declares
```

## Why it parses the workflow instead of listing the commands

A local runner that keeps its own copy of the command list is a second source of truth, and it
drifts the moment somebody edits one and not the other — silently, in the direction that matters,
because the local run is the one you trust when you are in a hurry.

So `Invoke-LocalCI.ps1` reads the commands out of `verify.yml`. Add a step to CI and the local
runner picks it up with no edit. Change the workflow's *shape* into something the runner cannot
execute and it **fails rather than quietly checking less**.

## The completeness check is the point, and it is there because it once failed open

The runner does not merely extract the steps it recognises. It accounts for **every** `run:` line
in the job and hard-fails on any shape it cannot execute.

That check exists because the original — the runner this one is extracted from — did fail open.
Its parser matched only `run: python *.py`, so a `shell: pwsh` gate vanished from the local run
while the summary still printed *"every gate GitHub Actions would have run passed here."* Eight
steps reported, nine in the workflow, no warning. A tool asserting its own completeness while
being incomplete. (Measured 2026-08-08; the fix landed the same day.)

Note what the fix was. Not "teach it pwsh" — that would have closed one instance. It was "add a
completeness check so the class cannot recur."

**This constrains `verify.yml`, on purpose.** Every `run:` must be a single line, or a folded
`>-` scalar. A `run: |` block is a multi-line shell body the runner will not guess at, so it
reaches the completeness check as unaccounted and fails the run. If you add a step in a shape the
runner does not know, you have exactly two honest options — teach the runner that shape, or add a
justified entry to its deliberately tiny ignore list. **Do not widen the ignore list to make a
failure go away.** That is how the fail-open above comes back.

## Why the workflow itself is gated

`verify.yml` is a *portable copy* of a fuller workflow in the source repository, and a copy with no
gate drifts. Measured 2026-08-17, before `check_workflow_parity.py` existed: the hosted workflow
declared 42 `run:` steps and this one declared 22, with 17 commands in common — so 20 hosted steps
had no portable counterpart, nothing recorded which of them were deliberate, and nothing noticed the
number growing. It had grown by one that same morning.

The gate does not ask the two files to become identical. Most of the difference is real and should
stay: a runner the source repository owns can install a pinned binary, and your laptop cannot be
asked to. It asks that every difference be **a decision somebody wrote down** — in
`workflow-parity-exceptions.json`, with a reason — and it fails a registration whose difference has
since disappeared, so the list cannot quietly become a blanket exemption.

It also asserts this file's own shape contract: every `run:` step declares `shell: pwsh`, which is
what lets `Invoke-LocalCI.ps1` route by the shell the workflow *declares* rather than by guessing
from the command text. Nothing checked that before.

**On a distribution it exits 2**, and that is correct rather than a defect: the hosted workflow was
never shipped to you, so there is nothing to compare. The runner reports it as SKIPPED — partial
cover, never a pass.

## Exit contract

| Exit | Meaning |
|------|---------|
| `0` | Every gate ran and passed. |
| `1` | A gate FAILED, **or** a gate ran and measured nothing (INCONCLUSIVE). |
| `2` | Everything that ran passed, but at least one gate was **SKIPPED**. Not a green build. |

`INCONCLUSIVE` and `SKIPPED` are different states and deliberately do not share a code. "I chose
not to run this" is a skip. "It ran and measured nothing" is a failure — a check whose extractor
has broken produces an empty finding set, and empty must never share an outcome with clean.

## What a local pass does not cover

- **The accuracy half of the triggering eval.** `eval_skills.py` needs an API key and exits 2
  without one, by design. `verify.yml` calls it with `--coverage-only`, which reads no key, calls
  no model, and says on every run that it measured no accuracy at all. Key-gated accuracy belongs
  in a separate optional job, not in the run a recipient makes on day one.
- **Anything that needs the hosted runner.** A local pass is evidence, not authority. Where real
  CI exists, it stays the authority.
- **Checks whose second side you did not receive.** Two gates here compare two independent
  implementations of one contract, and only one side ships in a single-toolkit distribution. Those
  report SKIPPED with the reason named, and the run exits 2 — never a green 0. Point them at the
  other side with `--repo-lint` / `--harness` if you have it.
