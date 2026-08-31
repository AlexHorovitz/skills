# ADR-0018: The SSD artifact store — a symlinked `.ssd` backed by a separate private repository

## Status

Proposed — 2026-08-28 — designed in the `ssd-store` workstream
([01-architect.md](../../.ssd/features/ssd-store/01-architect.md)).

## Context

[ADR-0017](ADR-0017-private-mode.md) (v2.8.0–v2.9.0) gave SSD a private posture: under
`gitignore_mode: private` nothing SSD produces is tracked by the project's git. That solved
**visibility** and said nothing about **durability**.

The consequence is sharp. A private project's entire methodology record — every brief, architect spec,
review round, deploy log, and the whole evolution of `current.yml` — lives in one untracked directory
on one machine. No history, no backup, no way to see how a decision moved, and one `rm -rf` ends it.
Private mode is *for* work where the paper trail matters (client engagements, a personal practice
inside a team repo) and is therefore exactly where losing it hurts most.

The user's requirement: capture everything under `.ssd/` in a **separate git repository**, outside the
project, by making `.ssd` a symlink into it — so the complete SSD workflow and history is preserved
independently of a project that has privacy turned on.

## Decision

**`.ssd` becomes an absolute symlink to a per-project subdirectory inside one private git repository.
Every SSD skill and gate rule continues to read and write `.ssd/` unchanged.**

```
<store-root>/                 ← ONE git repo: the private history
├── .gitignore                ← minimal (see "The store's ignores")
├── README.md
├── <project-a>/              ← project A's .ssd content, fully committed
└── <project-b>/

<project-a>/.ssd  ->  <store-root>/<project-a>      (absolute; NEVER committed)
```

### The symlink is the single source of truth

`project.yml` records the store location too, but `project.yml` **lives inside the store** — reading it
already required following the link. So it can never be the authority. `store.sh status` uses
`readlink`, and a `project.yml` that disagrees with the link is **drift to report**, not a value to
trust. `store-link-sane` FAILs on that disagreement.

### Zero changes to existing consumers

Verified by inspection, not assumed: **no tool anywhere `cd`s into `.ssd/`.** All three helpers
(`gate-rules.sh`, `migrate.sh`, `issue-sync.sh`) resolve `PROJECT_ROOT` once via
`git rev-parse --show-toplevel` from the invocation cwd and then read `"$PROJECT_ROOT/.ssd/…"`, which
follows the symlink transparently. `ls`, `find`, `head` and `[[ -f ]]` were all confirmed to traverse
it. No consumer needed changing — which is what makes this mechanism cheap rather than invasive.

### The leak this feature would otherwise create

**A symlinked `.ssd` defeated both existing protection layers.** Reproduced on a scratch repo before
any code was written:

```
$ cat .gitignore                 # methodology/private.gitignore, verbatim
.ssd/
$ git check-ignore -v .ssd
(no output)                      # NOT IGNORED
$ git add -A && git commit -m t && git ls-files -s
120000 1043e5e0… 0    .ssd       # committed, as a symlink
$ git cat-file -p 1043e5e0
/private/tmp/slink/store/proj    # the ABSOLUTE TARGET PATH
```

Two independent causes:

- **`.gitignore`:** a trailing-slash pattern matches **directories only**. To git a symlink is a
  *file*, so `.ssd/` cannot match a symlink named `.ssd`. A bare `.ssd` line does.
- **`no-leaky-state`:** its deny-list uses the same prefix form.
  `matches_deny_pattern ".ssd" ".ssd/"` → **no match**; with an exact `.ssd` entry → match.

Left unaddressed, enabling this feature would commit the user's home path and private-store location
into the very repository they are keeping private. **The naive implementation inverts the feature's own
purpose.** Three layers therefore ship together:

1. A bare `.ssd` line in `private.gitignore` — **and deliberately NOT in `selective.gitignore`.** See
   "The store requires private mode" below: adding it there is a catastrophic regression, and the first
   attempt at this feature did exactly that.
2. An exact `.ssd` entry in **both** `no-leaky-state` baselines. This one is safe in both, because it
   only *adds* a deny; it cannot un-include anything.
3. A new gate rule, `store-link-sane`: when `.ssd` is a symlink it must be gitignored, **not tracked**,
   its target must exist, its content must be reachable, the mode must not be `selective`, and
   `project.yml` must agree with the link — every failure mode is a FAIL, never a SKIP, because each is
   a silent leak or data-loss path.

### The store requires private mode — a correction to this ADR's first draft

This ADR originally asserted the store was "not required by private mode, and not requiring it," and
that both pattern files should gain a bare `.ssd`. **Both claims were wrong**, and the test that
settled it is one line:

```
$ git add .ssd/features/f1/00-brief.md
fatal: pathspec '.ssd/features/f1/00-brief.md' is beyond a symbolic link
```

**Git cannot track files through a directory symlink at all.** It only ever records `.ssd` itself as a
symlink blob. So `selective` mode — whose entire purpose is committing `.ssd/features/**` *into the
project* — becomes silently impossible the moment `.ssd` is a link: the allow-list negations can never
match anything. The store therefore **requires `private` (or `blanket`)**, `store.sh link` refuses on
`selective` with that explanation, and `store-link-sane` FAILs on the combination.

And the bare `.ssd` line must **not** go into `selective.gitignore`. A bare pattern excludes the
*directory*, and gitignore cannot re-include a file whose parent directory is excluded — so it renders
every `!.ssd/features/**/…` negation inert and a selective project commits **nothing** under `.ssd/`.
Verified by regression: `git add -A` staged only `.gitignore`. The full 205-assertion suite passed while
that was true, because no fixture asserted selective mode's core promise. One does now
(`selective-artifacts-still-committable`), and it is the guard that would have caught it.

In private mode the same line is harmless — the whole tree is excluded anyway — so that is where it
lives.

### One repo, subdirectory per project

User-ratified. One remote, one clone, one backup, and all SSD history in one place. Per-project repos
remain mechanically workable (the tooling resolves the enclosing `.git`) but one repo is the supported
layout.

### Auto-commit is local; push is explicit

User-ratified: the store is committed on **every phase advance**, giving the finest-grained history —
commit noise is free in a private repo. Constrained deliberately:

- **`commit` has no network path at all.** Committing is bookkeeping; pushing is an outward action that
  stays under explicit human control, consistent with this repo's refusal to auto-tag or auto-push.
- **Silent no-op** when nothing changed, so a phase that wrote nothing produces no commit.
- **Never fails a phase.** A store-commit failure warns and continues — the local `.ssd/` write already
  succeeded and remains the authoritative state, exactly as `issue-sync.sh` treats a mirror failure.

### `link` is the second destructive operation in the library

It *moves* an existing `.ssd/` into the store, so it inherits the discipline ADR-0017's retrofit
established: refuse to clobber a non-empty destination, enumerate every path completely, **dry-run by
default** (exit 10) with `--confirm` to act, `mv` rather than copy-then-delete, and on a cross-device
fallback **never delete the original**.

### The store's ignores must be minimal

`selective.gitignore` deliberately excludes `current.yml`, `project.yml`, `archive/`, `audits/`, `*.bak`
and the snapshot machinery — precisely the files whose *history* this store exists to preserve. Copying
SSD's project-side ignores into the store would silently drop them. The store ignores only noise
(`.DS_Store`, `*.tmp`), and **`*.bak` is deliberately kept**: `migrate.sh` writes backups before
mutating, and in the store those are evidence.

## Rationale

- **A symlink means zero consumer changes.** Every alternative (a config-driven `artifact_root`, a
  wrapper layer, copying artifacts out) would touch every skill that reads `.ssd/`. The symlink is
  resolved by the filesystem, and the audit above proves nothing in the library can see past it.
- **Separation of concerns, with one hard coupling.** ADR-0017 governs what the project *tracks*; this
  governs where the tree *lives*. They compose — but not freely: because git cannot track through a
  symlink, the store requires a mode that tracks nothing under `.ssd/`. That coupling is discovered,
  not chosen, and it is enforced in three places rather than documented and hoped for.
- **The failure mode is the design driver.** The mechanism is a symlink; the *feature* is three layers
  of protection around it plus a helper that will not destroy data. Without those, this is a footgun.

## Consequences

**Easier**
- Full version history of the methodology record, independent of the project.
- One private repo backs up every project's SSD tree.
- Git worktrees can share one authoritative store (each needs its own link), which is arguably better
  than ADR-0007's "authoritative `.ssd` at the main checkout".

**Harder**
- A second repository to keep, push and back up. If it is lost, the history is lost — the store is not
  a backup *of* anything, it *is* the record.
- Two more places where the `.ssd` pattern must stay correct (both pattern files, both deny-lists), on
  top of ADR-0008's existing dual-maintenance warning.
- `project.yml` describing a location it lives inside is a genuine inversion a reader must hold.

**What we give up**
- **Self-containedness.** A project's SSD state is no longer inside the project. Clone the project
  alone and `.ssd` dangles — which `store-link-sane` reports rather than letting SSD write into nothing.
- **Automatic worktree linking** — documented, not built.
- **An unlink verb.** Reversing is `mv` the content back and remove the symlink; automating it would
  add a second destructive path for no gain.

## Non-Goals

- **Not** syncing or merging stores across machines. It is a git repo; the user pushes and pulls it.
- **Not** automatic `push`.
- **Not** encryption. Private by *location*, not cryptography — the same posture as ADR-0017, and
  "private" must not be heard as "secret".
- **Not** compatible with `selective` mode, and this is a hard requirement rather than a preference —
  git cannot track through a directory symlink. `private` or `blanket` only.
- **Not** a change to any project that does not opt in: absent a `store` block and a symlink, behavior
  is byte-identical to v2.9.0.

## Alternatives Rejected

- **Configurable `artifact_root` pointing outside the project.** No symlink, no gitignore hazard — but
  every skill and helper that hardcodes `.ssd/` would need to resolve a variable, and ADR-0017 already
  measured that class of change at **12 non-`.ssd/` files** for `docs/decisions/` alone. Rejected on
  the same "keep the paths" reasoning ADR-0008 established.
- **Copy artifacts into the store periodically.** A sync problem with a stale window and two sources of
  truth. Rejected.
- **Git submodule for `.ssd/`.** Puts a gitlink *in the project's index* — the exact leak this ADR
  exists to prevent, plus submodule ergonomics. Rejected.
- **Relative symlink target.** Leaks less if committed, but breaks worktrees at other depths. Rejected
  because the three layers make an accidental commit the thing we *prevent* rather than mitigate.
- **Per-project store repos as the default.** Stronger isolation, more repos to manage. Available but
  not the supported layout (user-ratified).
- **Auto-push with auto-commit.** Rejected: it would make every phase advance an outward action.
