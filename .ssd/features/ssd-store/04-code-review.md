---
skill: code-reviewer
version: 1.7.0
produced_at: 2026-08-31T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: v2.10.0 as shipped (PR #43, squash c445d08) — post-hoc review
consumed_by: [ssd]
finding_counts:
  blocker: 0
  major: 1
  minor: 0
  question: 0
  suggestion: 0
  nit: 0
gate_pass: false
remediation_mode: false
round: 1
closed_from_previous_round: []
---

# Code Review — ssd-store (v2.10.0 as shipped), round 1

**Verdict: `gate_pass: false` — 1 MAJOR in shipped code.**

**Why this artifact exists, and late.** A `/ssd gate` run found that **PR #43 merged with no
code-review artifact** — rails invariant 4 ("at least one code review with `gate_pass: true`") was
never satisfied for the feature that shipped as v2.10.0. This is the second time in this epic (#41 was
the first). A post-hoc review is worth more than recording the gap, and it immediately found a defect,
which is the argument against treating the missing step as paperwork.

## 🟠 MAJOR-1 — `store_root` / `store_dir` are read with generic key names that already collide in `project.yml`

[methodology/store.sh](../../../methodology/store.sh) `do_status` / `store_dir_name`, and
[methodology/gate-rules.sh:710](../../../methodology/gate-rules.sh#L710).

Both read the store location with flat, generic keys:

```bash
recorded_root="$(yaml_scalar "$PROJECT_YML" root)"
recorded_dir="$(yaml_scalar "$PROJECT_YML"  dir)"
rroot="$(yaml_get "$PROJECT_YML" "root")"; rdir="$(yaml_get "$PROJECT_YML" "dir")"
```

`yaml_scalar` / `yaml_get` match the **first `<key>:` at any indentation**. And `project.yml` has
carried a `root:` key since `ssd-init` v1.0.0 — under `project:`, meaning the **project's own path**:

```yaml
project:
  name: …
  slug: insanelygreat-skills
  root: /Users/ahorovit/Development/insanelygreat/skills   ← this is what `root` resolves to
```

Verified:

```
yaml_scalar root -> [/Users/ahorovit/Development/insanelygreat/skills]   # the PROJECT, not the store
yaml_scalar dir  -> []
```

**Two failure modes, one latent and one active:**

1. **The drift check is silently inert today.** Both call sites guard on
   `[[ -n "$rroot" && -n "$rdir" ]]`. `rdir` is empty (nothing writes a bare `dir:`), so the comparison
   never runs. `store-link-sane`'s `DRIFT` verdict — advertised in ADR-0018 and in the enforcement
   chapter as one of the rule's six checks — **cannot currently fire**. A documented safety check that
   is structurally unreachable is precisely the class this epic has been finding all week.
2. **It becomes a false FAIL the moment anyone writes the documented config.** `ssd-init`'s template
   (as I wrote it) documents a nested `store:` block with `root:` and `dir:`. Fill that in and `rdir`
   becomes non-empty while `rroot` still resolves to the **project** path — so the rule compares the
   link target against `<project-root>/<dir>` and FAILs a perfectly healthy store.

So the feature ships with its drift check dead, and the act of configuring it as documented turns the
check actively wrong. Either alone is a MAJOR; together they are the same defect from both sides.

**Root cause, stated plainly:** I designed a *nested* `store:` block but read it with *flat* readers
that have no block scoping. `gate-rules.sh`'s `yaml_get` and `store.sh`'s `yaml_scalar` are both
documented as "first `key:` at any indentation" — the design and the readers were never reconciled.

**Recommended fix — flat, uniquely-named keys, not a new block-scoped reader.**
`project.yml`'s `ssd:` block is already flat and already has the naming precedent: **`worktree_root`**.
So `store_root`, `store_dir`, `store_auto_commit`. Each is unique in the file, both existing readers
work unmodified, and no new YAML machinery is introduced to a pair of deliberately crude parsers.

Rejected alternative: add a block-scoped getter to both files. It preserves the prettier nested block,
but it means two new readers (or duplicating `migrate.sh`'s `set_yaml_scalar` scoping logic in two more
places) to solve a problem that a naming change solves for free. `worktree_root` shows the flat form is
this file's convention anyway.

## What I verified and did not flag

| Claim | How |
|---|---|
| The three leak layers hold | `git check-ignore .ssd` ignores the symlink; `git add -A` stages nothing; both deny-list baselines carry an exact `.ssd`; `store-link-sane` PASSes on a healthy link. Re-confirmed on the shipped tag. |
| `link` is non-destructive by default | Dry-run moves nothing and exits 10; the complete file list is printed first. |
| `mv`-into-existing-dir is fixed | `rmdir` of an empty destination, then `mv`; content verified through the link before success is reported. Pinned by `store-link-confirm`. |
| `commit` is local-only | No network path in `do_commit`; fixture asserts it. |
| Selective refusal | `link` exits 2 on selective; the rule FAILs on the combination. |
| Zero consumer changes | No tool `cd`s into `.ssd/`; all three resolve `PROJECT_ROOT` from cwd. |
| Parity | 258/258 on the shipped tag; mechanical gate vs `v2.9.0` is 7 pass · 4 skip · 0 fail. |

## Required to close

MAJOR-1 must be fixed. It is in released code, so the fix is a **patch release (v2.10.1)**, and the
fixture must be shown to fail against the shipped reader before the rename lands.
