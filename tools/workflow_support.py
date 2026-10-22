"""Shared, dependency-free evidence storage for Cauldron's local developer tools."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import time
import uuid


class WorkflowError(Exception):
    """An actionable failure, suitable for a concise command-line diagnostic."""


def git(*args: str, cwd: Path | None = None) -> str:
    result = subprocess.run(
        ["git", *args], cwd=cwd, text=True, capture_output=True, check=False
    )
    if result.returncode:
        raise WorkflowError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def repository() -> Path:
    return Path(git("rev-parse", "--show-toplevel")).resolve()


def state_directory(root: Path | None = None) -> Path:
    root = root or repository()
    common = Path(git("rev-parse", "--git-common-dir", cwd=root))
    if not common.is_absolute():
        common = root / common
    state = common.resolve() / "cauldron"
    state.mkdir(parents=True, exist_ok=True)
    return state


def snapshot(root: Path | None = None) -> dict:
    root = root or repository()
    return {
        "head": git("rev-parse", "HEAD", cwd=root),
        "tree": git("rev-parse", "HEAD^{tree}", cwd=root),
        "dirty": bool(git("status", "--porcelain", "--untracked-files=normal", cwd=root)),
        "worktree": str(root.resolve()),
    }


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise WorkflowError(f"Cannot read JSON evidence {path}: {error}") from error
    if not isinstance(value, dict):
        raise WorkflowError(f"Expected a JSON object in {path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    temporary.replace(path)


def new_run(kind: str, command: list[str], platform: str, scope: str) -> tuple[Path, dict]:
    root = repository()
    identifier = uuid.uuid4().hex
    directory = state_directory(root) / "runs" / identifier
    directory.mkdir(parents=True)
    path = directory / "result.json"
    record = {
        "version": 1,
        "id": identifier,
        "kind": kind,
        "platform": platform,
        "scope": scope,
        "status": "running",
        "before": snapshot(root),
        "command": command,
        "pid": os.getpid(),
        "startedAt": time.time(),
        "log": str(directory / "output.log"),
    }
    write_json(path, record)
    return path, record


def finish_run(path: Path, record: dict, status: str, **details) -> dict:
    after = snapshot(Path(record["before"]["worktree"]))
    record.update(details)
    record.update(
        status=status,
        after=after,
        finishedAt=time.time(),
        reproducible=not record["before"]["dirty"] and record["before"] == after,
    )
    write_json(path, record)
    return record


def run_records(root: Path | None = None) -> list[tuple[Path, dict]]:
    records = []
    for path in (state_directory(root) / "runs").glob("*/result.json"):
        records.append((path, read_json(path)))
    return sorted(records, key=lambda item: item[1].get("startedAt", 0))


def successful_for(record: dict, head: str, *, scope: str | None = None) -> bool:
    before = record.get("before", {})
    after = record.get("after", {})
    return (
        record.get("version") == 1
        and record.get("status") == "passed"
        and record.get("reproducible") is True
        and before.get("head") == head
        and before == after
        and before.get("dirty") is False
        and (scope is None or record.get("scope") == scope)
    )
