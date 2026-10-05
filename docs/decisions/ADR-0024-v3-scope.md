# ADR-0024: SSD 3.0 scope, and what is not in it

## Status

Accepted — 2026-10-05 — SSD 3.0.0.

## Context

The v3 plan's optional items (coded workflows, secondary verification, specialist fan-out, cloud routines, deeper usage export, MCP, Spec Kit, clone retirement) are not prerequisites. The implementation environment has no Claude Code CLI, no spending ceiling, and no cloud credentials. Shipping a stub that cannot run would claim a capability the tests did not exercise.

## Decision

1. Version 3.0.0 ships the local core: portable frontmatter, compact entrypoints, path and state classification, one authored schema, doctor, setup planning, portable export, lifecycle helpers, three role definitions, the constrained executor, finding certification, model selection that defaults to inherit, the authorization boundary, resume and fingerprint replay, hook adapters, and snapshot-bound gate evidence.
2. The default autonomy mode remains `propose`. Unattended `run` is available only where the jail and the outside control directory both work. Otherwise doctor reports the gap and the effective mode is `propose`. Configuration is not rewritten.
3. The following are deferred. They are not implemented and not registered as tools:
   - T26 coded workflows
   - T27 secondary verification of disputed findings
   - T28 specialist fan-out
   - T29 cloud routines
   - T30 usage export beyond unknown token counts
   - T31 MCP
   - T32 Spec Kit
   - T33 clone retirement
4. Clone installation and the plugin manifest coexist. Neither is deleted. No deprecation date is set.
5. `.ssd/format` containing `3` is written by migration `format-marker`. A library whose major version is lower than that marker refuses to write. A marker that is absent means an older project is unchanged. Libraries released before 3.0.0 do not read the marker; rollback uses the pre-migration backup, not a promise that a v2.14 binary will refuse.

## Consequences

The owner ran `claude plugin validate .` on a Mac. The result was "Validation passed with warnings", and both warnings are addressed in the tree. Live model comparisons, the five-user pilot, and in-session instruction loading remain `NOT_RUN` in the 3.0.0 evidence bundle. They are not passes. Publishing, marketplace submission, tagging, and deployment are owner actions and are not performed by the implementation change.
