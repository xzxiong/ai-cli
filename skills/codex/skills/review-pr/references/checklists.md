# Review Checklists

Use this file after reading `SKILL.md`. Apply the checklist that matches the selected review mode.

## Standard Mode

Use this mode for production-oriented changes where correctness and operational safety matter more than idea exploration.

### Priorities

- Verify correctness, edge cases, and rollback behavior.
- Check API, config, schema, and data contract compatibility.
- Inspect state handling, idempotency, ordering assumptions, and concurrency safety.
- Look for performance, cost, batching, fan-out, N+1, and resource-lifecycle issues.
- Check security basics: auth boundaries, secrets, validation, and unsafe defaults.
- Verify observability for risky behavior changes: logs, metrics, error surfaces, alerts.
- Check whether tests cover the new behavior or the riskiest failure modes.

### Good Findings

Prefer findings that are concrete and user-impacting, for example:
- a nil path or empty-state crash
- a race, deadlock, or shared-state corruption risk
- a backward-incompatible API or config change
- an unbounded retry, loop, or concurrency multiplier
- a missing validation or secret leak
- a missing test around a meaningful regression surface

## Explore Mode

Use this mode for demos, PoCs, and exploratory work where the goal is to validate a direction rather than polish every implementation detail.

### Priorities

- Clarify the problem, boundaries, assumptions, and non-goals.
- Reconstruct the data flow and module interactions from input to output.
- Check whether the PR description matches the implementation.
- Verify that the experiment emits enough evidence to judge success: logs, metrics, eval output, debug hooks, sampled artifacts.
- Check whether the design is easy to iterate on: flags, seams, dependency boundaries, fallback paths, testability, debuggability.
- Look for obvious external pressure risks such as multiplicative concurrency, repeated client creation, or unbounded downstream calls.

### Blocking Findings Only

In explore mode, raise code-level issues mainly when they would cause:
- crash or stuck execution
- data loss or corruption
- irreversible resource leakage
- secret exposure
- an experiment that cannot be evaluated because it emits no useful evidence

Ignore minor style, naming, and micro-optimization issues unless they hide a real blocker.

### Maturity Signal

At the top of the review, state one of these outcomes:
- `Green`: coherent direction; safe to iterate further
- `Yellow`: promising, but missing critical validation or guardrails
- `Red`: core assumptions break or implementation contradicts the stated approach

## Evidence Heuristics

- Read the surrounding file before claiming a bug from a diff hunk.
- Confirm whether the behavior is already handled elsewhere.
- Prefer one strong finding over several speculative ones.
- Name the trigger condition, not just the code smell.
- Be explicit about uncertainty when repository context or runtime assumptions are missing.
- Mention positive context when it materially reduces severity.

## Suggested Report Shape

- `Summary`: one line on what changed and why it matters.
- `Findings`: only the highest-signal issues, ordered by severity.
- `Open Questions`: assumptions that need author confirmation.
- `Notes`: missing tests, observability gaps, or positive changes worth keeping.
