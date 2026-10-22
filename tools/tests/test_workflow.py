"""Exercise completion and integration via the CLI against disposable Git repositories."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cauldron-workflow-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        (self.root / "README").write_text("base\n")
        self.git("add", "README")
        self.git("commit", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")
        self.git("switch", "-c", "integration")
        self.worker = Path(self.temporary.name) / "worker"
        self.git("worktree", "add", "-b", "worker", str(self.worker), self.base)
        (self.worker / "feature").write_text("implemented\n")
        self.git("add", "feature", cwd=self.worker)
        self.git("commit", "-m", "feature", cwd=self.worker)
        self.head = self.git("rev-parse", "HEAD", cwd=self.worker)
        self.tree = self.git("rev-parse", "HEAD^{tree}", cwd=self.worker)
        self.check = self.root / ".git" / "check.json"
        state = {"head": self.head, "tree": self.tree, "dirty": False, "worktree": str(self.worker)}
        self.check.write_text(json.dumps({
            "version": 1, "kind": "checks", "scope": "focused", "status": "passed",
            "before": state, "after": state, "reproducible": True, "testCount": 3,
        }))
        self.brief = self.root / ".git" / "brief.json"
        self.brief.write_text(json.dumps({"version": 1, "ticket": "test", "criteria": ["persist", "reject"]}))
        self.result_path = self.root / ".git" / "worker.json"
        self.result = {
            "version": 1, "status": "complete", "ticket": "test", "head": self.head, "base": self.base,
            "criteria": [{"id": key, "status": "met", "evidence": ["focused regression"]}
                         for key in ("persist", "reject")],
            "checks": [str(self.check)], "remaining": [], "manual": ["real-device sync"],
        }

    def git(self, *args, cwd=None):
        return subprocess.check_output(["git", *args], cwd=cwd or self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def command(self, *args):
        self.result_path.write_text(json.dumps(self.result))
        return subprocess.run(
            [sys.executable, "-B", str(TOOLS / "workflow.py"), *args,
             "--result", str(self.result_path), "--brief", str(self.brief)],
            cwd=self.root, capture_output=True, text=True,
        )

    def test_partial_and_unaccounted_acceptance_cannot_advance(self):
        self.result["status"] = "partial"
        self.assertNotEqual(self.command("worker-check").returncode, 0)
        self.result["status"] = "complete"
        self.result["criteria"].pop()
        self.assertNotEqual(self.command("worker-check").returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)

    def test_zero_failed_dirty_and_stale_check_records_are_rejected(self):
        original = json.loads(self.check.read_text())
        for changes in ({"testCount": 0}, {"status": "build-failed"}, {"reproducible": False}):
            self.check.write_text(json.dumps({**original, **changes}))
            self.assertNotEqual(self.command("worker-check").returncode, 0)
        stale = {**original, "before": {**original["before"], "head": self.base}}
        self.check.write_text(json.dumps(stale))
        self.assertNotEqual(self.command("worker-check").returncode, 0)

    def test_clean_complete_worker_fast_forwards_exact_tested_revision(self):
        result = self.command("integrate", "worker")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.head)
        self.assertEqual(self.git("rev-parse", "main"), self.base)
        self.assertEqual((self.root / "feature").read_text(), "implemented\n")

    def test_dirty_target_and_dirty_worker_are_preserved(self):
        (self.root / "README").write_text("user work\n")
        self.assertNotEqual(self.command("integrate", "worker").returncode, 0)
        self.assertEqual((self.root / "README").read_text(), "user work\n")
        (self.root / "README").write_text("base\n")
        (self.worker / "feature").write_text("unfinished\n")
        self.assertNotEqual(self.command("integrate", "worker").returncode, 0)
        self.assertEqual((self.worker / "feature").read_text(), "unfinished\n")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)

    def test_stale_worker_and_new_integration_tip_are_refused(self):
        (self.root / "other").write_text("another ticket\n")
        self.git("add", "other")
        self.git("commit", "-m", "another ticket")
        before = self.git("rev-parse", "HEAD")
        self.assertNotEqual(self.command("integrate", "worker").returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), before)


if __name__ == "__main__":
    unittest.main()
