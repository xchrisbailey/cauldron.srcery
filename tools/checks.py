#!/usr/bin/env python3
"""Run native project checks and record reproducible local evidence."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True

import workflow_support as support


SELECTOR = re.compile(
    r"CauldronTests/[A-Za-z_][A-Za-z0-9_.]*(?:/[A-Za-z_][A-Za-z0-9_.]*(?:\([A-Za-z0-9_:,.-]*\))?)?\Z"
)
ASSERTION_MARKERS = ("XCTAssert", "Expectation failed", "#expect failed")
BUILD_MARKERS = ("SwiftCompile", "CompileSwift", "BUILD FAILED")


class CheckFailure(Exception):
    def __init__(self, status: str, message: str, **details):
        super().__init__(message)
        self.status = status
        self.details = details


def validate_selector(value: str) -> str:
    if not SELECTOR.fullmatch(value):
        raise support.WorkflowError(f"Malformed test selector: {value!r}")
    return value


def run_command(argv: list[str], *, cwd: Path, log: Path) -> tuple[int, str]:
    with log.open("a") as stream:
        stream.write("$ " + " ".join(argv) + "\n")
        stream.flush()
        try:
            process = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        except OSError as error:
            raise CheckFailure("runner-failed", f"could not launch {argv[0]}: {error}") from error
        output, _ = process.communicate()
        stream.write(output)
    return process.returncode, output


def classify_failure(output: str, returncode: int) -> CheckFailure:
    if any(marker.lower() in output.lower() for marker in BUILD_MARKERS) or re.search(
        r"error: (?:emit-module|compile|no such module|cannot find|failed to build)", output, re.IGNORECASE
    ):
        return CheckFailure("build-failed", f"build failed (exit {returncode})")
    if any(marker.lower() in output.lower() for marker in ASSERTION_MARKERS) or re.search(
        r"test(?: case)? .* failed|^FAIL:|^ERROR:|^FAILED ", output, re.IGNORECASE | re.MULTILINE
    ):
        return CheckFailure("assertion-failed", f"test assertions failed (exit {returncode})")
    return CheckFailure("runner-failed", f"test runner failed (exit {returncode})")


def xcode_summary(bundle: Path) -> dict:
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle), "--compact"],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as error:
        raise CheckFailure("runner-failed", f"could not launch xcresulttool: {error}") from error
    if result.returncode:
        raise CheckFailure("runner-failed", "xcresult summary could not be read")
    try:
        value = json.loads(result.stdout)
        counts = {key: int(value[key]) for key in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")}
        counts["result"] = value["result"]
        if not isinstance(counts["result"], str):
            raise TypeError("result is not a string")
    except (ValueError, KeyError, TypeError) as error:
        raise CheckFailure("runner-failed", f"invalid xcresult summary: {error}") from error
    return counts


def xcode_run(root: Path, platform: str, selectors: list[str], log: Path, artifact_dir: Path) -> int:
    bundle = artifact_dir / f"{platform}-{uuid.uuid4().hex}.xcresult"
    destination = "platform=macOS" if platform == "macos" else os.environ.get(
        "IOS_SIMULATOR", "platform=iOS Simulator,name=iPhone 17,OS=27.0"
    )
    command = ["xcodebuild", "-project", "Cauldron.xcodeproj", "-scheme", "Cauldron", "-skipPackagePluginValidation", "-destination", destination]
    for selector in selectors:
        command.extend(["-only-testing:" + selector])
    command.extend(["-resultBundlePath", str(bundle), "test"])
    code, output = run_command(command, cwd=root / "apple", log=log)
    if code:
        raise classify_failure(output, code)
    if not bundle.exists():
        raise CheckFailure("runner-failed", "xcodebuild succeeded without creating a result bundle")
    counts = xcode_summary(bundle)
    executed = counts["totalTestCount"]
    if executed <= 0:
        raise CheckFailure("zero-tests", "Xcode reported zero executed tests")
    if counts["failedTests"] > 0 or counts["result"].lower() not in {"passed", "success", "succeeded"}:
        raise CheckFailure(
            "assertion-failed", f"{counts['failedTests']} test(s) failed", testCount=executed, xcresult=counts
        )
    return executed


def package_run(root: Path, filter_value: str | None, log: Path) -> int:
    command = ["swift", "test", "--package-path", "CauldronKit"]
    if filter_value is not None:
        command.extend(["--filter", filter_value])
    code, output = run_command(command, cwd=root / "apple", log=log)
    if code:
        raise classify_failure(output, code)
    matches = re.findall(r"Executed (\d+) tests?", output)
    count = int(matches[-1]) if matches else 0
    if count <= 0:
        raise CheckFailure("zero-tests", "Swift reported zero executed tests")
    return count


def tooling_run(root: Path, log: Path) -> int:
    code, output = run_command(
        ["python3", "-B", "-m", "unittest", "discover", "-s", "tools/tests"], cwd=root, log=log
    )
    if code:
        raise classify_failure(output, code)
    matches = re.findall(r"Ran (\d+) tests?", output)
    count = int(matches[-1]) if matches else 0
    if count <= 0:
        raise CheckFailure("zero-tests", "Python unittest reported zero executed tests")
    return count


def execute_ready(root: Path, log: Path, artifact_dir: Path) -> dict:
    counts: dict[str, int | bool] = {}
    try:
        code, output = run_command(["make", "lint"], cwd=root / "apple", log=log)
        if code:
            raise classify_failure(output, code)
        counts["lint"] = True
        counts["package"] = package_run(root, None, log)
        for platform in ("macos", "ios"):
            try:
                counts[platform] = xcode_run(root, platform, [], log, artifact_dir)
            except CheckFailure as error:
                if error.details.get("testCount"):
                    counts[platform] = error.details["testCount"]
                raise
        counts["toolingTestCount"] = tooling_run(root, log)
        counts["tooling"] = True
    except CheckFailure as error:
        raise CheckFailure(error.status, str(error), counts=counts, **error.details) from error
    return counts


def with_ios_lock(state: Path):
    lock = state / "ios-runner.lock"
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.write(descriptor, f"{os.getpid()}\n".encode())
    return lock, descriptor


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    focused = commands.add_parser("focused")
    focused.add_argument("--platform", required=True, choices=("macos", "ios"))
    focused.add_argument("--test", required=True, action="append")
    package = commands.add_parser("package")
    package.add_argument("--filter")
    commands.add_parser("tooling")
    commands.add_parser("ready")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    root = support.repository()
    scope = "full" if args.command == "ready" else "focused"
    platform = (
        "all" if args.command == "ready" else
        args.platform if args.command == "focused" else
        "tooling" if args.command == "tooling" else "package"
    )
    try:
        selectors = [validate_selector(value) for value in args.test] if args.command == "focused" else []
    except support.WorkflowError as error:
        parser().error(str(error))
    command = ["checks.py", *(argv if argv is not None else sys.argv[1:])]
    path, record = support.new_run("checks", command, platform, scope)
    log = Path(record["log"])
    artifacts = path.parent
    lock = None
    fd = None
    try:
        if args.command == "ready":
            try:
                lock, fd = with_ios_lock(support.state_directory(root))
            except FileExistsError as error:
                raise CheckFailure("runner-failed", "another iOS test runner holds the shared lock") from error
            counts = execute_ready(root, log, artifacts)
            test_count = None
        elif args.command == "package":
            test_count = package_run(root, args.filter, log)
            counts = {"package": test_count}
        elif args.command == "tooling":
            test_count = tooling_run(root, log)
            counts = {}
        else:
            if args.platform == "ios":
                try:
                    lock, fd = with_ios_lock(support.state_directory(root))
                except FileExistsError as error:
                    raise CheckFailure("runner-failed", "another iOS test runner holds the shared lock") from error
            test_count = xcode_run(root, args.platform, selectors, log, artifacts)
            counts = {}
        after = support.snapshot(root)
        if after != record["before"]:
            raise CheckFailure("runner-failed", "checkout revision or working tree changed during checks")
        if args.command == "ready" and record["before"]["dirty"]:
            raise CheckFailure("runner-failed", f"full checks require a clean starting revision: {record['before']}")
        status = "passed"
        details = {"counts": counts}
        if test_count is not None:
            details["testCount"] = test_count
    except CheckFailure as error:
        status = error.status
        details = {"error": str(error), **error.details}
        print(f"checks: {error.status}: {error}", file=sys.stderr)
    except KeyboardInterrupt:
        status = "interrupted"
        details = {"error": "interrupted"}
        print("checks: interrupted", file=sys.stderr)
    except support.WorkflowError as error:
        status = "runner-failed"
        details = {"error": str(error)}
        print(f"checks: runner-failed: {error}", file=sys.stderr)
    finally:
        if fd is not None:
            os.close(fd)
        if lock is not None:
            lock.unlink(missing_ok=True)
    details["artifacts"] = [str(item) for item in sorted(artifacts.glob("*.xcresult"))]
    final = support.finish_run(path, record, status, **details)
    summary = f"checks: {final['status']} ({final['scope']}/{final['platform']})"
    if final.get("testCount") is not None:
        summary += f", {final['testCount']} tests"
    if final.get("counts"):
        summary += ", " + ", ".join(f"{key}={value}" for key, value in final["counts"].items())
    summary += f"\nrecord: {path}\nlog: {log}"
    print(summary)
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
