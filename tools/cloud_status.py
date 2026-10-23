#!/usr/bin/env python3
"""Read-only, exact-commit Xcode Cloud status from App Store Connect."""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = "api.appstoreconnect.apple.com"
BASE = f"https://{HOST}/v1"
PAGE_LIMIT = 10


class StatusError(Exception):
    pass


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    inline = os.environ.get("ASC_TOKEN")
    if inline:
        return inline
    key_id, issuer, private_key = (os.environ.get(name) for name in
                                   ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_FILE"))
    if not (key_id and issuer and private_key):
        raise StatusError("Credentials missing. Set ASC_TOKEN, or ASC_KEY_ID, ASC_ISSUER_ID, and ASC_PRIVATE_KEY_FILE.")
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 900,
                               "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing = f"{header}.{claims}".encode()
    try:
        signature = subprocess.run(["openssl", "dgst", "-sha256", "-sign", private_key],
                                   input=signing, capture_output=True, check=True).stdout
        # OpenSSL emits ASN.1 DER ECDSA; JWT requires fixed-width r || s.
        return f"{header}.{claims}.{b64url(der_to_raw(signature))}"
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        raise StatusError("Could not create App Store Connect token; verify OpenSSL and private-key configuration.") from error


def der_to_raw(signature: bytes) -> bytes:
    """Convert an OpenSSL P-256 DER signature to the JWT 64-byte representation."""
    if len(signature) < 8 or signature[0] != 0x30:
        raise ValueError("invalid ECDSA signature")
    pos = 2
    if signature[1] & 0x80:
        n = signature[1] & 0x7f
        pos = 2 + n
    values = []
    for _ in range(2):
        if signature[pos] != 2:
            raise ValueError("invalid ECDSA integer")
        length = signature[pos + 1]
        value = signature[pos + 2:pos + 2 + length].lstrip(b"\0")
        values.append(value.rjust(32, b"\0"))
        pos += 2 + length
    raw = b"".join(values)
    if len(raw) != 64:
        raise ValueError("invalid P-256 signature length")
    return raw


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise StatusError("App Store Connect returned a redirect; refusing to forward credentials.")


def get_json(url: str, bearer: str) -> dict:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != HOST or parsed.port not in (None, 443):
        raise StatusError("Refusing an untrusted App Store Connect URL.")
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {bearer}",
                                                    "Accept": "application/json"}, method="GET")
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(request, timeout=20) as response:
            return json.loads(response.read())
    except StatusError:
        raise
    except urllib.error.HTTPError as error:
        raise StatusError(f"App Store Connect request failed with HTTP {error.code}.") from None
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        raise StatusError("App Store Connect request failed (network or invalid response).") from None


def resource(url: str, bearer: str) -> dict:
    data = get_json(url, bearer).get("data")
    if not isinstance(data, dict):
        raise StatusError("App Store Connect response omitted the requested resource.")
    return data


def pages(url: str, bearer: str) -> list[dict]:
    result, seen = [], set()
    for _ in range(PAGE_LIMIT):
        if url in seen:
            raise StatusError("App Store Connect pagination loop detected.")
        seen.add(url)
        response = get_json(url, bearer)
        data = response.get("data", [])
        if not isinstance(data, list):
            raise StatusError("App Store Connect returned an invalid collection.")
        result.extend(item for item in data if isinstance(item, dict))
        nxt = response.get("links", {}).get("next")
        if not nxt:
            return result
        url = urllib.parse.urljoin(BASE + "/", nxt)
        # Validate before the next request; never send the bearer to a foreign host.
        parsed = urllib.parse.urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname != HOST:
            raise StatusError("Refusing an untrusted pagination URL.")
    raise StatusError("App Store Connect pagination exceeded the safety limit.")


def exact_run_commit(run: dict) -> tuple[str, str, dict]:
    attrs = run.get("attributes")
    if not isinstance(attrs, dict) or type(attrs.get("isPullRequestBuild")) is not bool:
        raise StatusError("Build run is missing Apple's documented isPullRequestBuild boolean.")
    field = "sourceCommit" if attrs["isPullRequestBuild"] else "destinationCommit"
    metadata = attrs.get(field)
    if not isinstance(metadata, dict):
        raise StatusError(f"Build run is missing Apple's {field} commit metadata object.")
    sha = metadata.get("commitSha")
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        raise StatusError(f"Build run has no valid {field}.commitSha.")
    return sha.lower(), field, attrs


def status(commit: str, version: str | None = None, tag: str | None = None,
           build_run_id: str | None = None, workflow_id: str | None = None) -> dict:
    if not re.fullmatch(r"[0-9a-fA-F]{40,64}", commit):
        raise StatusError("Commit must be an exact 40- or 64-character hexadecimal SHA.")
    bearer = token()
    run_data = None
    if build_run_id:
        run_data = resource(f"{BASE}/ciBuildRuns/{urllib.parse.quote(build_run_id, safe='')}", bearer)
    elif workflow_id:
        runs = pages(f"{BASE}/ciWorkflows/{urllib.parse.quote(workflow_id, safe='')}/buildRuns?limit=200", bearer)
        for item in runs:
            run_commit, _, _ = exact_run_commit(item)
            if run_commit == commit.lower():
                run_data = item
                break
    else:
        raise StatusError("Provide --build-run-id or --workflow-id to query a bounded resource collection.")
    if run_data is None:
        return {"status": "not-found", "requestedCommit": commit, "verifiedCommit": None,
                "version": version, "versionStatus": "unknown",
                "buildRun": None, "message": "No build run for the exact requested commit."}
    verified_commit, commit_field, attrs = exact_run_commit(run_data)
    if verified_commit != commit.lower():
        raise StatusError("The requested build run belongs to a different commit.")
    run_id = run_data.get("id")
    builds = pages(f"{BASE}/ciBuildRuns/{urllib.parse.quote(str(run_id), safe='')}/builds?limit=200", bearer)
    build_versions = [b.get("attributes", {}).get("version") for b in builds
                      if isinstance(b.get("attributes"), dict)]
    matching_versions = [v for v in build_versions if isinstance(v, str)]
    if version is None:
        version_status = "unknown"
    elif version in matching_versions:
        version_status = "matched"
    elif matching_versions and len(matching_versions) == len(build_versions):
        version_status = "mismatch"
    else:
        version_status = "unknown"
    return {"status": attrs.get("completionStatus") or attrs.get("executionProgress") or "unknown",
            "requestedCommit": commit, "verifiedCommit": verified_commit,
            "commitField": f"attributes.{commit_field}.commitSha",
            "commitType": "pull-request-source" if attrs["isPullRequestBuild"] else "branch-or-tag-destination",
            "version": version, "versionStatus": version_status,
            "tag": tag, "buildRun": {"id": run_id, "url": f"https://appstoreconnect.apple.com/ci/builds/{urllib.parse.quote(str(run_id), safe='')}",
                                      "progress": attrs.get("executionProgress"),
                                      "completion": attrs.get("completionStatus")},
            "builds": [{"id": b.get("id"), "platform": b.get("attributes", {}).get("platform"),
                        "version": b.get("attributes", {}).get("version"),
                        "processingState": b.get("attributes", {}).get("processingState")} for b in builds]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("commit")
    parser.add_argument("--version")
    parser.add_argument("--tag")
    parser.add_argument("--build-run-id")
    parser.add_argument("--workflow-id")
    args = parser.parse_args(argv)
    try:
        print(json.dumps(status(args.commit, args.version, args.tag, args.build_run_id, args.workflow_id), indent=2))
        return 0
    except StatusError as error:
        print(f"cloud-status: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
