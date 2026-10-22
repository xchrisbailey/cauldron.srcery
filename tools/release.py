#!/usr/bin/env python3
"""Fail-closed, local release evidence for Cauldron."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import uuid

import workflow_support as support

TEAM = "5U2B7W5F39"
CONTAINER = "iCloud.computer.srcery.cauldron"
BUNDLE_ID = "computer.srcery.cauldron"
VERSION_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def run(command: list[str], *, cwd: Path) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True, check=False)
    if result.returncode:
        raise support.WorkflowError(result.stderr.strip() or f"Command failed: {command[0]}")
    return result


def version_label(value: str) -> str:
    if not VERSION_RE.fullmatch(value):
        raise support.WorkflowError("Version must be vMAJOR.MINOR.PATCH")
    return value


def project_versions(root: Path) -> tuple[str, str]:
    project = (root / "apple/project.yml").read_text()
    matches = re.findall(r'^\s*MARKETING_VERSION:\s*["\']?([^\s"\']+)', project, re.M)
    if len(matches) != 1:
        raise support.WorkflowError("Expected exactly one MARKETING_VERSION in apple/project.yml")
    generated_text = (root / "apple/Cauldron.xcodeproj/project.pbxproj").read_text()
    generated = set(re.findall(r"\bMARKETING_VERSION\s*=\s*([^;\s]+)\s*;", generated_text))
    if len(generated) != 1:
        raise support.WorkflowError("Expected one consistent generated MARKETING_VERSION")
    return matches[0], generated.pop()


def git_tags(root: Path) -> list[tuple[tuple[int, int, int], str]]:
    tags = support.git("tag", "--list", "v*", cwd=root).splitlines()
    result = []
    for tag in tags:
        match = VERSION_RE.fullmatch(tag)
        if match:
            result.append((tuple(map(int, match.groups())), tag))
    return sorted(result)


def source_map(root: Path, revision: str = "HEAD") -> dict[str, bytes]:
    listing = support.git("ls-tree", "-r", "--name-only", revision, cwd=root).splitlines()
    swift = {name for name in listing if name.endswith(".swift")}
    registry = {name for name in swift if "CauldronStore" in name or "ModelRegistry" in name}
    result = subprocess.run(
        ["git", "grep", "-l", "-I", "-e", "@Model", revision, "--", "*.swift"],
        cwd=root, text=True, capture_output=True, check=False,
    )
    if result.returncode not in (0, 1):
        raise support.WorkflowError(result.stderr.strip() or "git grep failed while scanning model sources")
    model_paths = ({line[len(revision) + 1:] if line.startswith(f"{revision}:") else line
                    for line in result.stdout.splitlines()} if result.returncode == 0 else set())
    selected = model_paths | registry
    if not selected <= swift:
        raise support.WorkflowError("git grep selected a Swift source outside the revision tree")
    return {name: support.git("show", f"{revision}:{name}", cwd=root).encode()
            for name in sorted(selected)}


def model_fingerprint(root: Path) -> str:
    digest = hashlib.sha256()
    for name, content in sorted(source_map(root).items()):
        digest.update(name.encode() + b"\0" + content + b"\0")
    return digest.hexdigest()


def schema_change(root: Path) -> tuple[bool, str | None, str]:
    current = source_map(root)
    tags = git_tags(root)
    ancestors = [tag for _, tag in tags if subprocess.run(
        ["git", "merge-base", "--is-ancestor", tag, "HEAD"], cwd=root,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
    ).returncode == 0]
    previous = max(ancestors, key=lambda tag: next(v for v, t in tags if t == tag), default=None)
    fingerprint = model_fingerprint(root)
    if previous is None:
        return True, None, fingerprint
    before = source_map(root, previous)
    changed = current != before
    return changed, previous, fingerprint


def artifact_digest(app: Path) -> str:
    if not app.is_dir() or app.is_symlink():
        raise support.WorkflowError(f"App bundle does not exist or is not a directory: {app}")
    digest = hashlib.sha256()
    for path in sorted(app.rglob("*")):
        relative = path.relative_to(app).as_posix()
        digest.update(relative.encode() + b"\0")
        if path.is_symlink():
            digest.update(b"link\0" + os.readlink(path).encode())
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
        elif path.is_dir():
            digest.update(b"dir\0")
    return digest.hexdigest()


def signed_entitlements(app: Path, root: Path) -> dict:
    result = run(["codesign", "-d", "--entitlements", ":-", str(app)], cwd=root)
    try:
        return plistlib.loads(result.stdout.encode())
    except (ValueError, plistlib.InvalidFileException) as error:
        raise support.WorkflowError(f"Could not parse signed entitlements for {app}: {error}") from error


def inspect_app(app: Path, environment: str, root: Path) -> dict:
    app = app.resolve()
    verify = run(["codesign", "--verify", "--deep", "--strict", str(app)], cwd=root)
    del verify
    entitlements = signed_entitlements(app, root)
    expected_entitlements = {
        "com.apple.developer.team-identifier": TEAM,
        "com.apple.developer.icloud-container-environment": environment,
    }
    for key, expected in expected_entitlements.items():
        if entitlements.get(key) != expected:
            raise support.WorkflowError(f"{app}: signed entitlement {key} must be {expected}")
    containers = entitlements.get("com.apple.developer.icloud-container-identifiers", [])
    if CONTAINER not in containers:
        raise support.WorkflowError(f"{app}: signed entitlements omit {CONTAINER}")
    plist_path = app / "Contents/Info.plist"
    try:
        with plist_path.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise support.WorkflowError(f"Cannot read app bundle Info.plist {plist_path}: {error}") from error
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise support.WorkflowError(f"{app}: unexpected CFBundleIdentifier")
    return {
        "path": str(app), "environment": environment,
        "version": info.get("CFBundleShortVersionString"),
        "team": TEAM, "container": CONTAINER,
        "digest": artifact_digest(app),
    }


def build(configuration: str) -> dict:
    root = support.repository()
    if configuration not in {"Debug", "Release"}:
        raise support.WorkflowError("Configuration must be Debug or Release")
    before = support.snapshot(root)
    if before["dirty"]:
        raise support.WorkflowError("Build requires a clean checkout")
    state = support.state_directory(root)
    build_id = uuid.uuid4().hex
    derived = state / "builds" / build_id / "DerivedData"
    app = derived / "Build/Products" / configuration / "Cauldron.app"
    command = ["xcodebuild", "-project", "apple/Cauldron.xcodeproj", "-scheme", "Cauldron",
               "-configuration", configuration, "-destination", "platform=macOS",
               "-derivedDataPath", str(derived), "build"]
    run_path, run_record = support.new_run("release-build", command, "macos", "artifact")
    log_path = Path(run_record["log"])
    try:
        with log_path.open("w") as log:
            process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, text=True)
            returncode = process.wait()
        if returncode:
            raise support.WorkflowError(f"xcodebuild failed with exit code {returncode}; log: {log_path}")
        after = support.snapshot(root)
        if before != after:
            raise support.WorkflowError(f"Checkout changed during build; refusing provenance; log: {log_path}")
        env = "Development" if configuration == "Debug" else "Production"
        evidence = inspect_app(app, env, root)
        record = {
            "version": 1, "id": build_id, "configuration": configuration,
            "head": before["head"], "tree": before["tree"], "artifact": evidence,
            "createdAt": time.time(), "runRecord": str(run_path),
        }
        record["signatureDigest"] = hashlib.sha256(
            (evidence["digest"] + json.dumps(signed_entitlements(app.resolve(), root), sort_keys=True)).encode()
        ).hexdigest()
        support.finish_run(run_path, run_record, "passed", configuration=configuration,
                           artifact=evidence, buildRecord=build_id)
        manifest = state / "builds" / f"{configuration.lower()}-{build_id}.json"
        support.write_json(manifest, record)
        record["record"] = str(manifest)
        return record
    except (OSError, support.WorkflowError) as error:
        details = {"error": str(error), "log": str(log_path)}
        if "returncode" in locals():
            details["returncode"] = returncode
        try:
            support.finish_run(run_path, run_record, "build-failed", **details)
        except support.WorkflowError:
            pass
        raise


def attest(phase: str, version: str, note: str) -> dict:
    root = support.repository()
    version_label(version)
    note = note.strip()
    if not note:
        raise support.WorkflowError("Attestation note must not be empty")
    snapshot = support.snapshot(root)
    if snapshot["dirty"]:
        raise support.WorkflowError("Schema attestation requires a clean checkout")
    changed, _, fingerprint = schema_change(root)
    path = support.state_directory(root) / "schemas" / f"{phase}-{version}-{snapshot['head']}-{fingerprint}.json"
    if phase == "deployed":
        initialized = support.state_directory(root) / "schemas" / f"initialized-{version}-{snapshot['head']}-{fingerprint}.json"
        if not initialized.exists():
            raise support.WorkflowError("Deployment attestation requires matching initialization attestation")
        prior = support.read_json(initialized)
        if (prior.get("phase") != "initialized" or prior.get("head") != snapshot["head"]
                or prior.get("release") != version or prior.get("fingerprint") != fingerprint
                or not prior.get("note") or not prior.get("author")
                or not isinstance(prior.get("createdAt"), (int, float)) or not prior.get("id")):
            raise support.WorkflowError("Deployment attestation requires valid matching initialization evidence")
    author = run(["git", "config", "user.name"], cwd=root).stdout.strip()
    if not author:
        raise support.WorkflowError("Schema attestation requires git user.name as the human author")
    record = {
        "version": 1, "id": hashlib.sha256(str(path).encode()).hexdigest(),
        "phase": phase, "release": version, "head": snapshot["head"],
        "fingerprint": fingerprint, "note": note, "author": author,
        "createdAt": time.time(), "schemaChanged": changed,
    }
    support.write_json(path, record)
    return record


def preflight(version: str, debug_path: Path, release_path: Path) -> dict:
    root = support.repository()
    version_label(version)
    snapshot = support.snapshot(root)
    if snapshot["dirty"]:
        raise support.WorkflowError("Preflight requires a clean checkout")
    source_version, generated_version = project_versions(root)
    expected = version[1:]
    if source_version != expected or generated_version != expected:
        raise support.WorkflowError("Requested version must match project.yml and generated project version")
    if version in support.git("tag", "--list", version, cwd=root).splitlines():
        raise support.WorkflowError(f"Tag already exists: {version}")
    records = []
    for path, record in support.run_records(root):
        if support.full_checks_for(record, snapshot["head"], snapshot["tree"]):
            records.append((path, record))
    if not records:
        raise support.WorkflowError("Missing current reproducible full check evidence")
    check_path, check = records[-1]
    debug = inspect_app(debug_path, "Development", root)
    release = inspect_app(release_path, "Production", root)
    if debug["version"] != expected or release["version"] != expected:
        raise support.WorkflowError("Signed app bundle version does not match requested version")
    builds = list((support.state_directory(root) / "builds").glob("*.json"))
    artifacts = []
    for evidence, configuration in ((debug, "Debug"), (release, "Release")):
        matches = []
        for path in builds:
            record = support.read_json(path)
            recorded_id = path.stem.removeprefix(f"{configuration.lower()}-")
            signature_digest = hashlib.sha256(
                (evidence["digest"] + json.dumps(signed_entitlements(Path(evidence["path"]), root), sort_keys=True)).encode()
            ).hexdigest()
            run_path = Path(record.get("runRecord", ""))
            run_record = support.read_json(run_path) if run_path.is_file() else {}
            if (record.get("version") == 1 and record.get("configuration") == configuration
                    and record.get("head") == snapshot["head"] and record.get("tree") == snapshot["tree"]
                    and record.get("id") == recorded_id
                    and record.get("artifact", {}).get("path") == evidence["path"]
                    and record.get("artifact", {}).get("digest") == evidence["digest"]
                    and record.get("signatureDigest") == signature_digest):
                if (run_record.get("kind") == "release-build"
                        and run_record.get("configuration") == configuration
                        and run_record.get("buildRecord") == record.get("id")
                        and support.successful_for(run_record, snapshot["head"], scope="artifact")
                        and run_record.get("artifact", {}).get("path") == evidence["path"]
                        and run_record.get("artifact", {}).get("digest") == evidence["digest"]):
                    matches.append(record)
        if not matches:
            raise support.WorkflowError(f"Missing exact-revision {configuration} build provenance for artifact")
        artifacts.append({**evidence, "buildRecord": matches[-1]["id"], "revision": snapshot["head"]})
    changed, previous, fingerprint = schema_change(root)
    schema = {"changedSincePreviousRelease": changed, "previousRelease": previous,
              "fingerprint": fingerprint, "attestations": []}
    if changed:
        for phase in ("initialized", "deployed"):
            path = support.state_directory(root) / "schemas" / f"{phase}-{version}-{snapshot['head']}-{fingerprint}.json"
            if not path.exists():
                raise support.WorkflowError(f"Missing or stale {phase} schema attestation")
            record = support.read_json(path)
            if (record.get("phase") != phase or record.get("head") != snapshot["head"]
                    or record.get("release") != version or record.get("fingerprint") != fingerprint
                    or not record.get("note") or not record.get("author")
                    or not isinstance(record.get("createdAt"), (int, float)) or not record.get("id")):
                raise support.WorkflowError(f"Missing or stale {phase} schema attestation")
            schema["attestations"].append(record["id"])
        schema["status"] = "initialized and deployed attestations recorded"
    else:
        schema["status"] = "unchanged; no deployment attestation required"
    schema["attestationsAreLocalRecordsNotRemoteVerification"] = True
    # Recheck the tree/head after all evidence reads and app inspection.
    if support.snapshot(root) != snapshot:
        raise support.WorkflowError("Checkout changed during preflight")
    output = {
        "version": 1, "status": "passed", "head": snapshot["head"], "tree": snapshot["tree"],
        "label": version, "artifacts": artifacts,
        "checkrecord": str(check_path), "schema": schema,
    }
    destination = support.state_directory(root) / "releases" / f"{version}.json"
    support.write_json(destination, output)
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    schema = commands.add_parser("record-schema")
    schema.add_argument("version")
    schema.add_argument("--phase", required=True, choices=("initialized", "deployed"))
    schema.add_argument("--note", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--configuration", required=True, choices=("Debug", "Release"))
    check = commands.add_parser("preflight")
    check.add_argument("version")
    check.add_argument("--debug-app", required=True, type=Path)
    check.add_argument("--release-app", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "record-schema":
            value = attest(args.phase, args.version, args.note)
        elif args.command == "build":
            value = build(args.configuration)
        else:
            value = preflight(args.version, args.debug_app, args.release_app)
        print(json.dumps(value, indent=2, sort_keys=True))
        return 0
    except (support.WorkflowError, OSError) as error:
        print(f"release: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
