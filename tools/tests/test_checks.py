from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class ChecksCLITests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        (self.root / "tools").mkdir()
        shutil.copy(SOURCE / "checks.py", self.root / "tools/checks.py")
        shutil.copy(SOURCE / "workflow_support.py", self.root / "tools/workflow_support.py")
        (self.root / "apple/CauldronKit").mkdir(parents=True)
        (self.root / "apple/Cauldron.xcodeproj").mkdir()
        (self.root / "tools/tests").mkdir(parents=True)
        self.bin = self.root / "fake-bin"
        self.bin.mkdir()
        self.install("swift", "echo 'Executed 2 tests'\nexit \"${SWIFT_EXIT:-0}\"\n")
        self.install("make", "exit 0\n")
        self.install("xcodebuild", "if [ \"${STALE:-0}\" = 1 ]; then echo changed >> ../tracked.txt; fi\nwhile [ $# -gt 0 ]; do if [ \"$1\" = -resultBundlePath ]; then shift; mkdir -p \"$1\"; fi; shift; done\nif [ \"${XCODE_EXIT:-0}\" != 0 ]; then echo 'error: compile failed'; exit \"$XCODE_EXIT\"; fi\n")
        self.install(
            "xcrun",
            "if [ -n \"${SUMMARY:-}\" ]; then printf '%s\\n' \"$SUMMARY\"; else cat tools/tests/fixtures/checks/summary.json; fi\n",
        )
        self.install(
            "python3",
            "printf 'Ran 1 test\\n'\nexit \"${TOOLING_EXIT:-0}\"\n",
        )
        (self.root / "tools/tests/fixtures/checks").mkdir(parents=True)
        (self.root / "tools/tests/fixtures/checks/summary.json").write_text(
            '{"totalTestCount":2,"passedTests":2,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Passed"}\n'
        )
        self.git("init", "-q")
        self.git("config", "user.email", "checks@example.test")
        self.git("config", "user.name", "Checks Test")
        (self.root / "tracked.txt").write_text("stable\n")
        self.git("add", ".")
        self.git("add", "-f", "fake-bin")
        self.git("commit", "-qm", "fixture")
        self.assertEqual(subprocess.check_output(["git", "status", "--porcelain"], cwd=self.root, text=True), "")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def invoke(self, *args: str, **env: str) -> subprocess.CompletedProcess:
        environment = os.environ | {"PATH": str(self.bin) + os.pathsep + os.environ["PATH"]} | env
        return subprocess.run(
            [sys.executable, "-B", "tools/checks.py", *args], cwd=self.root, env=environment,
            capture_output=True, text=True, check=False,
        )

    def records(self) -> list[dict]:
        records = [json.loads(path.read_text()) for path in (self.root / ".git/cauldron/runs").glob("*/result.json")]
        return sorted(records, key=lambda record: record["startedAt"])

    def test_focused_uses_exact_selector_and_xcresult_failure_counts(self) -> None:
        summary = '{"totalTestCount":2,"passedTests":1,"failedTests":1,"skippedTests":0,"expectedFailures":0,"result":"Failed"}'
        result = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/ImportTests/testImports()", SUMMARY=summary)
        self.assertEqual(result.returncode, 1)
        self.assertIn("assertion-failed", result.stderr)
        log = Path(self.records()[0]["log"]).read_text()
        self.assertIn("-only-testing:CauldronTests/ImportTests/testImports()", log)

    def test_build_and_zero_test_failures_are_not_passes(self) -> None:
        failed = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/Suite", XCODE_EXIT="1")
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "build-failed")
        zero = self.invoke(
            "focused", "--platform", "macos", "--test", "CauldronTests/Suite",
            SUMMARY='{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Passed"}',
        )
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "zero-tests")

    def test_selector_validation_and_package_bootstrap_failure(self) -> None:
        bad = self.invoke("focused", "--platform", "macos", "--test", "testImports")
        self.assertEqual(bad.returncode, 2)
        package = self.invoke("package", SWIFT_EXIT="1")
        self.assertEqual(package.returncode, 1)

    def test_stale_revision_and_ios_lock_conflict_fail_closed(self) -> None:
        stale = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/Suite", STALE="1")
        self.assertEqual(stale.returncode, 1, stale.stdout + stale.stderr)
        self.assertIn("changed during", stale.stderr)
        lock = self.root / ".git/cauldron/ios-runner.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        lock.write_text("other runner\n")
        conflict = self.invoke("focused", "--platform", "ios", "--test", "CauldronTests/Suite")
        self.assertEqual(conflict.returncode, 1)
        self.assertIn("holds the shared lock", conflict.stderr)

    def test_ready_records_complete_counts_and_tooling_evidence(self) -> None:
        result = self.invoke("ready")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        record = self.records()[0]
        self.assertEqual(record["status"], "passed")
        self.assertEqual(record["scope"], "full")
        self.assertEqual(record["counts"], {"ios": 2, "lint": True, "macos": 2, "package": 2, "tooling": True})
        self.assertTrue(record["reproducible"])


if __name__ == "__main__":
    unittest.main()
