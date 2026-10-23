"""Hook checks use staged content and never rewrite a developer's checkout."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))


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

    def test_copy_lint_parses_visible_literals_not_comments_metadata_or_copy_expressions(self):
        result = subprocess.run(
            ["xcrun", "--find", "swiftc"], capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        source = self.root / "fixture.swift"
        source.write_text("\n".join([
            '// Text("not visible")',
            "Text(Copy.title)",
            'Label(Copy.title, systemImage: "fork.knife")',
            'Button("\\(Copy.action)") { }',
            'Text("bad")',
            'Text(verbatim: "also bad")',
            'Text("composed " + Copy.detail)',
            "// copylint:ignore -- debug specimen, not product copy",
            'Text("preview")',
            'Text("adjacent title")',
            'Text("copylint:ignore -- text is not a directive")',
            "// copylint:ignore --",
            'Text("reason required")',
        ]) + "\n")
        from hooks import copy_lint
        with self.assertRaises(Exception) as failure:
            copy_lint([("apple/Cauldron/Fixture.swift", source.read_bytes())])
        diagnostics = str(failure.exception)
        for line in (5, 6, 7, 10, 11, 13):
            self.assertIn(f":{line}:", diagnostics)
        self.assertNotIn(":9:", diagnostics)
        self.assertIn("requires `// copylint:ignore -- reason`", diagnostics)

    def test_copy_lint_suppression_is_comment_trivia_and_belongs_to_one_call(self):
        from hooks import copy_lint
        source = self.root / "exceptions.swift"
        source.write_text("\n".join([
            "// copylint:ignore -- one preview only",
            'Text("first")',
            'Text("second")',
            'Text("copylint:ignore -- text, not a comment")',
            "// copylint:ignore --",
            'Text("empty reason")',
            'Text("trailing exception") // copylint:ignore -- one call only',
            'Text("after trailing exception")',
            "// copylint:ignore --missing separator",
            'Text("malformed directive")',
        ]) + "\n")
        with self.assertRaises(Exception) as failure:
            copy_lint([("apple/Cauldron/Exceptions.swift", source.read_bytes())])
        diagnostics = str(failure.exception)
        for line in (3, 4, 6, 8, 10):
            self.assertIn(f":{line}:", diagnostics)
        for line in (2, 7):
            self.assertNotIn(f":{line}:", diagnostics)
        self.assertIn("requires `// copylint:ignore -- reason`", diagnostics)

    def test_copy_lint_recompiles_when_injected_sdk_or_host_identity_changes(self):
        from hooks import copy_lint

        def identity(sdk_build, syntax_hash):
            return {
                "swiftc": {
                    "path": "/toolchain/usr/bin/swift-frontend", "invoked_path": "/toolchain/usr/bin/swiftc",
                    "sha256": "compiler",
                },
                "swiftc_version": "Swift version stable",
                "sdk_path": "/sdk/MacOSX.sdk",
                "sdk_version": "27.0",
                "sdk_build": sdk_build,
                "architecture": "arm64",
                "host_path": "/toolchain/usr/lib/swift/host",
                "host_inputs": [{"path": "libSwiftSyntax.dylib", "sha256": syntax_hash}],
            }

        identities = [identity("build-a", "syntax-a")] * 2
        identities.extend([identity("build-b", "syntax-a"), identity("build-b", "syntax-b")])
        commands = []

        def run(args, **_kwargs):
            commands.append(args)
            if "-o" in args:
                Path(args[args.index("-o") + 1]).write_bytes(b"cached checker")
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        with (
            mock.patch("hooks.repository", return_value=self.root),
            mock.patch("hooks.toolchain_identity", side_effect=identities),
            mock.patch("hooks.subprocess.run", side_effect=run),
        ):
            for _ in identities:
                copy_lint([("apple/Cauldron/Fixture.swift", b"Text(Copy.title)\n")], b"checker")

        compiles = [args for args in commands if "-o" in args]
        self.assertEqual(len(compiles), 3)
        self.assertEqual(sum(args[0].endswith("/copy-lint") for args in commands), 4)

    def test_staged_copy_violation_cannot_be_hidden_by_worktree_fix_or_unstaged_ignore(self):
        app = self.root / "apple/Cauldron"
        app.mkdir(parents=True)
        (self.root / "apple/.swift-format").write_text("{}\n")
        path = app / "Visible.swift"
        path.write_text('Text("visible")\n')
        (self.root / "tools").mkdir()
        (self.root / "tools/copy_lint.swift").write_bytes((TOOLS / "copy_lint.swift").read_bytes())
        share = self.root / "apple/ShareSheet/Visible.swift"
        share.parent.mkdir(parents=True)
        share.write_text('Text("share visible")\n')
        self.git("add", "apple", "tools/copy_lint.swift")
        path.write_text('// copylint:ignore -- not user facing\nText("visible")\n')
        share.write_text("Text(Copy.share.title)\n")
        binary = self.root / ".git/fake-bin"
        binary.mkdir()
        swift = binary / "swift"
        swift.write_text("#!/bin/sh\nexit 0\n")
        swift.chmod(0o755)
        environment = {**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"]}
        result = self.command("pre-commit", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Visible.swift", result.stderr)
        self.assertIn("ShareSheet", result.stderr)

    def test_install_preserves_custom_hooks(self):
        self.git("config", "core.hooksPath", "custom-hooks")
        result = self.command("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("config", "core.hooksPath"), "custom-hooks")

    def test_install_refuses_executable_default_hook(self):
        hook = self.root / ".git/hooks/pre-commit"
        hook.write_text("#!/bin/sh\nexit 0\n")
        hook.chmod(0o755)
        result = self.command("install")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(hook.read_text(), "#!/bin/sh\nexit 0\n")

    def test_install_refuses_inherited_hooks_path(self):
        config = self.root / ".git/custom-global-config"
        config.write_text("[core]\n\thooksPath = inherited-hooks\n")
        environment = {**os.environ, "GIT_CONFIG_GLOBAL": str(config)}
        result = self.command("install", environment=environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("inherited-hooks", result.stderr)

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

    def test_destination_release_tag_requires_preflight_even_when_source_is_head(self):
        result = self.command("pre-push", stdin=f"HEAD {self.base} refs/tags/v0.0.1 {'0' * 40}\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("evidence", result.stderr)

    def test_tooling_push_tests_the_active_worktree_not_the_hook_owner(self):
        path = self.root / "tools/tests/test_new_failure.py"
        path.parent.mkdir(parents=True)
        path.write_text("import unittest\nclass NewTests(unittest.TestCase):\n def test_new(self):\n  self.fail('new revision fails')\n")
        self.git("add", "tools")
        self.git("commit", "-m", "new tooling regression")
        head = self.git("rev-parse", "HEAD")
        owner = self.root / ".git/owning-checkout/tools"
        (owner / "tests").mkdir(parents=True)
        for name in ("hooks.py", "workflow_support.py"):
            (owner / name).write_bytes((TOOLS / name).read_bytes())
        (owner / "tests/test_owner.py").write_text("import unittest\nclass OldTests(unittest.TestCase):\n def test_old(self):\n  self.assertTrue(True)\n")
        result = subprocess.run(
            [sys.executable, "-B", str(owner / "hooks.py"), "pre-push"], cwd=self.root,
            input=f"refs/heads/main {head} refs/heads/main {self.base}\n", capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("new revision fails", result.stderr)

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

    def test_new_branch_without_origin_main_cannot_hide_earlier_native_change(self):
        path = self.root / "apple/Cauldron/Feature.swift"
        path.parent.mkdir(parents=True)
        path.write_text("let feature = 1\n")
        self.git("add", "apple")
        self.git("commit", "-m", "native change")
        (self.root / "README").write_text("later documentation\n")
        self.git("add", "README")
        self.git("commit", "-m", "documentation tip")
        head = self.git("rev-parse", "HEAD")
        result = self.command("pre-push", stdin=f"refs/heads/new {head} refs/heads/new {'0' * 40}\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)

    def test_new_destination_ref_does_not_trust_unrelated_origin_main(self):
        path = self.root / "apple/Cauldron/Feature.swift"
        path.parent.mkdir(parents=True)
        path.write_text("let feature = 1\n")
        self.git("add", "apple")
        self.git("commit", "-m", "native on origin")
        head = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", head)
        result = self.command("pre-push", stdin=f"HEAD {head} refs/heads/new-on-another-remote {'0' * 40}\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)


if __name__ == "__main__":
    unittest.main()
