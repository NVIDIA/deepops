import subprocess
import sys
import tempfile
import unittest

from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / 'files' / 'parse_manifest.py'


class ParseManifestTest(unittest.TestCase):
    def test_parse_versioning_rejects_non_dict_json(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            manifest = Path(temp_dir) / 'versioning.json'
            manifest.write_text('[1,2,3]\n')

            result = subprocess.run(
                [sys.executable, str(SCRIPT), 'parse_versioning', str(manifest)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
            )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(
            result.stdout,
            'No JSON could be loaded, is the container already running?\n',
        )
        self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main()
