"""Hook checks use staged content and never rewrite a developer's checkout."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]


class HookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cauldron-hooks-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        (self.root / "README").write_text("base\n")
        self.git("add", "README")
        self.git("commit", "-m", "base")
        self.base = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.DEVNULL, text=True).strip()

    def command(self, *args, stdin="", environment=None):
        return subprocess.run(
            [sys.executable, "-B", str(TOOLS / "hooks.py"), *args],
            cwd=self.root, capture_output=True, text=True, input=stdin,
            env=environment or os.environ.copy(),
        )

    def test_staged_json_not_working_copy_is_checked_and_nothing_rewritten(self):
        path = self.root / "data.json"
        path.write_text("{broken")
        self.git("add", "data.json")
        path.write_text('{"fixed": true}\n')
        result = self.command("pre-commit")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("show", ":data.json"), "{broken")
        self.assertEqual(path.read_text(), '{"fixed": true}\n')

    def test_native_policy_catches_staged_banned_store_even_when_working_copy_fixed(self):
        path = self.root / "apple/Cauldron/Unsafe.swift"
        path.parent.mkdir(parents=True)
        path.write_text("let store = ModelContainer()\n")
        config = self.root / "apple/.swift-format"
        config.write_text("{}\n")
        self.git("add", "apple")
        path.write_text("let safe = 1\n")
        binary = self.root / ".git/fake-bin"
        binary.mkdir()
        swift = binary / "swift"
        swift.write_text("#!/bin/sh\nexit 0\n")
        swift.chmod(0o755)
        environment = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"]}
        result = self.command("pre-commit", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CauldronStore", result.stderr)
        self.assertEqual(path.read_text(), "let safe = 1\n")

    def test_install_preserves_custom_hooks(self):
        self.git("config", "core.hooksPath", "custom-hooks")
        result = self.command("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("config", "core.hooksPath"), "custom-hooks")

    def test_installed_hook_rejects_bad_commit_without_touching_files(self):
        installed = self.command("install")
        self.assertEqual(installed.returncode, 0, installed.stderr)
        path = self.root / "data.json"
        path.write_text("{broken")
        self.git("add", path.name)
        committed = subprocess.run(["git", "commit", "-m", "bad staged JSON"], cwd=self.root,
                                   capture_output=True, text=True)
        self.assertNotEqual(committed.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)
        self.assertEqual(path.read_text(), "{broken")

    def test_malformed_staged_entitlements_are_rejected(self):
        path = self.root / "Bad.entitlements"
        path.write_text("<plist><dict>")
        self.git("add", path.name)
        result = self.command("pre-commit")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Bad.entitlements", result.stderr)
        self.assertEqual(path.read_text(), "<plist><dict>")

    def test_tag_push_requires_preflight_and_never_pushes(self):
        self.git("tag", "-a", "v0.0.1", "-m", "release")
        tag = self.git("rev-parse", "v0.0.1")
        result = self.command("pre-push", stdin=f"refs/tags/v0.0.1 {tag} refs/tags/v0.0.1 {'0' * 40}\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("evidence", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)

    def test_native_push_reuses_only_current_nonzero_full_evidence(self):
        path = self.root / "apple/Cauldron/Feature.swift"
        path.parent.mkdir(parents=True)
        path.write_text("let feature = 1\n")
        self.git("add", "apple")
        self.git("commit", "-m", "native")
        head = self.git("rev-parse", "HEAD")
        state = {"head": head, "tree": self.git("rev-parse", "HEAD^{tree}"), "dirty": False, "worktree": str(self.root)}
        record = {
            "version": 1, "kind": "checks", "scope": "full", "status": "passed",
            "before": state, "after": state, "reproducible": True, "lint": True, "tooling": True,
            "counts": {"package": 2, "macos": 3, "ios": 4},
        }
        directory = self.root / ".git/cauldron/runs/example"
        directory.mkdir(parents=True)
        (directory / "result.json").write_text(json.dumps(record))
        update = f"refs/heads/main {head} refs/heads/main {self.base}\n"
        result = self.command("pre-push", stdin=update)
        self.assertEqual(result.returncode, 0, result.stderr)
        (self.root / "README").write_text("uncommitted user work\n")
        result = self.command("pre-push", stdin=update)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / "README").read_text(), "uncommitted user work\n")


if __name__ == "__main__":
    unittest.main()
