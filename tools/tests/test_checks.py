from __future__ import annotations

import json
import os
from pathlib import Path
import fcntl
import signal
import select
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class ChecksCLITests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        (self.root / "tools").mkdir()
        shutil.copy(SOURCE / "checks.py", self.root / "tools/checks.py")
        shutil.copy(SOURCE / "hooks.py", self.root / "tools/hooks.py")
        shutil.copy(SOURCE / "workflow_support.py", self.root / "tools/workflow_support.py")
        (self.root / "apple/CauldronKit").mkdir(parents=True)
        (self.root / "apple/Cauldron.xcodeproj").mkdir()
        (self.root / "tools/tests").mkdir(parents=True)
        self.bin = self.root / "fake-bin"
        self.bin.mkdir()
        self.install("swift", "printf '%s\\n' \"${SWIFT_OUTPUT:-Executed 2 tests}\"\nexit \"${SWIFT_EXIT:-0}\"\n")
        self.install("make", "if [ -n \"${CALLS:-}\" ]; then echo make >> \"$CALLS\"; fi\nexit 0\n")
        self.install("xcodebuild", "echo 'SwiftCompile normal arm64 source.swift'\nif [ \"${STALE:-0}\" = 1 ]; then echo changed >> ../tracked.txt; fi\nwhile [ $# -gt 0 ]; do if [ \"$1\" = -resultBundlePath ]; then shift; mkdir -p \"$1\"; fi; shift; done\nif [ \"${XCODE_EXIT:-0}\" != 0 ]; then if [ \"${XCODE_ASSERTION:-0}\" = 1 ]; then echo \"Test Case 'Suite.testExample' failed\"; else echo 'error: emit-module command failed'; fi; exit \"$XCODE_EXIT\"; fi\n")
        self.install(
            "xcrun",
            "case \"$*\" in *'test-results tests'*) case \"$*\" in *macos-*) tree=\"${MAC_TREE:-}\" ;; *ios-*) tree=\"${IOS_TREE:-}\" ;; esac; if [ -n \"$tree\" ]; then printf '%s\\n' \"$tree\"; else cat tools/tests/fixtures/checks/target-tests.json; fi ;; *) if [ -n \"${SUMMARY:-}\" ]; then printf '%s\\n' \"$SUMMARY\"; else cat tools/tests/fixtures/checks/summary.json; fi ;; esac\n",
        )
        self.install(
            "python3",
            "if [ \"${TOOLING_BLOCK:-0}\" = 1 ]; then echo live-marker; read release < \"$TOOLING_GATE\"; fi\nprintf 'Ran %s tests\\n' \"${TOOLING_COUNT:-1}\"\nif [ \"${TOOLING_EXIT:-0}\" != 0 ]; then echo 'FAIL: sample'; fi\nexit \"${TOOLING_EXIT:-0}\"\n",
        )
        (self.root / "tools/tests/fixtures/checks").mkdir(parents=True)
        (self.root / "tools/tests/fixtures/checks/summary.json").write_text(
            '{"totalTestCount":2,"passedTests":2,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Passed"}\n'
        )
        (self.root / "tools/tests/fixtures/checks/target-tests.json").write_text(
            '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronTests","nodeType":"Unit test bundle","children":[{"name":"Suite","nodeType":"Test Suite","children":[{"name":"testApp()","nodeType":"Test Case","result":"Passed"}]}]},{"name":"CauldronUITests","nodeType":"UI test bundle","children":[{"name":"WeekTargetsUITests","nodeType":"Test Suite","children":[{"name":"testTargetsRoundtrip()","nodeType":"Test Case","result":"Passed"}]}]}]}]}\n'
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

    def test_focused_accepts_ui_test_method_selectors(self) -> None:
        result = self.invoke(
            "focused", "--platform", "ios",
            "--test", "CauldronUITests/WeekTargetsUITests/testTargetsRoundtrip()",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "-only-testing:CauldronUITests/WeekTargetsUITests/testTargetsRoundtrip()",
            Path(self.records()[-1]["log"]).read_text(),
        )

    def test_ready_requires_ios_ui_but_does_not_select_mac_ui(self) -> None:
        result = self.invoke("ready")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        record = self.records()[0]
        log = Path(record["log"]).read_text()
        self.assertIn("-only-testing:CauldronTests", log)
        self.assertIn("-only-testing:CauldronUITests", log)
        self.assertEqual(record["counts"]["requiredTargets"], {
            "macos": ["CauldronTests"],
            "ios": ["CauldronTests", "CauldronUITests"],
        })
        self.assertEqual(record["counts"]["executedTargets"], record["counts"]["requiredTargets"])
        self.assertEqual(record["counts"]["targetTestCounts"], {
            "macos": {"CauldronTests": 1},
            "ios": {"CauldronTests": 1, "CauldronUITests": 1},
        })
        self.assertEqual(record["counts"]["macosUITests"], "opt-in-not-run")
        self.assertNotIn("-only-testing:CauldronUITests", log.split("platform=macOS", 1)[1].split("platform=iOS", 1)[0])

    def test_ready_fails_when_required_ios_ui_target_is_omitted_or_skipped(self) -> None:
        app_only = '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronTests","nodeType":"Unit test bundle","children":[{"name":"appCase","nodeType":"Test Case","result":"Passed"}]}]}]}'
        omitted = self.invoke(
            "ready",
            IOS_TREE=app_only,
        )
        self.assertEqual(omitted.returncode, 1)
        self.assertIn("expected one CauldronUITests bundle, found 0", omitted.stderr)
        skipped_ui = '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronTests","nodeType":"Unit test bundle","children":[{"name":"appCase","nodeType":"Test Case","result":"Passed"}]},{"name":"CauldronUITests","nodeType":"UI test bundle","children":[{"name":"testSkipped()","nodeType":"Test Case","result":"Skipped"}]}]}]}'
        skipped = self.invoke(
            "ready",
            IOS_TREE=skipped_ui,
        )
        self.assertEqual(skipped.returncode, 1)
        self.assertIn("CauldronUITests test case was skipped", skipped.stderr)

    def test_ready_fails_when_required_ios_app_target_is_missing_empty_or_skipped(self) -> None:
        ui_only = '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronUITests","nodeType":"UI test bundle","children":[{"name":"uiCase","nodeType":"Test Case","result":"Passed"}]}]}]}'
        empty_app = '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronTests","nodeType":"Unit test bundle","children":[]},{"name":"CauldronUITests","nodeType":"UI test bundle","children":[{"name":"uiCase","nodeType":"Test Case","result":"Passed"}]}]}]}'
        skipped_app = '{"testNodes":[{"name":"Cauldron","nodeType":"Test Plan","children":[{"name":"CauldronTests","nodeType":"Unit test bundle","children":[{"name":"appCase","nodeType":"Test Case","result":"Skipped"}]},{"name":"CauldronUITests","nodeType":"UI test bundle","children":[{"name":"uiCase","nodeType":"Test Case","result":"Passed"}]}]}]}'
        for tree, expected in ((ui_only, "expected one CauldronTests bundle, found 0"),
                               (empty_app, "CauldronTests executed zero test cases"),
                               (skipped_app, "CauldronTests test case was skipped")):
            with self.subTest(expected=expected):
                result = self.invoke("ready", IOS_TREE=tree)
                self.assertEqual(result.returncode, 1)
                self.assertIn(expected, result.stderr)

    def test_build_and_zero_test_failures_are_not_passes(self) -> None:
        failed = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/Suite", XCODE_EXIT="1")
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "build-failed")
        self.assertEqual(self.records()[-1]["testCount"], 2)
        zero = self.invoke(
            "focused", "--platform", "macos", "--test", "CauldronTests/Suite",
            SUMMARY='{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Passed"}',
        )
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "zero-tests")

    def test_nonzero_xcode_assertion_overrides_compile_progress(self) -> None:
        summary = '{"totalTestCount":2,"passedTests":1,"failedTests":1,"skippedTests":0,"expectedFailures":0,"result":"Failed"}'
        result = self.invoke(
            "focused", "--platform", "macos", "--test", "CauldronTests/Suite",
            XCODE_EXIT="1", XCODE_ASSERTION="1", SUMMARY=summary,
        )
        self.assertEqual(result.returncode, 1)
        record = self.records()[-1]
        self.assertEqual(record["status"], "assertion-failed")
        self.assertEqual(record["testCount"], 2)
        self.assertEqual(record["xcresult"]["failedTests"], 1)

    def test_bootstrap_failure_with_empty_bundle_is_not_a_zero_test_success(self) -> None:
        self.install("xcodebuild", "while [ $# -gt 0 ]; do if [ \"$1\" = -resultBundlePath ]; then shift; mkdir -p \"$1\"; fi; shift; done\necho 'SwiftCompile normal arm64 source.swift'\necho 'Early unexpected exit while bootstrapping tests'\nexit 65\n")
        self.git("add", "fake-bin/xcodebuild")
        self.git("commit", "-qm", "bootstrap failure fixture")
        result = self.invoke(
            "focused", "--platform", "macos", "--test", "CauldronTests/Suite",
            SUMMARY='{"totalTestCount":0,"passedTests":0,"failedTests":0,"skippedTests":0,"expectedFailures":0,"result":"Failed"}',
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "runner-failed")
        self.assertEqual(self.records()[-1]["testCount"], 0)

    def test_interrupt_reaps_owned_child_before_releasing_ios_lock(self) -> None:
        ready = self.root / ".git/child-ready"
        blocked = self.root / ".git/child-blocked"
        os.mkfifo(ready)
        os.mkfifo(blocked)
        descriptor = os.open(ready, os.O_RDWR | os.O_NONBLOCK)
        self.addCleanup(os.close, descriptor)
        self.install("xcodebuild", "while [ $# -gt 0 ]; do if [ \"$1\" = -resultBundlePath ]; then shift; mkdir -p \"$1\"; fi; shift; done\nif [ \"${BLOCK_CHILD:-0}\" = 1 ]; then echo $$ > \"$READY_FIFO\"; read release < \"$BLOCK_FIFO\"; fi\nexit 0\n")
        self.git("add", "fake-bin/xcodebuild")
        self.git("commit", "-qm", "interrupt fixture")
        environment = os.environ | {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"], "BLOCK_CHILD": "1",
            "READY_FIFO": str(ready), "BLOCK_FIFO": str(blocked),
        }
        for interruption in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=interruption):
                child_pid = None
                process = subprocess.Popen(
                    [sys.executable, "-B", "tools/checks.py", "focused", "--platform", "ios", "--test", "CauldronTests/Suite"],
                    cwd=self.root, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                )
                try:
                    readable, _, _ = select.select([descriptor], [], [], 10)
                    self.assertTrue(readable, "fake child did not signal readiness")
                    child_pid = int(os.read(descriptor, 128).decode().strip())
                    process.send_signal(interruption)
                    process.communicate(timeout=10)
                    self.assertEqual(self.records()[-1]["status"], "interrupted")
                    with self.assertRaises(ProcessLookupError):
                        os.kill(child_pid, 0)
                    retry = self.invoke("focused", "--platform", "ios", "--test", "CauldronTests/Suite")
                    self.assertEqual(retry.returncode, 0, retry.stderr)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.communicate(timeout=10)
                    if child_pid is not None:
                        try:
                            os.kill(child_pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass

    def test_xcode_all_skipped_and_malformed_counts_fail(self) -> None:
        skipped = self.invoke(
            "focused", "--platform", "macos", "--test", "CauldronTests/Suite",
            SUMMARY='{"totalTestCount":2,"passedTests":0,"failedTests":0,"skippedTests":2,"expectedFailures":0,"result":"Passed"}',
        )
        self.assertEqual(skipped.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "zero-tests")
        for invalid in (True, -1, "2", 1.5):
            summary = json.dumps({
                "totalTestCount": invalid, "passedTests": 1, "failedTests": 0,
                "skippedTests": 0, "expectedFailures": 0, "result": "Passed",
            })
            malformed = self.invoke(
                "focused", "--platform", "macos", "--test", "CauldronTests/Suite", SUMMARY=summary
            )
            self.assertEqual(malformed.returncode, 1)
            self.assertEqual(self.records()[-1]["status"], "runner-failed")

    def test_selector_validation_and_package_bootstrap_failure(self) -> None:
        bad = self.invoke("focused", "--platform", "macos", "--test", "testImports")
        self.assertEqual(bad.returncode, 2)
        package = self.invoke("package", SWIFT_EXIT="1")
        self.assertEqual(package.returncode, 1)

    def test_package_prefers_swift_testing_summary_over_xctest_zero(self) -> None:
        output = "Executed 0 tests\n✔ Test run with 593 tests in 127 suites passed after 0.003 seconds."
        result = self.invoke("package", SWIFT_OUTPUT=output)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(self.records()[-1]["testCount"], 593)
        failed = self.invoke(
            "package", SWIFT_OUTPUT="✘ Test run with 4 tests in 2 suites failed after 0.003 seconds."
        )
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "assertion-failed")
        self.assertEqual(self.records()[-1]["testCount"], 4)

    def test_tooling_records_positive_count_and_rejects_zero(self) -> None:
        passed = self.invoke("tooling", TOOLING_COUNT="3")
        self.assertEqual(passed.returncode, 0, passed.stderr + passed.stdout)
        passing_record = self.records()[-1]
        self.assertEqual(passing_record["kind"], "checks")
        self.assertEqual(passing_record["scope"], "focused")
        self.assertEqual(passing_record["platform"], "tooling")
        self.assertEqual(passing_record["testCount"], 3)
        self.assertTrue(passing_record["reproducible"])

        failed = self.invoke("tooling", TOOLING_EXIT="1")
        self.assertEqual(failed.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "assertion-failed")

        zero = self.invoke("tooling", TOOLING_COUNT="0")
        self.assertEqual(zero.returncode, 1)
        self.assertEqual(self.records()[-1]["status"], "zero-tests")

    def test_stale_revision_and_ios_lock_conflict_fail_closed(self) -> None:
        stale = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/Suite", STALE="1")
        self.assertEqual(stale.returncode, 1, stale.stdout + stale.stderr)
        self.assertIn("changed during", stale.stderr)
        lock = self.root / ".git/cauldron/ios-runner.lock"
        lock.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        inode = lock.stat().st_ino
        conflict = self.invoke("focused", "--platform", "ios", "--test", "CauldronTests/Suite")
        self.assertEqual(conflict.returncode, 1)
        self.assertIn("holds the shared lock", conflict.stderr)
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
        self.assertEqual(lock.stat().st_ino, inode)
        abandoned = self.invoke("focused", "--platform", "ios", "--test", "CauldronTests/Suite")
        self.assertEqual(abandoned.returncode, 0, abandoned.stderr + abandoned.stdout)
        self.assertEqual(lock.stat().st_ino, inode)

    def test_ready_records_complete_counts_and_tooling_evidence(self) -> None:
        result = self.invoke("ready")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        record = self.records()[0]
        self.assertEqual(record["status"], "passed")
        self.assertEqual(record["scope"], "full")
        self.assertEqual(record["counts"], {
            "ios": 2, "iosUITests": 1, "macos": 2,
            "macosUITests": "opt-in-not-run",
            "requiredTargets": {
                "macos": ["CauldronTests"],
                "ios": ["CauldronTests", "CauldronUITests"],
            },
            "executedTargets": {
                "macos": ["CauldronTests"],
                "ios": ["CauldronTests", "CauldronUITests"],
            },
            "targetTestCounts": {
                "macos": {"CauldronTests": 1},
                "ios": {"CauldronTests": 1, "CauldronUITests": 1},
            },
            "package": 2, "toolingTestCount": 1,
        })
        self.assertIs(record["lint"], True)
        self.assertIs(record["tooling"], True)
        self.assertTrue(record["reproducible"])
        head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=self.root, text=True).strip()
        hook_check = subprocess.run(
            [sys.executable, "-B", "-c", "import sys; sys.path.insert(0, 'tools'); from hooks import full_checks_exist; assert full_checks_exist(sys.argv[1])", head],
            cwd=self.root, capture_output=True, text=True,
        )
        self.assertEqual(hook_check.returncode, 0, hook_check.stderr)

    def test_ready_dirty_checkout_fails_before_launching_commands(self) -> None:
        (self.root / "tracked.txt").write_text("dirty\n")
        marker = self.root / "commands.log"
        result = self.invoke("ready", CALLS=str(marker))
        self.assertEqual(result.returncode, 1)
        self.assertIn("clean starting revision", result.stderr)
        self.assertFalse(marker.exists())

    def test_focused_dirty_run_passes_but_is_not_reproducible(self) -> None:
        (self.root / "tracked.txt").write_text("TDD edit\n")
        result = self.invoke("focused", "--platform", "macos", "--test", "CauldronTests/Suite")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        record = self.records()[-1]
        self.assertEqual(record["status"], "passed")
        self.assertTrue(record["before"]["dirty"])
        self.assertFalse(record["reproducible"])

    def test_tooling_output_is_written_live_before_command_exits(self) -> None:
        gate = self.root / "release-gate"
        os.mkfifo(gate)
        environment = os.environ | {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "TOOLING_BLOCK": "1", "TOOLING_GATE": str(gate),
        }
        process = subprocess.Popen(
            [sys.executable, "-B", "tools/checks.py", "tooling"], cwd=self.root,
            env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
        )
        log_path = None
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and log_path is None:
            paths = list((self.root / ".git/cauldron/runs").glob("*/result.json"))
            if paths:
                log_path = Path(json.loads(paths[0].read_text())["log"])
            else:
                time.sleep(0.005)
        marker_seen = False
        try:
            self.assertIsNotNone(log_path)
            while time.monotonic() < deadline and not marker_seen:
                marker_seen = "live-marker" in log_path.read_text()
                if not marker_seen:
                    time.sleep(0.005)
            self.assertTrue(marker_seen, "child output was not visible in the run log before exit")
        finally:
            if process.poll() is None:
                if marker_seen:
                    with gate.open("w") as release:
                        release.write("continue\n")
                else:
                    os.killpg(process.pid, signal.SIGTERM)
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, 0, stderr + stdout)


if __name__ == "__main__":
    unittest.main()
