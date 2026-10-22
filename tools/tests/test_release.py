from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class ReleaseCLITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        (self.root / "tools").mkdir()
        (self.root / "tools/workflow_support.py").write_bytes((SOURCE / "workflow_support.py").read_bytes())
        (self.root / "tools/release.py").write_bytes((SOURCE / "release.py").read_bytes())
        (self.root / "tools/tests").mkdir()
        (self.root / "apple/Cauldron.xcodeproj").mkdir(parents=True)
        (self.root / "apple/Cauldron").mkdir()
        (self.root / "apple/project.yml").write_text('MARKETING_VERSION: "1.2.3"\n')
        (self.root / "apple/Cauldron.xcodeproj/project.pbxproj").write_text(
            "MARKETING_VERSION = 1.2.3;\nMARKETING_VERSION = 1.2.3;\n"
        )
        self.model = self.root / "apple/Cauldron/Recipe.swift"
        self.model.write_text("@Model final class Recipe {}\n")
        self.git("init", "-q")
        self.git("config", "user.name", "Release Test")
        self.git("config", "user.email", "release@example.test")
        self.commit()
        self.git("tag", "v1.2.2")
        self.bin = Path(self.temp.name) / "bin"
        self.bin.mkdir()
        self._fake_tools()
        self.env = {**os.environ, "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}"}
        self.run_cli("build", "--configuration", "Debug")
        self.run_cli("build", "--configuration", "Release")
        self.debug = self.state / "builds/Debug/Build/Products/Debug/Cauldron.app"
        self.release = self.state / "builds/Release/Build/Products/Release/Cauldron.app"

    def tearDown(self):
        self.temp.cleanup()

    @property
    def state(self):
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=self.root,
                                text=True, capture_output=True, check=True).stdout.strip()
        return (self.root / common / "cauldron").resolve()

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, text=True, capture_output=True, check=True)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "snapshot")

    def _fake_tools(self):
        codesign = self.bin / "codesign"
        codesign.write_text('''#!/bin/sh
if [ "$1" = "--verify" ]; then exit 0; fi
cat "$4/entitlements.plist"
''')
        codesign.chmod(0o755)
        xcodebuild = self.bin / "xcodebuild"
        xcodebuild.write_text('''#!/bin/sh
derived=""
configuration=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -derivedDataPath) derived="$2"; shift 2 ;;
    -configuration) configuration="$2"; shift 2 ;;
    *) shift ;;
  esac
done
app="$derived/Build/Products/$configuration/Cauldron.app"
mkdir -p "$app/Contents"
python3 - "$app/Contents/Info.plist" "$configuration" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"CFBundleIdentifier": "computer.srcery.cauldron", "CFBundleShortVersionString": "1.2.3"}, f)
PY
python3 - "$app/entitlements.plist" "$configuration" <<'PY'
import plistlib, sys
env = "Development" if sys.argv[2] == "Debug" else "Production"
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"com.apple.developer.team-identifier": "5U2B7W5F39",
      "com.apple.developer.icloud-container-environment": env,
      "com.apple.developer.icloud-container-identifiers": ["iCloud.computer.srcery.cauldron"]}, f)
PY
''')
        xcodebuild.chmod(0o755)

    def run_cli(self, *args, check=True):
        return subprocess.run(["python3", "-B", "tools/release.py", *map(str, args)], cwd=self.root,
                              env=self.env, text=True, capture_output=True, check=check)

    def add_full_check_record(self, *, counts=None, head=None):
        head = head or self.git("rev-parse", "HEAD").stdout.strip()
        snap = {"head": head, "tree": self.git("rev-parse", "HEAD^{tree}").stdout.strip(),
                "dirty": False, "worktree": str(self.root)}
        record = {"version": 1, "kind": "checks", "scope": "full", "status": "passed",
                  "reproducible": True, "before": snap, "after": dict(snap),
                  "counts": counts or {"package": 1, "macos": 1, "ios": 1},
                  "lint": True, "tooling": True, "startedAt": 1}
        path = self.state / "runs/test/result.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(record))

    def apps(self):
        return ["--debug-app", self.debug, "--release-app", self.release]

    def test_preflight_success_requires_exact_records_and_passes(self):
        self.add_full_check_record()
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["status"], "passed")
        self.assertTrue((self.state / "releases/v1.2.3.json").exists())

    def test_rejects_wrong_environment_and_artifact_mutation(self):
        self.add_full_check_record()
        entitlements = self.debug / "entitlements.plist"
        data = plistlib.loads(entitlements.read_bytes())
        data["com.apple.developer.icloud-container-environment"] = "Production"
        entitlements.write_bytes(plistlib.dumps(data))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("entitlement", result.stderr)

    def test_rejects_artifact_tampering_after_build(self):
        self.add_full_check_record()
        resources = self.debug / "Contents/Resources"
        resources.mkdir()
        (resources / "payload").write_text("mutated")
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("build provenance", result.stderr)

    def test_rejects_check_record_from_another_head(self):
        self.add_full_check_record(head="0" * 40)
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("full check evidence", result.stderr)

    def test_rejects_missing_full_tests_or_zero_counts(self):
        self.add_full_check_record(counts={"package": 0, "macos": 4, "ios": 2})
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("full check evidence", result.stderr)

    def test_rejects_dirty_tree_and_existing_tag(self):
        self.add_full_check_record()
        (self.root / "untracked").write_text("dirty")
        self.assertIn("clean checkout", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)
        (self.root / "untracked").unlink()
        self.git("tag", "v1.2.3")
        self.assertIn("Tag already exists", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)

    def test_model_change_requires_current_human_init_then_deployment(self):
        self.model.write_text("@Model final class Recipe { var title: String = \"\" }\n")
        self.commit()
        self.run_cli("build", "--configuration", "Debug")
        self.run_cli("build", "--configuration", "Release")
        self.add_full_check_record()
        self.assertIn("Missing or stale initialized", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)
        self.assertIn("requires matching initialization", self.run_cli(
            "record-schema", "v1.2.3", "--phase", "deployed", "--note", "approved", check=False
        ).stderr)
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initialized locally")
        self.assertIn("Missing or stale deployed", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)
        self.run_cli("record-schema", "v1.2.3", "--phase", "deployed", "--note", "Deployed manually")
        self.assertEqual(json.loads(self.run_cli("preflight", "v1.2.3", *self.apps()).stdout)["status"], "passed")

    def test_rejects_provenance_from_another_revision(self):
        self.add_full_check_record()
        # Retain a valid artifact but replace its provenance head with another revision.
        path = next((self.state / "builds").glob("debug-*.json"))
        record = json.loads(path.read_text())
        record["head"] = "0" * 40
        path.write_text(json.dumps(record))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("build provenance", result.stderr)


if __name__ == "__main__":
    unittest.main()
