#!/usr/bin/env python3
"""Run native project checks and record reproducible local evidence."""

from __future__ import annotations

import argparse
import base64
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import uuid

sys.dont_write_bytecode = True

import workflow_support as support


SELECTOR = re.compile(
    r"Cauldron(?:UI)?Tests/[A-Za-z_][A-Za-z0-9_.]*(?:/[A-Za-z_][A-Za-z0-9_.]*(?:\([A-Za-z0-9_:,.-]*\))?)?\Z"
)
ASSERTION_MARKERS = ("XCTAssert", "Expectation failed", "#expect failed")


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
            process = subprocess.Popen(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)
        except OSError as error:
            raise CheckFailure("runner-failed", f"could not launch {argv[0]}: {error}") from error
        try:
            output_lines = []
            if process.stdout is not None:
                for line in process.stdout:
                    stream.write(line)
                    stream.flush()
                    output_lines.append(line)
            return process.wait(), "".join(output_lines)
        except BaseException:
            # Reap this invocation's child before the caller releases its simulator lock.
            # Its isolated process group keeps cancellation away from unrelated developer jobs.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            raise
        finally:
            if process.stdout is not None:
                process.stdout.close()


def classify_failure(output: str, returncode: int) -> CheckFailure:
    if re.search(
        r"\bBUILD FAILED\b|error: (?:emit-module|compile|no such module|cannot find|failed to build|could not build|unable to build)",
        output,
        re.IGNORECASE,
    ):
        return CheckFailure("build-failed", f"build failed (exit {returncode})")
    if any(marker.lower() in output.lower() for marker in ASSERTION_MARKERS) or re.search(
        r"test(?: case)? .* failed|test run with .* failed|^FAIL:|^ERROR:|^FAILED ",
        output,
        re.IGNORECASE | re.MULTILINE,
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
        keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
        counts = {key: value[key] for key in keys}
        if any(type(value) is not int or value < 0 for value in counts.values()):
            raise ValueError("test counts must be nonnegative integers")
        if counts["skippedTests"] > counts["totalTestCount"]:
            raise ValueError("skippedTests exceeds totalTestCount")
        counts["result"] = value["result"]
        if not isinstance(counts["result"], str):
            raise TypeError("result is not a string")
    except (ValueError, KeyError, TypeError) as error:
        raise CheckFailure("runner-failed", f"invalid xcresult summary: {error}") from error
    return counts


def xcode_ui_test_count(bundle: Path) -> int:
    try:
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--compact"],
            text=True, capture_output=True, check=False,
        )
    except OSError as error:
        raise CheckFailure("runner-failed", f"could not launch xcresulttool test tree: {error}") from error
    if result.returncode:
        raise CheckFailure("runner-failed", "xcresult test tree could not be read")
    try:
        root = json.loads(result.stdout)
        nodes = root["testNodes"]
        if not isinstance(nodes, list):
            raise TypeError("testNodes is not an array")
    except (ValueError, KeyError, TypeError) as error:
        raise CheckFailure("runner-failed", f"invalid xcresult test tree: {error}") from error

    bundles = []
    def visit(node: object) -> int:
        if not isinstance(node, dict):
            raise TypeError("test result node is not an object")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise TypeError("test result children is not an array")
        if node.get("nodeType") == "Test Case":
            if node.get("result") == "Skipped":
                raise ValueError("UI test case was skipped")
            if node.get("result") != "Passed":
                raise ValueError(f"UI test case result is {node.get('result')!r}")
            return 1
        return sum(visit(child) for child in children)

    try:
        def find(node: object) -> None:
            if not isinstance(node, dict):
                raise TypeError("test result node is not an object")
            if node.get("nodeType") == "UI test bundle" and node.get("name") == "CauldronUITests":
                bundles.append(node)
            for child in node.get("children", []):
                find(child)
        for node in nodes:
            find(node)
        if len(bundles) != 1:
            raise ValueError(f"expected one CauldronUITests bundle, found {len(bundles)}")
        count = visit(bundles[0])
        if count <= 0:
            raise ValueError("CauldronUITests executed zero test cases")
    except (TypeError, ValueError) as error:
        raise CheckFailure("zero-tests", f"invalid UI test execution evidence: {error}") from error
    return count


def xcode_run(root: Path, platform: str, selectors: list[str], log: Path, artifact_dir: Path) -> tuple[int, int]:
    bundle = artifact_dir / f"{platform}-{uuid.uuid4().hex}.xcresult"
    destination = "platform=macOS" if platform == "macos" else os.environ.get(
        "IOS_SIMULATOR", "platform=iOS Simulator,name=iPhone 17,OS=27.0"
    )
    command = ["xcodebuild", "-project", "Cauldron.xcodeproj", "-scheme", "Cauldron", "-skipPackagePluginValidation", "-destination", destination]
    for selector in selectors:
        command.extend(["-only-testing:" + selector])
    command.extend(["-resultBundlePath", str(bundle), "test"])
    code, output = run_command(command, cwd=root / "apple", log=log)
    rendered = re.findall(
        r"UI evidence PNG BASE64:(week-(?:no-targets|targets)-(?:390|1100)-(?:light|dark)):([A-Za-z0-9+/=]+)",
        output,
    )
    if rendered:
        destination = artifact_dir / "ui-rendered"
        destination.mkdir(parents=True, exist_ok=True)
        for name, encoded in rendered:
            try:
                image = base64.b64decode(encoded, validate=True)
            except ValueError as error:
                raise CheckFailure("runner-failed", f"invalid rendered screenshot data: {name}") from error
            if not image.startswith(b"\x89PNG\r\n\x1a\n"):
                raise CheckFailure("runner-failed", f"rendered screenshot is not a PNG: {name}")
            (destination / f"{name}.png").write_bytes(image)
    counts = None
    if bundle.exists():
        try:
            counts = xcode_summary(bundle)
        except CheckFailure:
            if not code:
                raise
    if code:
        if counts is not None:
            executed = counts["totalTestCount"] - counts["skippedTests"]
            if counts["failedTests"] > 0:
                raise CheckFailure(
                    "assertion-failed", f"{counts['failedTests']} test(s) failed", testCount=executed, xcresult=counts
                )
            if executed <= 0:
                failure = classify_failure(output, code)
                failure.details.update(testCount=0, xcresult=counts)
                raise failure
            failure = classify_failure(output, code)
            failure.details.update(testCount=executed, xcresult=counts)
            raise failure
        raise classify_failure(output, code)
    if counts is None:
        raise CheckFailure("runner-failed", "xcodebuild succeeded without creating a result bundle")
    ui_count = 0
    requires_ui = not selectors or any(selector.startswith("CauldronUITests/") for selector in selectors)
    if requires_ui:
        try:
            ui_count = xcode_ui_test_count(bundle)
        except CheckFailure as failure:
            failure.details.update(testCount=counts["totalTestCount"] - counts["skippedTests"], xcresult=counts)
            raise
    executed = counts["totalTestCount"] - counts["skippedTests"]
    if executed <= 0:
        raise CheckFailure("zero-tests", "Xcode reported zero executed tests", testCount=0, xcresult=counts)
    if counts["failedTests"] > 0 or counts["result"].lower() not in {"passed", "success", "succeeded"}:
        raise CheckFailure(
            "assertion-failed", f"{counts['failedTests']} test(s) failed", testCount=executed, xcresult=counts
        )
    return executed, ui_count


def package_run(root: Path, filter_value: str | None, log: Path) -> int:
    command = ["swift", "test", "--package-path", "CauldronKit"]
    if filter_value is not None:
        command.extend(["--filter", filter_value])
    code, output = run_command(command, cwd=root / "apple", log=log)
    swift_testing = re.findall(
        r"(?:✔|✘)?\s*Test run with\s+(\d+)\s+tests?\s+in\s+\d+\s+suites?\s+(passed|failed)",
        output,
        re.IGNORECASE,
    )
    xctest = re.findall(r"Executed (\d+) tests?", output)
    count = int(swift_testing[-1][0]) if swift_testing else int(xctest[-1]) if xctest else 0
    swift_testing_failed = bool(swift_testing and swift_testing[-1][1].lower() == "failed")
    if code:
        failure = classify_failure(output, code)
        if count:
            failure.details.update(testCount=count)
        raise failure
    if swift_testing_failed:
        raise CheckFailure("assertion-failed", "Swift Testing reported failures", testCount=count)
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
        try:
            counts["package"] = package_run(root, None, log)
        except CheckFailure as error:
            if error.details.get("testCount"):
                counts["package"] = error.details["testCount"]
            raise
        for platform in ("macos", "ios"):
            try:
                counts[platform], counts[f"{platform}UITests"] = xcode_run(
                    root, platform, [], log, artifact_dir)
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
    descriptor = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(descriptor)
        raise
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
    lint_passed = tooling_passed = None
    def interrupt(_signum, _frame):
        raise KeyboardInterrupt
    previous_sigterm = signal.signal(signal.SIGTERM, interrupt)
    try:
        if args.command == "ready":
            if record["before"]["dirty"]:
                raise CheckFailure("runner-failed", "full checks require a clean starting revision")
            try:
                lock, fd = with_ios_lock(support.state_directory(root))
            except BlockingIOError as error:
                raise CheckFailure("runner-failed", "another iOS test runner holds the shared lock") from error
            counts = execute_ready(root, log, artifacts)
            lint_passed = counts.pop("lint")
            tooling_passed = counts.pop("tooling")
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
                except BlockingIOError as error:
                    raise CheckFailure("runner-failed", "another iOS test runner holds the shared lock") from error
            test_count, _ = xcode_run(root, args.platform, selectors, log, artifacts)
            counts = {}
        after = support.snapshot(root)
        if after != record["before"]:
            raise CheckFailure("runner-failed", "checkout revision or working tree changed during checks")
        status = "passed"
        details = {"counts": counts}
        if args.command == "ready":
            details.update(lint=lint_passed, tooling=tooling_passed)
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
        signal.signal(signal.SIGTERM, previous_sigterm)
    details["artifacts"] = [
        str(item) for item in sorted(artifacts.glob("*.xcresult"))
    ] + [str(item) for item in sorted(artifacts.glob("ui-rendered/*.png"))]
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
