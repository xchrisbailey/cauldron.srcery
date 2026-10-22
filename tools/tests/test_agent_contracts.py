"""Provider profiles and skill mounts resolve the same repository-owned contracts."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AgentContractTests(unittest.TestCase):
    def test_both_provider_profiles_point_directly_to_the_shared_role(self):
        for role in ("coder", "reviewer", "scout", "shepherd", "adversary"):
            contract = f"docs/agents/roles/{role}.md"
            self.assertTrue((ROOT / contract).is_file())
            for provider in (".claude", ".opencode"):
                profile = (ROOT / provider / "agents" / f"{role}.md").read_text()
                body = profile.split("---", 2)[2]
                self.assertIn(f"`{contract}`", body)
                self.assertNotIn(".claude/agents/", body)
                self.assertNotIn("make ready", body)

    def test_project_skill_mounts_share_one_authoritative_body(self):
        expected = (ROOT / ".agents/skills/implement-spec/SKILL.md").resolve()
        self.assertTrue(expected.is_file())
        for provider in (".claude", ".opencode"):
            mounted = ROOT / provider / "skills/implement-spec/SKILL.md"
            self.assertEqual(mounted.resolve(), expected)
        skill = expected.read_text()
        self.assertRegex(skill, r"(?m)^name: implement-spec$")
        for scenario in ("partial-worker", "zero-test-success", "clean-mechanical-integration"):
            self.assertTrue((expected.parent / "evals" / scenario / "prompt.md").is_file())


if __name__ == "__main__":
    unittest.main()
