---
skill: systems-designer
version: "1.6.0"
produced_at: "2026-10-05T18:40:00Z"
produced_by: implementing agent
project: skills
scope: ssd-v3
consumed_by: []
machine_checked:
  parity: "384/384 exit 0"
  v3_suite: "98 pass, 0 fail, 4 NOT_RUN"
  shellcheck: "exit 0"
human_review:
  required: true
  note: "owner reviews the pull request; this artifact is not that review"
block_conditions_met: false
block_conditions:
  live_models: "NOT_RUN"
  five_user_pilot: "NOT_RUN"
  native_plugin_validate: "NOT_RUN"
result_status: NOT_RUN
reviewed_snapshot: "implementation tree before the release commit; re-run the gate after the commit"
execution_method: inline
---

# Systems design

`production_runtime` in `.ssd/gate.yml` is false, so rail step 2 is out of scope for `deviations-recorded`. This artifact exists so the design is on disk. `block_conditions_met` is false because the live and pilot checks did not run.

Strong-assurance review requires the jail. Doctor reports that capability from `unshare`, not from a role name.
