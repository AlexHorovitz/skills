# Changelog

All notable changes to the InsanelyGreat's SSD skills library are documented here.

Format: `[version] — date — description`

---

## [2.11.3] — 2026-09-01

### A stacked pull request triggered no CI at all, and the merge button still looked green

Found by running `/ssd gate` on a stacked PR rather than by auditing the workflow. `quality.yml`
filtered `pull_request` on `branches: [main]`, so a PR whose base is another feature branch matched
nothing:

```
gh pr checks 48  → no checks reported on the 'fix-doc-truth-d12-d13a' branch
gh run list --branch fix-doc-truth-d12-d13a → (empty)
```

**PR #48 merged into its parent branch with zero checks** — no gate, no parity, no shellcheck. Its
content was covered afterwards, when the parent's own PR re-ran against `main`, but that is coverage
*after* the merge decision, and only if the stack is merged bottom-up. A safety net that disappears
exactly when you split work into a stack is worse than no net, because nothing about the UI says so.

**Two changes, and the second is the one that makes the first useful.**

The `branches:` filter is gone from `pull_request`, so any PR triggers CI regardless of base. `push`
stays scoped to `main` — a push-triggered gate run has no base to diff against, which is why the gate
job is already `if: github.event_name == 'pull_request'`.

The gate job no longer hardcodes `--base origin/main`. It resolves **`github.base_ref`**, the PR's own
base. Without that, a stacked PR would be measured against `main` and report the *whole stack* rather
than its own delta — inheriting its parent's findings and turning the check into noise. #48 would have
gone red on `feynman-clean` for a report it did not contain.

`base_ref` reaches bash through **`env:`**, not through `${{ }}` inside the `run:` block. A branch name
can contain shell metacharacters and the runner expands interpolations before bash sees them; that is
the standard GitHub Actions script-injection vector, and a workflow that lints other people's shell
should not model the mistake.

**Parity 294 → 300.** Six structural assertions on the YAML, each verified to fail individually — three
separate reversions, because unscoping `push` and unfiltering `pull_request` are independent edits and a
single batch revert would have left two assertions unproven.

They are **structural**, and labelled as such in the fixture: a bash suite cannot exercise a GitHub
Actions trigger. The proof that a stacked PR now gets checked is a green check on one, which is an
observation to make rather than an assertion to write. This release's own PR is not stacked, so it does
not provide that evidence either — the next stacked PR does.

One assertion **failed on its first run against the finished fix**: the regex for *"base_ref is not
interpolated into a run block"* matched the correct `env:` line. Restated as "the interpolation occurs
exactly once, and that once is the env assignment." An over-broad regex is a broken assertion, not a
finding — the third time this session an assertion has caught its own author.

---

## [2.11.2] — 2026-09-01

### Two documents asserted things the system contradicted — and prose fixes now carry assertions

Closes **D12** and **D13a** from the [post-v2.11.0 audit](.ssd/milestones/2026-09-01-post-v2.11.0-audit/feynman.md).
Both were documentation-truth defects, the kind that normally get fixed and then rot again because
nothing checks them. Each fix ships with a parity assertion.

**D12 — `quality.yml` claimed there was no branch protection here.** There is: an active `Overwatch`
ruleset on every branch requiring `pull_request` and `required_signatures`, which is why every push
this session reported *"Bypassed rule violations"*.

The reconciliation matters more than the correction, because ADR-0012 Pillar 5 explicitly rejects
branch-protection walls and three other files repeat that doctrine. **The doctrine survives intact:**
Pillar 5 rejects *required status checks that gate a merge*, and the ruleset does not list
`required_status_checks` — so neither CI job can block anything, and admins bypass it anyway.
A PR requirement is a paper trail, not a wall. The header now says that, and cites the `gh api`
invocation that proves it.

**D13a — `phases.md` quoted a `core.md` line that did not exist.** It put *"tag every release"* in
quotation marks and attributed it to `core.md` §4. `grep -cwi tag methodology/core.md` returned **0**,
and §4 is the Ratchet Principle — tests, types, lint, coverage. The entire release-tagging obligation
cited a phrase from a document that had never contained it.

Fixed at the source rather than by deleting the claim: `core.md` §4's ratchet-mechanism list gains the
tooth **"Every release is tagged on its merge commit"** — an untagged release is a version you cannot
navigate back to, which is precisely the ratchet slipping backward. `phases.md` now quotes that tooth
verbatim, so the citation resolves.

**Two more things the same sentence was getting wrong.** It claimed the post-v1.19 milestone *fixed*
the missing-tags drift; that milestone closed it for **v1.16.0 and later**, and 16 releases below that
line remain untagged. The text now says the fix was scoped, not finished. And the copyable `git tag`
example used `-m` with a double-quoted summary — backticks inside which the shell command-substitutes
before git sees them, exactly what mangled the `v2.10.0` annotation in this repo. The example now uses
`-F` with a heredoc, and says why.

**Parity 291 → 294.** Three assertions, each verified to fail against the unfixed text: the tooth
present in `core.md`, the quote verbatim in `phases.md`, and `quality.yml` no longer asserting the
false claim. The third one **failed on its first run against the fix** — the new header quoted the old
claim verbatim while explaining it, and a grep cannot tell an assertion from a quotation. The
correction was reworded rather than the assertion weakened.

No `migrations.yml` entry: the tagging obligation already existed in `phases.md`, so nothing a project
must do has changed — only whether the citation for it resolves.

---

## [2.11.1] — 2026-09-01

### The leak detector returned PASS on a leaked file, if the filename was not ASCII

A post-release `/feynman` audit ([report](.ssd/milestones/2026-09-01-post-v2.11.0-audit/feynman.md))
control-tested `no-leaky-state` with one variable changed — the filename:

```
.ssd/archive/plain.md   →  FAIL no-leaky-state :: 1 file(s) gitignored by policy but tracked
.ssd/archive/café.md    →  PASS no-leaky-state :: no gitignored-by-policy files in diff
                           git's own view: ".ssd/archive/caf\303\251.md"   ·   the file IS tracked
```

`diff_files()` ran `git diff --name-only` without `core.quotepath=false`, so git C-quoted every
non-ASCII path — wrapping it in double quotes and octal-escaping the bytes — and every downstream path
comparison missed. **Six of the twelve rules read that function**, and the worst affected is the one
ADR-0017 and the published guide both call *the primary enforcement of the privacy boundary*.

Present since **v1.5.0 (`ee3b897`), 27 releases.** Not a v2.11.0 regression — v2.11.0 is where someone
finally looked. `rails-walked`, added in v2.11.0, inherited it: a release whose only feature directory
was accented and carried no review returned `SKIP :: release touches no .ssd/features/ directory`, a
reassuring sentence for a check that did not run.

**The fix is one line, and the audit had the shape wrong.** It assumed `-z`, copying `migrate.sh`'s
fix. Tested first: `-c core.quotepath=false` returns raw UTF-8 for accents, spaces, apostrophes and
umlauts alike, while `-z` would change the function's contract from newline- to NUL-delimited and force
all six consumers to move together. Taken, with the residual recorded in the function: a path
containing a literal newline still breaks a newline-delimited pipeline. A newline in a path under
`.ssd/` is pathological; an accent is a Tuesday in a French codebase.

**The sweep, which shrank the audit's own finding.** The audit graded the under-swept class on
`grep -c '\-z'` across four scripts — a measure of a missing flag, not of an exposure. The real sweep
found the library enumerates git paths in exactly **two** places: `migrate.sh` (fixed in iteration B)
and `diff_files()` (this defect). `store.sh` and `issue-sync.sh` never enumerate paths at all. The
audit was right that the class was under-swept and wrong about how far it spread — wrong in the
direction that made the finding sound worse, which is the harder bias to notice.

**The process change matters more than the one-liner.** `code-reviewer` → **1.8.0**: Phase 3.5 gains
step 8, *"Was the CLASS swept, or only the instance?"* — before accepting a fix as closed, grep the
project for the pattern it addresses. Three findings inside two weeks were closed at the wrong
granularity, and each time the reviewer read the diff carefully and the diff was not where the rest of
the defect lived. Step 8 also requires the adversarial probe list to be derived from *this project's*
defect history: round 1 of v2.11.0 ran seven probes against the new rule and non-ASCII paths was not
one of them, in a repo whose own epic had already produced a MAJOR of exactly that class.

**Parity 281 → 291** (+10). Five assertions red against the unfixed enumerator, verified by reversion,
plus a live control outside the fixture. One of the ten passed for the wrong reason on the first red
run — the accented case was masked by the ASCII control still sitting in the diff — and the fixture now
removes the control from the index and asserts that it is gone.

---

## [2.11.0] — 2026-09-01

### The gate finally checks a rails invariant — and the check falsified the audit that asked for it

A `/feynman` epistemic audit ([report](.ssd/milestones/2026-09-01-feynman-audit/feynman.md), posture
`drifting`) found that for eleven releases the gate enforced eleven **hygiene** rules and **not one
rails invariant**. That is why PR #43 shipped v2.10.0 with zero code-review artifacts while every rule
was green and CI passed. This release converts findings into checks that run.

**New rule: `rails-walked`.** A change set that bumps `VERSION` — i.e. claims to be a release — must
carry a code review with `gate_pass: true` for every `.ssd/features/<slug>/` directory it touches.
Deliberately release-scoped: you commit a brief long before a review exists. Only `code-review*.md` /
`round-*.md` count, because `feynman.md` also carries `gate_pass:` and a passing epistemic audit is
not a code review.

**The experiment, and it went against the audit.** Run over **all 25 VERSION-bumping commits in
history**: **1 FAIL · 18 PASS · 6 SKIP.** The audit predicted at least two failures and warned that
more than four would mean the rails were never walked. Actual compliance was **18 of 19** — the rails
*were* walked, by hand, for a year. The gap was in **checking**, not in **doing**, and the audit's
framing said otherwise. It also returned PASS for #41, which **falsifies the "second occurrence in
this epic (#41 was the first)" line this file carried in the 2.10.1 entry** — #41's touched feature
dirs each hold a passing review. That claim was repeated from the record three times and graded by
nobody until a rule did it.

**`_assert` now rejects a non-integer verdict.** bash coerces both `""` and `"banana"` to 0, so an
assertion whose command substitution produced *nothing* scored as a PASS, silently and green. All 211
call sites were already guarded, so no result changes — the guard is now structural rather than
conventional.

**`frontmatter-valid` stops reporting absence when it means "no schema".** On a diff of only
schemaless artifacts it said *"no SSD artifacts in scope"* — false, and standing for four releases
because the previous fix to that block corrected the other branch and left this one asserting
something untrue. New `schemas/brief.yml` and `schemas/deploy.yml` close the coverage gap behind it:
whole-tree validation goes **90 → 98 PASS**, and the two new schemas surfaced 3 genuine violations in
older iterations (backfilled here). The deploy log — the artifact recording what shipped — had never
been validated by anything.

**`/ssd ship --force` is gone from the documentation, because it never existed in the code.** It was
described as "the logged override" in four places; no script accepts it, and `rail_deviations:` has
never been written by any tool in 15 workstreams. Corrected in `ssd/SKILL.md`,
`chapters/enforcement.md`, `chapters/phases.md`, `gate-rules.sh`, and the user-facing `migrations.yml`
guidance. ADR-0016 reasoned *from* the override's existence and gets an addendum rather than a rewrite.
What the docs now say is what happens: you merge a red gate deliberately and record why by hand.
Implementing a real `--force` is a feature with its own ADR, not a refactor.

**shellcheck ran for the first time.** `lint_results:` had recorded `exit_code: 127 — pre-existing
environment gap` across five artifacts and three features; 5,124 lines of shell had never been linted.
The gap was `brew install shellcheck`. It found **2 warnings, 9 findings total, and no quoting bug** —
cleaner than predicted. The one substantive result was a *coverage* gap, not a defect: SC2043 flagged a
one-iteration loop, and asking why it existed revealed that **blanket mode, documented as supported by
the artifact store, had no test at all**. New fixture `store-link-blanket-mode`. A `shellcheck` job
added to CI so the finding cannot silently reopen.

**Parity 264 → 281** (+17), each new fixture verified by reversion.

**One more correction, earned the hard way.** The plan, the review and this entry all first claimed
`rails-walked` would SKIP on the PR that ships it, since a refactor touches no feature directory.
Running the gate returned **`PASS rails-walked :: 2 feature dir(s)`** — R3's metadata backfill touched
two `iterations/` directories that both carry passing reviews. Three documents in a release dedicated
to deleting unchecked claims made the same unchecked claim from reasoning alone, and the new rule
refuted them on its first real run. The blind spot is real and sized at **6 of 25** historical
releases; this PR is simply not an instance of it.

Deliberately **not** in this release (hard rule 4): writing `rail_deviations:`, a real `--force`,
tagging the 16 untagged v1.x releases, forking `rails.md` for a step skipped 13 times out of 13, and
the audit's highest-value item — running SSD on a project that is not this one.

---

## [2.10.1] — 2026-08-31

### The artifact store's drift check shipped unreachable (ADR-0018 addendum)

v2.10.0 designed a **nested** `project.yml.ssd.store` block with `root:`/`dir:` keys and read it with
**flat** readers. Both `gate-rules.sh`'s `yaml_get` and `store.sh`'s `yaml_scalar` match the first
`<key>:` at **any** indentation — and `project.yml` has carried `project.root`, the *project's own*
path, since `ssd-init` v1.0.0:

```
yaml_scalar root -> [/Users/ahorovit/Development/insanelygreat/skills]   # the PROJECT, not the store
yaml_scalar dir  -> []
```

Two failure modes from one cause:

- **The `DRIFT` check could not fire.** Both call sites guard on `[[ -n "$rroot" && -n "$rdir" ]]` and
  nothing writes a bare `dir:`, so the comparison never ran. One of the six checks ADR-0018 advertises
  for `store-link-sane` was structurally unreachable.
- **Configuring the feature as documented made it a false FAIL.** With `dir:` present, `root:` still
  resolved to the project path, so the rule compared the link target against `<project-root>/<dir>` and
  would FAIL a healthy store.

Renamed to **`store_root` / `store_dir` / `store_auto_commit`** — flat and each unique in
`project.yml`, so both readers work unmodified and no new YAML machinery lands in two deliberately
crude parsers. `worktree_root` is the existing precedent. A block-scoped getter was rejected: prettier
block, duplicated scoping logic in two more files.

**How it got through, and it is the process finding that matters:** PR #43 merged with **no
code-review artifact** — rails invariant 4 ("at least one code review with `gate_pass: true`") was
never satisfied for the release. A `/ssd gate` run surfaced the gap, the post-hoc review was written,
and it found this MAJOR in released code on the first pass. Second occurrence in this epic (#41 was the
first). The missing rails step was not paperwork.

Parity: **258 → 264 assertions** (+6), including an assertion that genuine drift is still caught — a
fix that merely deleted the check would have been worse than the bug.

---

## [2.10.0] — 2026-08-28

### The private artifact store — `.ssd` as a symlink into a separate private repo (ADR-0018)

[ADR-0017](docs/decisions/ADR-0017-private-mode.md) solved **visibility**: under
`gitignore_mode: private` nothing SSD produces is tracked by the project. It did nothing for
**durability** — the whole methodology record then lives in one untracked directory on one machine,
with no history, no backup, and one `rm -rf` between you and losing it. Private mode is *for* work where
the paper trail matters, which is exactly where losing it hurts.

`.ssd` can now be an absolute symlink into a per-project subdirectory of one separate private git repo:

```
private-ssd/            ← ONE git repo: the private history
├── .gitignore          ← MINIMAL, deliberately
├── skills/             ← that project's .ssd content, fully committed
└── client-x/

project/.ssd -> private-ssd/<name>       ← never committed
```

- **New `methodology/store.sh`** — `status` · `init` · `link` · `commit` · `push`. `link` *moves* an
  existing `.ssd/` into the store, so it is **dry-run by default** (exit 10) and prints the complete
  file list first — the second destructive operation in the library, held to the same discipline as
  v2.9.0's retrofit interlock.
- **New `store-link-sane` gate rule.** When `.ssd` is a symlink it must be gitignored, **not tracked**,
  its target present, its content reachable, the mode not `selective`, and `project.yml` in agreement.
  Every failure is a **FAIL, never a SKIP**.
- **`ssd-init --store <root>`** and Step 5.6, offered only after private mode is accepted.
- **Auto-commit on phase advance** (`store.auto_commit`), and the constraint that matters: **commit is
  local, `push` is explicit**. `store.sh commit` has no network path at all.
- **Zero changes to any existing consumer.** All three helpers resolve `PROJECT_ROOT` once from the
  invocation cwd and read `"$PROJECT_ROOT/.ssd/…"`, which the filesystem resolves through the link.
  Verified by inspection that **no tool anywhere `cd`s into `.ssd/`**, so none can resolve the *store's*
  git root by mistake. That audit is what made the mechanism cheap instead of invasive.

### The leak the naive implementation would have shipped

Tested before any code was written, and it inverts the feature's own purpose:

```
$ cat .gitignore          # private.gitignore, verbatim
.ssd/
$ git check-ignore -v .ssd
(no output)               # NOT IGNORED
$ git add -A && git ls-files -s
120000 1043e5e0… 0  .ssd  # committed, as a symlink
$ git cat-file -p 1043e5e0
/private/tmp/…/store/proj # the ABSOLUTE TARGET PATH
```

**A trailing-slash gitignore pattern matches directories only, and to git a symlink is a file** — so
`.ssd/` cannot match a `.ssd` symlink. `no-leaky-state` was blind the same way:
`matches_deny_pattern ".ssd" ".ssd/"` is a non-match. Enabling the store would have committed the
user's home path and private-store location into the very repository they were keeping private.

Fixed in three layers: a bare `.ssd` line in `private.gitignore`, an exact `.ssd` entry in **both**
`no-leaky-state` baselines, and the new gate rule.

### Two corrections this feature forced on its own design

- **The store is incompatible with `selective` mode**, and the first draft of ADR-0018 said the
  opposite. One line settled it: `git add .ssd/features/f1/00-brief.md` →
  *`fatal: pathspec … is beyond a symbolic link`*. **Git cannot track files through a directory symlink
  at all**, so selective's whole purpose becomes silently impossible. `link` refuses; the gate rule
  FAILs; the ADR records the correction rather than quietly changing its mind.
- **A bare `.ssd` must NOT go in `selective.gitignore`** — the first implementation put it there. A bare
  pattern excludes the *directory*, and gitignore cannot re-include a file under an excluded parent, so
  it rendered every `!.ssd/features/**/…` negation inert and a selective project committed **nothing**
  under `.ssd/`. `git add -A` staged only `.gitignore`. **The full 205-assertion suite passed while that
  was true**, because no fixture asserted selective mode's core promise. One does now
  (`selective-artifacts-still-committable`), and it is the guard that would have caught it.

### Two bugs the live dogfood found that the fixtures had not

- **`mv src dest` with an existing `dest` moves src *inside* it.** `init` pre-creates `<root>/<dir>`, so
  the happy path produced `<dest>/.ssd/…` instead of `<dest>/…`. The clobber guard only fired on a
  *non-empty* destination.
- **Verifying that the link resolves is not enough.** A misplaced move leaves a symlink to a real
  directory whose content is one level too deep — which reads as healthy until something opens a file.
  `link` now verifies a file that was actually moved, and `store-link-sane` reports
  `MISPLACED-CONTENT` rather than the bogus `SELECTIVE-MODE` it inferred from an unreadable
  `project.yml`.

### Also released here: the epic-close guard fix (PR #42)

Merged to `main` after `v2.9.0` was tagged, so it is **not** in the `v2.9.0` tag and is released with
this version. Recorded here because a shipped fix with no changelog entry is exactly the kind of gap
this project's own gate rules exist to make loud.

`do_close_epic` refuses to close an epic while any `ssd:feature` child is still open — the guard
[ADR-0014](docs/decisions/ADR-0014-github-issue-state-tracking.md)'s D1 split provides against a
**premature epic close**. It was **inert**: found while acting on an instruction to close epic #37, the
tool reported *"all children closed"* with **#38 and #39 both OPEN**.

The same file wrote one format and read another — `ensure_feature` emits `**Epic:** #N` (markdown
emphasis) while `find_open_children` matched the literal `Epic: #N`, so the colon was followed by `**`
rather than a space and the pattern matched **no body for any epic**. The reader now strips emphasis
before matching, which keeps the `#27`-vs-`#270` word boundary intact.

Its fixture had hand-written the child body as plain `x: Epic: #27` — a shape the writer never
produces — so it passed for the entire life of the defect. The fixture now uses the real writer format
and adds a **mirror assertion** that writer and reader still agree.

**On the tag line:** `v2.9.0` points at `7984dd8` (PR #41) and correctly does not contain this fix.
`main` carried `VERSION 2.9.0` while being one commit ahead of that tag — an ambiguity resolved by this
release, where `VERSION` and the `v2.10.0` tag agree again.

Parity: **205 → 258 assertions** (+53). Projects without a store block behave identically to v2.9.0.

---

## [2.9.0] — 2026-08-28

### The private-mode retrofit — and a new manifest concept: entries that are *not* drift (ADR-0017 iter B)

v2.8.0 shipped greenfield private mode and deliberately **no retrofit**: it never ran
`git rm --cached`, so the one destructive operation in the whole feature was quarantined behind its own
review cycle. This is that cycle.

**A decision from iteration A had to be corrected.** Iteration A recorded that the retrofit would be
*"a `/ssd upgrade` migration entry (`private-mode`, mechanical)."* Implemented literally that is
**actively harmful**, because `migrations.yml` exists to answer *"what has this project drifted past?"* —
every entry is drift to be closed:

- **`mechanical`** → `/ssd upgrade --apply` on **any** project would `git rm --cached` its committed
  ADRs, briefs, and reviews. A team repo swept into privacy because someone ran a routine upgrade.
- **`guided`** → re-surfaces every run until adopted, nagging every project forever about a posture
  most should never take.

There is a second-order harm on the mechanical route: version advancement stops at the first
outstanding entry, so **every non-private project would be frozen below it**, reporting permanent,
unclosable drift.

**Private mode is a choice, not a convention. The manifest had no vocabulary for that.**

- **New `elective: true` manifest field** ([ADR-0013 addendum](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)).
  An elective entry is excluded from the default sweep: never listed, never `PENDING`, never applied by
  `--apply`, never a participant in recorded-version advancement. Absent ⇒ false, so all twelve
  pre-existing entries are unaffected. **Orthogonal to `kind`, deliberately not a third `kind` value** —
  `kind` answers *how* an entry is adopted, `elective` answers *whether every project should adopt it*.
  Collapsing them would have destroyed the information the elect path needs (that the entry is
  mechanically appliable), and the 2×2 is fully meaningful in all four cells.
- **New `--elect <id>` / `--confirm`**, surfaced as `/ssd upgrade --apply private-mode`. A pre-loop
  short-circuit mirroring `--adopt`, so the elect path and the sweep can never interleave.
- **Dry-run by default.** `--elect` mutates *nothing* and exits **10** (needs-confirm); `--confirm`
  acts. This inverts the engine's normal behavior deliberately: it is the only operation in
  `migrate.sh` that can remove anything from git, and ADR-0013 iteration A shipped read-only for
  exactly that reason.
- **The itemized-consent interlock.** Enumerates every tracked path under `.ssd/` and the three SSD
  `docs/` trees, prints the **complete** list (never truncated), and separates files SSD demonstrably
  produced from files it **cannot confirm** — by ADR naming *and* by SSD frontmatter, so SSD's own
  runbooks are recognized rather than flagged. A warning that fires on the tool's own output trains
  the user to ignore it. The heading claims only "UNCONFIRMED", never authorship the probe cannot
  establish.
- **Two independent layers** keep an elective entry out of the sweep: the report loop skips it before
  any bookkeeping, **and** elective ids are absent from the swept `apply_dispatch`/`detect` tables.
  Reversion testing showed removing either alone is *not* enough to make `--apply` destructive; both
  are now asserted.

### A field-shifting bug this release almost shipped

Appending `elective` to `read_manifest`'s record broke every entry that lacked an `obsoleted_in` —
which is all of them. **Tab is IFS *whitespace*, so bash collapses consecutive tabs** and every field
after an empty one shifts left. The 7-column form was safe only because its one optional field was
**last**, where a trailing empty field is harmless. The symptom: `--elect private-mode` rejected its own
manifest entry as *"not an elective migration."* The record delimiter is now `\x1f` (unit separator),
which is not IFS whitespace and therefore preserves empty fields — verified empirically, and pinned by
a fixture that tests the observable symptom rather than the delimiter choice.

### Two MAJORs the review caught, both in the destructive path

Found by feeding the interlock a filename the fixtures never tried, and both fixed and verified by
reversion.

- **`git ls-files` C-quotes unusual paths.** Any path with non-ASCII bytes comes back as
  `"docs/decisions/ADR-0002-h\303\251llo.md"` — quoted and octal-escaped. That string cannot match the
  ADR naming pattern (so a real ADR was misreported as UNCONFIRMED), fails `[[ -f ]]` (so the
  frontmatter probe silently could not run), and is rejected by `git rm --cached` as a pathspec. Because
  git validates **all** pathspecs before acting, **one accented filename made the entire retrofit
  impossible.** Enumeration is now NUL-delimited (`ls-files -z`, `sort -z`, `read -r -d ''`).
- **The config was written before the destructive step was validated.** Any `rm` failure left a
  half-migrated repo — `gitignore_mode: private` recorded while every artifact stayed tracked, a state
  neither mode describes. The mitigation was weaker than assumed: `no-leaky-state` is diff-scoped, so it
  **SKIPs** when there is no diff and the state is then invisible. The untrack is now pre-flighted with
  `git rm --cached --dry-run` before anything is written, so a failure aborts with the repo untouched —
  deliberately independent of the quoting fix, so it guards causes nobody has thought of.

Also closed: `set_yaml_scalar` was unscoped, reintroducing a class `bump_recorded_version` had already
been hardened against by a prior review — it now takes a block argument, which matters most for
`issue_tracking`, whose list-item scope made "first match" correct only by accident of the current
template. And `--confirm` outside `--elect` is now a usage error rather than a silent no-op.

**How it got through:** ten fixtures, several genuinely red, every guard reversion-verified — and all of
them using ASCII filenames. Red-first on the cases you thought of is not coverage; the defect was in an
input class the tests never produced.

### Also

- `branch_pattern` defaults to `{slug}` under private mode and the retrofit rewrites an existing key;
  branches of workstreams created *before* the switch are not renamed.
- A portable `set_yaml_scalar` helper (awk + mv, **not** `sed -i` — BSD needs `-i ''` and GNU needs a
  bare `-i`, the same divergence that produced two defects in v2.8.0).
- ADR-0017 amendment recording the elective correction and, explicitly, what the retrofit **cannot**
  undo: history is not rewritten, files are untracked not deleted, and there is no inverse migration.

### Also in this release: two recorded engine defects fixed

Two defects recorded during the `ssd-private-mode` epic and deliberately left out of its PRs under
hard rule 4 ("refactor only after shipping — separate PRs, never mixed with feature work"). Neither is
part of private mode; both are pre-existing engine faults that the epic's dogfooding exposed.

### `issue-sync-current` could never pass, and blamed `gh` for calls it never made

`parse_active_workstreams` treated **every** `- ` line under `active:` as a new workstream boundary.
But `rail_deviations`, `adrs_authored` and `touches` are all documented v2 schema **list** fields, so a
single realistic workstream fragmented into ~18 records:

```
[ssd-private-mode|deploy|]    <- slug + phase, no issue
[||] × 16                      <- one per nested list item
[||39]                         <- the issue, with NO slug
```

The record carrying `issue:` had an empty slug, so the rule's own `[[ -n "$slug" ]]` guard skipped it,
`checked` stayed 0, and it emitted **`SKIP … issue binding(s) present but gh lookups all failed`** —
having made **zero** `gh` calls. A misleading detail string on top of a rule that had, almost
certainly, never passed on a real workstream since shipping in v2.4.0.

The parser is now **indent-aware**: the first list item under `active:` defines the workstream indent,
only `- ` at that exact indent starts a new workstream, and scalar fields are read only at the field
indent. The indent is derived rather than hardcoded, so a change in emitter style cannot break it, and
reading fields only at their own depth means a same-named key nested deeper cannot overwrite the
workstream's own.

On this repository the rule now reports `PASS issue-sync-current :: 1 issue binding(s) open and
phase-label in sync` — its first pass on a real workstream.

**Why it survived so long:** the fixture that covered it built a *flat* `current.yml`
(`slug`/`phase`/`issue`, nothing nested) — a shape no real workstream has. The new fixture is built
from the realistic schema and drives the rule through a mocked `gh`, so it exercises the loop rather
than stopping at the availability check. It also asserts the rule **keeps its teeth**: label/phase
drift must still FAIL, since a "fix" that made the rule always pass would be worse than the bug.

### `committed-gate-yml` / `strict-selective-gitignore` reported ERROR for an unmet precondition

On a project with no `.gitignore` at all, both appliers returned failure, so the engine emitted
`ERROR :: apply ran but convention still absent` and **exit 3** — telling a user their upgrade engine
was broken when the project state simply was not ready. The same misleading-signal class v2.9.0 fixed
for `gate-inputs-present`, in two appliers that never adopted the `NOOP` vocabulary it introduced.

Both now return `NOOP` (8) with a note naming the missing precondition **and the remedy**:

```
NOOP committed-gate-yml :: … no .gitignore exists, so the !.ssd/gate.yml exception cannot be
                           added — run the selective-gitignore migration first
```

`committed-gate-yml` guards **before** creating `gate.yml`, so it no longer leaves a half-applied
convention behind. Both fixtures carry a control arm asserting that with the selective pattern present
the migrations still apply — a fix that made them unconditionally NOOP would be worse than the bug.

**A declarative alternative was considered and rejected on evidence.** Adding a `requires: <id>` field
to the manifest, checked generically by the engine, reads as the better design. It does not work here:
`selective-gitignore`'s detect probe tests the `gitignore_mode` **marker key in `project.yml`**, not the
`.gitignore` **pattern** — and in the exact failing scenario the marker is present while the pattern is
absent. A `requires` guard would have reported "precondition satisfied" and the apply would still have
ERRORed, adding a second false signal on top of the first. Only the applier knows its own real
precondition.

### Release tags backfilled

The 2.x tag line skipped **v2.0.0, v2.5.0, v2.6.0 and v2.7.0** — one more than previously recorded;
v2.0.0 (the BREAKING SSD 2.0 release) was also missing. Each is now tagged on the commit where
`VERSION` became that value, cross-checked against its `CHANGELOG` entry and confirmed to be an
ancestor of `main`. The 2.x line is contiguous v2.0.0 → v2.8.0, and v2.9.0 tags this release.

Parity: **128 → 202 assertions** (+74) across both private-mode iterations and the two engine fixes.
Projects that never elect private mode are byte-identical to v2.8.0.

---

## [2.8.0] — 2026-08-28

### `gitignore_mode: private` — SSD with no paper trail in git (ADR-0017, iteration A)

SSD had two postures toward git and neither was private. Even on `blanket`, `.ssd/gate.yml` was
force-committed, `docs/decisions/` was committed *by design* (ADR-0008 argues ADRs belong in
history), branch names carried an `add-` prefix, and `ssd-init` offered to advertise the practice in
a committed `CLAUDE.md`. A developer wanting to use SSD where the methodology paper trail is
unwelcome — client work, a shared repo where SSD is a personal practice, an OSS contribution — could
hand-edit `.gitignore` and then fight `ssd-init`, `/ssd upgrade`, and the gate rules forever, because
nothing recorded the intent.

`private` is the third value in the enum ADR-0008's "Future Compatibility" section reserved.

- **New canonical pattern file `methodology/private.gitignore`** — six lines against selective's
  forty-plus, ignoring all of `.ssd/` plus `docs/decisions/`, `docs/runbooks/`,
  `docs/architecture/`. Contains **no `!` negation of any kind**, in particular no `!.ssd/gate.yml`.
  Selective mode needs a precise allow-list because it commits a subset; private mode commits
  nothing, so there is no allow-list to get wrong. Carries a `# ssd:gitignore-mode=private`
  sentinel, because `ssd-init` Step 5.5 runs before `project.yml` exists and no functional line in
  the pattern is distinctive enough (a bare `.ssd/` is indistinguishable from blanket).
- **`ssd-init --private`** — Step 5 fourth case, Step 5.5 third detection branch (order is
  load-bearing: **private → selective → blanket**, since a private `.gitignore` also contains a bare
  `.ssd/` line and would otherwise misclassify as blanket), Step 6 template, Step 3 note, and Step 8
  skips the committed-`CLAUDE.md` offer. Sets `branch_pattern: "{slug}"`, forces
  `integrations.github.issue_tracking: off`, and writes `test_command` / `feature_flag_marker` as
  **real keys** in `project.yml` rather than commented placeholders.
- **`issue-sync.sh preflight` refuses under private mode** (`exit 4`, `state=refused`,
  `reason=private-mode`), before any `gh` call. Duplicates `ssd-init`'s refusal on purpose:
  `project.yml` is hand-editable, so init-time validation alone is a single point of failure.
- **`migrate.sh`: `committed-gate-yml` and `strict-selective-gitignore` are N/A under private.**
  Left alone they reported *permanent, unfixable* drift — and `--apply` would have re-added the
  `!.ssd/gate.yml` negation, **actively breaking privacy**. A latent defect in the existing upgrade
  path that private mode would have tripped. `apply_gate_inputs_present` now writes to `project.yml`
  under private mode, so it and `ssd-init` agree on where a private project's gate config lives.

### The gate must not go quiet

Four gate rules are diff-scoped, and under private mode no SSD artifact is ever in a diff. All four
bodies were read rather than assumed:

- **`adr-delta` was a hard deadlock, not a degradation.** Past the 200-line threshold it FAILs
  demanding a committed ADR delta that private mode forbids, while `no-leaky-state` FAILs if one is
  force-added. **Both branches FAIL and the gate becomes unpassable** on an ordinary feature. Fixed
  with a new `artifact_scope()` helper (`diff` normally, `worktree` under private) and a worktree
  probe for an ADR modified since the base commit.
- **`feynman-clean`** globs reports on disk under private mode; diff-scoping left it permanently
  toothless, so a project that ran `/feynman` and got contradicted claims would have sailed through.
- **`frontmatter-valid` needed no change** — its existing no-diff branch already walks the tree.
  Pinned by a fixture so a future refactor cannot silently blind private projects.
- **`no-leaky-state`** runs against an expanded deny-list under private mode and becomes the primary
  enforcement of the privacy boundary. Under `blanket` it SKIPs because nothing needs protecting;
  under `private` a leaked artifact is a privacy failure, not commit noise.

This was not optional polish. SSD shipped [ADR-0015](docs/decisions/ADR-0015-ssd-init-gate-readiness.md)
because `/ssd gate` once exited 0 with one of nine rules having verified anything — "a green signal
that attests to less than the reader believes." Shipping private mode with a hollow gate would have
reproduced SSD's own worst documented failure, deliberately, three releases after fixing it.

### An unrecognized `gitignore_mode` is now loud

`no-leaky-state` used to emit `SKIP :: unknown gitignore_mode`, so a typo (`privat`) silently
disabled SSD's only leak-detection rule. It now **FAILs**. Under a mode whose entire purpose is
privacy, a typo that turns protection off without saying so is unacceptable. `blanket` still SKIPs —
the loud error is for *unrecognized* values, not the documented opt-out. No fourth status was
invented; FAIL is the loud channel in the `PASS|FAIL|SKIP` contract.

### Two MAJORs the code review caught

Both were in the *seams* rather than the design, and neither was reachable by the coder phase's own
dogfood (macOS, `selective`-shaped `project.yml`). Both closures were verified by reverting the fix
and confirming the new fixture fails — not by reading the claim.

- **`file_mtime` tried the BSD form first**, which corrupts the value on every GNU/Linux host: there
  `-f` is `--file-system`, so `stat -f %m FILE` parses as two operands and prints a filesystem status
  block to **stdout** before failing. `adr-delta` would have FAILed on every private Linux project,
  CI runners included — the same defect class as the `find` bug below, on the opposite platform. Now
  GNU-first **and** validating the result is a bare integer, so no `stat` variant's output can be
  mistaken for a timestamp.
- **The private `no-leaky-state` branch silently dropped `project.yml.ssd.gitignored_state`**,
  contradicting both `chapters/enforcement.md` and the `project.yml` template's "additive only"
  promise — in the one mode where the rule is the primary safety layer. The same failure shape as the
  hazard this whole workstream was organized around, reintroduced one screen below the fix. The read
  is now hoisted above the mode branch so there is **one** deny-list assembly for both modes and the
  two drifting call sites no longer exist.

Also closed: the worktree `feynman-clean` glob recognized a broader artifact set than diff scope (a
`feynman-draft.md` under `.ssd/` would have FAILed the gate while being ignored on a selective
project), and `apply_gate_inputs_present`'s private branch was missing the `^ssd:` guard both sibling
appliers use.

### Two bugs the fixtures caught during development

- **`find -newermt "@epoch"` is GNU-only.** BSD `find` (stock macOS) rejects it outright —
  `Can't parse date/time` — which turned the `adr-delta` worktree probe into a permanent FAIL on
  macOS, trading the deadlock for a different unpassable gate. Replaced with a portable
  `stat -f %m` / `stat -c %Y` probe. The bug was masked in development by an interactive
  GNU-compatible `find` shim; only the fixture, which runs under `bash`, exposed it.
- **mtime granularity.** `-newermt` and `-nt` are strictly-greater and mtimes are second-granular,
  so an ADR written in the same second as the base commit did not count. The probe now allows one
  second of slack — erring toward PASS, since a false FAIL here is an unpassable gate.

### `/ssd upgrade --apply` no longer reports a broken engine for a blameless project

Found as a QUESTION during review of this feature and fixed on the user's direction. Two
individually-correct decisions were colliding: [ADR-0015](docs/decisions/ADR-0015-ssd-init-gate-readiness.md)
specifies a *commented* `test_command` placeholder when no test framework is detected, and the
manifest's `detect` probe deliberately does not match a commented key. The apply returned success,
`detect` correctly reported absent, and the engine — having no vocabulary for "cannot apply" — emitted
`ERROR :: apply ran but convention still absent` and **`exit 3`**. Every project that simply has no
test framework yet was told its upgrade engine was broken.

`apply_dispatch` now has an explicit return-code contract — `0` applied · `8` **NOOP** · `9`
**DEFER** · other ERROR — and the report loop renders `NOOP`/`DEFER` without setting `engine_error`.
A NOOP leaves the convention outstanding and the recorded version parked below it, so a later
`--apply` re-offers it once the precondition exists; the status line names the missing precondition
and the manual fix. **This is ADR-0015's own distinction applied to the migration engine**, which had
the inverse bug: that ADR exists because a rule which *could not run* was indistinguishable from one
that *passed*; here a state that *could not apply* was indistinguishable from one that *failed*.

`9 = DEFER` had been documented in `apply_dispatch`'s contract but handled by **neither** side — a
dead path that would have become a spurious `ERROR` + `exit 3` for the first apply function to use it.
Both codes are now live.

Two adjacent appliers (`committed-gate-yml`, `strict-selective-gitignore`) still report `ERROR` for an
absent precondition, but only in a state where a v1.18.0 migration never ran. Left as a recorded
finding rather than silently widened — see round-3 review.

### The pattern/deny-list mirror test can now actually fail

`deny-list-mirrors-pattern-file` asserted that four **known** patterns appeared in both
`private.gitignore` and `gate-rules.sh`'s `private_baseline`. It could not detect the failure it
existed to prevent: a fifth pattern added to one side left it green, because the fixture never learned
about the fifth. It now extracts both sides and compares them as **sets**, so any addition, removal,
or typo on either side fails by construction — verified in both directions, with the symmetric
difference printed under `-v`. Given that these two files are the same set in two syntaxes and a
forgotten side is a silent privacy leak, a spot-check was not adequate coverage.

### Decisions recorded

- **[ADR-0017](docs/decisions/ADR-0017-private-mode.md)** (new, Proposed) — the mode, its non-goals,
  and the attribution carve-out.
- **[ADR-0015](docs/decisions/ADR-0015-ssd-init-gate-readiness.md) addendum** — private mode
  knowingly reopens root cause **P2**: no committed `gate.yml` can exist, so a private project's
  gate config does not travel to a second clone or a CI runner. Verified graceful (`gate_input()`
  reads `project.yml` first), which is why the inputs are promoted to real keys there. P2's cost is
  proportional to collaborator count, and private mode's premise is that there are none.
- **ADR-0008 reaffirmed, not superseded.** Relocating SSD docs under `.ssd/docs/`, and the general
  `ssd.docs_root` indirection, were both **rejected on measurement**: twelve non-`.ssd/` files
  hardcode `docs/decisions/`, including `rails.md` invariant 7, `adr-delta`, `parity-test.sh`, and
  seven sub-skill `SKILL.md` files. ADR-0008 already rejected this exact move — *"keep the paths,
  change the gitignore."* A falsifiable revisit trigger is recorded.
- **A brief-level correction worth keeping.** The design brief feared that gitignoring `docs/`
  would silently untrack pre-existing non-SSD content. It cannot: **`.gitignore` has no effect on
  already-tracked files.** That hazard exists only via `git rm --cached`, which lives entirely in
  iteration B's retrofit path — which is where its itemized-consent interlock belongs.

### Attribution is deliberately kept

The `🛠️ Crafted with SSD` commit/PR footer is **not** suppressed under private mode. Privacy here
means no SSD mechanics or documentation in the tree; it does **not** mean anonymity. Requires no
code — recorded so the absence of a footer change is not mistaken for an oversight.

### Not in this release (iteration B)

Retrofit via `/ssd upgrade`: the `private-mode` migration entry, `detect_`/`apply_` functions, the
itemized-consent interlock before any `git rm --cached`, the "history is not rewritten" warning, and
the `branch_pattern` override plumbing in `chapters/workstreams.md`. **Iteration A never runs
`git rm --cached`** — the one genuinely destructive operation is quarantined behind its own review
cycle.

Parity: **83 → 128 assertions** (+45). `selective` and `blanket` projects are byte-identical to
v2.7.0 — every change sits inside a `private` branch.

---

## [2.7.0] — 2026-08-26

### `/feynman` is now invoked by the workflow it claimed to serve (ADR-0016)

v2.6.0 shipped the `feynman` skill with an `## Interface` table asserting that `ssd` consumed it, that
it ran at four `/ssd` phases, and that its `gate_pass` "blocks ship on `contradicted` or `theater`
claims." `grep -rn 'feynman' ssd/ methodology/gate-rules.sh` returned **nothing**. Three
present-tense, load-bearing claims backed by no code — the defect this skill exists to find, in the
skill itself. This release backs them, and constrains how.

- **New `feynman-clean` gate rule.** Any `feynman.md` in the change set must report zero
  `contradicted` and zero `theater` claims. Four deliberate properties: it reads the **counters, not
  `gate_pass`** (a rule trusting the boolean could be cleared by editing one character, making the
  report judge its own verdict); it reads **frontmatter only, never the body** (report prose
  legitimately contains lines like `contradicted: 0` — a gate the report can argue with is not a
  gate); it is **diff-scoped**; and **no report means SKIP, never FAIL**.
- **Not a Pillar 5 wall.** [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) Pillar 5's
  reversibility contract says the gate should not block absent evidence of ungated defects reaching
  users. No exception was taken, because none is needed: Pillar 5 rejects *branch-protection walls and
  required merge checks*, not FAILable rules. `wip-commits` has FAILed since v1.4.0 with the same
  logged `/ssd ship --force` override. ADR-0016 § "Alternatives rejected" records why claiming an
  exception would have been a miscategorization with a bad precedent.
- **Proposed, never auto-run.** The skill's own § "Frequency" warns that running it every sprint makes
  it the eighteenth ritual nobody can trace to a decision — *"at which point Phase 3 will catch it, and
  should."* Auto-invocation would make the skill fail its own inventory. So `/ssd milestone` gains
  **Step 0.5**, which *offers* the audit and **records a decline** rather than passing silently (the
  same move v2.6.0 made for the deliberately-unset `feature_flag_marker`: a reader can tell a choice
  from a gap). `/ssd verify` re-proposes it — verification's own "all findings closed" is itself a
  claim worth grading. `/ssd audit` offers it as the internal counterpart to `software-standards`.
- **New `methodology/schemas/feynman.yml`.** Feynman reports were counted among `frontmatter-valid`'s
  "unvalidated (no matching schema)" tally — the count v2.6.0 added to stop overstating coverage.
  `not_examined` is a **required** field: structural validation cannot tell whether an audit was
  honest, but it can refuse a report that never says what it skipped. Gate now reads
  `52 validated; 33 unvalidated`, up from 51/34.
- **What a PASS does not mean.** Every place the rule is documented states that PASS or SKIP means
  "no failing audit in this change set", *not* "this project's beliefs are calibrated." Citing it as
  the latter would be a fresh instance of the misleading-coverage defect v2.6.0 was released to fix.
- **Three stale orchestrator claims fixed while in there.** `ssd/chapters/skills.md` and
  `ssd/chapters/phases.md` both still said `codebase-skeptic` reviews through **ten** expert voices —
  fifteen since v1.5.0 (2026-07-20). This is the same error the v2.6.0 Feynman audit graded 🔴 (C6) and
  "fixed" **in `README.md` only**, leaving it live in the two files the orchestrator actually loads.
  Also: review tiers three → four, `code-reviewer`'s missing `verify` phase, a ninth overlap pair
  (`codebase-skeptic` / `feynman` — coordination, feynman first), and `issue-sync-current` added to
  both enforcement catalogs, which had documented eight and seven rules while the script ran nine.
- **Parity 77 → 83 assertions,** including a **negative** assertion (body prose mimicking clean
  counters must not talk the rule out of a FAIL) and an exit-code assertion. Confirmed the harness
  fails when the rule is deliberately broken — 3 assertions — rather than assuming it checks anything.
- **Migration** `feynman-gate-rule` (guided, ADR-0016). Nothing to install; the rule SKIPs where no
  audit exists, so a project that never runs `/feynman` is unaffected.
- Skills touched: `feynman` → 1.1.0, `ssd` → 2.7.0 (banner re-align, three chapters),
  `methodology` → 1.7.1 (rule catalog completed). `VERSION` → 2.7.0.

## [2.6.0] — 2026-08-19

### Feynman audit remediation — the gate names its skips, and the allow-list actually blocks

A `/feynman` epistemic audit of this repo (`.ssd/milestones/2026-08-19-feynman-audit/feynman.md`)
graded 15 claims the library makes about itself and found four contradicted, three misleading, and one
piece of pure theater. This release closes the ones that were fixable mechanically. New skill
**`feynman`** (1.0.0) — claim ledger, six-grade scale, cargo-cult ritual inventory, and a mandatory
lean-over-backwards self-audit.

- **The library now runs its own gate (C1/C2/C3).** v2.5.0 shipped "the gate is functional, not merely
  present" and never applied it here: no `.ssd/gate.yml`, and the repo's own `.gitignore` never got the
  `!.ssd/gate.yml` negation that went into `methodology/selective.gitignore`. Both fixed, plus a
  `.ssd/project.yml` (the orchestrator refuses to run without one, and the repo had none). `/ssd gate`
  goes from **4 pass / 5 skip** to **5 pass / 4 skip**, with `tests-pass` running
  `bash scripts/parity-test.sh` for real. The remaining `feature-flag-present` SKIP is now a *recorded
  decision* in `gate.yml` — this repo has no runtime flag system — rather than a silent gap.
- **The gate names its skips (C4/C5/C9).** `frontmatter-valid` reported "51 artifact(s) validated" while
  34 artifacts had no matching schema at all; `skill-version-sync` reported "9 skill example(s) match"
  while 2 skills — including `ssd/SKILL.md`, the orchestrator — were structurally exempt. Both rules now
  report the unvalidated/exempt count, and every run ends with
  `GATE N pass · N skip · N fail — a skip is a check that did not run`. `--json` gains `pass_count` /
  `skip_count`.
- **The selective `.gitignore` allow-list is now load-bearing (C12/C14).** `.ssd/*` matches depth-1
  children only, so once `!.ssd/features/` re-included the directory, **every** file beneath it was
  committable and the 12-line allow-list constrained nothing — a stray `secrets.env` under a feature dir
  sailed through, and `no-leaky-state`'s fixed baseline would not catch it. Added `.ssd/features/**` /
  `.ssd/milestones/**` deep denies plus directory re-includes. This also surfaced that
  `code-reviewer`'s declared milestone output `review-<pr>.md` was **never in the allow-list** — three
  such artifacts are tracked in this repo only because the list was inert. `!.ssd/milestones/**/review-*.md`
  and `!.ssd/milestones/**/feynman.md` added.
- **New `strict-selective-gitignore` migration (ADR-0008)** so existing projects actually receive the
  fix. `apply_selective_gitignore`'s idempotency sentinel (`!.ssd/features/**/01-architect.md`) is
  present in the *old* inert block, so re-running it would have skipped silently and left every
  downstream project holed. Verified end-to-end against a pre-change project: `secrets.env` goes
  committable → blocked, all declared artifact paths stay committable, idempotent on re-run.
- **`README.md`** — `/codebase-skeptic` said "10 expert lenses"; it has been fifteen since v1.5.0
  (2026-07-20). Corrected, `/feynman` registered in both tables, `.ssd` → `/ssd` typo in the taxonomy.
- **Parity harness 69 → 77 assertions** — new `strict-selective-gitignore` fixture with negative
  assertions (a stray file *must* be blocked). Confirmed it fails when the migration is deliberately
  broken, rather than assuming it checks anything.

Not fixed here: `ssd-init` Step 6.5 remains prose executed by a model with no harness to test it — the
most important untested path in the library, and the one place the audit could grade nothing.

---

## [2.5.0] — 2026-08-06

### `ssd-init` gate readiness — iteration A (ADR-0015)

`ssd-init` now leaves the gate **functional, not merely present.** Before this change a freshly
initialized project's `/ssd gate` SKIPped `tests-pass` and `feature-flag-present` in *every* project
(P1: `ssd-init` never wrote their inputs), and because those inputs lived only in gitignored
`project.yml` the configuration could not travel to a second clone or a CI runner (P2). Iter A closes
both.

- **`ssd-init` Step 6.5 (new)** — detects the project's `test_command` most-specific-first
  (`Makefile` `test:` → `npm test` → `pytest` → `go test ./...` → `cargo test` → `swift test`; prompt
  on genuine ambiguity, commented placeholder when nothing is detected) and writes it to a **committed
  `.ssd/gate.yml`**. The `project.yml` template gains commented `test_command` / `feature_flag_marker`
  local-override stubs.
- **`.ssd/gate.yml`** — the one committed `.ssd/*` config file, carrying only portable gate inputs
  (`!.ssd/gate.yml` added to `methodology/selective.gitignore`, the single source `ssd-init` and
  `migrate.sh` consume). Machine state stays in gitignored `project.yml`.
- **`gate-rules.sh` fallback chain** — new `gate_input()` reads `.ssd/project.yml` first (local
  override), then `.ssd/gate.yml` (the committed floor); `tests-pass` and `feature-flag-present` use it.
- **Migrations** — `gate-inputs-present` and `committed-gate-yml` (mechanical, ADR-0015) let
  `/ssd upgrade --apply` retrofit projects initialized before this change, with executable
  `detect()`/`apply_*()` in `migrate.sh`.

Iters B (library-root resolution + hook fix), C (Step 9 gate-readiness reporting), and D (workflow-rule
docs + CI validator vendoring) remain pending. Skills touched: `ssd-init` → 1.11.0.

---

## [2.4.0] — 2026-06-14

### GitHub issue state tracking — iteration B (ADR-0014)

Completes the close lifecycle and read-back check deferred from iter A. **Still default-off** — a
project without `integrations.github.issue_tracking: on` is byte-for-byte unchanged, zero network.

- **`issue-sync.sh` `close-feature` / `close-epic`** (replace the iter A exit-2 stubs). Closing is the
  only outward-destructive action and is double-gated: the `integrations.github.auto_close` toggle
  (default `false`) OR an explicit `--confirm` must be present, and `close-epic` additionally refuses
  while any `ssd:feature` child issue is still open. New exit code **10 = needs-confirm** (the
  orchestrator prompts, then re-runs with `--confirm`). Idempotent: closing a closed issue is a no-op.
- **Child discovery by label query** (MINOR-2/D2): an epic's children are the `ssd:feature` issues
  whose body references `Epic: #<n>`, not the epic task list. Word-boundary match (`#27` ≠ `#270`).
- **D1 split guard for epic close:** the script answers "are all GitHub children closed?"; the
  orchestrator (reading `.ssd/current.yml`) owns "is another iteration planned?". Neither closes alone —
  why epic #27 stayed open when iter A's #28 closed.
- **D3 iteration-qualified feature issue:** an iterated workstream syncs under `<slug>#<iter>:` so a new
  iteration gets its own issue instead of re-opening the closed prior one.
- **New `issue-sync-current` gate rule** (ADR-0014 Q3) — informational, SKIP-by-default (tracking off /
  no `gh` / no issue binding); FAILs only on hard mirror drift (recorded issue closed while active, or
  phase-label ≠ local phase). Checks bindings before any network call.
- **Discoverability:** `migrations.yml` `github-issue-tracking-keys` (guided); `ssd-init` template gains
  the two toggles; README "GitHub Issue Tracking" section; `methodology/SKILL.md` script catalog
  (`issue-sync.sh` + `migrate.sh`); `ssd/chapters/phases.md` close-lifecycle prose.
- **Tests:** first unit coverage for `issue-sync.sh` via a mock-`gh` shim. parity 59 → 69.
- ADR-0014 → Accepted, amended (MINOR-2, D1, D3, Q3). `ssd` skill banner 2.3.0 → 2.4.0.

## [2.3.0] — 2026-06-14

### GitHub issue state tracking — iteration A (ADR-0014)

New opt-in feature (`github-issue-tracking`; epic [#27](https://github.com/AlexHorovitz/skills/issues/27),
workstream [#28](https://github.com/AlexHorovitz/skills/issues/28)) that mirrors SSD workstream state to
GitHub issues, one-way (local `.ssd/` drives GitHub). **Default off — projects without the toggle are
byte-for-byte unchanged, zero network calls.** Dogfooded on this repo (the convention created its own
epic + feature issue).

- **New `methodology/issue-sync.sh`** — best-effort bash helper in the `gate-rules.sh`/`migrate.sh`
  style (bash 3.2, `set -uo pipefail`, `--json`, exit-code driven). Subcommands: `preflight`,
  `ensure-epic <ADR-NNNN> <title>`, `ensure-feature <slug> <phase> <epic#>`, `set-phase <issue#>
  <phase>`. Idempotent by local title-prefix match (robust against GitHub search tokenization);
  distinguishes a `gh` list failure from a genuine empty (refuses to create on failure → no
  duplicates). `close-feature`/`close-epic` are stubbed for iter B.
- **Convention (ADR-0014):** ADR → epic issue (`ssd:epic`, title `[ADR-NNNN] …`); workstream → feature
  issue (`ssd:feature` + one `ssd:phase/<phase>`), linked to its epic. Auto-sync on phase advance;
  create/update automatic under the toggle, **close gated behind `integrations.github.auto_close`**
  (default = prompt; ADR-0014 Q2).
- **`.ssd/project.yml`:** new `integrations.github.issue_tracking` (default `off`) + `auto_close`
  (default `false`). **`current.yml.active[]`:** new optional `epic:`/`issue:` cache fields
  (lazy-backfill, `branch:` precedent; no schema bump). Documented in `ssd/chapters/state.md`.
- **Orchestrator:** `ssd/chapters/phases.md` documents the auto-sync on phase advance — each action
  surfaced (rule-zero); `gh`-absent (preflight exit 3) → warn + continue, never block a phase.
- **Gate:** round-1 FAIL (MAJOR-1 stdout/JSON contract) → round-2 PASS after fix; parity 59/59.
  Banner: `ssd` 2.1.0 → **2.3.0** (chapters changed; banner-lag re-align). `VERSION` → 2.3.0.
- **Deferred to iter B** (tracked on #28/#27): `close-feature`/`close-epic` automation, the
  `issue-sync-current` gate rule, a `migrations.yml` entry + `ssd-init` template keys, README docs,
  `methodology/SKILL.md` script-catalog entry, and the MINOR-2 epic-linkage data-model amendment.

---

## [2.2.0] — 2026-06-14

### SSD 2.0 — iteration C: the deprecation path (epic complete)

Third and final [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) cut (ssd-2.0-cuts;
[#15](https://github.com/AlexHorovitz/skills/issues/15)). Makes the `/ssd upgrade` deprecation path
coherent: *teach the 2.0 removals, and stop teaching the dead key.* Not breaking.

- **New `obsoleted_in` manifest field** ([ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)
  addendum). An append-only manifest could express "introduced" but not "removed", so the stale
  `dev-profile-keys` entry would *re-add* `developer_profile` — the exact key 2.0 deleted — on
  `--apply`. `dev-profile-keys` now carries `obsoleted_in: "2.0.0"`; `migrate.sh` skips any entry
  whose `obsoleted_in <= --to` (a staged upgrade to a pre-removal target still sees it). The stable
  id is never deleted.
- **Two new guided entries** (`introduced_in: 2.0.0`): `profile-concept-removed` ("delete
  `developer_profile` / `teaching_mode` — now ignored") and `single-surface-doctrine` (commands are a
  thin alias, not a co-equal surface). Both re-surface (R3) on `/ssd upgrade` until a project
  `--adopt`s them, so v1-era projects learn what 2.0 changed.
- **Engine:** `read_manifest()` extracts `obsoleted_in` as a trailing column; one guard line in the
  selection loop. `migration-manifest-current` gate rule unchanged (ignores unknown fields).
- **Parity:** new fixture `migrate-obsoleted-in` (not offered at `--to 2.2.0`, still offered at
  `--to 1.25.0`, `--apply` to 2.x never writes `developer_profile`). Harness 53 → **59** assertions.
- **Deprecation ledger:** ADR-0012's four "Revisit when" reversibility triggers are tracked on #15
  (ADR-0012 Pillar 4 / ADR-0011 revisit-aware issue) — no separate issue, per ADR-0012's anchoring.
- `VERSION` → 2.2.0. No skill banner behavior change (no SKILL.md logic touched).

---

## [2.1.0] — 2026-06-14

### SSD 2.0 — iteration B: single surface + verb collapse

Second of the [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) cuts (ssd-2.0-cuts;
[#15](https://github.com/AlexHorovitz/skills/issues/15)), Pillar 3. **Subtraction + reframing on the
v1.x spine** — SSD now presents **one surface, progressively disclosed**. Not breaking: every v1
invocation still works.

- **Collapsed `ssd/SKILL.md` § "Invocation"** from the front-loaded 13-verb table into a
  progressive-disclosure block: the bare `/ssd` (no-arg Auto-Detect) is the headline everyday path
  (+ `/ssd start` for an un-stated project), and the **full verb set is relocated** into an
  intent→verb→chapter pointer table. Every verb stays one hop away and now names the chapter that
  documents it (`chapters/{phases,upgrade,workstreams}.md`).
- **Stated the single-surface doctrine once, in the live spine:** the command path is a **thin alias**
  that lowers into the conversational path — a power-user shorthand, *not* a co-equal surface with its
  own state. (ADR-0012 Pillar 3.)
- The "dual-surface perfect parity" doctrine required **no live edit** — iter A already removed it with
  `chapters/profile.md` and the superseded ADR-0004; it now survives only in immutable/historical files
  (governing ADR-0012, superseded ADR-0004, `.ssd/` history). Verified by grep at the gate.
- **NeXTSTEP held:** no verb added, removed, or renamed; only the front-page teaching order changed.
- Banner: `ssd` 2.0.0 → **2.1.0**. `VERSION` → 2.1.0. No other skill touched.
- Iter C (`/ssd upgrade` guided deprecation entries + ADR-0011 tracking issue) follows on #15.

---

## [2.0.0] — 2026-06-14

### SSD 2.0 — iteration A: remove the profile concept (BREAKING)

First of the [ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) cuts (ssd-2.0-cuts;
[#15](https://github.com/AlexHorovitz/skills/issues/15)). **Subtraction on the v1.x core** — the
`developer_profile` / `teaching_mode` concept is removed library-wide. One system serves both
newcomer and expert through **progressive disclosure** (the no-arg Auto-Detect proposes the next
step; every manual verb stays invokable — NeXTSTEP: remove the *mode*, keep the *capability*).

**Breaking:** `developer_profile` and `teaching_mode` in `.ssd/project.yml` are no longer read. A v1
`project.yml` that still carries them is **ignored** (no crash); `/ssd upgrade` will surface a guided
clean-up (iter C).

- **Deleted** `ssd/chapters/profile.md` + its spine stub + chapter-index row + the bridge-flags table.
- **Collapsed each profile-keyed behavior to its former `standard` default** (no behavior lost): 
  `code-reviewer` → MINOR inline / NIT summarized (§ "Finding-Severity Reporting"); `coder` → REVIEW
  markers on genuine uncertainties (§ "REVIEW-Marker Density"); `systems-designer` → the standard
  checklist (§ "Checklist Depth"); `codebase-skeptic` → relevant voices (§ "Voice Selection").
  Gate-critical behavior (BLOCKER/MAJOR-inline, `gate_pass`, safety gates, halt-on-blocker) was always
  profile-independent — unchanged.
- **`architect` / `methodology` / `refactor`**: dropped the obsolete `> Profile stance: invariant`
  note — they never branched; no behavior change.
- **`ssd-init`**: removed `developer_profile`/`teaching_mode` from the `project.yml` template; Step 5 +
  Step 5.5 no longer branch on profile (always propose, user declines); `switch_note_default` is now a
  plain knob (default `prompt`).
- **ADR-0004** + **ADR-0010** marked **Superseded by ADR-0012** (retained as historical record).
- Banners: `ssd` 1.25.0 → **2.0.0**, `ssd-init` → 1.10.0, `code-reviewer` → 1.7.0, `coder` → 1.4.0,
  `systems-designer` → 1.5.0, `codebase-skeptic` → 1.4.0, `architect` → 1.3.0, `methodology` → 1.7.0,
  `refactor` → 1.3.0. `VERSION` → 2.0.0.
- Iter B (single surface + verb collapse) and iter C (`/ssd upgrade` guided deprecation entries +
  ADR-0011 tracking issue) follow on #15.

---

## [1.25.1] — 2026-06-14

### Docs/decision: accept ADR-0012 (SSD 2.0 greenlit) + README refresh

No behavior change. Two bundled docs/decision updates.

- **[ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) Proposed → Accepted.** The SSD 2.0
  direction (progressive disclosure replacing the profile *concept* — NeXTSTEP: lead the newcomer,
  never take the Terminal from the expert; single surface; verb collapse; warnings-not-walls) is now a
  committed decision — the cuts may begin ([#15](https://github.com/AlexHorovitz/skills/issues/15)).
  **Accepted ≠ shipped:** `methodology/core.md` keeps citing ADR-0011, not ADR-0012, until the 2.0
  cuts land; the de-riskers done so far are `/ssd upgrade` (#17) and the chapter-split (P1, v1.25.0).
- **README refresh** (doc currency): command lists now include `/ssd upgrade` and the v1.16+ parallel
  workstream commands (`/ssd feature new` · `switch` · `worktree`); the dogfood epics list is current
  through v1.25 (adds `ssd-profile-audit`, `ssd-upgrade`, `ssd-skill-chapter-split`).
- `VERSION` → 1.25.1. `ssd/SKILL.md` unchanged (banner stays 1.25.0 per the banner-lag pattern).

---

## [1.25.0] — 2026-06-14

### Refactor: `ssd/SKILL.md` chapter-split (2.0 prerequisite P1, path A)

Splits the 1,465-line `ssd/SKILL.md` monolith into a **thin ~295-line spine + on-demand chapter
files** under `ssd/chapters/`, relieving the context-ceiling forcing function
([#15](https://github.com/AlexHorovitz/skills/issues/15),
[ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md)). Shipped on the 1.x line as a
**behavior-preserving refactor** (Hard Rule 4 — separate PR) ahead of the contested 2.0 deletions, so
2.0 becomes pure subtraction on an already-chaptered file (mirrors `/ssd upgrade` shipping ahead of
the cuts).

- **Stub-and-chapter** approach: the spine keeps every section *heading* as a redirect stub, so all
  live `ssd/SKILL.md § "…"` cross-references (sibling skills, ADRs, README) keep resolving — zero churn.
- Spine keeps the front matter: Purpose / Prerequisite / Invocation / the no-arg **Auto-Detect** core /
  The Rails / Hard Rules. Chapters: `phases`, `upgrade`, `workstreams`, `profile`, `artifacts`, `state`,
  `enforcement`, `skills`.
- **No deletions.** `chapters/profile.md` (developer profile + teaching mode) is **relocated, not
  removed**, and flagged as the ADR-0012 Pillar-1 deletion candidate — 2.0 becomes a one-file `rm`.
- In-file changelog moved out to this file (`CHANGELOG.md`); spine carries a pointer.
- `ssd/SKILL.md` 1.24.0 → 1.25.0; `VERSION` → 1.25.0.

---

## [1.24.0] — 2026-06-13

### Feature: `/ssd upgrade` — iteration C (guided adoption + manifest-currency gate); **epic complete**

Closes [#17](https://github.com/AlexHorovitz/skills/issues/17) /
[ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md).

- **Guided-adoption tracking** decoupled from the version gate: `/ssd upgrade --adopt <id>` records a
  guided practice in `project.yml.ssd.adopted_guided` (`.bak` first; rejects non-guided ids and refuses
  an inline-form list rather than emit malformed YAML). An adopted entry reports `GUIDED-ADOPTED` and is
  *satisfied*, so the recorded version advances past it; a fully caught-up project bumps to `--to`
  (zero drift). Unadopted guided entries still re-surface (R3).
- New **`migration-manifest-current`** gate rule — structural manifest health (unique ids, ascending
  `introduced_in`, none newer than `VERSION`); closes R2; SKIPs outside the skills-library repo.
- **`gate-rules.sh` `yaml_get` hardened** to strip inline comments on scalar values, quote-aware (the
  parser half of iter-B's MAJOR-4).
- `scripts/parity-test.sh` → 53 assertions. `ssd` 1.23.0 → 1.24.0.

---

## [1.23.0] — 2026-06-13

### Refactor: `ssd-upgrade` extraction — engine owns all four mechanical migrations

The `ssd-init`→engine extraction deferred from iter B
([ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md) extraction addendum).

- `current-yml-v2` no longer `DEFER`s — `apply_current_yml_v2` performs the v1→v2 split in the
  **conservative-safe** form (`.bak` + fresh v2 skeleton + the entire original preserved under
  `current.notes.yml` `legacy_v1_import:`), keeping R1 airtight without a field-classifying heuristic.
- Selective `.gitignore` pattern extracted to single-source `methodology/selective.gitignore`, consumed
  by both `migrate.sh` and `ssd-init` (closes the iter-B review's SUGGESTION-1 duplication).
- `scripts/parity-test.sh` → 43 assertions. `ssd-init` 1.8.0 → 1.9.0; `ssd` 1.22.0 → 1.23.0.

---

## [1.22.0] — 2026-06-13

### Feature: `/ssd upgrade` — iteration B (`--apply` mechanical migrations)

`/ssd upgrade --apply` runs the manifest's mechanical migrations, each `detect`-gated and `.bak`-backed
(R1), re-confirmed via `detect` (`APPLIED`/`SKIP-present`/`DEFER`/`ERROR`), bumping
`project.yml.ssd.version` to the highest **contiguous adopted** version and appending to
`.ssd/init-log.md`. The bump stops at the first outstanding entry — including a guided one — so guided
practices re-surface until adopted (R3).

- Three executable apply functions (`dev-profile-keys`, `parallel-features-keys`, `selective-gitignore`);
  `current-yml-v2` reported `DEFER` (extracted in 1.23.0). Honors `--to`/`--json`.
- Two MAJORs found + fixed by dogfooding `--apply` on this repo (gitignore pattern duplication; a gate
  rule silently degraded to SKIP). `scripts/parity-test.sh` → 41 assertions. `ssd` 1.21.0 → 1.22.0.

---

## [1.21.0] — 2026-06-13

### Feature: `/ssd upgrade` — iteration A (read-only drift report)

First concrete 2.0-era feature ([#17](https://github.com/AlexHorovitz/skills/issues/17),
[ADR-0013](docs/decisions/ADR-0013-project-upgrade-migration-manifest.md)), shipping ahead of the
contested 2.0 surface cuts because it's independent of them and is the migration vehicle ADR-0012's
deprecation path will need.

`/ssd upgrade` detects when a project has drifted past the latest SSD conventions and reports the
gap. **Iteration A is read-only** (detect-only; no write path, so a bad migration cannot corrupt a
project — ADR-0013 R1 cannot fire).

- **`methodology/migrations.yml`** — declarative, append-only migration manifest; the 5 historical
  project-visible conventions (current.yml v2, dev-profile keys, parallel-features keys,
  selective-gitignore, decision-record doctrine), each tagged `applies_to`/`kind`/`detect`/`adr`.
- **`methodology/migrate.sh`** — bash+awk detect-only engine (bash 3.2-compatible). Selects
  `applies_to: project` entries newer than the project's recorded `ssd.version` and reports each as
  `PENDING` / `SKIP-present` / `GUIDED`. Per-`id` detect probes anchored to YAML-key form (won't
  false-positive on comments). `--apply` refuses (exit 2) — lands in iter B.
- **`ssd/SKILL.md`** — `/ssd upgrade` command + § doc; `ssd-init` ↔ `/ssd upgrade` state-disjoint
  overlap row (now **8 pairs**); `ssd` 1.20.0 → 1.21.0.
- **`scripts/parity-test.sh`** — +2 fixtures; harness 16 → 20 assertions.

Warnings, not walls (ADR-0012 Pillar 5): reports only; never forces, never silent-rewrites. Iter B
(`--apply` mechanical migrations) and iter C (guided + manifest-currency gate) follow as v1.22/v1.23.

---

## [1.20.1] — 2026-06-13

### Doctrine: decision records + "warnings, not walls"

A doc/doctrine patch (no behavior change to the gate). Seeds of the SSD 2.0 epic
([#15](https://github.com/AlexHorovitz/skills/issues/15)) plus two honesty fixes.

- **[ADR-0011](docs/decisions/ADR-0011-decision-record-doctrine.md) (Accepted):** a consequential
  decision is recorded as a committed ADR (durable *why*) **+** a revisit-aware tracking issue (live
  status + a falsifiable `Revisit when:` section), cross-linked. Codified in `methodology/core.md`
  § "Recording Decisions" (`methodology` 1.6.1 → 1.6.2). The issue tracker is the *ledger*, never the
  *gate*; non-GitHub projects carry `Revisit when:` inline in the ADR.
- **Warnings, not walls** (ADR-0012 Pillar 5): `/ssd` informs and records but does not block — the
  developer may ship past a failing gate, loudly and on the record. Two overclaims fixed to match:
  `quality.yml` no longer says CI "blocks the merge" (it REPORTS — no branch protection by design),
  and the `ssd/SKILL.md` Hard Rules now read as strongly-discouraged-with-a-logged-override, not a
  physical block. The only truly inviolable rule is "never silently advance a phase."
- **[ADR-0012](docs/decisions/ADR-0012-ssd-2.0-architecture.md) (Proposed):** the SSD 2.0 architecture
  seed (progressive disclosure replaces the profile concept; single surface; warnings-not-walls).
  Lands as a Proposed record only — the 2.0 *decision* is not made here.

---

## [1.20.0] — 2026-06-13

### Feature: profile-awareness audit across sub-skills (ssd-profile-audit / R9)

Closes the deferred 🔴 P2 + F2 from the post-v1.19 milestone: the sub-skills were profile-blind
even though ADR-0004 established a `developer_profile`. **[ADR-0010](docs/decisions/ADR-0010-profile-aware-subskills.md)**
sets the boundary rule — a sub-skill branches on profile only when profile changes output
*substance* (markers, findings, voices, checklist items), never tone (which stays the
orchestrator's job), and **never suppresses gate-critical output**.

- New `ssd/SKILL.md` § "Profile-aware sub-skill behavior" — the single source of truth table, the
  normative invariant guarantee, and how a sub-skill learns the active profile. (`ssd` 1.19.1 → 1.20.0.)
- **Invariant** (explicit stance note): `architect` 1.2.1, `methodology` 1.6.1, `refactor` 1.2.2.
- **Profile-aware** (new `## Profile-Aware Behavior` section): `systems-designer` 1.4.0 (checklist
  depth), `coder` 1.3.0 (`# REVIEW:` marker density), `code-reviewer` 1.6.0 (MINOR/NIT reporting;
  BLOCKER/MAJOR + `gate_pass` always profile-independent), `codebase-skeptic` 1.3.0 (voice breadth;
  milestone/pre-release audits keep full breadth regardless of profile).

`standard` is the unchanged baseline — `novice` and `expert` are deltas around it. Docs-only; the
`skill-version-sync` gate rule (v1.19.1) kept all eight bumped banners in sync with their
frontmatter examples throughout.

---

## [1.19.1] — 2026-06-11

### Post-v1.19 milestone refactor (first milestone audit; doctrine-tightening patch)

The library's first `/ssd milestone` audit ([skeptic-before.md](.ssd/milestones/2026-06-10-post-v1.19/skeptic-before.md))
flagged posture **drifting**: the methodology's own documentation had fallen out of sync with
its own implementation. This patch closes the high-leverage findings (refactor items R1–R8;
R9 — the profile-awareness audit — is deferred to v1.20.0 as its own pass).

**CI & release discipline.**

- **R1** — new `.github/workflows/quality.yml`: runs `methodology/gate-rules.sh` on every PR to
  `main` and `scripts/parity-test.sh` on every PR and push. Either job failing blocks merge —
  the library that preaches "encode the ratchet in CI" now has CI. README gains a status badge.
- **R2** — backfilled the missing release tags `v1.16.0`–`v1.19.0` (only `v1.15.0` existed).
- **R7** — documented the banner-lag pattern (skill banners track the library version *at last
  change*) and added a "Tag the release" step to `ssd/SKILL.md` § "/ssd ship".

**Version-drift defense.**

- **R3** — synced the required-frontmatter `version:` example to the banner in all **8** drifted
  sub-skills (the audit named 6; `refactor` and `software-standards` were also stale).
- **R4** — new `skill-version-sync` gate rule + `frontmatter-validate.py --check-skill-examples`
  mode mechanically enforce example/banner consistency going forward. Scoped to skill
  documentation examples, not `.ssd/` artifacts (which keep the version that produced them) — see
  **[ADR-0009](docs/decisions/ADR-0009-skill-version-sync.md)**. Two test-first parity fixtures;
  harness 14 → 16 assertions. `methodology/SKILL.md` 1.5.0 → 1.6.0.

**Documentation.**

- **R5** — `ssd/SKILL.md` § "Resolving Skill Overlap" expanded from 3 to 7 pairs (adds the four
  coordination pairs).
- **R6** — README lists the three dogfooded epics, each linking its architect spec.
- **R8** — `ssd/SKILL.md` documents the single-Claude-session-per-project concurrency assumption
  and incident recovery.

`ssd/SKILL.md` 1.18.0 → 1.19.1. Milestone verification (`/ssd verify`) tracked in
[.ssd/milestones/2026-06-10-post-v1.19/](.ssd/milestones/2026-06-10-post-v1.19/).

---

## [1.19.0] — 2026-06-10

### Iteration B — ssd-commit-split: optional pre-commit hook + dogfood (epic complete)

Second of (originally) three iterations of the ssd-commit-split epic ([ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md)).
Iter A (v1.18.0) shipped the enforcement floor (selective `.gitignore` + `ssd-init`
migration + `no-leaky-state` gate rule). Iter B adds the **optional pre-commit hook** that
catches violations *before* the commit lands and polishes the migration UX. With v1.19.0
the ssd-commit-split epic is **complete** — iter C's original scope (dogfood the historical
artifacts) was satisfied by a manual user commit (`b6fc739`) between v1.18.0 ship and this
iter B start, so its residual polish (the README dogfood paragraph) rolled into this PR.

**New: optional pre-commit hook.**

- `methodology/hooks/pre-commit-no-leaky-state.sh` — plain bash script for symlink install.
  Locates `methodology/gate-rules.sh` via `git rev-parse --show-toplevel`, invokes
  `--staged --rules no-leaky-state`, exits with the same code as the gate rule. No
  framework dependency (no husky / pre-commit.com). Documented at the top of the script
  with install / coexistence / doctrine reminders.
- `methodology/hooks/README.md` — full install / uninstall / coexistence docs.
  Documents the symlink convention, the coexistence pattern for projects that already
  have a `pre-commit` hook, the CI integration backstop, and the hook script contract for
  anyone adding additional hooks under `methodology/hooks/` in the future.

**New: `--staged` mode for `gate-rules.sh`.**

- `methodology/gate-rules.sh` — new `--staged` flag. Switches `diff_files()` to use
  `git diff --cached --name-only` instead of `git diff --name-only $BASE...HEAD`. Used by
  the pre-commit hook. `wip-commits` SKIPs cleanly in staged mode (no commits to grep
  yet); other rules read `diff_files()` through the same helper and adapt. New
  `diff_scope_label()` helper produces the right SKIP detail message ("no diff (vs main)"
  vs "no diff (staged files)").

**Updated: `ssd-init` Step 5.5 (offer pre-commit hook install).**

- `ssd-init/SKILL.md` v1.7.0 → v1.8.0. New Step 5.5 between Step 5 (gitignore) and Step 6
  (project shape). Expert-profile users get a yes/no/skip prompt offering the install;
  standard / novice profiles silently skip. The orchestrator prints the install command
  but does NOT execute it — git hooks are a per-checkout trust boundary. Pre-existing
  `.git/hooks/pre-commit` triggers a coexistence-pattern message instead of the bare
  symlink path. Step 5.5 skipped entirely on `gitignore_mode: blanket` (the hook would be
  a no-op).

**Updated: README dogfood paragraph.**

- `README.md` — new paragraph between the core invariant and the Methodology section
  noting that as of v1.19.0 this repo tracks its own SSD artifacts under
  `.ssd/features/`. Reflects the user-driven manual backfill in commit `b6fc739`
  (between v1.18.0 ship and this iter B start) which committed 16 historical artifacts
  from the parallel-features and ssd-skill-upgrades epics. Read the methodology's own
  history using the methodology itself.

**Acknowledgment: manual dogfood backfill.**

The original ssd-commit-split iter C scope was "stage all previously-untracked
`.ssd/features/*` artifacts" — satisfied by the user's commit `b6fc739 added features stuff`
on 2026-06-10 (between v1.18.0 ship and this iter B start). That commit added 16 historical
artifact files (~4385 lines). Iter B's architect spec accordingly declared the epic complete
at v1.19.0 with the README dogfood paragraph as the only residual scope.

**Touched skills:**

- `ssd-init` v1.7.0 → v1.8.0 (new Step 5.5 + changelog).

**Tooling:**

- `methodology/gate-rules.sh` — new `--staged` flag + `diff_scope_label()` helper.
  `wip-commits` rule extended to SKIP in staged mode with explicit detail message.
- `methodology/hooks/pre-commit-no-leaky-state.sh` NEW (executable, symlink-install).
- `methodology/hooks/README.md` NEW.

**Epic close: ssd-commit-split**

| Iter | Version | Scope |
|---|---|---|
| A | v1.18.0 | Selective `.gitignore` + `ssd-init` migration + `no-leaky-state` gate rule |
| B | v1.19.0 | Optional pre-commit hook + `--staged` mode + README dogfood polish |
| C | (n/a — folded into B) | Originally "stage historical artifacts"; satisfied by user commit b6fc739 |

The original ask ("ensure the selective `.ssd/` commit split") is fully delivered:
gitignore enforces at staging time, gate rule enforces at PR time, optional hook enforces
at pre-commit time, and the repo dogfoods its own convention.

---

## [1.18.0] — 2026-05-24

### Iteration A — selective `.ssd/` commit split (enforcement floor)

First of three iterations of the ssd-commit-split epic. Replaces the v1.3.0–v1.17.x blanket
`.ssd/` gitignore with a **selective commit split**: durable artifacts (briefs, architect
specs, coder-status, code reviews, deploy notes, milestone records) get committed; machine
state (`current.yml`, `project.yml`, `init-log.md`, `archive/`, `audits/`, snapshot machinery)
stays gitignored.

See [ADR-0008](docs/decisions/ADR-0008-ssd-commit-split.md) for the rationale, alternatives
rejected, and the three-iteration plan. This iteration ships the enforcement floor: gitignore
pattern, `ssd-init` migration, and the `no-leaky-state` gate rule.

**Why now.** Briefs and architect specs are the same class of artifact as ADRs — they describe
engineering decisions. With the blanket gitignore they're invisible to PR review, milestone
audits, and external onboarding. The parallel-features epic (v1.15.0–v1.17.0) added
cross-user surface area, which compounds the cost of invisible artifacts. Time to split.

**What ships in iter A:**

- **New `.gitignore` pattern** — block-then-allow selective. ~30 lines, fully auditable. The
  pattern in this repo is now on the selective convention.
- **`ssd-init/SKILL.md` v1.6.0 → v1.7.0.** Step 5 (Gitignore) rewritten with the four-case
  flow: no gitignore / no `.ssd` reference / blanket `.ssd/` / already selective. Detects
  blanket-mode existing projects, surfaces a prompted migration (with `.bak` backup,
  idempotent, profile-aware suppression for novice). Two new `project.yml.ssd.*` keys
  written at init time: `gitignore_mode: selective|blanket` (default selective) and
  `gitignored_state: []` (additive deny-list extensions).
- **`methodology/gate-rules.sh`** — new `no-leaky-state` rule. Reads
  `git diff --name-only <base>...HEAD`, matches each file against a hard-coded baseline
  deny-list + project-supplied additional patterns. PASSes when no forbidden files appear.
  FAILs on any. SKIPs cleanly on `gitignore_mode: blanket` or no-diff. Catches force-add
  (`git add -f .ssd/current.yml`), edited `.gitignore` regressions, and new artifact types
  not yet in the gitignore. Doctrine cite in the rule output: ADR-0008.
- **`methodology/gate-rules.sh` `--rules <comma-list>` flag.** New CLI arg to filter which
  rules run. Used by the iter-B pre-commit hook (the other rules are too slow for
  pre-commit). Default behavior (no `--rules`) runs all rules — unchanged.
- **`ssd/SKILL.md` v1.17.1 → v1.18.0.** § "The SSD Artifact Tree" gains a committed-vs-
  gitignored table mapping every artifact path. § "Methodology Enforcement" gains
  `no-leaky-state` and `frontmatter-valid` rows (the latter was previously implicit).
  Changelog entry.

**Self-justifying iter A.** When this PR merges, the gitignore change makes this repo's
previously-untracked `.ssd/features/ssd-commit-split/00-brief.md` and `01-architect.md`
become tracked. They appear in the PR diff alongside ADR-0008. **This is the intended
outcome of ADR-0008** — the methodology starts publicly citing its own work product. The
larger-than-typical diff is the feature, not an oversight.

**Migration UX.** Existing projects (v1.3.0–v1.17.x) on the blanket gitignore get a one-time
prompt on next `ssd-init` invocation:

> Three options: **migrate** (write `.gitignore.bak`, switch to selective, print summary of
> now-trackable files for the user to stage), **defer** (ask again next time), **permanent
> opt-out** (set `gitignore_mode: blanket` in `project.yml`, stop asking).

Profile-aware: novice silently keeps blanket (re-offered on novice→standard promotion);
standard/expert get the prompt by default.

**Opt-out at any time:** set `project.yml.ssd.gitignore_mode: blanket` and replace the
selective `.gitignore` pattern with a bare `.ssd/` line. The `no-leaky-state` rule SKIPs
cleanly under blanket mode.

**Deferred to iteration B (v1.19.0):**

- `methodology/hooks/pre-commit-no-leaky-state.sh` — optional pre-commit hook that runs
  `gate-rules.sh --rules no-leaky-state` before the commit lands.
- `methodology/hooks/README.md` — installation docs (symlink convention, no framework
  dependency).
- `ssd-init` mention of the hook as an optional install during init for expert profile.

**Deferred to iteration C (v1.20.0):**

- **Dogfood commit:** stage and commit this repo's previously-untracked
  `.ssd/features/{ssd-skill-upgrades, parallel-features}/**/*.md` artifacts under the new
  selective convention. The methodology's own history becomes a worked example.

**Touched skills:**

- `ssd` 1.17.1 → 1.18.0 (Artifact Tree table + Methodology Enforcement rows + changelog)
- `ssd-init` 1.6.0 → 1.7.0 (Step 5 rewrite + new project.yml keys + migration flow)

**Tooling:**

- `methodology/gate-rules.sh` — new `no-leaky-state` rule (6 rules total), new `--rules` flag
- `methodology/gate-rules.sh` — new `yaml_get_list` helper, new `matches_deny_pattern` glob
  matcher (handles `**`, `*`, `?`, dir-prefix patterns)

---

## [1.17.1] — 2026-05-24

### Docs — canonical-reference and cross-linking pass

Documentation-only release. No behavior change in any executable skill, gate rule, or validator.

- **methodology/SKILL.md** → 1.5.0. Adds a "canonical methodology pages" line at the top pointing
  to insanelygreat.com (ssd.html, guide.html, agile2.html) and states the website is the
  user-facing reference while this skill set is the in-repo doctrine the orchestrator enforces.
- **methodology/core.md.** Adds a canonical-reference banner. Makes the Continuous-Delivery vs.
  SSD distinction explicit ("CD says *can*; SSD requires *is*"). Names Alex Horovitz as
  originator. Links the Ratchet Principle CI implementation to
  [insanelygreat.com/ratchet-principle.html](https://insanelygreat.com/ratchet-principle.html)
  (which has a working `.github/workflows/quality.yml`).
- **methodology/adoption.md.** Refreshes the methodology-comparison block (date-stamped
  2026-05-24, satisfies the SKILL.md ≤12-month-refresh requirement). Adds Shape Up and Kanban
  comparisons. Adds a team-size × work-shape decision table. Replaces the bare-books "Resources"
  list with a canonical-page section linking the six new long-form articles at
  insanelygreat.com (solo-developer-manifesto, scrum-alternatives, ratchet-principle,
  releases-small-teams, simplest-lifecycle, methodologies-small-teams).
- **methodology/patterns.md.** Pattern 3 (Dark Launching) now cross-links
  [How Small Teams Should Think About Releases](https://insanelygreat.com/releases-small-teams.html)
  for the full deploy/release decoupling treatment.
- **ssd/SKILL.md** → 1.17.1. Canonical-reference banner; Purpose paragraph names Alex Horovitz
  as originator and links the About page.
- **README.md.** Adds shields.io badges (Methodology: InsanelyGreat SSD, Manifesto: Agile²,
  License) and a new "Methodology" section linking the five canonical insanelygreat.com pages.

Motivation: close the citation graph in both directions. The website now links into the skills
repo (badge + README links); the skills repo now links back to the website's canonical pages
(banners + cross-references). This is the inbound-signal half of the LLM-visibility plan.

---

## [1.17.0] — 2026-05-24

### Iteration C — parallel-features overlap detection (epic complete)

Third and final iteration of the parallel-features epic. Iter A (v1.15.0) shipped the schema
substrate (`branch`, `worktree`, `touches`). Iter B (v1.16.0) shipped the orchestrator commands
(`/ssd feature new`, `/ssd switch`, `/ssd worktree`). **Iter C makes iter A's `touches:` field
load-bearing** — the architect-pass intent and coder-pass diff backfill that have been recorded
since v1.15.0 are now actually consumed at gate time.

See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md) — same ADR covers all three
iterations.

**The behavior change.** When `/ssd gate <slug>` runs and `current.yml.active[]` has more than
one workstream, two new things happen:

1. **Touches backfill.** The orchestrator computes `git diff --name-only <base>...HEAD` for
   the gated workstream and unions the result into `current.yml.active[<slug>].touches`. This
   runs BEFORE code-reviewer, so the reviewer sees an up-to-date touch list. Architect-intent
   paths that haven't been touched yet are preserved (union, not replacement).

2. **Cross-workstream overlap check.** `code-reviewer` consults the peer workstreams'
   `touches:` fields, intersects via `git ls-files <glob>`, and emits `OVERLAP-N` findings for
   any non-empty intersections — at **SUGGESTION tier**, never BLOCKER or MAJOR. The gate is
   not blocked by overlap. Per ADR-0007, this is by design: overlap can be intentional, and
   the user has context the orchestrator doesn't.

The new `🔗 OVERLAP:` severity prefix is added to the canonical severity table in
`code-reviewer/SKILL.md`. ADR-0007 § "Alternatives Rejected" explicitly forbids upgrading
OVERLAP-N to MAJOR on speculation.

**Touched skills:**

- `code-reviewer` — v1.4.0 → v1.5.0. New § "Cross-Workstream Overlap Check" (~80 lines) with
  algorithm, finding format, edge cases (`**` globs, untracked files, empty `touches:`,
  self-exclusion guarantee), and explicit no-upgrade rule. New `🔗 OVERLAP:` severity prefix
  row in the severity table.
- `ssd` — v1.16.0 → v1.17.0. § "Methodology Enforcement" gains two paragraphs: one naming the
  cross-workstream overlap check as part of `/ssd gate`, one documenting the workstream-aware
  base detection pattern (orchestrator passes `--base` explicitly; gate-rules.sh remains
  standalone). § "Session Continuity" `touches:` schema comment now documents the gate-time
  union and the OVERLAP-N consumer.

**Tooling:**

- `methodology/gate-rules.sh` — added comment block near `BASE="main"` declaration explaining
  the standalone-vs-orchestrator contract. No behavior change to the script.

**Schema:** unchanged. Iter A's `touches:` field is now actually consumed; no new fields.

**Trigger conditions for the overlap check** (all must hold; if any false, the check skips and
no OVERLAP findings are emitted):

- Review is invoked via `/ssd gate` (not an ad-hoc code-reviewer invocation).
- `current.yml.active[]` has more than one entry.
- The gated workstream's `touches:` is non-empty.
- At least one other active workstream has non-empty `touches:`.

**Out-of-scope for iter C, deferred to iter D (only if real friction emerges):**

- `/ssd workstream adopt <slug> <branch>` — claim an existing branch as a workstream.
- `/ssd workstream set-branch <slug> <branch>` — rename / repair (called out in iter B's
  FM-14 as the eventual remedy for worktree-branch drift).
- `/ssd workstream handoff <slug>` — write a handoff note for a workstream not currently
  resolved as `source` (useful when detached HEAD blocked auto-capture during `/ssd switch`).
- Workstream-base auto-derivation in `gate-rules.sh` — explicit `--base` from the orchestrator
  is the current contract.

**Parallel-features epic status: COMPLETE.**

Three iterations, three ADR-0007-conformant releases, no schema-version bumps. The original
ask ("I would like to be allowed to work on multiple features at once") is now fully
delivered: schema substrate (iter A), ergonomic commands (iter B), cross-workstream
awareness (iter C). The epic-level workstream `parallel-features` archives to
`.ssd/archive/features/parallel-features/` after this release.

---

## [1.16.0] — 2026-05-24

### Iteration B — parallel-features orchestrator commands

Second of three iterations of the parallel-features epic. Ships the three new orchestrator
commands designed in iteration A's architect spec. No new schema fields (iter A shipped those);
this iteration is pure documentation that makes the LLM-driven orchestrator able to *execute*
parallel-workstream lifecycle. See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md).

**New orchestrator commands** (documented in `ssd/SKILL.md` § "Workstream Lifecycle Commands"):

- **`/ssd feature new <slug>[#<iter>] [--branch <name>] [--worktree] [--from <ref>] [--allow-dirty]`**
  — start a new workstream end-to-end. Creates the git branch, optional worktree (sibling-of-repo
  by default), brief stub, `current.yml.active[]` entry, and `current.notes.yml` section in one
  step. Twelve numbered failure modes covering dirty trees, branch collisions, slug/iteration
  collisions, worktree path collisions, brief-file collisions. Handles `<slug>#<iter>` syntax
  per § "Iterations Inside a Feature" — creates iterations on existing features (prompting to
  promote flat-layout features) or new features with their first iteration.

- **`/ssd switch <slug>[#<iter>] [--no-note | --auto-note | --allow-dirty]`** — validates-all-first
  switch. Step 3 verifies target exists, target branch is resolvable, working tree is clean (or
  `--allow-dirty`), worktree path exists if applicable. Only after every validation passes does
  step 4 write the handoff note (per `switch_note_default` / profile — prompt/auto/skip) and
  step 5 run `git checkout` (or surface a literal `cd <path>` line for worktrees). Step-3
  validation guarantees no state mutation on failure — solves the "handoff written then checkout
  fails" race.

- **`/ssd worktree <slug>[#<iter>] add|remove [--path <path>]`** — explicit worktree lifecycle,
  decoupled from `feature new`. `add` resolves the worktree path via the configurable
  `worktree_root` + `worktree_name_pattern` (defaults `../` + `{repo}-{slug}`). `remove` refuses
  on dirty worktrees (FM-9), `git worktree prune`s when the path is missing on disk (recovery
  for manual `rm`), preserves the underlying branch.

**Self-verification block at end of § "Workstream Lifecycle Commands"** — instructs the
LLM-executing orchestrator to verify all failure-mode checks ran, all git invocations matched
the documented commands verbatim, and `current.yml` / `current.notes.yml` writes are atomic
(temp-file-rename or in-memory-prepare-then-write).

**Touched skills:**

- `ssd` — v1.15.0 → v1.16.0. New ~250-line "Workstream Lifecycle Commands" section. Updated
  Invocation table with three new command rows. Step 0 of `/ssd` (no-arg) Auto-Detect now
  cross-references the new commands.
- `ssd-init` — v1.5.0 → v1.6.0. Step 6 (project.yml write) now writes the four
  `project.yml.ssd.*` parallel-features keys with their defaults (`branch_pattern: "add-{slug}"`,
  `worktree_root: "../"`, `worktree_name_pattern: "{repo}-{slug}"`, `switch_note_default: prompt`).
  New paragraph after Step 6 explains the parallel-features defaults and links to ADR-0007.
- `ssd/rails.md` — v1.0.0 → v1.1.0. New "What This Is NOT" bullet clarifying that the
  v1.16.0 workstream lifecycle commands are intentionally non-rail (workflow ergonomics on the
  workstream container, not methodology on the workstream's eight rail steps).

**Edge cases resolved (iter B architect spec EC-1 through EC-5):**

- EC-1: Branch naming for iterations is `add-<slug>-<iter>` (advisory, configurable). The
  orchestrator records the full string in the workstream entry's `branch:` field; auto-detect
  Step 0's exact-match path handles it.
- EC-2: `/ssd feature new <slug>#<iter>` is valid and creates an iteration on an existing or
  new feature; promotion from flat-layout is non-destructive per ADR-0001.
- EC-3: Dirty-tree check runs BEFORE any state mutation (formalized in the validate-all-first
  step 3 of `/ssd switch`).
- EC-4: Detached HEAD on `/ssd switch` means `source` is `null` — handoff capture is skipped,
  warning logged, switch proceeds.
- EC-5: `/ssd worktree remove` on a missing worktree dir runs `git worktree prune` and clears
  state with a warning, rather than failing.

**Schema:** no changes. Iter A's optional `branch` / `worktree` / `touches` fields on
`current.yml.active[]` cover everything iter B needs. The new commands write those fields
directly.

**Deferred to iteration C (v1.17.0):**

- Coder-pass `touches:` backfill on gate runs (`git diff --name-only <base>...HEAD` union into
  the recorded `touches:` list).
- Cross-workstream overlap check at `/ssd gate` time, surfacing as `OVERLAP-N` SUGGESTION-tier
  findings in `code-reviewer/SKILL.md`.
- `methodology/gate-rules.sh` workstream-aware base-branch detection.

**Deferred (iteration D, only if real friction emerges):**

- `/ssd workstream adopt <slug> <branch>` (claim an existing branch as a workstream).
- `/ssd workstream set-branch <slug> <branch>` (rename / repair).
- `/ssd workstream handoff <slug>` (write a handoff note for a workstream not currently
  resolved as the source — useful when detached HEAD blocked auto-capture).

---

## [1.15.0] — 2026-05-21

### Iteration A — parallel-features schema + auto-detect (read-only)

First of three iterations of the parallel-features epic. Promotes branch/worktree/touched-files
to first-class workstream artifacts, enabling concurrent feature workstreams without per-switch
git ceremony. See [ADR-0007](docs/decisions/ADR-0007-parallel-features.md) for the rationale,
the alternatives rejected, and the three-iteration slicing.

**Also bundled in this release:** [ADR-0006](docs/decisions/ADR-0006-frontmatter-validator.md) —
retroactive documentation of the v1.14.0 frontmatter validator. The v1.14.0 release shipped the
validator + 5th gate rule without an ADR; ADR-0006 closes that doctrine debt. Cherry-picked
into this PR rather than shipped on its own branch to avoid an ADR-numbering gap on `main`
(round-1 code-review MAJOR-1 from this iteration).

**This iteration is intentionally read-only at the orchestrator surface** — no new commands
ship, no existing commands change behavior beyond auto-detect. New commands and overlap
detection ship in iterations B (v1.16.0) and C (v1.17.0) respectively.

**Schema additions (`.ssd/current.yml.active[]`, all optional, backward-compatible):**
- `branch: <string>` — git branch for this workstream. Defaults from
  `project.yml.ssd.branch_pattern`.
- `worktree: <absolute-path-or-null>` — opt-in worktree path; `null` = main checkout.
- `touches: [<glob>, ...]` — file globs the workstream is known to modify. Populated by
  architect (intent at design) and unioned by coder (actual diff each gate). Used for
  cross-workstream overlap detection in iteration C — not yet active.

Existing v2 `current.yml` files without these keys parse and behave identically. The
`schema_version: 2` field is unchanged — additions are strictly additive per ADR-0007's
"reject `schema_version: 3` bump" decision.

**Configuration additions (`.ssd/project.yml.ssd`, all optional, defaulted):**
- `branch_pattern: "add-{slug}"` — default for `/ssd feature new` (iteration B).
- `worktree_root: "../"` — default parent directory for new worktrees.
- `worktree_name_pattern: "{repo}-{slug}"` — default worktree directory name.
- `switch_note_default: prompt|auto|skip` — handoff-note capture behavior on
  `/ssd switch` (iteration B). Novice profile defaults to `prompt`; expert to `auto`.

**Orchestrator behavior (`ssd/SKILL.md` v1.15.0):**
- `/ssd` (no-arg) gains **Step 0**: branch → workstream auto-resolution. (1) Exact match
  against any `active[].branch`, (2) pattern match via `branch_pattern` prefix strip,
  (3) fall through to the existing decision tree on no-match. Read-only; the resolution
  changes which workstream the decision tree operates on, but the proposal itself still
  has to be accepted.
- Lazy backfill: on the next state write, an active entry with `branch: <absent>` gets
  the current checkout's branch — but only when exactly one active workstream is
  ambiguous (no guess on multi-ambiguity).

**Touched skills:**
- `ssd` — v1.10.0 → v1.15.0 (re-aligns SKILL.md version with library version). New
  Step 0 in `/ssd` (no-arg). New schema fields documented in Session Continuity.
  New worktree footnote in Artifact Tree.

**Spec drift (recorded for the code-reviewer):**
- The architect spec called for extending `methodology/schema-validator.sh` with optional-field
  checks. No such file exists — the actual validator (`methodology/frontmatter-validate.py`,
  introduced in v1.14.0) validates *artifact frontmatter*, not `current.yml`. The new fields
  live on `current.yml.active[]`, which has no separate schema-validating script. Coder
  dropped the validator change from iteration A. See [.ssd/features/parallel-features/03-coder-status.md](.ssd/features/parallel-features/03-coder-status.md)
  for details. If `current.yml` schema validation becomes load-bearing for the parallel-features
  flow (it currently is not — fields are optional and the orchestrator reads them tolerantly),
  iteration B or C will add a dedicated `current.yml` validator.

**Deferred to iteration B (v1.16.0):**
- New commands: `/ssd feature new`, `/ssd switch`, `/ssd worktree`.
- `ssd-init/SKILL.md` mention of concurrent workstream support + writing the four new
  `project.yml.ssd.*` defaults at init time.
- `ssd/rails.md` brief annotation that `switch`/`pause` are intentionally non-rail.

**Deferred to iteration C (v1.17.0):**
- Coder-pass `touches:` backfill on gate runs.
- Cross-workstream overlap check (`OVERLAP-N` SUGGESTION-tier finding in
  `code-reviewer/SKILL.md`).
- `methodology/gate-rules.sh` workstream-aware base-branch detection.

---

## [1.14.0] — 2026-04-29

### Iter A — frontmatter schema validator

Closes one of the two deferred-but-tractable items from the v1.13.0 ssd-skill-upgrades epic close:
**frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts.** The other deferred
item (true two-surface parity test) remains open — it requires Agent SDK harness work, not in
scope here.

**New artifacts:**
- `methodology/frontmatter-validate.py` — Python 3 + PyYAML validator. Walks
  `.ssd/features/<slug>/*.md` and `.ssd/milestones/<topic>/*.md`, parses the YAML frontmatter,
  matches each file to its skill schema, validates field presence and top-level type. Supports
  `--json` for structured output. Exits 0 on full pass, 1 on any FAIL.
- `methodology/schemas/architect.yml`, `coder.yml`, `code-reviewer.yml`, `systems-designer.yml`
  — per-skill schemas (deliberately minimal in v1: required fields + top-level types only).
  Sub-field shape and enum/regex constraints documented in each SKILL.md but not yet enforced;
  v2 may tighten.

**New gate rule (5th in `methodology/gate-rules.sh`):**
- `frontmatter-valid` — runs the validator on changed `.ssd/` artifacts (or walks the whole tree
  if no diff). PASSes when every artifact validates against its schema; FAILs on missing required
  fields or wrong types. SKIPs gracefully if Python 3 or PyYAML aren't on the host (matches
  existing precedent for `tests-pass` SKIP-when-precondition-missing).

**Type system** (validator): `string`, `int`, `bool`, `list`, `dict`, `timestamp`. The
`timestamp` type accepts datetime, date, or string — PyYAML auto-parses ISO-8601 strings to
datetime, so the schemas accept either representation.

**Parity-test harness updates** (`scripts/parity-test.sh`):
- 2 new fixtures: `frontmatter-valid` (passes), `frontmatter-invalid` (fails on missing fields).
- Both fixtures symlink the validator + schemas into the fixture's `methodology/` to avoid
  validator-finds-the-real-repo issues (root cause: `Path.cwd()` is now the project root for
  artifact discovery, but `__file__.resolve()` is still used for schema location, so symlinks
  resolve correctly for schemas while artifact discovery stays scoped to the fixture).
- Fixture setup now disables `commit.gpgsign` locally — fixtures in `/tmp` shouldn't and
  generally can't be GPG-signed; the global gitconfig was breaking them in environments where
  signing is on by default.
- Total assertions: 12 → 14, all passing.

**Touched skills:**
- `methodology` — v1.3.1 → v1.4.0 (Reference Files table now lists the validator + schemas;
  Gate Rules table adds `frontmatter-valid`; new "Frontmatter validator" sub-section).

**Deferred (still open):**
- True two-surface parity test (conversational vs command surface produce identical artifact
  trees). Requires Agent SDK harness; deferred until SSD has executable surface drivers.
- v2 schema tightening: per-field enum/regex/format validation, sub-dict shape (e.g.,
  `deliverables.component_diagram` boolean enforcement). Useful but separable iteration.

---

## [1.13.0] — 2026-04-29

### Iteration 9 of the SSD skill-upgrades epic — parity-test harness (final)

The architect doc envisioned a "two-surface parity test" comparing artifact trees produced via
the conversational vs command surface. That test isn't directly buildable from bash because the
surfaces are LLM-driven behaviors, not invokable processes. Iteration 9 ships the achievable
substitute: **structural conformance** for `methodology/gate-rules.sh`, the one piece of the
chain that IS bash and can be regression-tested.

**New file**: `scripts/parity-test.sh` — fast (<5s) test harness that runs `gate-rules.sh`
against 7 synthetic git fixtures and asserts the expected `PASS`/`FAIL`/`SKIP` for each rule:

- `clean-flagged-with-adr` — all rules satisfied (PASS / PASS / PASS / SKIP).
- `wip-commit-fails` — `wip-commits` FAILs on `WIP:` commit.
- `missing-flag-fails` — `feature-flag-present` FAILs on unflagged code addition.
- `docs-only-skips-flag` — `feature-flag-present` SKIPs on doc-only diffs.
- `missing-adr-fails` — `adr-delta` FAILs on 300-line architectural change without ADR.
- `yaml-comment-skip` — regression for round-2 MINOR-1 (commented YAML key not read as value).
- `spaced-path` — regression for round-2 MAJOR-2 (filenames with spaces handled correctly).

Plus 2 assertions on `--base` argument validation (regression for round-2 MINOR-2). Total: **12
assertions**; harness exits 0 on full pass.

**Out of scope (deferred until SSD has executable surface drivers):**
- True two-surface parity test (conversational vs command produce identical artifact trees).
- Frontmatter schema validator for `.ssd/features/<slug>/*.md` artifacts. Useful but separate
  iteration.

**Touched skills:** None — this is a CI-utility script, not a skill update.

**New artifact:** `scripts/parity-test.sh`.

**Iteration sequence:** 9 of 9 done — **the ssd-skill-upgrades epic is complete.** All seven
Part I upgrades plus rails.md (P2.A) and developer profile + teaching mode (P2.B) have shipped.
Part II's "two-surface parity test" remains an open ambition for when SSD gains executable
surface drivers (not in current scope).

---

## [1.12.0] — 2026-04-29

### Iteration 8 of the SSD skill-upgrades epic — developer profile + teaching mode (P2.B, ADR-0004)

Two audiences use SSD: newcomers who want the system to decide for them, and experienced
engineers who want every step explicit. v1.12.0 lets one product serve both without forking.

**New `project.yml` fields:**
```yaml
developer_profile: novice | standard | expert    # default: standard
teaching_mode:
  enabled: true|false                            # auto-true for first 5 invocations
  invocations_remaining: <int>                   # decay counter; default 5
rails: rails.md                                  # default; forkable per ADR-0003
```

**Profile-aware defaults** (hints, not gates — a novice can always invoke any command an expert
can):

| Profile | Default surface | Phase cmds | Confirmations | Narration | YAML editing |
|---|---|---|---|---|---|
| novice   | conversational | rejected with hint | irreversible only | full | discouraged |
| standard | conversational | accepted           | destructive only  | concise | allowed |
| expert   | command (or convo, user choice) | accepted | none | minimal | expected |

**Teaching mode**: decaying narration on conversational turns ("under the hood: I called
architect because phase=design"). Decrements per turn; auto-disables at 0.

**Auto-promotion**: novice→standard on first successful command-surface call;
standard→expert on >2 manual `current.yml` edits. Each prompt asks at most once per project.

**Bridge flags** (every surface reveals the other): `--explain` (conversational dry-run shows
command), `--narrate` (command emits conversational summary), `--raw` (conversational dumps raw
yaml), `--teach` (re-enable teaching).

**Touched skills:**
- `ssd` — v1.9.0 → v1.10.0 (new "Developer Profile + Teaching Mode" section)
- `ssd-init` — v1.4.0 → v1.5.0 (project.yml template updated; existing files fall back to
  defaults)

**New artifact:** `docs/decisions/ADR-0004-developer-profile-and-teaching-mode.md`.

**Iteration sequence:** 8 of 9 done. Next: P2.parity (test harness — final iteration).

---

## [1.11.0] — 2026-04-29

### Iteration 7 of the SSD skill-upgrades epic — `rails.md` as first-class artifact (P2.A, ADR-0003)

The eight-step canonical SSD sequence (brief → design → code → review → gate → deploy →
rollout-advance → flag-removal) was previously folklore scattered across `ssd/SKILL.md`,
per-skill files, and `methodology/core.md`. Iteration 7 names it.

**New file**: `ssd/rails.md` (v1.0.0). The single source of truth for:
- The eight-step canonical sequence.
- The eight critic-grade invariants every shipped feature satisfies.
- The `rail_deviations` logging contract (`current.yml.active[].rail_deviations`).
- The surface-agnostic guarantee: conversational and command surfaces walk the same rails.

**New behavior**: forks. A team with genuinely different needs forks `rails.md`, names the variant,
and points `project.yml.rails:` at it. The default is `rails.md`.

**Touched skills:**
- `ssd` — v1.8.0 → v1.9.0 (new "The Rails" section cross-references rails.md)

**New artifacts:**
- `ssd/rails.md`
- `docs/decisions/ADR-0003-rails-as-canonical-path.md`

**Iteration sequence:** 7 of 9 done. Next: P2.B (profile + teaching mode).

---

## [1.10.0] — 2026-04-29

### Iteration 6 of the SSD skill-upgrades epic — no-arg `/ssd` auto-detect (P1.3)

`/ssd` with no argument is now the **primary** entrypoint. Instead of requiring users to know
which phase command to type, the orchestrator reads state and proposes the next action.

**Behavior**: read `.ssd/current.yml` + `.ssd/current.notes.yml`. Inspect each active workstream's
`phase` field + the latest artifact, then propose the corresponding next phase command (with
slug + iteration suffix where applicable). Never silently advances — proposes and asks.

**Decision tree**: phase=brief → propose design; design → code; code → review; review with
gate_pass=false → return to code; review with gate_pass=true → ship; gate (post-pass) → deploy.
Renders `handoff_notes` from the notes sidecar as starting context.

**Multiple workstreams**: list with phase / last-touched / blockers; flag over-budget and stale
(>3 days untouched) entries. Ask user which to resume.

**Falls back to "ask"** for ambiguous or malformed state. Surfaces parse errors rather than
guessing.

**Touched skills:**
- `ssd` — v1.7.0 → v1.8.0

**Iteration sequence:** 6 of 9 done. Next: P2.A (rails.md).

---

## [1.9.0] — 2026-04-29

### Iteration 5 of the SSD skill-upgrades epic — bundled design pass (P1.4)

`architect` and `systems-designer` always run sequentially with the same inputs in the standard
`/ssd feature` flow. v1.9.0 lets them run as one logical step.

**New phase**: `/ssd design <slug>` (or `/ssd design <slug>#<iter>` for multi-iteration features):
1. Invokes `architect`; produces `01-architect.md`.
2. Reads the architect output, invokes `systems-designer`; produces `02-systems-designer.md`.
3. Surfaces gaps systems-designer rejected back to the user as one actionable block.

**Individual invocations remain valid.** `architect` and `systems-designer` are independently
invocable for ad-hoc design work, milestone redesigns, and external consumers (`codebase-skeptic`
reading just the architect spec). `/ssd design` is a convenience — it does not gate or change either
skill's contract.

**Skip `/ssd design` when systems-designer is N/A** (markdown-only repos, ADR-only PRs, skills
libraries). Invoke `architect` directly.

**Touched skills:**
- `ssd` — v1.6.0 → v1.7.0
- `architect` — v1.1.1 → v1.2.0 (changelog note only)
- `systems-designer` — v1.2.1 → v1.3.0 (changelog note only)

**Iteration sequence:** 5 of 9 done. Next: P1.3 (no-arg `/ssd` auto-detect).

---

## [1.8.0] — 2026-04-29

### Iteration 4 of the SSD skill-upgrades epic — deferred-findings ledger (P1.5)

Carry-over of non-blocking findings between iterations of a multi-iteration feature was previously
encoded as prose bullets in `current.yml` (`carried_to_pr_3c: [...]`). Iteration 4 makes it a
structured ledger with auto-load and auto-verify behavior.

**New artifact:** `.ssd/features/<slug>/iterations/<iter>/deferred.yml` (v1 schema):

```yaml
schema_version: 1
findings:
  - id: <severity>-<n>
    summary: <one-line>
    source: <relative-path-to-source-review>
    raised_in_iteration: <iter-id>
    target_iteration: <iter-id>|null
    status: open|closed|rolled-forward
    closed_in: <code-review-path>|null
```

**Auto-load on coder entry**: when entering coder phase for `<iter>`, the orchestrator pulls
entries with `target_iteration: <iter>` and `status: open` into the coder's input context as a
"Deferred from prior iterations" block. Coder either closes them in the diff or rolls them forward
with rationale.

**Auto-verify on review**: every multi-iteration review reads `deferred.yml` and checks each
entry's status against the diff. New frontmatter block `deferred_handled` with `closed`,
`rolled_forward`, and `silent_findings` (the last MUST be empty — silent findings are themselves a
MAJOR).

**Coder-status frontmatter additions**: `deferred.loaded` (count), `deferred.closed` (IDs),
`deferred.rolled_forward` (IDs).

**Single-cycle features** (no `iterations/` subdirectory) skip the ledger entirely — the schema
stays lean for the common case.

**Touched skills:**
- `coder` — v1.1.1 → v1.2.0
- `code-reviewer` — v1.3.0 → v1.4.0

**Iteration sequence:** 4 of 9 done. Next: P1.4 (bundled design pass).

---

## [1.7.0] — 2026-04-29

### Iteration 3 of the SSD skill-upgrades epic — multi-round gates (P1.2)

A `code-review` round that emits BLOCKER/MAJOR sends the workstream back to coder. The follow-up
review used to be tracked via filename suffixes (`04-code-review-round-2.md` was a manual
convention). It is now a structured concept the orchestrator auto-manages.

**Frontmatter additions to `code-reviewer` output:**
- `round: <int>` — 1 for first review, N for re-reviews. Auto-numbered by inspecting existing
  `code-review*` artifacts in the directory.
- `closed_from_previous_round: [<finding-id>, ...]` — list of finding IDs the reviewer verified
  closed since round N-1. Round 1 reviews use `[]`. Verification is per-claim against the code,
  not a copy from coder-status.

**Output paths by round + context:**
- Single-cycle feature, round 1: `.ssd/features/<slug>/04-code-review.md` (existing convention,
  unchanged).
- Single-cycle feature, round 2+: `.ssd/features/<slug>/04-code-review-round-N.md`.
- Multi-iteration feature: `.ssd/features/<slug>/iterations/<iter>/code-review/round-N.md`.
- Inline round-2 in the existing `04-code-review.md` remains valid for small remediations
  (1–3 closures) — pattern used by iteration 1 of this epic.

**`current.yml.active[].gate_rounds`** (field added in iter 1, populated from this iter): the
orchestrator increments it when a new round is written. Useful budget signal — `gate_rounds: 3`
suggests a contested design, scope cut, or rework.

**Touched skills:**
- `code-reviewer` — v1.2.1 → v1.3.0
- `ssd` — v1.5.0 → v1.6.0

**Iteration sequence:** 3 of 9 done. Next: P1.5 (deferred ledger), parallel-safe with this iter on
the iter-2 substrate.

---

## [1.6.0] — 2026-04-29

### Iteration 2 of the SSD skill-upgrades epic — first-class iterations (P1.1, ADR-0001)

A "feature" in SSD is no longer assumed to be a single design → build → review → deploy cycle.
Multi-iteration features (e.g., athena's `talentos-reimagined-phase3-ui` shipping as 3a / 3b / 3c)
now have a first-class home rather than the filename hack (`-3b`, `-round-2`) that observed usage
had been driving toward.

**Schema additions** (additive; back-compat with single-cycle features is total):
- `<slug>#<iter-id>` syntax accepted on every `/ssd` phase command.
- Opt-in `.ssd/features/<slug>/iterations/<iter-id>/` subtree per feature; epic-level docs
  (`00-brief.md`, `01-architect.md`, `02-systems-designer.md`) stay at the feature root and are
  shared across iterations.
- Per-iteration files: `brief.md`, `coder-status.md`, `code-review/round-N.md` (P1.2 in iter 3),
  `deferred.yml` (P1.5 in iter 4), `deploy.md`.
- `iteration` field in `current.yml` v2 (added in iter 1) is now actively populated.

**Resolution rules** documented in `ssd/SKILL.md` § "Iterations Inside a Feature":
1. Slug with `#`: operate on the iteration subtree; first reference promotes a flat-layout feature
   non-destructively (epic artifacts stay at the root).
2. Slug without `#` on a multi-iteration feature: orchestrator surfaces active iterations and asks.
3. Slug without `#` on a flat-layout feature: single-cycle path, unchanged.

**Touched skills:**
- `ssd` — v1.4.0 → v1.5.0
- `ssd-init` — v1.3.0 → v1.4.0 (documents that `iterations/` subdirs are created by the
  orchestrator on demand, not by init)

**New artifact:** `docs/decisions/ADR-0001-iterations-as-schema-substrate.md`.

**Iteration sequence:** 2 of 9 done. Next: P1.2 (multi-round gates), which builds on this
substrate.

---

## [1.5.0] — 2026-04-28

### Iteration 1 of the SSD skill-upgrades epic

First substantive iteration of the multi-iteration plan documented at
[.ssd/features/ssd-skill-upgrades/01-architect.md](.ssd/features/ssd-skill-upgrades/01-architect.md). Bundled
two engine-level upgrades that have no inter-dependency (P1.6 + P1.7).

**Executable gate rules (P1.6, ADR-0005):**
- New file `methodology/gate-rules.sh` — bash routine implementing four mechanical checks
  (`wip-commits`, `tests-pass`, `feature-flag-present`, `adr-delta`) with `PASS|FAIL|SKIP`
  structured stdout and `--json` mode for CI consumption.
- `ssd/SKILL.md` § "Methodology Enforcement" now invokes the script synchronously and refuses to
  pass the gate on any FAIL with the doctrine cite named.
- `methodology/SKILL.md` (v1.3.0) gains a "Gate Rules — Executable" section describing the script,
  the rule table, and direct-invocation usage for CI.
- Rationale: gate rules that aren't executable are decoration. ADR-0005 documents why bash is the
  right tool versus orchestrator-internal LLM checks (composability, reproducibility, testability,
  speed, fail-loud).

**`current.yml` v2 split + notes sidecar (P1.7, ADR-0002):**
- `.ssd/current.yml` is now schema-validated machine state; carries `schema_version: 2`.
- `.ssd/current.notes.yml` is the new free-form sidecar for handoff notes, scope changes, and
  questions for the next session.
- `ssd-init/SKILL.md` (v1.3.0) Step 7 split into "create both files fresh" and "v1 detected →
  prompted migration with `.bak`" paths. Migration is opt-in. Legacy v1 files continue to parse.
- v2 schema includes nullable `iteration`, `gate_rounds`, `rail_deviations` fields. Populated by
  later iterations (P1.1, P1.2, P2.A); present from v1.5.0 so the schema ships forward-compatible.

**Touched skills:**
- `ssd` — v1.3.0 → v1.4.0
- `methodology` — v1.2.1 → v1.3.0 → **v1.3.1** (round-2 fixes from iteration-1 code review)
- `ssd-init` — v1.2.0 → v1.3.0

**Round-2 fixes** (closed during iteration 1's code-review gate, before merge):
- MAJOR-1: `feature-flag-present` greps the added diff lines (`^+[^+]`) instead of file contents.
  A pre-existing flag marker elsewhere in a file no longer gives unflagged additions a free pass.
- MAJOR-2: both `feature-flag-present` and `adr-delta` build a quoted bash array of changed files
  instead of unquoted command substitution, closing a silent-SKIP on filenames with spaces or
  shell metacharacters.
- MINOR-1: `yaml_get` skips comment lines so `# test_command: pytest` is documentation, not a value.
- MINOR-2: `--base` argument parser rejects missing values and adjacent flags.
- Both MAJORs verified with synthetic git fixtures: file with pre-existing flag + unflagged
  addition → correct FAIL; spaced directory + ADR-less architectural change → correct FAIL.

**New artifacts:**
- `methodology/gate-rules.sh`
- `docs/decisions/ADR-0002-current-yml-split.md`
- `docs/decisions/ADR-0005-gate-execution-model.md`

**Iteration sequence:** This is iteration 1 of 9. Next: P1.1 (first-class iterations substrate). The
remaining iterations will land independently per the epic plan.

---

## [1.4.0] — 2026-04-28

### Working-tree convention: `ssd/` → `.ssd/`

The SSD working directory at the project root is renamed from visible `ssd/` to hidden `.ssd/`. All
path references in skill specs, gitignore guidance, and orchestrator logic are updated in lockstep.

**Why.** Two reasons: (1) in the SSD skills repo itself, a visible `ssd/` directory at the project
root collides with the orchestrator skill source directory, making `/ssd-init` impossible to run
cleanly inside this repo; (2) the working tree is transient state — review reports, design specs,
session-continuity pointers — not source code humans need to browse alongside the rest of the repo.
Hiding it keeps file-tree noise down while remaining fully accessible via `cd .ssd/`, IDE go-to-file,
and `ls -a`.

**Touched skills (path references updated; behavior unchanged):**
- `ssd` (orchestrator) → v1.3.0
- `ssd-init` → v1.2.0
- `architect`, `code-reviewer`, `codebase-skeptic`, `coder`, `methodology`, `refactor`,
  `software-standards`, `systems-designer` — Interface tables and inline path references updated;
  per-skill changelog entries added.

**Touched docs:**
- `README.md` — `Where to Start` and skill table use `.ssd/`.
- `CHANGELOG.md` — this entry; historical entries restored to their original `ssd/` wording (the
  convention they actually shipped under).
- `real-world-artifacts/ssd-upgrades-plan.md` — working-tree references updated; references to the
  orchestrator skill source (`~/.claude/skills/ssd/SKILL.md`) preserved.

`/ssd-init` invocations on existing projects with an `ssd/` working tree should: (a) stop, (b) `mv
ssd .ssd`, (c) re-run `/ssd-init` (idempotent — will detect existing state).

---

## [1.3.0] — 2026-04-18

### Post-v1.2-remediation skill improvements

Executed from `ai_working_directory/claude_skills_improvements/` plan (00-README + 01–04). The
remediation branch for work shipped successfully but fresh critic runs exposed gaps in the skills
themselves — missing operational failure-mode lenses, no loop closure, no structured hand-offs between
skills. This release addresses those gaps.

**New skill — ssd-init (v1.1.0):**
- First-run housekeeping for SSD projects. Creates `ssd/` (gitignored), `ssd/project.yml`,
  `ssd/current.yml`, `docs/decisions/`, `docs/runbooks/`, `docs/architecture/`, and runs SSD
  prerequisite checks (CI/CD, tests, flags, deployed hello-world). Idempotent — safe to re-run.
  Prerequisite to all `/ssd` phases. (Working tree later renamed to `.ssd/` in v1.4.0.)
- v1.1.0 aligns its artifact tree with the feature-centric / milestone-centric layout that every
  other sub-skill now declares: `ssd/features/<slug>/01-architect.md … 05-deploy.md` for features,
  `ssd/milestones/<YYYY-MM-DD-topic>/skeptic-before.md … verification.md` for milestones,
  `ssd/audits/<YYYY-MM-DD-scope>/` for audits. Replaces v1.0.0's per-skill subdirectory layout to
  eliminate the path mismatch that would have broken the chain.

**Orchestrator (ssd v1.2.0):**
- Declared the SSD artifact tree at `ssd/` (gitignored) + `docs/decisions/` (committed) (O1)
- Required YAML frontmatter on every primary output, with finding_counts / gate_pass / deliverables
  fields (O2)
- Added `/ssd verify` phase and mandatory before/after snapshot convention for milestones (O4, O5)
- Session continuity via `ssd/current.yml` (active workstreams, budget, last_touched) (O8)
- Methodology-backed gate enforcement table (O9)
- Skill-overlap priority table (coder vs python-django-coder, code-reviewer vs codebase-skeptic,
  codebase-skeptic vs software-standards) (O11)

**Review skills:**
- **codebase-skeptic (v1.2.0)**: mandatory Phase 2.5 Operational Failure Modes Sweep (C1);
  Forward-Looking Pass in Phase 4 (C4); Remediation Branch mode + self-verification in Operational
  Notes (C2, O6); reciprocal `/code-reviewer` hook table (C7); Incident-Story attestation for Beck,
  Domain-Modeling Stance for Evans, Deployment-Gate Hardening for Humble (C3, C5, C6).
- **code-reviewer (v1.2.0)**: Phase 1.5 Prior-Review Follow-up for remediation branches (R6); Phase 3.5
  Fix-Introduces-Edge-Cases (R2); 12 new Red Flags including LLM prompt injection, IntegrityError
  fetch mismatch, cache-without-race-test, release theatre (R3); Verify-Before-Escalating rule for
  sub-agent parallelization (R4); Severity Discipline (O7); Self-Verification (O6); LLM-specific
  examples, Edge Case Inventory template, Private-state mutation anti-pattern added to examples.md
  (R1, R5, R7).

**Build / design skills:**
- **architect (v1.1.0)**: output path + Quality Gate section mapping (A1, A2); Universal Principle 6
  "Integration Has a First-Class Contract" (A3); eight always-ADR decisions enumerated (A4); Current
  Scale Baseline required deliverable (A5).
- **systems-designer (v1.2.0)**: Phase 0 input validation against architect spec (S1); three-tier
  output with machine-check / human-review / block conditions (S2); new Concerns for AI/LLM
  Integration (S3), Compliance & Data Lifecycle (S4), Cost Observability (S5), Chaos / Failure
  Injection (S6).
- **coder (v1.1.0)**: output artifact `03-coder-status.md` with test/lint/typecheck results (C1, C2);
  Step 6.5 spec-drift check with ADR amendment prompt (C3); feature flag read from architect spec,
  halt if absent (C4); Cross-Language Boundaries section (C5).
- **refactor (v1.2.0)**: per-item finding citation requirement (R1); Step 4.5 Budget Check with
  halt-and-rollback options (R2); Step 5 Loop Closure with per-item re-check (R4); Step 6
  Systems-Designer Coordination trigger (R3).

**Audit / reference skills:**
- **software-standards (v1.1.0)**: two-mode support Comparative / Adversarial Single (ST1); 2–3
  evidence citations required per /10 score (ST2); explicit "When NOT to Use" delineation vs.
  codebase-skeptic (ST3); output path + frontmatter (ST4).
- **methodology (v1.2.0)**: clarified it provides machine-checkable rule source for `/ssd gate` (M1);
  added `/methodology score` self-adherence metric invocation (M2); audience-split expectation for
  adoption.md (M3); date-stamped comparisons with 12-month refresh prompt (M4).

**Cross-cutting:**
- Added "Skill Hygiene Contract" section to README.md (O10): file structure, interface discipline,
  header/license ordering, and future contract-test layer.
- Title-first header ordering enforced across all SKILL.md files (X6).
- License pointer already single-line since v1.2.0; Skill Hygiene Contract now requires it (X1).
- Per-skill `## Changelog` section required + added to all touched skills (X3).

---

## [1.2.0] — 2026-03-27

### Codebase review remediation

Eating own dogfood in real time. Executed findings from `codebase-skeptic` review (`documentation/skills/codebase-review-2026-03-27.md`). Voices activated: Fowler, Uncle Bob, Evans, Jobs, Wozniak.

- **ssd/SKILL.md** (v1.1.0) — replaced duplicated doctrine (shippable state invariant checklist, hard rules) with references to `methodology/core.md`; replaced inline ship checklist with directive to invoke `systems-designer`
- **code-reviewer/** (v1.1.0) — decomposed into orchestrator + `examples.md` sub-file; extracted all code examples (correctness, security, performance, maintainability, testing) and comment-writing examples into reference file; added language-adaptation note
- **refactor/** (v1.1.0) — decomposed into orchestrator + `patterns.md` sub-file; extracted scanning techniques and 6 refactoring patterns into reference file; added language-adaptation note
- **systems-designer/SKILL.md** (v1.1.0) — added language-adaptation note acknowledging Python-centric examples
- **methodology/SKILL.md** (v1.1.0) — version bumped to reflect prior decomposition (was still at 1.0.0)
- **All 37 files** — replaced 12-line per-file license blocks with one-line reference (`<!-- License: See /LICENSE -->`); ~500 tokens recovered per session
- **README** — updated contributing guide to reflect new license convention and framework template
- **architect/web/frameworks/TEMPLATE.md** — new file; structural template for framework guide contributions ensuring section parity across all guides
- **5 skills** — bumped version markers from 1.0.0 to 1.1.0 (ssd, code-reviewer, refactor, systems-designer, methodology)
- **.gitignore** — created; excludes `.DS_Store`

---

## [1.1.1] — 2026-03-27

- **README, CHANGELOG** — corrected brand name from "Insanely Great SSD" to "InsanelyGreat's SSD"

---

## [1.1.0] — 2026-03-27

### Structural improvements (this session)

- **LICENSE** — corrected to match shareware terms stated in all SKILL.md files (was accidentally set to The Unlicense)
- **README** — updated description to "free-for-personal-use"; added "Where to Start" section with canonical entry point (`/ssd`); added Skill Taxonomy table classifying skills as orchestrator / domain / review / reference
- **ssd/SKILL.md** — removed dead reference to local development file (`~/Development/Claude-Skills/ssd-meta-skill-proposal.md`)
- **methodology/** — decomposed 794-line monolith into focused sub-files:
  - `core.md` — Iron Law, Five Principles, Decision Framework, Metrics, Engineering Mindset (stable doctrine)
  - `patterns.md` — Five implementation patterns + Advanced topics (how-to layer)
  - `adoption.md` — Getting started, objections, org adoption, comparisons, resources (human onboarding material)
  - `SKILL.md` — slim orchestrator (~50 lines) that loads the right sub-file based on context
- **All SKILL.md files** — added standardized `## Interface` table (Input / Output / Consumed by / SSD Phase) to all 9 skills
- **All SKILL.md files** — added `**Version:** 1.0.0` marker to each skill header
- **CHANGELOG.md** — created this file

---

## [1.0.0] — 2026-03-25 / 2026-03-26

### Initial release

- `4b97b09` (2026-03-25) — Initial SSD skills: ssd, architect, coder, code-reviewer, systems-designer, refactor, methodology, software-standards, codebase-skeptic
- `f144156` (2026-03-25) — Updated license agreements across all files
- `8d9356b` (2026-03-26) — Made mobile, web, and desktop first-class citizens in SSD methodology; expanded platform coverage
- `abd9841` (2026-03-26) — Added 9 web framework guides (Next.js, Django, FastAPI, Rails, Laravel, Angular, Vue/Nuxt, Spring Boot, ASP.NET Core) and 5 language guides (C, C++, Go, PHP, Obj-C)

---

## Versioning Policy

Each SKILL.md carries its own version marker (`**Version:** x.y.z`). The library version in this changelog tracks the overall collection.

- **Patch** (x.y.**Z**): Corrections, typo fixes, updated code examples
- **Minor** (x.**Y**.z): New guides, new skills, new platform coverage, structural improvements that don't change skill behavior
- **Major** (**X**.y.z): Breaking changes to skill interface contracts or SSD doctrine
