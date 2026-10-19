"""Offline contract tests: missing/unsafe files must never report a ready cache."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "validate_model_cache.py"
REVISION = "a" * 40


class ModelCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.cache = Path(self.temp.name) / "hub"
        self.repo = self.cache / "models--example--model"
        self.snapshot = self.repo / "snapshots" / REVISION
        self.snapshot.mkdir(parents=True)
        self.blobs = self.repo / "blobs"
        self.blobs.mkdir()
        (self.blobs / "config").write_text('{"model_type": "example"}')
        (self.snapshot / "config.json").symlink_to("../../blobs/config")

    def run_validator(self, *extra, success=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--json", "--cache-dir", str(self.cache),
             "--repo-id", "example/model", "--revision", REVISION,
             "--require-file", "config.json", *extra],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr + result.stdout)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["ok"], success)
        self.assertEqual(payload["schema_version"], 1)
        return payload

    def test_pinned_symlink_snapshot_is_readable(self):
        result = self.run_validator()
        self.assertEqual(result["snapshot_path"], str(self.snapshot))
        self.assertEqual(result["checked_files"], ["config.json"])

    def test_direct_files_supported(self):
        (self.snapshot / "weights.safetensors").write_bytes(b"weights")
        self.run_validator("--require-file", "weights.safetensors")

    def test_shared_blob_store_supported(self):
        shared = self.cache / "blobs"
        shared.mkdir()
        (shared / "data").write_bytes(b"shared")
        (self.blobs / "config").unlink()
        (self.blobs / "config").symlink_to("../../blobs/data")
        self.run_validator()

    def test_missing_required_weight_fails(self):
        self.run_validator("--require-file", "weights.safetensors", success=False)

    def test_broken_blob_link_fails(self):
        (self.blobs / "config").unlink()
        self.run_validator(success=False)

    def test_empty_required_file_fails(self):
        (self.blobs / "config").write_bytes(b"")
        self.run_validator(success=False)

    def test_unreadable_blob_fails(self):
        if os.geteuid() == 0:
            self.skipTest("root bypasses file permissions")
        (self.blobs / "config").chmod(0)
        self.run_validator(success=False)

    def test_mutable_revision_rejected(self):
        self.run_validator("--revision", "main", success=False)

    def test_absent_revision_rejected(self):
        self.run_validator("--revision", "b" * 40, success=False)

    def test_repo_traversal_rejected(self):
        self.run_validator("--repo-id", "../model", success=False)

    def test_file_traversal_rejected(self):
        self.run_validator("--require-file", "../config.json", success=False)

    def test_absolute_file_rejected(self):
        self.run_validator("--require-file", "/etc/passwd", success=False)

    def test_external_blob_rejected(self):
        outside = Path(self.temp.name) / "outside"
        outside.write_text("not cache data")
        (self.blobs / "config").unlink()
        (self.blobs / "config").symlink_to(outside)
        self.run_validator(success=False)

    def test_external_snapshot_rejected(self):
        outside = Path(self.temp.name) / "outside"
        outside.mkdir()
        (outside / "config.json").write_text("not a snapshot")
        (self.snapshot / "config.json").unlink()
        self.snapshot.rmdir()
        self.snapshot.symlink_to(outside, target_is_directory=True)
        self.run_validator(success=False)

    def test_directory_not_a_file(self):
        (self.snapshot / "folder").mkdir()
        self.run_validator("--require-file", "folder", success=False)

    def test_fifo_rejected_without_blocking(self):
        os.mkfifo(self.snapshot / "fifo")
        self.run_validator("--require-file", "fifo", success=False)

    def test_nested_file_supported(self):
        (self.snapshot / "sub").mkdir()
        (self.snapshot / "sub" / "weights").write_bytes(b"weights")
        self.run_validator("--require-file", "sub/weights")

    def test_read_only_cache_not_modified(self):
        before = {str(p): p.lstat().st_mtime_ns for p in self.cache.rglob("*")}
        self.cache.chmod(0o550)
        self.addCleanup(self.cache.chmod, 0o750)
        self.run_validator()
        after = {str(p): p.lstat().st_mtime_ns for p in self.cache.rglob("*")}
        self.assertEqual(before, after)

    def test_missing_cache_not_created(self):
        missing = Path(self.temp.name) / "missing"
        self.run_validator("--cache-dir", str(missing), success=False)
        self.assertFalse(missing.exists())

    def test_required_files_cannot_be_omitted(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--cache-dir", str(self.cache),
             "--repo-id", "example/model", "--revision", REVISION],
            capture_output=True, text=True, timeout=5,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
