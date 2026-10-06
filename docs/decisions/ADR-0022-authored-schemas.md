# ADR-0022: One authored artifact schema

## Status

Accepted — 2026-10-05 — SSD 3.0.0.

## Context

Artifact contracts already lived in `methodology/schemas/*.yml` and were read by `methodology/frontmatter-validate.py`. A second hand-written JSON Schema would drift. Skeptic reports had no schema. Some filenames are unmatched on purpose, and the parity suite pins that.

## Decision

1. `methodology/schemas/*.yml` is the only authored contract. `methodology/ssdlib/schemas.py` generates `methodology/schemas/json/*.schema.json` with sorted keys and a trailing newline. Do not hand-edit the JSON.
2. Optional v3 fields (`reviewed_snapshot`, `execution_method`, `result_status`, `provenance`) are optional. Historical artifacts that omit them stay valid.
3. `codebase-skeptic` output (`skeptic-before.md`, `skeptic-after.md`, `skeptic-*.md`) has a schema. `software-standards`, `ssd-init`, and `methodology` produce no gate-validated rail artifact; `methodology/coverage.yml` says why.
4. `refactor-plan.md` stays unmatched. The parity fixture `frontmatter-valid-names-schemaless` requires that filename to be reported as in scope with no matching schema. Adding required fields would fail that fixture and older notes.
5. A delegation envelope schema matches only `delegation-envelope.yml`. It is not a rail artifact. Schema validity is not a gate result and is not authorization.
6. `frontmatter-valid` resolves `methodology/frontmatter-validate.py` in the project first, then beside `gate-rules.sh`. Fixtures that vendor the validator keep using their copy.

## Consequences

Generated JSON can express only the types the YAML names (`string`, `int`, `bool`, `list`, `dict`, `timestamp`). Nested shapes stay in the skill text. The generator records that limit in `x-ssd-notes` instead of inventing constraints.

A model-supplied `gate_pass` remains in the code-reviewer schema because `rails-walked` reads it. Certification in `methodology/ssdlib/findings.py` ignores it.
