"""Git guardrails: inspect staged content; validate exact revisions before pushes."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import platform
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
from xml.parsers.expat import ExpatError

from workflow_support import (
    WorkflowError, git, read_json, repository, run_records, snapshot,
    state_directory, full_checks_for,
)

TOOLS = Path(__file__).resolve().parent
STORE_PATTERN = re.compile(
    r"ModelContainer(?:\.init)?\(|ModelContainer *= *(?:try +)?\.init|ModelConfiguration|\.modelContainer\("
)
BUTTON_TARGETS = {"Cauldron", "CauldronImports", "CauldronShare", "CauldronWidgets", "ShareSheet"}
COPY_ROOTS = ("apple/Cauldron/", "apple/CauldronImports/", "apple/CauldronShare/",
              "apple/CauldronWidgets/", "apple/ShareSheet/", "apple/Shared/")


def child_environment() -> dict[str, str]:
    # Git exports repository-local variables to hooks. Tooling tests create foreign repositories;
    # inherited GIT_DIR/INDEX_FILE must not redirect their commands into the developer's checkout.
    return {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


def native_policy(path: str, text: str, policy: str = "all") -> list[str]:
    parts = Path(path).parts
    if len(parts) < 3 or parts[0] != "apple" or not path.endswith(".swift"):
        return []
    errors = []
    for number, line in enumerate(text.splitlines(), 1):
        if (
            policy in {"all", "store"}
            and parts[1] != "CauldronKit"
            and path != "apple/Cauldron/Data/CauldronStore.swift"
            and STORE_PATTERN.search(line.replace(".modelContainer(container)", ""))
        ):
            errors.append(f"{path}:{number}: open stores through CauldronStore.container(_:) only")
        if policy in {"all", "buttons"} and parts[1] in BUTTON_TARGETS and "borderedProminent" in line:
            errors.append(f"{path}:{number}: use .buttonStyle(.brandProminent)")
    return errors


def lint_native(policy: str) -> None:
    root = repository()
    errors = []
    for path in (root / "apple").rglob("*.swift"):
        if any(part in {".build", ".swiftpm", "DerivedData"} for part in path.parts):
            continue
        errors.extend(native_policy(str(path.relative_to(root)), path.read_text(), policy))
    if errors:
        raise WorkflowError("\n".join(errors))
    if policy in {"all", "copy"}:
        sources = []
        for directory in COPY_ROOTS:
            folder = root / directory
            if folder.exists():
                sources.extend((str(path.relative_to(root)), path.read_bytes()) for path in folder.rglob("*.swift"))
        copy_lint(sources)


def file_identity(path: Path) -> dict[str, str | int]:
    resolved = path.resolve(strict=True)
    stat = resolved.stat()
    digest = hashlib.sha256()
    with resolved.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "path": str(resolved),
        "size": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "sha256": digest.hexdigest(),
    }


def toolchain_identity() -> dict[str, object]:
    compiler_result = subprocess.run(["xcrun", "--find", "swiftc"], text=True, capture_output=True)
    if compiler_result.returncode:
        raise WorkflowError("Swift-aware copy lint requires Xcode's host Swift toolchain (xcrun --find swiftc failed).")
    compiler = Path(compiler_result.stdout.strip())
    compiler_realpath = compiler.resolve(strict=True)
    host = compiler.parent.parent / "lib/swift/host"
    sdk_path = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()).resolve(strict=True)
    architecture = "arm64" if platform.machine() == "arm64" else "x86_64"
    host_inputs = [
        host / "SwiftSyntax.swiftmodule" / f"{architecture}-apple-macos.swiftinterface",
        host / "SwiftParser.swiftmodule" / f"{architecture}-apple-macos.swiftinterface",
        host / "libSwiftSyntax.dylib",
        host / "libSwiftParser.dylib",
        host / "libSwiftDiagnostics.dylib",
    ]
    return {
        "swiftc": {
            **file_identity(compiler_realpath),
            "invoked_path": str(compiler),
        },
        "swiftc_version": subprocess.check_output([str(compiler), "--version"], text=True).splitlines()[0],
        "sdk_path": str(sdk_path),
        "sdk_version": subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-version"], text=True).strip(),
        "sdk_build": subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-build-version"], text=True).strip(),
        "architecture": architecture,
        "host_path": str(host.resolve(strict=True)),
        "host_inputs": [file_identity(path) for path in host_inputs],
    }


def copy_lint(
    sources: list[tuple[str, bytes]], helper_bytes: bytes | None = None,
    identity: dict[str, object] | None = None,
) -> None:
    root = repository()
    if helper_bytes is None:
        helper_bytes = (TOOLS / "copy_lint.swift").read_bytes()
    identity = identity or toolchain_identity()
    identity_bytes = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    digest = hashlib.sha256(identity_bytes + b"\0" + helper_bytes).hexdigest()
    cache = state_directory(root) / "copy-lint" / digest
    executable = cache / "copy-lint"
    if not executable.is_file():
        cache.mkdir(parents=True, exist_ok=True)
        source = cache / "copy_lint.swift"
        source.write_bytes(helper_bytes)
        compiler = Path(identity["swiftc"]["invoked_path"])
        host = Path(str(identity["host_path"]))
        sdk = str(identity["sdk_path"])
        target = str(identity["architecture"])
        command = [str(compiler), "-sdk", sdk, "-target", f"{target}-apple-macosx15.0", "-I", str(host), "-L", str(host), "-lSwiftSyntax", "-lSwiftParser", str(source), "-o", str(executable)]
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode:
            raise WorkflowError("Could not compile SwiftSyntax copy checker with the installed host toolchain; copy lint fails closed.\n" + result.stderr)
    with tempfile.TemporaryDirectory(prefix="cauldron-copy-lint-") as directory:
        args = [str(executable)]
        for path, content in sources:
            staged = Path(directory) / path
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(content)
            args.append(str(staged))
        result = subprocess.run(args, text=True, capture_output=True, env={**os.environ, "DYLD_LIBRARY_PATH": str(identity["host_path"])})
    if result.returncode:
        raise WorkflowError(result.stdout + result.stderr or "Swift-aware copy lint failed")


def pre_commit() -> None:
    root = repository()
    paths = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"], cwd=root
    ).decode().split("\0")
    errors = []
    swift = []
    staged_sources = []
    helper_bytes = None
    with tempfile.TemporaryDirectory(prefix="cauldron-staged-") as directory:
        temporary = Path(directory)
        for path in filter(None, paths):
            if not path.endswith((".swift", ".json", ".py", ".plist", ".entitlements")):
                continue
            content = subprocess.check_output(["git", "show", f":{path}"], cwd=root)
            try:
                if path.endswith((".plist", ".entitlements")):
                    plistlib.loads(content)
                    continue
                text = content.decode()
                if path.endswith(".json"):
                    json.loads(text)
                elif path.endswith(".py"):
                    ast.parse(text, filename=path)
                elif path.startswith("apple/"):
                    errors.extend(native_policy(path, text))
                    if path.endswith(".swift") and path.startswith(COPY_ROOTS):
                        staged_sources.append((path, content))
                    destination = temporary / path
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_text(text)
                    swift.append(str(destination))
            except (ValueError, SyntaxError, ExpatError, plistlib.InvalidFileException) as error:
                errors.append(f"{path}: {error}")
        if swift:
            configuration = subprocess.check_output(["git", "show", ":apple/.swift-format"], cwd=root)
            config_path = temporary / ".swift-format"
            config_path.write_bytes(configuration)
            result = subprocess.run(
                ["swift", "format", "lint", "--strict", "--configuration", str(config_path), *swift],
                cwd=root, text=True, capture_output=True,
            )
            if result.returncode:
                errors.append(result.stdout + result.stderr)
        if staged_sources:
            try:
                helper_bytes = subprocess.check_output(["git", "show", ":tools/copy_lint.swift"], cwd=root)
                copy_lint(staged_sources, helper_bytes)
            except (WorkflowError, subprocess.CalledProcessError) as error:
                errors.append(str(error))
    if errors:
        raise WorkflowError("Staged checks failed; nothing was rewritten:\n" + "\n".join(errors))
    print("Staged checks passed (Swift policies/format, JSON, property lists, Python syntax).")


def full_checks_exist(head: str) -> bool:
    tree = git("rev-parse", f"{head}^{{tree}}")
    return any(
        full_checks_for(record, head, tree)
        for _, record in run_records()
    )


def changed_paths(local: str, remote: str) -> list[str]:
    if set(remote) != {"0"}:
        return git("diff", "--name-only", remote, local).splitlines()
    # A new destination ref has no advertised comparison commit. origin/main might belong to
    # another remote, so conservatively inspect the introduced history rather than trusting it.
    return git("log", "--format=", "--name-only", local).splitlines()


def pre_push(lines: list[str]) -> None:
    root = repository()
    updates = []
    for line in lines:
        fields = line.split()
        if len(fields) != 4:
            raise WorkflowError("Malformed Git pre-push ref update")
        _, local_object, remote_ref, remote_object = fields
        if set(local_object) == {"0"}:
            continue
        commit = git("rev-parse", f"{local_object}^{{commit}}")
        updates.append((remote_ref, commit, changed_paths(commit, remote_object)))
    if not updates:
        return
    current = snapshot(root)
    needs_native = False
    needs_tooling = False
    for ref, commit, paths in updates:
        native = any(path.startswith("apple/") for path in paths)
        tooling = any(path.startswith(("tools/", ".githooks/")) for path in paths)
        release = ref.startswith("refs/tags/v")
        if native or tooling or release:
            if commit != current["head"] or current["dirty"]:
                raise WorkflowError("Validate/push one clean checked-out revision at a time; user files were not changed.")
        if release:
            label = ref.removeprefix("refs/tags/")
            if not re.fullmatch(r"v\d+\.\d+\.\d+", label):
                raise WorkflowError(f"Unsupported release tag: {label}")
            record = read_json(state_directory(root) / "releases" / f"{label}.json")
            if not (
                record.get("version") == 1 and record.get("status") == "passed"
                and record.get("head") == commit and record.get("tree") == current["tree"]
                and record.get("label") == label and record.get("artifacts")
                and full_checks_exist(commit)
            ):
                raise WorkflowError(f"Missing or stale release preflight for {label}; run tools/release.py preflight first.")
        needs_native |= native
        needs_tooling |= tooling
    if needs_native and not full_checks_exist(current["head"]):
        subprocess.run([sys.executable, "-B", str(TOOLS / "checks.py"), "ready"], cwd=root,
                       env=child_environment(), check=True)
        if not full_checks_exist(current["head"]):
            raise WorkflowError("Check runner did not produce current-head full validation evidence")
    elif needs_tooling:
        subprocess.run(
            [sys.executable, "-B", "-m", "unittest", "discover", "-s", "tools/tests"],
            cwd=root, env=child_environment(), check=True,
        )
    if snapshot(root) != current:
        raise WorkflowError("Checkout changed during pre-push validation; validate the new revision")
    print("Pre-push validation passed; this hook did not push anything.")


def install() -> None:
    root = repository()
    desired = TOOLS.parent / ".githooks"
    existing = subprocess.run(
        ["git", "config", "--get", "core.hooksPath"], cwd=root,
        text=True, capture_output=True,
    ).stdout.strip()
    if existing:
        path = Path(existing).expanduser()
        if not path.is_absolute():
            path = root / path
        if path.resolve() != desired.resolve():
            raise WorkflowError(f"Existing hooks preserved: {existing}. Integrate them explicitly before installing.")
    else:
        default = Path(git("rev-parse", "--git-path", "hooks", cwd=root))
        if not default.is_absolute():
            default = root / default
        custom = sorted(path.name for path in default.glob("*")
                        if path.is_file() and not path.name.endswith(".sample") and os.access(path, os.X_OK))
        if custom:
            raise WorkflowError(f"Existing default hooks preserved: {', '.join(custom)}. Integrate them explicitly before installing.")
    for name in ("pre-commit", "pre-push"):
        if not os.access(desired / name, os.X_OK):
            raise WorkflowError(f"Missing executable hook: {desired / name}")
    git("config", "--local", "core.hooksPath", str(desired.resolve()), cwd=root)
    print(f"Installed repository-local hooks from {desired}; custom hook files were not overwritten.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("install")
    sub.add_parser("pre-commit")
    sub.add_parser("pre-push")
    lint = sub.add_parser("lint-native")
    lint.add_argument("--policy", choices=("all", "store", "buttons", "copy"), default="all")
    args = parser.parse_args()
    try:
        if args.command == "install":
            install()
        elif args.command == "pre-commit":
            pre_commit()
        elif args.command == "pre-push":
            pre_push(sys.stdin.read().splitlines())
        else:
            lint_native(args.policy)
        return 0
    except (WorkflowError, OSError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
