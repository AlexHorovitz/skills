# `methodology/hooks/` — optional git hooks

(added v1.19.0, see [ADR-0008](../../docs/decisions/ADR-0008-ssd-commit-split.md))

Bash hook scripts for SSD's selective-commit-split convention. The hooks here are **opt-in
extensions** to the `/ssd gate` enforcement that runs at PR time. They catch the same class
of issues earlier in the pipeline (pre-commit), so you find out before pushing.

Each hook is a plain bash script designed for symlink install. No framework (husky,
pre-commit.com) is required — the SSD precedent is "if `bash` is on the machine, the hook
works."

## Hooks available

| Hook | What it catches |
|---|---|
| [`pre-commit-no-leaky-state.sh`](pre-commit-no-leaky-state.sh) | Staged files matching the `no-leaky-state` deny-list (machine state under `.ssd/` that's gitignored by policy per ADR-0008). Blocks the commit before it lands. |

## Install (the symlink convention)

From your repo root:

```bash
ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
chmod +x methodology/hooks/pre-commit-no-leaky-state.sh   # one-time, if needed
```

Verify:

```bash
ls -la .git/hooks/pre-commit
# Should show a symlink → ../../methodology/hooks/pre-commit-no-leaky-state.sh
```

## Verify it works

Try to force-add a gitignored-by-policy file and commit:

```bash
git add -f .ssd/current.yml          # force-add bypasses .gitignore
git commit -m "test"
```

You should see:

```
FAIL no-leaky-state :: 1 file(s) gitignored by policy but tracked: .ssd/current.yml|
```

…and `git commit` exits non-zero with no commit created. Unstage to recover:

```bash
git reset HEAD .ssd/current.yml
```

## Uninstall

If `.git/hooks/pre-commit` IS the no-leaky-state symlink:

```bash
rm .git/hooks/pre-commit
```

If it's a chained hook (see "Coexistence" below), remove the relevant invocation line from
the existing hook instead.

## Coexistence with existing pre-commit hooks

If your repo already has a `.git/hooks/pre-commit` hook (e.g., a project-wide formatter, a
secrets scanner, husky-installed wrapper), don't overwrite it. Add the no-leaky-state check
inline at the top of your existing hook:

```bash
# At the top of your existing .git/hooks/pre-commit:
bash "$(git rev-parse --show-toplevel)/methodology/gate-rules.sh" --staged --rules no-leaky-state || exit $?

# …then your existing hook logic continues below.
```

This pattern keeps no-leaky-state as the first check (cheap, fails fast on policy
violations) and lets your other hooks run after. If no-leaky-state fails, the commit is
blocked and your other hooks don't waste time.

## Why a plain symlink, not husky / pre-commit.com

Per [ADR-0008 § "Alternatives Rejected"](../../docs/decisions/ADR-0008-ssd-commit-split.md):

- **No framework dependency.** SSD already shells out to git and bash via
  `gate-rules.sh`. Adding a framework would create a parallel install path users have to
  learn.
- **Symlink is the git-native convention.** Git's hook discovery is already symlink-aware.
- **Plain bash is portable.** Works on macOS, Linux, WSL, and CI runners without setup.

If your team already uses husky or pre-commit.com for other hooks, the **coexistence**
pattern above is the integration path — invoke the bash script from inside the framework's
hook definition. Don't try to wedge the SSD hooks into a framework manifest; that's the
inverse of the contract.

## CI integration (the backstop)

Hooks are bypassable (`--no-verify` skips them; SSD doctrine forbids this but local
developers can technically do it). CI is the unbypassable backstop. Add this to your CI
workflow:

```yaml
# .github/workflows/ssd-gate.yml (or equivalent in your CI)
- name: Run SSD gate (no-leaky-state)
  run: bash methodology/gate-rules.sh --base origin/main --rules no-leaky-state
```

(Drop `--rules no-leaky-state` to run all gate rules; that's the recommended full-gate CI
pattern, not just the leaky-state subset.)

## Doctrine reminders

- **Never `--no-verify` your way past this hook.** SSD's hard rules (`ssd/SKILL.md` §
  "Hard Rules") forbid bypass. If the hook fires, the staged file is gitignored by policy
  for a reason. Fix the underlying issue.
- **The hook is opt-in.** Solo developers and small projects may run fine without it,
  relying on the `/ssd gate` PR-time check. Installing the hook is friction-reduction, not
  a methodology requirement.
- **Hooks are per-checkout state.** A clone of the repo by another contributor doesn't
  inherit the symlink. Each contributor installs the hook themselves (or your team's
  framework / `husky`-style auto-install handles it). Document the install step in your
  repo's onboarding.

## Hook script contract

If you add a new hook to this directory, it should:

1. Locate `methodology/gate-rules.sh` via `git rev-parse --show-toplevel`.
2. Invoke a specific subset of gate rules via `--rules <rule-name>[,<rule-name>...]`.
3. Use `--staged` for pre-commit hooks; default branch mode for post-commit / push hooks.
4. Pass through the exit code from `gate-rules.sh`. Don't translate.
5. Be silent on PASS (no output unless something's wrong — standard hook UX).
6. Add itself to this README's "Hooks available" table.

Don't reimplement gate-rule logic in the hook; always shell out to `gate-rules.sh`. Single
source of truth.
