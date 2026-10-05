# Deviations from the plan

| Item | What the plan asked | What shipped | Why |
| --- | --- | --- | --- |
| T02 live baseline | Three live repetitions of unchanged SSD and no-SSD before behavior edits | Parity 375/375 was recorded on `e732a93` before the behavior edits (`.ssd/milestones/2026-10-05-v3-baseline/verification.md`). Live arms are `NOT_RUN` | No model runtime and spending was forbidden. A fabricated green baseline is not allowed |
| T08 clean-host install | Run `claude plugin validate` and a clean host install | The owner ran `claude plugin validate .` on a Mac. Result: Validation passed with warnings. Both warnings are addressed (`docs/releases/3.0.0/plugin-validate.md`). A clean-host install was not run. This environment did not re-execute `claude` | Install and marketplace submission stay with the owner |
| T07 in-session loading | Confirm instructions seen in a session | `.claude/CLAUDE.md` contains `@../AGENTS.md`. Loading was not executed | No Claude Code session in this environment |
| T06 refactor schema | Close coverage gaps, and do not add a schema merely because a skill exists | `refactor-plan.md` stays unmatched | `scripts/parity-test.sh` fixture `frontmatter-valid-names-schemaless` requires that filename to be reported as in scope with no schema |
| T17 / T23 live review and run certification | Live comparative review and a full host run | Deterministic jail, authz, resume, and hook-process tests passed. Live dispatch is `NOT_RUN`. Unattended `run` is not certified outside the tested adapter | No host dispatched the role files |
| T24 five-user pilot | At least five people unfamiliar with SSD | `NOT_RUN` | No users in this environment |
| T26–T33 | Optional, after benefit is shown | Deferred. No stubs, no MCP tools, no cloud routines | No measured benefit, no cloud credentials, no identified MCP client, no Spec Kit demand. Clone retirement is not scheduled |
| STOP-4 replay | Reuse the registry; extend through an ADR | Conflicting fingerprint replay returns existing STOP-4 | ADR-0023. No new STOP number |
| Older readers | Prevent an older library from corrupting newer state | `.ssd/format` is read by 3.0.0+. v2.14 binaries do not know the file | Already-shipped binaries cannot be updated from this change. Recovery is the migrate backup |

Publishing the plugin, submitting the marketplace, tagging `3.0.0`, and deploying are not deviations of scope. They were outside the authorization for this change. They are listed in `owner-actions.md`.
