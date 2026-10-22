"""Check worker completion contracts and integrate tested revisions without a model roundtrip."""

from __future__ import annotations

import argparse
from pathlib import Path
import os
import re
import subprocess
import sys

from workflow_support import (
    WorkflowError, git, read_json, repository, run_records, snapshot, successful_for,
)


def worker_check(result_path: Path, brief_path: Path) -> dict:
    result = read_json(result_path)
    brief = read_json(brief_path)
    if result.get("version") != 1 or brief.get("version") != 1:
        raise WorkflowError("Unsupported worker-result/brief version")
    if result.get("status") != "complete":
        raise WorkflowError("Partial or blocked work does not advance the task graph")
    if not result.get("ticket") or result.get("ticket") != brief.get("ticket"):
        raise WorkflowError("Worker result must identify the brief's ticket")
    for key in ("head", "base"):
        if not isinstance(result.get(key), str) or not re.fullmatch(r"[0-9a-f]{40,64}", result[key]):
            raise WorkflowError(f"Worker {key} must be a full commit SHA")
        if git("rev-parse", f"{result[key]}^{{commit}}") != result[key]:
            raise WorkflowError(f"Worker {key} is not the specified commit")
    subprocess.run(["git", "merge-base", "--is-ancestor", result["base"], result["head"]], check=True)
    expected = brief.get("criteria")
    if not isinstance(expected, list) or not expected or any(not isinstance(value, str) or not value for value in expected):
        raise WorkflowError("Brief must list nonempty acceptance-criterion IDs")
    if len(set(expected)) != len(expected):
        raise WorkflowError("Brief has duplicate acceptance-criterion IDs")
    criteria = result.get("criteria")
    if not isinstance(criteria, list) or any(not isinstance(item, dict) for item in criteria):
        raise WorkflowError("Worker criteria must be objects with status and evidence")
    actual = [item.get("id") for item in criteria]
    if len(actual) != len(expected) or set(actual) != set(expected):
        raise WorkflowError("Worker result must account for every expected criterion exactly once")
    for item in criteria:
        evidence = item.get("evidence")
        if item.get("status") != "met" or not isinstance(evidence, list) or not evidence or any(
            not isinstance(value, str) or not value.strip() for value in evidence
        ):
            raise WorkflowError(f"Criterion {item.get('id')} is open or lacks evidence")
    if result.get("remaining") != [] or not isinstance(result.get("manual"), list):
        raise WorkflowError("Complete results need no remaining work and an explicit manual-check list")
    checks = result.get("checks")
    if not isinstance(checks, list) or not checks:
        raise WorkflowError("Worker result needs real runner evidence")
    for path in checks:
        if not isinstance(path, str):
            raise WorkflowError("Check evidence must be a runner-record path")
        record = read_json(Path(path))
        count = record.get("testCount", 0)
        full = record.get("counts", {})
        positive = type(count) is int and count > 0
        full_positive = isinstance(full, dict) and all(
            type(full.get(platform)) is int and full[platform] > 0 for platform in ("package", "macos", "ios")
        )
        if record.get("kind") != "checks" or not successful_for(record, result["head"]) or not (positive or full_positive):
            raise WorkflowError(f"Check evidence is failed, stale, dirty, or zero-test: {path}")
    return result


def worktree_for(branch: str) -> Path:
    text = git("worktree", "list", "--porcelain")
    for block in text.split("\n\n"):
        fields = dict(line.split(" ", 1) for line in block.splitlines() if " " in line)
        if fields.get("branch") == f"refs/heads/{branch}":
            return Path(fields["worktree"])
    raise WorkflowError("Worker branch must have a checkout so its cleanliness can be checked")


def integrate(branch: str, result_path: Path, brief_path: Path) -> None:
    root = repository()
    target = git("branch", "--show-current")
    if not target or target in {"main", "master"} or target == branch:
        raise WorkflowError("Run integration from a separate named non-main integration branch")
    git("check-ref-format", "--branch", branch)
    result = worker_check(result_path, brief_path)
    source = worktree_for(branch)
    before = snapshot(root)
    worker = snapshot(source)
    if before["dirty"] or worker["dirty"]:
        raise WorkflowError("Dirty source/target preserved; commit or resolve changes explicitly first")
    if worker["head"] != result["head"] or git("rev-parse", f"refs/heads/{branch}") != result["head"]:
        raise WorkflowError("Worker branch moved after its reported checks")
    ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", before["head"], result["head"]])
    if ancestor.returncode:
        raise WorkflowError("Worker must merge the latest integration tip and rerun focused checks first")
    # Fast-forwarding retains the exact checked revision; no untested merge commit is invented.
    subprocess.run(["git", "merge", "--ff-only", result["head"]], cwd=root, check=True)
    print(f"Integrated {result['ticket']} at {result['head']}; no push or ticket closure performed.")


def status() -> None:
    root = repository()
    current = snapshot(root)
    print(f"Revision: {current['head']} ({'dirty' if current['dirty'] else 'clean'})")
    for path, record in run_records(root):
        if record.get("before", {}).get("worktree") != str(root):
            continue
        state = record.get("status", "unknown")
        if state == "running":
            try:
                os.kill(record["pid"], 0)
            except ProcessLookupError:
                state = "interrupted (process exited without a final record)"
            except (KeyError, TypeError, PermissionError):
                state = "running status unverified"
        revision = record.get("before", {}).get("head", "unknown")
        print(f"{record.get('scope', '?')} {record.get('platform', '?')}: {state} @ {revision}\n  {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status")
    worker = commands.add_parser("worker-check")
    merge = commands.add_parser("integrate")
    merge.add_argument("branch")
    for command in (worker, merge):
        command.add_argument("--result", required=True, type=Path)
        command.add_argument("--brief", required=True, type=Path)
    args = parser.parse_args()
    try:
        if args.command == "status":
            status()
        elif args.command == "worker-check":
            result = worker_check(args.result, args.brief)
            print(f"Complete worker result accepted for review: {result['ticket']} @ {result['head']}")
        else:
            integrate(args.branch, args.result, args.brief)
        return 0
    except (WorkflowError, OSError, ValueError, TypeError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
