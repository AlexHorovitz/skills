"""Resolve library, project, worktree, and storage roots.

The v2.14 gate looked up methodology/frontmatter-validate.py only under the
project root. A project that merely *uses* an installed library then skipped
frontmatter validation. ``legacy_validator_path`` is that behavior, kept so a
test can reproduce it. ``resolve_validator`` prefers a project copy (fixture
and vendored installs) and otherwise uses the library next to this package.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


def library_root(start: Path | None = None) -> Path:
    here = (start or Path(__file__)).resolve()
    for candidate in [here, *here.parents]:
        if (
            (candidate / "VERSION").is_file()
            and (candidate / "methodology").is_dir()
            and (candidate / "ssd" / "SKILL.md").is_file()
        ):
            return candidate
    raise RuntimeError("SSD library root not found (need VERSION, methodology/, ssd/SKILL.md)")


def _git(cwd: Path, *args: str) -> str | None:
    try:
        out = subprocess.check_output(
            ["git", "-C", str(cwd), *args],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return None
    text = out.strip()
    return text or None


def project_root(cwd: Path | None = None) -> Path | None:
    """Directory whose .ssd/ (or git toplevel) is the project being operated on."""
    start = Path(cwd or os.getcwd()).resolve()
    top = _git(start, "rev-parse", "--show-toplevel")
    if top:
        return Path(top)
    for candidate in [start, *start.parents]:
        if (candidate / ".ssd" / "project.yml").is_file() or (candidate / ".git").exists():
            return candidate
    return None


def worktree_root(cwd: Path | None = None) -> Path | None:
    """Git worktree root of cwd. Distinct from the common git dir when linked."""
    start = Path(cwd or os.getcwd()).resolve()
    top = _git(start, "rev-parse", "--show-toplevel")
    return Path(top) if top else project_root(start)


def worktree_is_linked(cwd: Path | None = None) -> bool:
    start = Path(cwd or os.getcwd()).resolve()
    git_dir = _git(start, "rev-parse", "--git-dir")
    common = _git(start, "rev-parse", "--git-common-dir")
    if not git_dir or not common:
        return False
    return Path(git_dir).resolve() != Path(common).resolve()


def storage_root(project: Path) -> tuple[Path, str]:
    """Return (path, kind). kind is directory, symlink, missing, or unreadable."""
    ssd = project / ".ssd"
    try:
        if ssd.is_symlink():
            return ssd.resolve(), "symlink"
        if ssd.is_dir():
            return ssd.resolve(), "directory"
        if ssd.exists():
            return ssd, "not-a-directory"
        return ssd, "missing"
    except OSError:
        return ssd, "unreadable"


def legacy_validator_path(project: Path) -> Path | None:
    """v2.14 lookup. Does not consult the installed library. Reproduced on purpose."""
    candidate = project / "methodology" / "frontmatter-validate.py"
    return candidate if candidate.is_file() else None


def resolve_validator(project: Path, library: Path | None = None) -> Path | None:
    local = legacy_validator_path(project)
    if local is not None:
        return local
    lib = library or library_root()
    candidate = lib / "methodology" / "frontmatter-validate.py"
    return candidate if candidate.is_file() else None


def describe(cwd: Path | None = None) -> dict:
    lib = library_root()
    project = project_root(cwd)
    worktree = worktree_root(cwd)
    storage, storage_kind = storage_root(project) if project else (None, "no-project")
    return {
        "library_root": str(lib),
        "project_root": str(project) if project else None,
        "worktree_root": str(worktree) if worktree else None,
        "worktree_linked": worktree_is_linked(cwd) if worktree else False,
        "storage_root": str(storage) if storage else None,
        "storage_kind": storage_kind,
    }
