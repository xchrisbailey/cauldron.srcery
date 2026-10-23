from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / "cloud_status.py"
spec = importlib.util.spec_from_file_location("cloud_status", SOURCE)
cloud = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cloud)


class CloudStatusTests(unittest.TestCase):
    commit = "a" * 40

    def run_fixture(self, *, run_id="R1", is_pr=False, source=None, destination=None, progress="COMPLETE", completion="SUCCEEDED"):
        return {"id": run_id, "type": "ciBuildRuns", "attributes": {
               "isPullRequestBuild": is_pr,
               "sourceCommit": {"commitSha": source or "b" * 40, "message": "source"},
               "destinationCommit": {"commitSha": destination or self.commit, "message": "destination"},
               "executionProgress": progress, "completionStatus": completion}}

    @staticmethod
    def prerelease(version="1.2.3", platform="IOS"):
        return {"data": {"id": "P1", "type": "preReleaseVersions",
                         "attributes": {"version": version, "platform": platform}}}

    def test_build_run_uses_destination_commit_and_prerelease_version_and_platform(self):
        run = self.run_fixture()
        build = {"id": "B1", "type": "builds", "attributes": {
            "version": "42", "processingState": "VALID"}}
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=run), \
             patch.object(cloud, "pages", return_value=[build]), \
             patch.object(cloud, "get_json", return_value=self.prerelease()):
            result = cloud.status(self.commit, version="1.2.3", build_run_id="R1")
        self.assertEqual(result["verifiedCommit"], self.commit)
        self.assertEqual(result["commitField"], "attributes.destinationCommit.commitSha")
        self.assertEqual(result["commitType"], "branch-or-tag-destination")
        self.assertEqual(result["versionStatus"], "matched")
        self.assertEqual(result["builds"][0]["platform"], "IOS")
        self.assertEqual(result["builds"][0]["marketingVersion"], "1.2.3")
        self.assertEqual(result["builds"][0]["buildNumber"], "42")

    def test_64_character_commit_sha_matches_api_metadata(self):
        sha = "d" * 64
        run = self.run_fixture(destination=sha)
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=run), patch.object(cloud, "pages", return_value=[]):
            result = cloud.status(sha, build_run_id="R1")
        self.assertEqual(result["verifiedCommit"], sha)

    def test_workflow_uses_pr_source_commit_object(self):
        run = self.run_fixture(is_pr=True, source=self.commit, destination="c" * 40)
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "pages", side_effect=[[run], []]):
            result = cloud.status(self.commit, workflow_id="WF")
        self.assertEqual(result["verifiedCommit"], self.commit)
        self.assertEqual(result["commitField"], "attributes.sourceCommit.commitSha")
        self.assertEqual(result["commitType"], "pull-request-source")

    def test_requested_version_mismatch_is_reported(self):
        build = {"id": "B1", "attributes": {"version": "42"}}
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=self.run_fixture()), \
             patch.object(cloud, "pages", return_value=[build]), \
             patch.object(cloud, "get_json", return_value=self.prerelease(version="1.2.2")):
            result = cloud.status(self.commit, version="1.2.3", build_run_id="R1")
        self.assertEqual(result["versionStatus"], "mismatch")

    def test_missing_prerelease_relationship_is_unknown(self):
        build = {"id": "B1", "attributes": {"version": "42"}}
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=self.run_fixture()), \
             patch.object(cloud, "pages", return_value=[build]), \
             patch.object(cloud, "get_json", return_value={"data": None}):
            result = cloud.status(self.commit, version="1.2.3", build_run_id="R1")
        self.assertEqual(result["versionStatus"], "unknown")
        self.assertIsNone(result["builds"][0]["marketingVersion"])
        self.assertIsNone(result["builds"][0]["platform"])

    def test_multiple_builds_keep_each_marketing_version_build_number_and_platform(self):
        builds = [
            {"id": "B1", "attributes": {"version": "42", "processingState": "VALID"}},
            {"id": "B2", "attributes": {"version": "43", "processingState": "PROCESSING"}},
        ]
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=self.run_fixture()), \
             patch.object(cloud, "pages", return_value=builds), \
             patch.object(cloud, "get_json", side_effect=[self.prerelease("1.2.3", "IOS"),
                                                            self.prerelease("1.2.3", "MAC_OS")]):
            result = cloud.status(self.commit, version="1.2.3", build_run_id="R1")
        self.assertEqual(result["versionStatus"], "matched")
        self.assertEqual([(b["buildNumber"], b["marketingVersion"], b["platform"]) for b in result["builds"]],
                         [("42", "1.2.3", "IOS"), ("43", "1.2.3", "MAC_OS")])

    def test_build_run_rejects_commit_mismatch_and_missing_documented_shape(self):
        with patch.object(cloud, "token", return_value="safe"), patch.object(cloud, "resource", return_value=self.run_fixture(destination="d" * 40)):
            with self.assertRaisesRegex(cloud.StatusError, "different commit"):
                cloud.status(self.commit, build_run_id="R1")
        malformed = {"id": "R1", "attributes": {"sourceCommit": {"commitSha": self.commit}}}
        with patch.object(cloud, "token", return_value="safe"), patch.object(cloud, "resource", return_value=malformed):
            with self.assertRaisesRegex(cloud.StatusError, "isPullRequestBuild"):
                cloud.status(self.commit, build_run_id="R1")

    def test_missing_version_is_unknown(self):
        run = self.run_fixture()
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=run), patch.object(cloud, "pages", return_value=[]):
            result = cloud.status(self.commit, version="1.2.3", build_run_id="R1")
        self.assertEqual(result["versionStatus"], "unknown")

    def test_retry_progress_is_reported_without_success_translation(self):
        retry = self.run_fixture(progress="PENDING", completion=None)
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=retry), patch.object(cloud, "pages", return_value=[]):
            result = cloud.status(self.commit, build_run_id="R2")
        self.assertEqual(result["status"], "PENDING")
        self.assertIsNone(result["buildRun"]["completion"])

    def test_build_status_not_synthetic(self):
        run = self.run_fixture(progress="COMPLETE", completion="SUCCEEDED")
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=run), patch.object(cloud, "pages", return_value=[]):
            result = cloud.status(self.commit, build_run_id="R1")
        self.assertEqual(result["status"], "SUCCEEDED")

    def test_pagination_collects_all_pages(self):
        first = {"data": [{"id": "B1"}], "links": {"next": f"{cloud.BASE}/ciBuildRuns?page=2"}}
        second = {"data": [{"id": "B2"}], "links": {}}
        with patch.object(cloud, "get_json", side_effect=[first, second]):
            result = cloud.pages(f"{cloud.BASE}/ciBuildRuns?page=1", "safe")
        self.assertEqual([item["id"] for item in result], ["B1", "B2"])
    def test_workflow_listing_never_selects_another_commit(self):
        wrong = self.run_fixture(destination="b" * 40)
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "pages", return_value=[wrong]):
            result = cloud.status(self.commit, workflow_id="WF", version="1.2.3")
        self.assertEqual(result["status"], "not-found")
        self.assertIsNone(result["verifiedCommit"])
        self.assertEqual(result["versionStatus"], "unknown")

    def test_credentials_and_transport_failures_are_sanitized(self):
        with patch.dict("os.environ", {}, clear=True):
            with self.assertRaisesRegex(cloud.StatusError, "Credentials missing"):
                cloud.token()
        for url in ("https://evil.example/path", "http://api.appstoreconnect.apple.com/v1/x"):
            with self.assertRaisesRegex(cloud.StatusError, "untrusted"):
                cloud.get_json(url, "never-print-this")

    def test_pagination_rejects_untrusted_next_url_and_is_bounded(self):
        first = {"data": [], "links": {"next": "https://evil.example/steal"}}
        with patch.object(cloud, "get_json", return_value=first):
            with self.assertRaisesRegex(cloud.StatusError, "untrusted pagination"):
                cloud.pages(f"{cloud.BASE}/ciBuildRuns?limit=200", "secret")
        retry = {"data": [], "links": {"next": f"{cloud.BASE}/ciBuildRuns?page=2"}}
        with patch.object(cloud, "get_json", return_value=retry):
            with self.assertRaisesRegex(cloud.StatusError, "pagination loop"):
                cloud.pages(f"{cloud.BASE}/ciBuildRuns?page=1", "secret")

    def test_auth_error_does_not_disclose_response_or_token(self):
        error = type("HTTPError", (Exception,), {"code": 401})()
        with patch.object(cloud.urllib.request, "build_opener") as opener:
            opener.return_value.open.side_effect = __import__("urllib.error").error.HTTPError(
                f"{cloud.BASE}/x", 401, "unauthorized secret", {}, None)
            with self.assertRaisesRegex(cloud.StatusError, "HTTP 401") as caught:
                cloud.get_json(f"{cloud.BASE}/x", "private-token")
        self.assertNotIn("private-token", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
