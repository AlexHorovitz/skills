---
skill: ssd
version: 2.9.0
produced_at: 2026-08-28T00:00:00Z
produced_by: claude-opus-5
project: InsanelyGreat's SSD Skills Library
scope: feature ssd-store
consumed_by: [architect, coder, code-reviewer]
---

# Brief — ssd-store (private artifact store via a symlinked `.ssd`)

## Problem

`gitignore_mode: private` ([ADR-0017](../../../docs/decisions/ADR-0017-private-mode.md), v2.8.0–v2.9.0)
solved *visibility*: nothing SSD produces is tracked by the project's git. It did nothing for
**durability**. A private project's entire methodology record — briefs, architect specs, reviews,
deploy logs, the whole `current.yml` history — lives in one untracked directory on one machine. There
is no history, no backup, no way to see how a decision evolved, and one `rm -rf` ends it.

That is a real gap, not a theoretical one: private mode is *for* work where the paper trail matters
(client engagements, personal practice inside a team repo) and is precisely where losing it hurts.

## Goal

The SSD artifact tree lives in a **separate git repository**, outside the project, while every SSD
skill and gate rule continues to read and write `.ssd/` exactly as before. Full version history of the
methodology record, preserved independently of the project — and invisible to it.

## Mechanism (user-specified)

`.ssd` in the project becomes a **symlink** to a per-project directory inside one private repo:

```
/Users/ahorovit/Development/private-ssd/          ← ONE git repo: the private history
├── .git/
├── skills/                                       ← this project's .ssd content, fully committed
└── <other-project>/

<project>/.ssd  ->  /Users/ahorovit/Development/private-ssd/<repo-name>     (NEVER committed)
```

## User-ratified decisions

Settled before this brief. The architect should treat these as given.

1. **One private repo, subdirectory per project.** Store root is itself the git repo. One remote, one
   clone, one backup, all SSD history in one place. (Per-project repos remain *mechanically* workable
   since the tooling resolves the enclosing `.git`, but one repo is the supported layout.)
2. **Auto-commit on every phase advance.** The store is committed automatically as work progresses —
   the finest-grained history, and commit noise is free in a private repo.
   **Constrained by the architect:** auto-commit is **local only**. `push` stays explicit, because
   committing is bookkeeping and pushing is an outward action.
3. **Absolute symlink target.** A relative target breaks git worktrees at other depths, and worktrees
   are a first-class SSD feature ([ADR-0007](../../../docs/decisions/ADR-0007-parallel-features.md)).
   The absolute path is safe *because* the symlink is never committed — see H1, which is the whole
   safety story.

## H1 — the finding that reshapes this feature (verified, not assumed)

**A symlinked `.ssd` is not covered by either existing protection layer.** Reproduced on a scratch
repo before designing:

```
$ cat .gitignore            # methodology/private.gitignore, verbatim
.ssd/
docs/decisions/ …

$ git check-ignore -v .ssd
(no output)                 # *** NOT IGNORED ***

$ git add -A && git commit -m t && git ls-files -s
120000 1043e5e0… 0    .ssd            # committed, as a SYMLINK
$ git cat-file -p 1043e5e0
/private/tmp/slink/store/proj         # the ABSOLUTE TARGET PATH
```

Two independent reasons:

- **`.gitignore`:** a pattern with a trailing slash matches **directories only**. To git a symlink is
  a *file*, so `.ssd/` cannot match a symlink named `.ssd`. A **bare `.ssd`** line does — verified.
- **`no-leaky-state`:** its deny-list uses the same `.ssd/` prefix form. `matches_deny_pattern ".ssd"
  ".ssd/"` → **no match**; `matches_deny_pattern ".ssd" ".ssd"` → match. So the gate's second layer is
  equally blind, and an exact `.ssd` entry is required.

**Consequence if unaddressed:** enabling this feature on a private project would commit
`/Users/<name>/Development/private-ssd/<project>` into the very repository the user is keeping
private — leaking their username and the store's location. **The feature's naive implementation
inverts its own purpose.** Fixing both layers is not polish; it is the precondition.

## Scope

1. **Both protection layers fixed** — `private.gitignore` *and* `selective.gitignore` gain a bare
   `.ssd`; both `no-leaky-state` baselines gain an exact `.ssd`.
2. **A new gate rule** asserting the link is sane when `.ssd` is a symlink: gitignored, **not
   tracked**, target exists. This is what makes the mechanism safe rather than merely documented.
3. **`methodology/store.sh`** — sibling of `issue-sync.sh` / `migrate.sh`:
   `init` · `link` (migrate an existing `.ssd/` into the store, then symlink) · `status` ·
   `commit` · `push`.
4. **`ssd-init --store <dir>`** and a new step that links the store.
5. **Auto-commit wiring** at phase advance, local only, with the toggle recorded in `project.yml`.
6. **`/ssd store`** orchestrator verb (status · commit · push · link).
7. **ADR-0018**, docs (`chapters/artifacts.md`, `chapters/store.md` or `phases.md`), parity fixtures,
   `VERSION` + banners.

## Hazards for the architect

- **H2 — read-through is fine, but resolution may not be.** Verified that `ls`, `find`, `head` and
  `[[ -f ]]` all traverse the symlink transparently, so the gate rules and `frontmatter-validate.py`
  need no changes. Unverified: whether any tool `cd`s into `.ssd/` and then calls
  `git rev-parse --show-toplevel`, which from inside the store would resolve to the **store's** repo,
  not the project's. Must be checked, not assumed.
- **H3 — the store repo must not inherit SSD's selective ignores.** The point of the store is that
  *everything* is committed, including `current.yml`, `project.yml` and `archive/`, which
  `selective.gitignore` deliberately excludes. The store needs its own minimal `.gitignore`.
- **H4 — `no-leaky-state` semantics inside the store.** If the store's own repo were ever gated, the
  rule would flag as leaks the very files the store exists to commit. Confirm the rule is scoped to
  the *project* and that gating the store repo is out of scope.
- **H5 — worktrees.** Each linked worktree needs its own `.ssd` symlink to the same store. That is
  arguably an improvement over ADR-0007's "authoritative `.ssd` at the main checkout", since state
  becomes genuinely shared — but it must be stated, and creating those links is not automatic.
- **H6 — the store is a second repo the user must not lose.** A broken or dangling symlink means SSD
  silently writes into a normal directory (or fails). The new gate rule covers the tracked/ignored
  half; target existence is the other half.
- **H7 — idempotency and safety of `link`.** It *moves* an existing `.ssd/` into the store. That is
  the second destructive operation in the library (after iteration B's `git rm --cached`), so it needs
  the same discipline: dry-run by default, refuse to clobber a non-empty store, never delete.

## What shipping looks like

`ssd-init --store /Users/ahorovit/Development/private-ssd` on a private project produces a project
whose `.ssd` is a symlink, whose `git status` is clean, and whose SSD history accumulates as commits in
the private repo. `/ssd gate` reports the link as sane. Running the same command on a project that
already has a real `.ssd/` directory migrates it into the store without data loss. A project with no
store configured behaves exactly as it does today.

## Non-goals

- **Not** syncing or merging stores across machines. It is a git repo; the user pushes and pulls it.
- **Not** automatic `push`. Committing is bookkeeping; pushing is outward and stays explicit.
- **Not** encryption. The store is private by *location*, not by cryptography — same posture as
  ADR-0017.
- **Not** a change to any project that does not opt in.
