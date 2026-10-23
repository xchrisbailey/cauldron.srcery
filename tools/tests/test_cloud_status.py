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

    def test_exact_commit_build_status_and_missing_version_is_unknown(self):
        run = {"id": "R1", "attributes": {"sourceCommit": self.commit,
               "executionProgress": "COMPLETE", "completionStatus": "SUCCEEDED"}}
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=run), \
             patch.object(cloud, "pages", return_value=[{"id": "B1", "attributes": {"platform": "IOS"}}]):
            result = cloud.status(self.commit, build_run_id="R1")
        self.assertEqual(result["verifiedCommit"], self.commit)
        self.assertEqual(result["versionStatus"], "unknown")
        self.assertEqual(result["builds"][0]["platform"], "IOS")

    def test_wrong_commit_fails_and_run_retries_remain_raw(self):
        wrong = {"id": "R1", "attributes": {"sourceCommit": "b" * 40}}
        with patch.object(cloud, "token", return_value="safe"), patch.object(cloud, "resource", return_value=wrong):
            with self.assertRaises(cloud.StatusError):
                cloud.status(self.commit, build_run_id="R1")

    def test_retry_progress_is_reported_without_success_translation(self):
        retry = {"id": "R2", "attributes": {"sourceCommit": self.commit,
                 "executionProgress": "PENDING", "completionStatus": None}}
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "resource", return_value=retry), patch.object(cloud, "pages", return_value=[]):
            result = cloud.status(self.commit, build_run_id="R2")
        self.assertEqual(result["status"], "PENDING")
        self.assertIsNone(result["buildRun"]["completion"])

    def test_pagination_collects_all_pages(self):
        first = {"data": [{"id": "B1"}], "links": {"next": f"{cloud.BASE}/ciBuildRuns?page=2"}}
        second = {"data": [{"id": "B2"}], "links": {}}
        with patch.object(cloud, "get_json", side_effect=[first, second]):
            result = cloud.pages(f"{cloud.BASE}/ciBuildRuns?page=1", "safe")
        self.assertEqual([item["id"] for item in result], ["B1", "B2"])
    def test_workflow_run_listing_never_selects_another_commit(self):
        with patch.object(cloud, "token", return_value="safe"), \
             patch.object(cloud, "pages", return_value=[{"id": "R1", "attributes": {"sourceCommit": "b" * 40}}]):
            result = cloud.status(self.commit, workflow_id="WF", version="1.2.3")
        self.assertEqual(result["status"], "not-found")
        self.assertIsNone(result["verifiedCommit"])
        self.assertEqual(result["versionStatus"], "not-verified")

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
