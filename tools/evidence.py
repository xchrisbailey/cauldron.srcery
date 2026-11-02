#!/usr/bin/env python3
"""Upload screenshot evidence to the repository's `evidence` branch and print Markdown for a PR body.

`gh` cannot attach images to a PR, so screenshots go on an orphan branch, one folder per PR,
and the body links them by commit so the links never move.
"""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True

import workflow_support as support


BRANCH = "evidence"
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
MAX_BYTES = 10 * 1024 * 1024


class NotFound(support.WorkflowError):
    pass


def gh(*args: str, body: dict | None = None):
    command = ["gh", *args]
    if body is not None:
        command += ["--input", "-"]
    result = subprocess.run(
        command, input=None if body is None else json.dumps(body), text=True, capture_output=True, check=False,
    )
    if result.returncode:
        message = (result.stderr or result.stdout).strip() or f"gh {args[0]} failed"
        raise (NotFound if "HTTP 404" in message or "Not Found" in message else support.WorkflowError)(message)
    return json.loads(result.stdout) if result.stdout.strip() else None


def checked(files: list[Path]) -> list[Path]:
    names = set()
    for path in files:
        if path.suffix.lower() not in IMAGE_SUFFIXES:
            raise support.WorkflowError(f"{path}: not an image ({', '.join(sorted(IMAGE_SUFFIXES))})")
        if not path.is_file():
            raise support.WorkflowError(f"{path}: no such file")
        if path.stat().st_size > MAX_BYTES:
            raise support.WorkflowError(f"{path}: over {MAX_BYTES // (1024 * 1024)} MB")
        if path.name in names:
            raise support.WorkflowError(f"{path.name}: two files share this name")
        names.add(path.name)
    return files


def upload(pr: int, files: list[Path]) -> list[str]:
    files = checked(files)
    repo = gh("repo", "view", "--json", "nameWithOwner")["nameWithOwner"]
    api = f"repos/{repo}/git"
    try:
        parent = gh("api", f"{api}/ref/heads/{BRANCH}")["object"]["sha"]
        base_tree = gh("api", f"{api}/commits/{parent}")["tree"]["sha"]
    except NotFound:
        parent = base_tree = None
    entries = []
    for path in files:
        blob = gh("api", "-X", "POST", f"{api}/blobs",
                  body={"content": base64.b64encode(path.read_bytes()).decode(), "encoding": "base64"})
        entries.append({"path": f"pr-{pr}/{path.name}", "mode": "100644", "type": "blob", "sha": blob["sha"]})
    tree = gh("api", "-X", "POST", f"{api}/trees",
              body={"tree": entries, **({"base_tree": base_tree} if base_tree else {})})
    commit = gh("api", "-X", "POST", f"{api}/commits", body={
        "message": f"evidence: PR #{pr}", "tree": tree["sha"], "parents": [parent] if parent else [],
    })
    if parent:
        gh("api", "-X", "PATCH", f"{api}/refs/heads/{BRANCH}", body={"sha": commit["sha"]})
    else:
        gh("api", "-X", "POST", f"{api}/refs", body={"ref": f"refs/heads/{BRANCH}", "sha": commit["sha"]})
    return [
        f"![{path.stem}](https://github.com/{repo}/blob/{commit['sha']}/pr-{pr}/{path.name}?raw=true)"
        for path in files
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pr", required=True, type=int, help="the PR number the images belong to")
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args(argv)
    try:
        print("\n".join(upload(args.pr, args.files)))
        return 0
    except (support.WorkflowError, OSError, json.JSONDecodeError, KeyError) as error:
        print(f"evidence: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
