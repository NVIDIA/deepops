"""Exercise actual playbook tasks on scratch storage, with synthetic mount facts.

This proves guards, permissions and idempotence, not NFS behavior. No mounts,
remote hosts, users, packages or services are created by this fixture.
"""
import getpass
import grp
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[3]


@unittest.skipUnless(shutil.which("ansible-playbook"), "ansible-playbook required")
class ModelCachePlaybookTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.mount = Path(self.temp.name) / "shared"
        self.mount.mkdir()
        self.root = self.mount / "hf-cache"
        self.play = yaml.safe_load((ROOT / "playbooks/model-cache.yml").read_text())[0]
        self.play.update(hosts="all", gather_facts=False, connection="local")
        self.hosts = "localhost ansible_connection=local\n"
        self.site_vars = dict(
            model_cache_mount=str(self.mount), model_cache_owner=getpass.getuser(),
            model_cache_group=grp.getgrgid(os.getgid()).gr_name,
            ansible_become=False,
            ansible_mounts=[{"mount": str(self.mount), "fstype": "nfs4"}],
        )

    def run_play(self, success=True, check=False):
        path = Path(self.temp.name) / "fixture.yml"
        path.write_text(yaml.safe_dump([self.play]))
        config = Path(self.temp.name) / "ansible.cfg"
        config.write_text("[defaults]\nretry_files_enabled = False\n")
        env = dict(os.environ, ANSIBLE_CONFIG=str(config), ANSIBLE_NOCOLOR="1",
                   ANSIBLE_LOCAL_TEMP=str(Path(self.temp.name) / "ansible-local"),
                   ANSIBLE_REMOTE_TEMP=str(Path(self.temp.name) / "ansible-remote"))
        inventory = Path(self.temp.name) / "inventory"
        inventory.mkdir(exist_ok=True)
        (inventory / "hosts").write_text(self.hosts)
        (inventory / "group_vars").mkdir(exist_ok=True)
        (inventory / "group_vars" / "all.yml").write_text(yaml.safe_dump(self.site_vars))
        cmd = ["ansible-playbook", "-i", str(inventory), str(path)]
        if check:
            cmd.append("--check")
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0 if success else 2, result.stdout + result.stderr)
        return result.stdout

    def test_create_environment_permissions_and_idempotence(self):
        self.run_play()
        self.assertEqual(self.root.stat().st_mode & 0o7777, 0o2750)
        self.assertEqual((self.root / "hub").stat().st_mode & 0o7777, 0o2750)
        script = self.root / "environment.sh"
        self.assertEqual(script.stat().st_mode & 0o777, 0o640)
        result = subprocess.run(
            ["sh", "-c", '. "$1"; printf "%s|%s" "$HF_HUB_CACHE" "$HF_HOME"', "sh", str(script)],
            env={"PATH": os.environ["PATH"], "HF_HOME": "/private/user-cache"},
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(result.stdout, str(self.root / "hub") + "|/private/user-cache")
        self.assertIn("changed=0", self.run_play())

    def test_multiple_writers_rejected_before_cache_creation(self):
        self.hosts += "second-writer ansible_connection=local\n"
        self.run_play(success=False)
        self.assertFalse(self.root.exists())

    def test_absent_mount_fails_before_creating_cache(self):
        self.site_vars["ansible_mounts"] = []
        self.run_play(success=False)
        self.assertFalse(self.root.exists())

    def test_local_filesystem_fails(self):
        self.site_vars["ansible_mounts"][0]["fstype"] = "ext4"
        self.run_play(success=False)
        self.assertFalse(self.root.exists())

    def test_cache_cannot_be_mount_root(self):
        self.site_vars["model_cache_root"] = str(self.mount)
        self.run_play(success=False)
        self.assertFalse((self.mount / "hub").exists())

    def test_cache_cannot_escape_mount(self):
        self.site_vars["model_cache_root"] = str(self.mount) + "/../escape"
        self.run_play(success=False)
        self.assertFalse((self.mount.parent / "escape").exists())

    def test_symlink_cache_rejected(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        self.root.symlink_to(outside)
        self.run_play(success=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlink_hub_rejected(self):
        self.root.mkdir()
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (self.root / "hub").symlink_to(outside)
        self.run_play(success=False)
        self.assertEqual(list(outside.iterdir()), [])

    def test_inventory_can_choose_dedicated_cache_child(self):
        custom = self.mount / "models"
        self.site_vars["model_cache_root"] = str(custom)
        self.run_play()
        self.assertTrue((custom / "hub").is_dir())
        self.assertFalse(self.root.exists())

    def test_check_mode_has_no_cache_side_effects(self):
        self.run_play(check=True)
        self.assertFalse(self.root.exists())


if __name__ == "__main__":
    unittest.main()
