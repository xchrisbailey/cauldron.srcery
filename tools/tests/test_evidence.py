from __future__ import annotations

import base64
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("evidence", TOOLS / "evidence.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class FakeGitHub:
    def __init__(self, *, branch: str | None):
        self.branch = branch
        self.calls: list[tuple[list[str], dict | None]] = []

    def __call__(self, command, *, input=None, **_):
        body = json.loads(input) if input else None
        self.calls.append((command, body))
        args = command[1:]
        if args[:2] == ["repo", "view"]:
            return self.reply({"nameWithOwner": "owner/repo"})
        path = args[-3] if body is not None else args[-1]
        if path.endswith(f"ref/heads/{evidence.BRANCH}"):
            return self.reply({"object": {"sha": self.branch}}) if self.branch else self.reply(None, "gh: Not Found (HTTP 404)")
        if path.endswith(f"commits/{self.branch}"):
            return self.reply({"tree": {"sha": "oldtree"}})
        if path.endswith("/blobs"):
            return self.reply({"sha": f"blob{len(self.calls)}"})
        if path.endswith("/trees"):
            return self.reply({"sha": "newtree"})
        if path.endswith("/commits"):
            return self.reply({"sha": "newcommit"})
        return self.reply({})

    @staticmethod
    def reply(value, error: str = ""):
        return subprocess.CompletedProcess([], 1 if error else 0, "" if error else json.dumps(value), error)

    def bodies(self, suffix: str) -> list[dict]:
        return [body for command, body in self.calls if body is not None and command[-3].endswith(suffix)]


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.shot = self.folder / "week-dark.png"
        self.shot.write_bytes(b"\x89PNG fake")

    def upload(self, fake: FakeGitHub, *files: Path) -> list[str]:
        with patch.object(evidence.subprocess, "run", side_effect=fake):
            return evidence.upload(262, list(files or [self.shot]))

    def test_first_upload_creates_the_branch_and_links_by_commit(self):
        fake = FakeGitHub(branch=None)
        links = self.upload(fake)
        self.assertEqual(links, ["![week-dark](https://github.com/owner/repo/blob/newcommit/pr-262/week-dark.png?raw=true)"])
        self.assertEqual(fake.bodies("/blobs")[0]["content"], base64.b64encode(b"\x89PNG fake").decode())
        tree = fake.bodies("/trees")[0]
        self.assertNotIn("base_tree", tree)
        self.assertEqual(tree["tree"][0]["path"], "pr-262/week-dark.png")
        self.assertEqual(fake.bodies("/commits")[0]["parents"], [])
        self.assertEqual(fake.bodies("/refs")[0], {"ref": "refs/heads/evidence", "sha": "newcommit"})

    def test_later_upload_adds_to_the_existing_branch(self):
        fake = FakeGitHub(branch="oldcommit")
        self.upload(fake)
        self.assertEqual(fake.bodies("/trees")[0]["base_tree"], "oldtree")
        self.assertEqual(fake.bodies("/commits")[0]["parents"], ["oldcommit"])
        self.assertEqual(fake.bodies("refs/heads/evidence")[0], {"sha": "newcommit"})

    def test_rejects_non_images_and_clashing_names_before_calling_github(self):
        notes = self.folder / "notes.txt"
        notes.write_text("no")
        twin = self.folder / "other"
        twin.mkdir()
        (twin / "week-dark.png").write_bytes(b"x")
        for files in ([notes], [self.shot, twin / "week-dark.png"], [self.folder / "missing.png"]):
            fake = FakeGitHub(branch=None)
            with self.assertRaises(evidence.support.WorkflowError):
                self.upload(fake, *files)
            self.assertEqual(fake.calls, [])


if __name__ == "__main__":
    unittest.main()
