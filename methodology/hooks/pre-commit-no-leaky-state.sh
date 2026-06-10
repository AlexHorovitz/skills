#!/usr/bin/env bash
# methodology/hooks/pre-commit-no-leaky-state.sh — block staged files that match the SSD
# selective-commit deny-list before the commit lands.
#
# This hook is the iter-B safety net for ADR-0008's commit-split convention. It catches
# accidental staging of machine state (current.yml, project.yml, init-log.md, archive/,
# audits/, snapshot machinery) BEFORE the commit lands — complementing the no-leaky-state
# gate rule that runs at /ssd gate / PR time. It is a single-rule wrapper around
# `methodology/gate-rules.sh --staged --rules no-leaky-state`.
#
# Install (symlink convention, see methodology/hooks/README.md):
#     cd <repo-root>
#     ln -s ../../methodology/hooks/pre-commit-no-leaky-state.sh .git/hooks/pre-commit
#     chmod +x methodology/hooks/pre-commit-no-leaky-state.sh   # one-time, if needed
#
# Coexistence with existing pre-commit hooks (e.g., a project formatter): inline this
# invocation at the top of your existing hook instead of symlinking. See README.md.
#
# Doctrine: SSD forbids bypassing this hook via `git commit --no-verify`. If the hook fires,
# fix the underlying issue — the staged file is gitignored by policy for a reason.
#
# Exit codes:
#   0 — clean (no forbidden files staged, or project is on gitignore_mode: blanket)
#   1 — forbidden file(s) staged; commit blocked
#   other — environment error (missing gate-rules.sh, not in a git repo, etc.)
#
# License: see /LICENSE.

set -uo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$PROJECT_ROOT" ]]; then
  echo "pre-commit-no-leaky-state: not in a git repo" >&2
  exit 2
fi

GATE_RULES="$PROJECT_ROOT/methodology/gate-rules.sh"
if [[ ! -f "$GATE_RULES" ]]; then
  echo "pre-commit-no-leaky-state: methodology/gate-rules.sh not found at $GATE_RULES" >&2
  echo "  The hook expects the SSD skills library installed at the repo root." >&2
  echo "  If you copied this hook into a project without methodology/, either install" >&2
  echo "  the SSD library or remove the hook with:" >&2
  echo "      rm $PROJECT_ROOT/.git/hooks/pre-commit" >&2
  exit 2
fi

# Run only the no-leaky-state rule, in staged mode. The hook is intentionally narrow —
# wip-commits, tests-pass, adr-delta, frontmatter-valid are all PR-time concerns that
# would either no-op or be too slow for the commit pipeline.
bash "$GATE_RULES" --staged --rules no-leaky-state
exit $?
