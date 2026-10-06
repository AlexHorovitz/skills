# Task records

Status words: completed means the acceptance check that can run here did run. NOT_RUN is not a pass. Deferred means the optional package was not built.

| Task | Status | Evidence |
| --- | --- | --- |
| T00 | completed | `.ssd/milestones/2026-10-05-v3-baseline/verification.md`. Revision `e732a93`, VERSION 2.14.0, parity 375/375, gate 5 pass / 8 skip / 0 fail. Stops STOP-1..7 and FM-1..6 copied from the repo, not invented |
| T01 | completed for the driver | `scripts/eval_driver.py`, `methodology/ssdlib/live_eval.py`, `evals/fixtures/` (16), `evals/held-out/` (2). Offline arm C, planted failures, and reproduce ran. Live adapters are `claude-code` and `anthropic-api`. This environment did not call a model |
| T02 | driver ready; live repetitions NOT_RUN | The pre-edit parity result is the milestone above. Three live repetitions were not executed here. No retrospective green baseline. The owner command is in `live-evals.md` |
| T03 | completed for lint | `scripts/skill-frontmatter-check.py`, rule `skill-metadata`, ADR-0021. Negative fixtures in `scripts/v3_suite.py`. Routing against a live model is NOT_RUN |
| T04 | completed for the line check | Five entrypoints compacted; archives in `references/archive-v2.14.md`. Suite checks line count, required sentences, and links. "References were read by a model" is NOT_RUN |
| T05 | completed | `methodology/ssdlib/paths.py`, `state.py`. External project, spaces, linked worktree, corrupt versus missing. Suite |
| T06 | completed with the refactor deviation | Generated JSON in sync. Skeptic schema added. `refactor-plan.md` unmatched on purpose. Historical validator run had no FAIL |
| T07 | partial | `AGENTS.md`, `.claude/CLAUDE.md` `@../AGENTS.md`, `ssd-init/references/project-instructions.md`. In-session load NOT_RUN |
| T08 | completed for validate | `.claude-plugin/plugin.json` and `marketplace.json` (top-level `description`). Version matches `VERSION`. Owner ran `claude plugin validate .` on a Mac: Validation passed with warnings. Both warnings are addressed. Clean-host install was not run. Clone path unchanged |
| T09 | completed for the local tools | `doctor.py`, `lifecycle.plan` writes 0, discover does not execute. Suite |
| T10 | completed as format-validated | `portable.export`. Closure passed. `unattended_run` false. No host install of the bundle |
| T11 | completed for the helpers | Managed blocks, backup/restore functions, remove keeps `.ssd/` and foreign hooks, format marker, migrate `format-marker`. Coexistence keeps clone and plugin |
| T12 | completed for the deterministic foundation | Suite plus parity. Live discovery comparison NOT_RUN |
| T13 | partial | `agents/ssd-architect.md`, `ssd-coder.md`, `ssd-reviewer.md`, `methodology/schemas/delegation.yml`. Host did not dispatch them. NOT_RUN for observed delegation |
| T14 | completed for the jail | `executor.py` suite: symlink, absolute path, secret env, output dir, snapshot, network. Doctor marks the capability from that mechanism |
| T15 | partial | `findings.py` ignores `gate_pass`, grades a planted inventory, rejects a missing runner. The grade is of a fixture report, not a live review |
| T16 | completed for selection rules | Omitted model stays inherit. Unsupported name is not replaced. No commercial model is required |
| T17 | not certified as live review | No isolated-versus-inline model comparison. Inline is labeled inline |
| T18 | completed for the control directory | `authz.py` suite: in-repo grant ignored, worker cannot grant, one use, snapshot bind, missing guard fails closed |
| T19 | completed | Fingerprint replay and child budget in parity fixture `autorun-fingerprint-replay`. Same edge replays. Different edge is STOP-4. Child count is STOP-3 |
| T20 | partial | `hooks/hooks.json` and `ssd_hook.py`. Process tests for empty, malformed, deny, post-tool, and stop. Claude Code did not deliver an event. NOT_RUN for host delivery |
| T21 | completed for snapshot binding | `evidence.py`. Stale dirty tree fails. Missing record is NOT_RUN. SKIP from the gate summarizes as NOT_RUN. `test_command` spelling unchanged. `ssd-init/references/verify-template.md` |
| T22 | completed for the record rules | `resume.py`. Finished run does not reset. Live worker is FM-2. Fingerprint conflict is STOP-4. Shipping is not restored |
| T23 | not certified as unattended run on every profile | Certified adapter is the jail plus the external control directory on this Linux host. Effective mode otherwise stays `propose`. `--until ship` remains FM-4 in the existing parity fixture |
| T24 | NOT_RUN | `docs/releases/3.0.0/usability.md` |
| T25 | prepared, not published | This commit. Tag, release, and marketplace submission are owner actions |
| T26 | deferred | No workflow file. No measured benefit |
| T27 | deferred | Secondary verification is off. Not implemented |
| T28 | deferred | No specialist fan-out |
| T29 | deferred | No cloud credentials and no routine that posts anywhere |
| T30 | deferred | Token counts stay unknown. No export |
| T31 | deferred | No MCP client identified. No tool registered |
| T32 | deferred | No Spec Kit adapter. A mapping was not executed |
| T33 | deferred | Clone installation stays. No deprecation date |

## Plan sections

| Section | Where it landed |
| --- | --- |
| 1 Executive decision | ADR-0024. Default remains propose. Optional items are not in the release |
| 2 Contract | Referees extended. Stops reused. No `--force`. CI workflow still has no required-check change |
| 3 Experience | `ssd/chapters/doctor.md`, `autonomy.md` resume, setup plan, removal |
| 4 Decisions | ADR-0021 frontmatter, ADR-0022 schemas, ADR-0023 authorization, ADR-0024 scope |
| 5 Architecture | `methodology/ssdlib/`, delegation schema, capability rows in doctor |
| 6 Authorization | `authz.py`, `executor.py`, `docs/security-and-ops.md` |
| 7 Evaluation | `evals/`, `scripts/eval_driver.py`, `scripts/v3_suite.py`. Live rows NOT_RUN |
| 8 Work packages | This table |
| 9 Release sequence | One 3.0.0 commit for the local core. Later milestones are not claimed |
| 10 Implementing agent | Branch and PR only. No external publication |
| 11 Done | Done for the deterministic local scope. Not done for live review, pilot, or unattended run on untested hosts |
| 12 Platform notes | Docs checked during the earlier session for skills, hooks, and the plugin manifest. P3, P5, P6, P8, P9 were not re-fetched here and were not runtime-tested. Claims in code follow the limits in section 12.4 of the plan |
| 13 Dependencies | T26–T33 were not started, which matches their dependence on a finished T25 |

## EV

| ID | Result |
| --- | --- |
| EV-01 | NOT_RUN as a live trace. Offline fixtures exist |
| EV-02 | NOT_RUN as a live trace. Negative fixture `ev02-unrelated` is in the corpus only |
| EV-03 | NOT_RUN as a live trace. Arm C of `ev03-bare-ssd` ran with no skills and passed the protocol grader |
| EV-04 | PASS for plan/idempotent helpers in the suite. Live setup session NOT_RUN |
| EV-05 | NOT_RUN as a live trace. Skill text forbids automatic audits. `disable-model-invocation` is set |
| EV-06 | PASS in the suite (external project, spaces, linked worktree, library validator) |
| EV-07 | PASS for portable closure, plugin path checks, and the owner's `claude plugin validate .` (Validation passed with warnings; both warnings addressed). Clean-host install was not run |
| EV-08 | PASS. Historical frontmatter had no FAIL. Incomplete architect artifact FAILs. Schema sync empty |
| EV-09 | NOT_RUN. No host dispatched a role |
| EV-10 | PASS for `grade_review` on a fixture report. Live recall NOT_RUN |
| EV-11 | PASS for the jail's tested paths. Host tool paths outside the jail NOT_RUN |
| EV-12 | NOT_RUN as a live implementation task. The suite's own tests are the representative change |
| EV-13 | PASS for fingerprint ordering in autorun and hook deny. Host bypass NOT_RUN |
| EV-14 | PASS for control-directory denial with and without a grant. Lock is not consulted |
| EV-15 | PASS for a scoped grant consumed once. Human `/ssd ship` prose path was not driven by a host |
| EV-16 | PASS for missing guard, empty hook, malformed hook. Host timeout delivery NOT_RUN |
| EV-17 | PASS. Dirty snapshot fails `evidence.check`. No record is NOT_RUN |
| EV-18 | PASS for resume rules. Process kill of a live orchestrator was not injected |
| EV-19 | PASS. Child transitions share the budget. Replay does not append |
| EV-20 | PASS for grants bound to repo and snapshot. A second autorun start is still FM-2 in the existing parity fixture |
| EV-21 | PASS. Missing runner, missing evidence, and live eval without a ceiling are NOT_RUN, not PASS |
| EV-22 | PASS for managed-block strip, foreign hook kept, format refusal. Interrupted upgrade on every historical version was not enumerated one by one |
| EV-23 | NOT_RUN. No user session |
| EV-24 | PASS for the jail secret check. Exported portable bundle does not contain the test secret |
| EV-25 | Not required. Workflows deferred |
| EV-26 | Not required. Secondary verification deferred |
| EV-27 | Not required. Cloud deferred |
| EV-28 | Not required. No optional integration shipped |
