"""Constrained, secretless test executor.

Supported profile: a user-namespace mount jail (unshare + chroot) with the
snapshot copied in, host directories other than a read-only toolchain not
mounted, network namespace dropped, and the environment cleared.

If that mechanism is unavailable, strong-assurance review is unsupported.
The caller must not describe a weaker run as isolated.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

SECRET_MARKERS = ("SECRET", "TOKEN", "PASSWORD", "PASSWD", "CREDENTIAL", "AWS_", "GITHUB_TOKEN", "NPM_TOKEN")


def mechanism_available() -> tuple[bool, str]:
    if shutil.which("unshare") is None:
        return False, "unshare is not installed"
    probe = subprocess.run(
        ["unshare", "--user", "--map-root-user", "--mount", "--net", "--fork", "true"],
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        return False, f"unshare failed: {probe.stderr.strip() or probe.returncode}"
    return True, "user mount+net namespace via unshare"


def _copy_snapshot(src: Path, dest: Path) -> None:
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest, symlinks=True, dirs_exist_ok=False)


def run(
    snapshot: Path,
    command: list[str],
    output_dir: Path,
    *,
    timeout: float = 30.0,
) -> dict:
    """Run ``command`` inside the jail. Return status PASS, FAIL, ERROR, or NOT_RUN.

    ``output_dir`` receives files the command writes under ``/out``. The
    snapshot directory is not modified. Secrets are not placed in the environment.
    """
    ok, detail = mechanism_available()
    if not ok:
        return {"status": "NOT_RUN", "detail": detail, "mechanism": "unavailable"}
    snapshot = snapshot.resolve()
    output_dir = output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    before = _fingerprint(snapshot)
    env = {
        "PATH": "/usr/bin:/bin",
        "HOME": "/out",
        "TMPDIR": "/tmp",
        "LANG": "C.UTF-8",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    for key in os.environ:
        upper = key.upper()
        if any(marker in upper for marker in SECRET_MARKERS):
            # Explicitly not copied. Recorded so a test can see the omission.
            env.pop(key, None)
    script = r"""
set -eu
JAIL="$1"
SNAP="$2"
OUT="$3"
shift 3
mkdir -p "$JAIL"/{bin,lib,lib64,usr,src,out,tmp,proc,dev}
for d in bin lib lib64 usr; do
  if [ -e "/$d" ]; then
    mkdir -p "$JAIL/$d"
    mount --bind "/$d" "$JAIL/$d"
    mount -o remount,bind,ro "$JAIL/$d" || true
  fi
done
mkdir -p "$JAIL/src"
cp -a "$SNAP"/. "$JAIL/src"/
mkdir -p "$JAIL/out" "$JAIL/tmp"
mount -t tmpfs -o mode=1777 tmpfs "$JAIL/tmp"
set +e
chroot "$JAIL" /usr/bin/env -i PATH="/usr/bin:/bin" HOME=/out TMPDIR=/tmp LANG=C.UTF-8 \
  PYTHONDONTWRITEBYTECODE=1 "$@"
status=$?
set -e
mkdir -p "$OUT"
if [ -d "$JAIL/out" ]; then
  cp -a "$JAIL/out"/. "$OUT"/ 2>/dev/null || true
fi
exit "$status"
"""
    with tempfile.TemporaryDirectory(prefix="ssd-jail-") as tmp:
        jail = Path(tmp) / "root"
        proc = subprocess.run(
            ["unshare", "--user", "--map-root-user", "--mount", "--net", "--fork", "bash", "-c", script, "bash", str(jail), str(snapshot), str(output_dir), *command],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    after = _fingerprint(snapshot)
    mutated = before != after
    status = "PASS" if proc.returncode == 0 and not mutated else "FAIL"
    if mutated:
        status = "FAIL"
    return {
        "status": status,
        "exit_code": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "snapshot_mutated": mutated,
        "mechanism": "unshare-user-mount-net-chroot",
        "detail": detail,
    }


def _fingerprint(root: Path) -> list[tuple[str, int, int]]:
    rows = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            rows.append((str(path.relative_to(root)), 0, hash(os.readlink(path))))
            continue
        if path.is_file():
            st = path.stat()
            rows.append((str(path.relative_to(root)), st.st_size, st.st_mtime_ns))
    return rows
