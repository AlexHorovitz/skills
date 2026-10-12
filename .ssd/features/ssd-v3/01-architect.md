---
skill: architect
version: "1.3.1"
produced_at: "2026-10-05T18:40:00Z"
produced_by: implementing agent
project: skills
scope: ssd-v3
consumed_by: []
deliverables:
  component_diagram: "library helpers under methodology/ssdlib; referees stay gate-rules.sh and autorun.sh"
  data_model: "authored YAML schemas; grants outside the repo; .ssd/format major marker"
  api_contract: "methodology/ssd_cli.py and autorun.sh resume"
  decision_log: "ADR-0021 through ADR-0024"
  risk_assessment: "unattended run is certified only for the unshare jail plus the external control directory"
quality_gate_pass: false
---

# Architecture

Six layers stay separate. Doctrine is the skills. Contracts are `methodology/schemas`. Execution is the role files plus `executor.py`. Control stays in `gate-rules.sh`, `autorun.sh`, and `authz.py`. Evidence is the parity suite, `scripts/v3_suite.py`, and `scripts/eval_driver.py`. Delivery is the clone, `.claude-plugin/plugin.json`, and the generated portable bundle.

`quality_gate_pass` here is the architect skill's own field. It is not a ship grant. The code review's `gate_pass` is the legacy mirror `rails-walked` reads. Certification recomputes from the runner.

The default mode remains `propose`. Missing isolation does not rewrite configuration.
