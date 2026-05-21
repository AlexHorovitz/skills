# ADR-0006: Frontmatter schema validator as a Python + PyYAML tool

## Status
Accepted — 2026-05-04 — landed in v1.14.0 (PR #1, merged 2026-04-29). Documented retroactively here because the original commit omitted an ADR despite the change adding new tooling and a new gate rule.

## Context

The v1.13.0 close of the ssd-skill-upgrades epic deferred two items: (1) a true two-surface
parity test and (2) a frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts.
Iter A targeted (2).

The existing gate-rules.sh (ADR-0005) is bash. Its `yaml_get` helper is intentionally crude — a
single-purpose awk pattern that reads scalar keys from a YAML file. ADR-0005 explicitly notes
this is "a known-limitation tradeoff" for the existing rules' tiny scope. Frontmatter validation
needs more: nested dicts (`deliverables`, `finding_counts`, `test_results`), list types, conditional
type checks (bool vs int vs timestamp). Bash + awk is the wrong tool for that.

## Decision

Implement the frontmatter validator as a Python 3 + PyYAML script:

- **Tool**: `methodology/frontmatter-validate.py`. Walks `.ssd/features/<slug>/*.md` and
  `.ssd/milestones/<topic>/*.md`, parses YAML frontmatter via `yaml.safe_load`, matches each file
  to a schema, validates field presence and top-level type.
- **Schemas**: `methodology/schemas/<skill>.yml` — one file per consuming skill (`architect`,
  `coder`, `code-reviewer`, `systems-designer` in v1.14.0). Custom YAML format
  (`applies_to` + `required: <field>: <type>`); deliberately scoped to top-level structural
  validation in v1.
- **Type system**: `string`, `int`, `bool`, `list`, `dict`, `timestamp`. `timestamp` accepts
  `datetime`, `date`, or `str` because PyYAML auto-parses ISO-8601 to `datetime` and SSD specs
  describe these fields as ISO-8601 strings — both representations are valid in the wild.
- **Gate integration**: new 5th rule `frontmatter-valid` in `methodology/gate-rules.sh` shells
  out to the Python validator. Rule **SKIPs** (not FAILs) when Python 3 or PyYAML is unavailable,
  matching the existing precedent (`tests-pass` SKIPs when no `test_command`).
- **Parity test coverage**: 2 new fixtures in `scripts/parity-test.sh` (valid + invalid
  frontmatter) bring assertion count to 14, all passing.

## Rationale

**Why Python + PyYAML instead of bash:**

- Bash YAML parsing is a known fragility — gate-rules.sh `yaml_get` already documents its
  scalar-only limitation in code comments. Frontmatter has nested structures; expanding the bash
  parser to handle them reimplements PyYAML badly.
- PyYAML correctly handles edge cases that hurt the bash version: comment lines, multi-line
  scalars, ISO-8601 → datetime coercion, list/dict types.
- Python is universally available on the audience's machines (macOS, Linux dev environments).
  PyYAML is a one-line install (`pip3 install pyyaml`) and the standard YAML library.
- ADR-0005's preference for bash was scoped to "whole-repo state checks" (`git log`, `grep`,
  `xargs`) — operations bash is great at. Schema validation against typed structured data is the
  opposite problem; the right tool is different.

**Why a custom YAML schema format instead of JSON Schema:**

- JSON Schema is overkill for v1's needs (top-level field presence + type only).
- Custom format is 5 lines per schema; JSON Schema would be 20+ for the same coverage.
- A v2 of the validator that adds enum/regex/sub-dict validation can adopt JSON Schema then; the
  current format is forward-compatible with a `$ref:` field pointing at a JSON Schema file.
- Custom format reads like the SKILL.md "Required output frontmatter" blocks it mirrors —
  authoring a schema for a new skill is a 30-second cut-and-paste.

**Why SKIP-on-missing-Python instead of FAIL:**

- Matches `tests-pass` SKIP-when-no-test_command precedent (ADR-0005, doctrine: SKIP is not
  FAIL).
- A markdown-library consumer of SSD might not have Python installed and that's fine — the gate
  shouldn't force a Python install onto every consumer.
- A CI environment that DOES have Python will get real PASS/FAIL signal; a dev machine without
  PyYAML gets a clear SKIP message telling them what to install.

## Consequences

**Easier:**
- Frontmatter schemas can grow per-skill without affecting other rules.
- v2 can add per-field enum/regex/sub-dict validation by extending `TYPE_MAP` and the schema
  format. The validator's structure already supports it.
- Adding a new skill's schema is a 5-line YAML file — no orchestrator code change.
- CI integration trivial: `python3 methodology/frontmatter-validate.py --json | jq ...`.

**Harder:**
- Two languages in the gate (bash for the rule wrapper, Python for the validator). The boundary
  is well-defined (the rule shells out and parses stdout) but cross-language debugging is
  marginally more work than single-language.
- PyYAML is a hard dependency for the validator (graceful SKIP at the gate level mitigates).
- Schema files in YAML must stay in sync with each SKILL.md's "Required output frontmatter"
  block. No mechanical enforcement yet — relies on convention. A future iteration could generate
  schemas from SKILL.md or vice versa.

**What we give up:**
- Single-language gate. The doctrine of "the gate is bash" (ADR-0005) is now "the gate is bash
  with one Python sub-rule." Defensible but worth naming.

## Alternatives Rejected

- **Extend bash `yaml_get` to handle nested fields.** Rejected: reimplements PyYAML badly. The
  awk pattern is already at the edge of maintainability for scalar-only reads. Adding nested-dict
  support would push it past that edge.
- **Use `yq` instead of Python.** Considered. `yq` isn't universally installed; Python is. The
  Python option keeps install friction minimal for the audience.
- **JSON Schema instead of custom YAML.** Premature for v1. Forward-compatible (the schema files
  can adopt a `$ref:` indirection later).
- **Generate schemas from SKILL.md.** Tempting but more complex than the iteration warrants. Two
  hand-written schemas can drift; mechanically generated schemas trade drift for generation
  complexity. Defer.
- **Validate via a pre-commit hook instead of a gate rule.** Hooks are opt-in per developer;
  gates fail in CI. The gate rule guarantees the check runs in CI; a hook is a developer
  convenience layer that can be added on top later.

## Future Compatibility

- v2 of the validator: per-field enum/regex/format validation, sub-dict shape enforcement.
  Schema format extends with `enum:`, `pattern:`, `nested:` fields; validator extends `TYPE_MAP`
  semantics.
- A potential reimplementation in Go/Rust as a static binary remains an option — the validator's
  stdout contract (`STATUS path [skill] :: detail` lines, `--json` for structured) is the
  interface, language is implementation detail.
- Schemas can opt into JSON Schema for richer constraints by referencing an external schema file
  via `$ref:`. The custom format is the v1 default because it's lighter-weight and matches the
  SKILL.md prose it mirrors.

## Why This ADR Is Retroactive

The v1.14.0 commit shipped the validator and the new gate rule without an ADR. The `adr-delta`
gate rule fires (correctly) when 200+ architectural lines change without an accompanying ADR;
the post-merge gate run on `main` would have caught this if invoked. Surfaced when the user
asked for a `/ssd status` summary on 2026-05-04 — the gate `adr-delta` rule FAILed with "424
architectural lines changed but no ADR delta in docs/decisions/" against `main`. This ADR
closes that finding.

The lesson: the gate runs on the development branch before merge, but no automated mechanism
runs it on `main` post-merge to catch decisions that should have been documented. A future
iteration could add a post-merge gate sweep to surface this kind of miss earlier. For now, it
surfaces on the next `/ssd status` invocation, which is acceptable but worth noting.
