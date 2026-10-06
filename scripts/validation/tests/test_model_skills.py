"""Offline documentation contracts; these do not test agent behavior or GPUs."""
import pathlib
import re
import shlex
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[3]
SKILLS = ("model-workflows", "serve-model", "finetune-model")


class ModelSkillDocsTest(unittest.TestCase):
    def skill(self, name):
        path = ROOT / "skills" / name / "SKILL.md"
        self.assertTrue(path.is_file(), f"Missing skill: {name}")
        return path, path.read_text()

    def test_discovery(self):
        for name in SKILLS:
            with self.subTest(skill=name):
                _, text = self.skill(name)
                self.assertIn(f"name: {name}\n", text)
                self.assertRegex(text, r"(?m)^description: Use when .+")
                for index in ("AGENTS.md", "skills/README.md"):
                    self.assertIn(f"{name}/", (ROOT / index).read_text())

    def test_relative_links_exist(self):
        for name in SKILLS:
            path, text = self.skill(name)
            links = re.findall(r"\[[^\]]+\]\(([^)]+)\)", text)
            self.assertTrue(links)
            for link in links:
                with self.subTest(skill=name, link=link):
                    self.assertNotIn("://", link)
                    self.assertTrue((path.parent / link.split("#")[0]).is_file())

    def test_serving_command_matches_quickstart(self):
        _, text = self.skill("serve-model")
        quickstart = (ROOT / "docs/model-workflows/vllm-quickstart.md").read_text()
        commands = re.findall(r"```bash\n(.*?)\n```", text, re.S)
        self.assertEqual(len(commands), 1)
        command = commands[0]
        self.assertIn(command, quickstart)
        args = shlex.split(command.replace("\\\n", " "))
        self.assertEqual(args[:2], ["python3", "scripts/validation/validate_vllm.py"])
        # --help parses the real CLI without touching the cache or endpoint.
        result = subprocess.run(args + ["--help"], cwd=ROOT,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        for flag in args[2:]:
            if flag.startswith("--"):
                self.assertIn(flag, result.stdout)


if __name__ == "__main__":
    unittest.main()
