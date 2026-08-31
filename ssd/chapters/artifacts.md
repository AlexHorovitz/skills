<!-- Chapter of ssd/SKILL.md (spine). Loaded on demand by the /ssd orchestrator. License: see /LICENSE. -->

## The SSD Artifact Tree

Every SSD invocation produces artifacts at well-known paths relative to the project root. Sub-skills
read from and write to this tree. This is the mechanism that lets a session resume, a reviewer verify,
and a team member onboard.

```
<project-root>/
├── docs/
│   ├── decisions/                       # ADRs from architect (committed)
│   │   ├── ADR-0001-database-choice.md
│   │   └── ...
│   ├── runbooks/                        # Runbooks from systems-designer (committed)
│   │   └── <feature>.md
│   └── architecture/                    # Component diagrams, data models (committed)
│       └── <feature>.md
└── .ssd/                                 # SSD orchestrator state — gitignored by default
    ├── project.yml                      # Project shape: language, framework, platform
    ├── current.yml                      # Active features / milestones pointer
    ├── features/
    │   └── <feature-slug>/
    │       ├── 00-brief.md              # User's original brief (epic-level for multi-iter)
    │       ├── 01-architect.md          # architect spec (epic-level for multi-iter)
    │       ├── 02-systems-designer.md   # production readiness (epic-level for multi-iter)
    │       ├── 03-coder-status.md       # — single-cycle features only
    │       ├── 04-code-review.md        # — single-cycle features only
    │       ├── 05-deploy.md             # — single-cycle features only
    │       └── iterations/              # — multi-iteration features only (opt-in, see ADR-0001)
    │           └── <iter-id>/           # e.g., 3a, 3b, auth-flow
    │               ├── brief.md
    │               ├── coder-status.md
    │               ├── code-review/     # multi-round gates (round-N.md from iter 3 / P1.2)
    │               ├── deferred.yml     # carry-over ledger (iter 4 / P1.5)
    │               └── deploy.md
    ├── milestones/
    │   └── YYYY-MM-DD-<topic>/
    │       ├── sha-before               # git SHA at milestone start
    │       ├── metrics-before.yml       # coverage, perf, etc.
    │       ├── skeptic-before.md        # codebase-skeptic output pre-refactor
    │       ├── refactor-plan.md         # refactor skill output
    │       ├── refactor-prs.md          # list of PRs + per-PR code-reviewer outputs
    │       ├── skeptic-after.md         # codebase-skeptic output post-refactor
    │       └── verification.md          # /ssd verify summary
    └── archive/                         # closed feature and milestone directories
```

This is the **prescribed** layout. Teams may extend it but may not rename these files — sub-skills load
them by name. If the project already has `docs/decisions/`, `.ssd/` sits alongside it.

The `.ssd/` directory (and its `.gitignore` entry) is created by the `ssd-init` skill, which runs once
at the start of any SSD-managed project. `ssd-init` is a prerequisite for any `/ssd` phase; the
orchestrator checks for `.ssd/project.yml` on invocation and prompts the user to run `ssd-init` if
absent.

**Selective commit split (v1.18.0+, [ADR-0008](../../docs/decisions/ADR-0008-ssd-commit-split.md)).**
Artifacts under `.ssd/` divide along durable-vs-working lines:

| Path / pattern | Committed? | Why |
|---|---|---|
| `.ssd/features/<slug>/00-brief.md`, `01-architect.md`, `02-systems-designer.md`, `03-coder-status.md`, `04-code-review*.md`, `05-deploy.md` | ✅ committed | Durable design records, same class as ADRs |
| `.ssd/features/<slug>/iterations/<iter>/{brief,coder-status,deploy}.md`, `code-review/round-*.md` | ✅ committed | Same — per-iteration variants of the above |
| `.ssd/features/<slug>/iterations/<iter>/deferred.yml` | ❌ gitignored | Machine-managed carry-over ledger |
| `.ssd/milestones/<topic>/{skeptic-before,skeptic-after,refactor-plan,refactor-prs,verification}.md` | ✅ committed | Durable milestone records |
| `.ssd/milestones/<topic>/{sha-before,metrics-before.yml}` | ❌ gitignored | Snapshot machinery, not design docs |
| `.ssd/current.yml`, `.ssd/current.notes.yml`, `.ssd/init-log.md`, `.ssd/project.yml` | ❌ gitignored | Machine-managed state with absolute paths, per-user profile, draft handoff notes |
| `.ssd/archive/` | ❌ gitignored | Historical state of closed workstreams (their durable artifacts stay tracked in `features/<slug>/`) |
| `.ssd/audits/` | ❌ gitignored | Often sensitive — vendor names, internal opinions |

The gitignore pattern, the `no-leaky-state` gate rule (§ "Methodology Enforcement"), and the
optional pre-commit hook all share the same deny-list — they're symmetric layered defenses
around the same boundary. A solo developer who prefers the legacy v1.3.0–v1.17.x blanket
behavior sets `project.yml.ssd.gitignore_mode: blanket` and replaces the selective `.gitignore`
pattern with a bare `.ssd/` line; the `no-leaky-state` rule then SKIPs cleanly.

**Private mode (v2.8.0+, [ADR-0017](../../docs/decisions/ADR-0017-private-mode.md)).** A third value,
`gitignore_mode: private`, tracks **nothing** SSD produces — the whole of `.ssd/` plus the
`docs/decisions/`, `docs/runbooks/`, and `docs/architecture/` trees. The three modes side by side:

| Path class | `selective` (default) | `blanket` | `private` |
|---|---|---|---|
| `.ssd/features/**` durable artifacts | ✅ committed | ❌ | ❌ |
| `.ssd/milestones/**` durable records | ✅ committed | ❌ | ❌ |
| `.ssd/gate.yml` (ADR-0015 gate inputs) | ✅ committed | ✅ committed | ❌ |
| `.ssd/` machine state | ❌ | ❌ | ❌ |
| `docs/decisions/` ADRs | ✅ committed | ✅ committed | ❌ |
| `docs/runbooks/`, `docs/architecture/` | ✅ committed | ✅ committed | ❌ |
| `no-leaky-state` gate rule | enforces the split | SKIPs (nothing to protect) | **enforces the privacy boundary** |

Two things to note about the last row and the `gate.yml` row:

- Private mode is the mode where `no-leaky-state` is **load-bearing** rather than advisory. Under
  `blanket` it SKIPs because nothing needs protecting; under `private` a leaked artifact is a privacy
  failure, not commit noise.
- Private mode **does not change artifact paths** — ADRs still go to `docs/decisions/` in every mode.
  Only the commit posture changes. Relocating them under `.ssd/docs/` was considered and rejected;
  twelve non-`.ssd/` files hardcode `docs/decisions/`, and ADR-0008 already settled this as "keep the
  paths, change the gitignore."

**The private artifact store (v2.10.0+, [ADR-0018](../../docs/decisions/ADR-0018-ssd-artifact-store.md)).**
Private mode makes the record invisible; it does not make it *durable*. The store closes that by making
`.ssd` an **absolute symlink** into a per-project subdirectory of one separate private git repo:

```
<store-root>/            ← ONE git repo: the private history
├── .gitignore           ← MINIMAL. Must NOT copy SSD's project-side ignores, or the store
├── README.md              silently drops current.yml, project.yml, archive/ and *.bak —
├── <project-a>/           precisely the files whose history it exists to keep.
└── <project-b>/

<project-a>/.ssd  ->  <store-root>/<project-a>      (never committed)
```

Every skill and gate rule reads `.ssd/` unchanged: all three helpers resolve `PROJECT_ROOT` once from
the invocation cwd and then read `"$PROJECT_ROOT/.ssd/…"`, which the filesystem resolves through the
link. **No tool anywhere `cd`s into `.ssd/`**, so none can resolve the *store's* git root by mistake —
which is why the mechanism needs zero consumer changes.

**Requires `private` or `blanket`, and this is a hard constraint, not a preference.** Git cannot track
files through a directory symlink at all (`fatal: pathspec … is beyond a symbolic link`), so
`selective` mode's whole purpose — committing `.ssd/features/**` into the project — becomes silently
impossible. `store.sh link` refuses on `selective`; `store-link-sane` FAILs on it.

Managed by [`methodology/store.sh`](../../methodology/store.sh): `status` · `init` · `link` (dry-run by
default; it *moves* your artifacts) · `commit` (**local only**) · `push` (explicit). With
`store.auto_commit: true`, phase advances commit the store automatically — committing is bookkeeping,
pushing stays an outward action under explicit control.

Canonical pattern sources: [`methodology/selective.gitignore`](../../methodology/selective.gitignore)
and [`methodology/private.gitignore`](../../methodology/private.gitignore). Both are consumed verbatim
by `ssd-init` Step 5 and `methodology/migrate.sh`; neither pattern is duplicated anywhere else.

**Worktree note (v1.15.0, [ADR-0007](../../docs/decisions/ADR-0007-parallel-features.md)):** a workstream
with a non-null `worktree:` field has its *working tree* (source files, in-progress edits) at the
recorded sibling path — but the authoritative `.ssd/` directory remains at the main repo checkout.
`current.yml`, `current.notes.yml`, and the `features/<slug>/` artifact tree are read and written
only in the main checkout; linked worktrees share the git index but not the `.ssd/` working files
(`.ssd/` is gitignored). Sub-skills invoked from a linked worktree resolve the main checkout's
path via `git rev-parse --path-format=absolute --git-common-dir` (then take the parent directory)
before touching `.ssd/`. **Requires git 2.31+** (the `--path-format` flag was added in March
2021); on older git, fall back to `realpath "$(git rev-parse --git-common-dir)"` which works
back to git 2.5+ but requires a `realpath` binary (GNU coreutils or BSD/macOS native). The
iteration-B `worktree` and `switch` commands carry this fallback in their git-shell-out helper.

---

