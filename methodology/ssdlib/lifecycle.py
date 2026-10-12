"""Setup planning, managed-block ownership, backup, restore, and removal.

Removal deletes SSD-owned hook symlinks and managed blocks. It leaves source,
``.ssd/`` history, and unrelated git hooks in place.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

BEGIN = "<!-- ssd:managed id={block_id} -->"
END = "<!-- /ssd:managed -->"

DISCOVERY_CANDIDATES = (
    ("scripts/parity-test.sh", "bash scripts/parity-test.sh"),
    ("Makefile", "make test"),
    ("package.json", "npm test"),
    ("pyproject.toml", "python -m pytest"),
    ("go.mod", "go test ./..."),
    ("Cargo.toml", "cargo test"),
)


def discover_test_commands(project: Path) -> list[dict]:
    """Name candidate test commands. Do not execute them."""
    found = []
    for marker, command in DISCOVERY_CANDIDATES:
        if (project / marker).exists():
            found.append({"marker": marker, "command": command, "executed": False})
    return found


def plan(project: Path, *, library: Path) -> dict:
    """Files a setup apply would create. This function does not write."""
    changes = []
    for rel in (
        ".ssd/project.yml",
        ".ssd/current.yml",
        ".ssd/current.notes.yml",
        ".ssd/gate.yml",
        ".ssd/init-log.md",
        ".ssd/README.md",
        "docs/decisions",
        "docs/runbooks",
        "docs/architecture",
    ):
        path = project / rel
        changes.append({
            "path": rel,
            "action": "keep" if path.exists() else "create",
        })
    gitignore = project / ".gitignore"
    changes.append({
        "path": ".gitignore",
        "action": "edit-if-consented" if gitignore.exists() else "create",
        "note": "selective pattern from methodology/selective.gitignore; existing mode is preserved",
    })
    for name in ("CLAUDE.md", "AGENTS.md"):
        path = project / name
        changes.append({
            "path": name,
            "action": "merge-managed-block" if path.exists() else "create-managed-block",
            "note": "existing text outside the managed block is preserved",
        })
    hook = project / ".git" / "hooks" / "pre-commit"
    changes.append({
        "path": ".git/hooks/pre-commit",
        "action": "unchanged",
        "note": "not installed unless a later explicit consent says so; a foreign hook is never replaced",
    })
    return {
        "project": str(project),
        "library": str(library),
        "storage_mode": "selective",
        "test_commands": discover_test_commands(project),
        "optional_permissions": [
            "git hook install (off unless consented)",
            "GitHub issue mirror (off unless consented)",
            "private mode (off unless consented)",
        ],
        "changes": changes,
        "writes": 0,
    }


def _wrap(block_id: str, body: str) -> str:
    return f"{BEGIN.format(block_id=block_id)}\n{body.rstrip()}\n{END}\n"


def merge_managed(path: Path, block_id: str, body: str) -> str:
    """Return the new text. Does not write. Replaces only the named block."""
    wrapped = _wrap(block_id, body)
    begin = BEGIN.format(block_id=block_id)
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    start = existing.find(begin)
    if start == -1:
        if existing and not existing.endswith("\n"):
            existing += "\n"
        return existing + ("\n" if existing else "") + wrapped
    end = existing.find(END, start)
    if end == -1:
        raise ValueError(f"managed block {block_id} has no closing marker; refusing to guess")
    end = end + len(END)
    if end < len(existing) and existing[end] == "\n":
        end += 1
    return existing[:start] + wrapped + existing[end:]


def apply_managed(path: Path, block_id: str, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(merge_managed(path, block_id, body), encoding="utf-8")


def strip_managed(text: str, block_id: str | None = None) -> str:
    """Remove one managed block, or every SSD managed block when block_id is None."""
    while True:
        if block_id:
            begin = BEGIN.format(block_id=block_id)
            start = text.find(begin)
        else:
            start = text.find("<!-- ssd:managed id=")
        if start == -1:
            return text
        end = text.find(END, start)
        if end == -1:
            raise ValueError("unclosed managed block; refusing to delete surrounding text")
        end = end + len(END)
        if end < len(text) and text[end] == "\n":
            end += 1
        text = text[:start] + text[end:]


def backup(project: Path, dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    for rel in (".ssd", "AGENTS.md", "CLAUDE.md", ".gitignore"):
        src = project / rel
        if not src.exists():
            continue
        target = dest / rel
        if src.is_dir():
            shutil.copytree(src, target, symlinks=True, dirs_exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)
    return dest


def restore(backup_dir: Path, project: Path) -> None:
    for rel in (".ssd", "AGENTS.md", "CLAUDE.md", ".gitignore"):
        src = backup_dir / rel
        target = project / rel
        if not src.exists():
            continue
        if src.is_dir():
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(src, target, symlinks=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target)


def remove(project: Path, *, library: Path) -> dict:
    """Disable SSD-owned integration points. Keep .ssd/ and user source."""
    removed = []
    kept = [".ssd/"]
    for name in ("AGENTS.md", "CLAUDE.md"):
        path = project / name
        if not path.is_file():
            continue
        original = path.read_text(encoding="utf-8")
        try:
            updated = strip_managed(original)
        except ValueError as exc:
            return {"status": "ERROR", "detail": str(exc), "removed": removed, "kept": kept}
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            removed.append(name)
        if path.is_file() and not path.read_text(encoding="utf-8").strip():
            # Leave an empty file only if the user had nothing else. Still their file.
            kept.append(name)
    hook = project / ".git" / "hooks" / "pre-commit"
    owned = library / "methodology" / "hooks" / "pre-commit-no-leaky-state.sh"
    if hook.is_symlink():
        try:
            target = hook.resolve()
        except OSError:
            target = None
        if target == owned.resolve():
            hook.unlink()
            removed.append(".git/hooks/pre-commit")
        else:
            kept.append(".git/hooks/pre-commit (not SSD-owned)")
    elif hook.exists():
        kept.append(".git/hooks/pre-commit (regular file, not removed)")
    return {"status": "PASS", "removed": removed, "kept": kept, "history": "preserved"}


def format_marker(project: Path) -> int | None:
    path = project / ".ssd" / "format"
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8").strip()
    try:
        return int(text.split(".", 1)[0])
    except ValueError:
        return None


def assert_can_write(project: Path, library_version: str) -> None:
    """Older libraries must not rewrite state marked with a newer format."""
    marker = format_marker(project)
    if marker is None:
        return
    try:
        major = int(library_version.split(".", 1)[0])
    except ValueError as exc:
        raise RuntimeError(f"unreadable library version {library_version!r}") from exc
    if major < marker:
        raise RuntimeError(
            f"library {library_version} cannot safely write state format {marker}; "
            "refusing rather than corrupting it"
        )


def coexistence(library: Path) -> dict:
    plugin = (library / ".claude-plugin" / "plugin.json").is_file()
    clone = (library / ".git").exists()
    return {
        "clone": clone,
        "plugin_manifest": plugin,
        "resolution": "both present; do not delete either" if clone and plugin else "single",
    }


def run_migrate_preview(library: Path, project: Path, recorded: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(library / "methodology" / "migrate.sh"), "--from", recorded],
        cwd=project,
        capture_output=True,
        text=True,
    )
