from __future__ import annotations

import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys
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
        self.debug_record = self.build_cli("Debug")
        self.release_record = self.build_cli("Release")
        self.debug = Path(self.debug_record["artifact"]["path"])
        self.release = Path(self.release_record["artifact"]["path"])

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
if [ "${FAKE_XCODEBUILD_FAIL:-}" = "1" ]; then echo "injected build failure"; exit 7; fi
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

    def build_cli(self, configuration, *, check=True, fail=False):
        env = {**self.env, **({"FAKE_XCODEBUILD_FAIL": "1"} if fail else {})}
        result = subprocess.run(["python3", "-B", "tools/release.py", "build", "--configuration", configuration],
                                cwd=self.root, env=env, text=True, capture_output=True, check=check)
        return result if not check else json.loads(result.stdout)

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

    def test_plan_is_read_only_advisory_and_dirty_edits_are_excluded(self):
        self.model.write_text('@Model final class Recipe { var committed = "yes" }\n')
        self.commit()
        before = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        result = self.run_cli("plan", "v1.2.3")
        plan = json.loads(result.stdout)
        self.assertEqual(plan["status"], "advisory")
        self.assertEqual(plan["schemaSourcePaths"], ["apple/Cauldron/Recipe.swift"])
        self.assertEqual(plan["requiredEvidence"], ["initialized", "deployed or production-current"])
        after = {path.relative_to(self.root): path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        self.assertEqual(after, before)
        self.model.write_text("@Model final class Recipe { var changed = true }\n")
        self.git("add", str(self.model.relative_to(self.root)))
        self.model.write_text("@Model final class Recipe { var stagedAndChanged = true }\n")
        (self.root / "untracked-model.swift").write_text("@Model final class Extra {}\n")
        dirty = json.loads(self.run_cli("plan").stdout)
        self.assertEqual(dirty["workingTree"], "dirty")
        self.assertIn("committed HEAD only", dirty["scope"])
        self.assertEqual(dirty["schemaSourcePaths"], plan["schemaSourcePaths"])
        self.assertIn("staged, unstaged, and untracked", dirty["warning"])
        self.assertEqual(json.loads(self.run_cli("plan", "v9.9.9").stdout)["requestedVersionMatches"], False)

    def test_plan_in_fresh_repository_does_not_create_evidence_or_touch_git_files(self):
        fresh = Path(self.temp.name) / "fresh"
        (fresh / "tools").mkdir(parents=True)
        (fresh / "tools/workflow_support.py").write_bytes((SOURCE / "workflow_support.py").read_bytes())
        (fresh / "tools/release.py").write_bytes((SOURCE / "release.py").read_bytes())
        (fresh / "apple/Cauldron.xcodeproj").mkdir(parents=True)
        (fresh / "apple/Cauldron").mkdir()
        (fresh / "apple/project.yml").write_text('MARKETING_VERSION: "1.2.3"\n')
        (fresh / "apple/Cauldron.xcodeproj/project.pbxproj").write_text("MARKETING_VERSION = 1.2.3;\n")
        (fresh / "apple/Cauldron/Recipe.swift").write_text("@Model final class Recipe {}\n")
        subprocess.run(["git", "init", "-q"], cwd=fresh, check=True)
        subprocess.run(["git", "config", "user.name", "Plan Test"], cwd=fresh, check=True)
        subprocess.run(["git", "config", "user.email", "plan@example.test"], cwd=fresh, check=True)
        subprocess.run(["git", "add", "."], cwd=fresh, check=True)
        subprocess.run(["git", "commit", "-qm", "fixture"], cwd=fresh, check=True)
        subprocess.run(["git", "tag", "v1.2.2"], cwd=fresh, check=True)
        git_files_before = {path.relative_to(fresh / ".git"): path.read_bytes()
                            for path in (fresh / ".git").rglob("*") if path.is_file()}
        result = subprocess.run(["python3", "-B", "tools/release.py", "plan"], cwd=fresh,
                                text=True, capture_output=True, check=True)
        self.assertEqual(json.loads(result.stdout)["status"], "advisory")
        self.assertFalse((fresh / ".git/cauldron").exists())
        git_files_after = {path.relative_to(fresh / ".git"): path.read_bytes()
                           for path in (fresh / ".git").rglob("*") if path.is_file()}
        self.assertEqual(git_files_after, git_files_before)

    def test_rejects_wrong_environment_and_artifact_mutation(self):
        self.add_full_check_record()
        entitlements = self.debug / "entitlements.plist"
        data = plistlib.loads(entitlements.read_bytes())
        data["com.apple.developer.icloud-container-environment"] = "Production"
        entitlements.write_bytes(plistlib.dumps(data))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("entitlement", result.stderr)

    def test_rejects_missing_cloudkit_environment_entitlement(self):
        data = plistlib.loads((self.debug / "entitlements.plist").read_bytes())
        del data["com.apple.developer.icloud-container-environment"]
        (self.debug / "entitlements.plist").write_bytes(plistlib.dumps(data))
        self.add_full_check_record()
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("icloud-container-environment", result.stderr)

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
        self.debug_record = self.build_cli("Debug")
        self.release_record = self.build_cli("Release")
        self.debug = Path(self.debug_record["artifact"]["path"])
        self.release = Path(self.release_record["artifact"]["path"])
        self.add_full_check_record()
        self.assertIn("Missing or stale initialized", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)
        self.assertIn("requires matching initialization", self.run_cli(
            "record-schema", "v1.2.3", "--phase", "deployed", "--note", "approved", check=False
        ).stderr)
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initialized locally")
        self.assertIn("Missing or stale deployed", self.run_cli("preflight", "v1.2.3", *self.apps(), check=False).stderr)
        self.run_cli("record-schema", "v1.2.3", "--phase", "deployed", "--note", "Deployed manually")
        self.assertEqual(json.loads(self.run_cli("preflight", "v1.2.3", *self.apps()).stdout)["status"], "passed")

    def prepare_schema_change(self):
        self.model.write_text('@Model final class Recipe { var title: String = "" }\n')
        self.commit()
        self.debug_record = self.build_cli("Debug")
        self.release_record = self.build_cli("Release")
        self.debug = Path(self.debug_record["artifact"]["path"])
        self.release = Path(self.release_record["artifact"]["path"])
        self.add_full_check_record()

    def test_production_current_attestation_is_explicit_and_satisfies_preflight(self):
        self.prepare_schema_change()
        missing_init = self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                                    "--note", "Console shows no pending production changes", check=False)
        self.assertNotEqual(missing_init.returncode, 0)
        self.assertIn("matching initialization", missing_init.stderr)
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                     "--note", "Console shows nothing to deploy")
        result = json.loads(self.run_cli("preflight", "v1.2.3", *self.apps()).stdout)
        self.assertEqual(result["schema"]["status"], "initialized; production confirmed current")
        self.assertEqual(result["schema"]["productionEvidencePhase"], "production-current")
        self.assertEqual(len(result["schema"]["attestations"]), 2)

    def test_production_current_rejects_malformed_or_earlier_initialization_time(self):
        self.prepare_schema_change()
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        schema_dir = self.state / "schemas"
        init_path = next(schema_dir.glob("initialized-*.json"))
        initialized = json.loads(init_path.read_text())
        initialized["createdAt"] = 200
        init_path.write_text(json.dumps(initialized))
        current = self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                               "--note", "No pending changes")
        current_record = json.loads(current.stdout)
        current_path = next(schema_dir.glob("production-current-*.json"))
        current_record["createdAt"] = 100
        current_path.write_text(json.dumps(current_record))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("production-current", result.stderr)

    def test_production_current_rejects_stale_identity_and_malformed_record(self):
        self.prepare_schema_change()
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                     "--note", "Console shows nothing to deploy")
        current = next((self.state / "schemas").glob("production-current-*.json"))
        original = json.loads(current.read_text())
        for key, invalid in (("head", "0" * 40), ("release", "v9.9.9"),
                             ("fingerprint", "0" * 64), ("note", ""), ("id", "")):
            with self.subTest(field=key):
                record = dict(original)
                record[key] = invalid
                current.write_text(json.dumps(record))
                result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
                self.assertNotEqual(result.returncode, 0)

    def test_production_evidence_rejects_future_timestamps_and_boolean_version(self):
        self.prepare_schema_change()
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                     "--note", "Console shows nothing to deploy")
        schemas = self.state / "schemas"
        init = next(schemas.glob("initialized-*.json"))
        production = next(schemas.glob("production-current-*.json"))
        original_init = json.loads(init.read_text())
        original_production = json.loads(production.read_text())
        for field, path, original in (("initialized", init, original_init),
                                      ("production-current", production, original_production)):
            with self.subTest(phase=field):
                record = dict(original)
                record["createdAt"] = 4102444800
                path.write_text(json.dumps(record))
                if field == "initialized":
                    current = dict(original_production)
                    current["createdAt"] = 4102444801
                    production.write_text(json.dumps(current))
                result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
                self.assertNotEqual(result.returncode, 0)
                init.write_text(json.dumps(original_init))
                production.write_text(json.dumps(original_production))
        malformed = dict(original_init)
        malformed["version"] = True
        init.write_text(json.dumps(malformed))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)

    def test_recording_production_requires_strict_initialized_record(self):
        self.prepare_schema_change()
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        init = next((self.state / "schemas").glob("initialized-*.json"))
        original = json.loads(init.read_text())
        for field, invalid in (("version", 999), ("note", {"text": "initialized"}),
                               ("author", ["Release Test"]), ("createdAt", True),
                               ("createdAt", float("inf"))):
            with self.subTest(field=field, invalid=invalid):
                record = dict(original)
                record[field] = invalid
                init.write_text(json.dumps(record))
                result = self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                                      "--note", "Console shows nothing to deploy", check=False)
                self.assertNotEqual(result.returncode, 0)

    def test_reinitialization_invalidates_older_production_confirmation(self):
        self.prepare_schema_change()
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initializer succeeded")
        self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                     "--note", "Console shows nothing to deploy")
        schemas = self.state / "schemas"
        production_path = next(schemas.glob("production-current-*.json"))
        production = json.loads(production_path.read_text())
        self.run_cli("record-schema", "v1.2.3", "--phase", "initialized", "--note", "Initialized again")
        initialized = json.loads(next(schemas.glob("initialized-*.json")).read_text())
        self.assertGreater(initialized["createdAt"], production["createdAt"])
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("production-current", result.stderr)

    def test_production_current_rejects_stale_release_and_unknown_programmatic_phase(self):
        self.prepare_schema_change()
        invalid = self.run_cli("record-schema", "v1.2.3", "--phase", "production-current",
                               "--note", "No pending changes", check=False)
        self.assertNotEqual(invalid.returncode, 0)
        from importlib.util import module_from_spec, spec_from_file_location
        sys.path.insert(0, str(SOURCE))
        spec = spec_from_file_location("release_module", SOURCE / "release.py")
        release = module_from_spec(spec)
        spec.loader.exec_module(release)
        with self.assertRaises(release.support.WorkflowError):
            release.attest("unknown", "v1.2.3", "note")
        sys.path.remove(str(SOURCE))

    def test_rejects_provenance_from_another_revision(self):
        self.add_full_check_record()
        # Retain a valid artifact but replace its provenance head with another revision.
        path = next((self.state / "builds").glob("debug-*.json"))
        record = json.loads(path.read_text())
        record["head"] = "0" * 40
        path.write_text(json.dumps(record))
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("build provenance", result.stderr)

    def test_build_failure_is_ledgered_with_log_and_consecutive_builds_are_isolated(self):
        manifest_count = len(list((self.state / "builds").glob("*.json")))
        failure = self.build_cli("Debug", check=False, fail=True)
        self.assertNotEqual(failure.returncode, 0)
        ledgers = [record for _, record in self.run_records()
                   if record.get("kind") == "release-build" and record.get("status") == "build-failed"]
        failed = ledgers[-1]
        self.assertEqual(failed["status"], "build-failed")
        self.assertTrue(Path(failed["log"]).is_file())
        self.assertEqual(len(list((self.state / "builds").glob("*.json"))), manifest_count)
        first = self.debug_record
        second = self.build_cli("Debug")
        self.assertNotEqual(first["artifact"]["path"], second["artifact"]["path"])
        self.assertNotEqual(first["runRecord"], second["runRecord"])
        # A manifest cannot borrow one build's path while retaining another build's ledger.
        manifest = Path(second["record"])
        data = json.loads(manifest.read_text())
        data["artifact"]["path"] = first["artifact"]["path"]
        manifest.write_text(json.dumps(data))
        Path(first["record"]).unlink()
        self.add_full_check_record()
        result = self.run_cli("preflight", "v1.2.3", *self.apps(), check=False)
        self.assertIn("build provenance", result.stderr)

    def run_records(self):
        return [(path, json.loads(path.read_text())) for path in (self.state / "runs").glob("*/result.json")]


if __name__ == "__main__":
    unittest.main()
