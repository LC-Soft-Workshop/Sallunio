import tempfile
import unittest
from pathlib import Path
from publication_files import audit
from package_release import RUNTIME_FILES, audit_runtime

class PrivacyTests(unittest.TestCase):
    def test_reject_user_files_even_in_source_folders(self):
        for name in ['lib/events.sqlite', 'test/reservations.csv', 'backup.tableo.json',
                     'output/plan.pdf', 'windows/runner/resources/logo-client.png', '.env']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                audit([name])

    def test_reject_personal_files_in_compiled_folder(self):
        workspace_tmp = Path(__file__).resolve().parents[1] / 'tmp'
        workspace_tmp.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=workspace_tmp) as directory:
            root = Path(directory)
            for name in RUNTIME_FILES:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'compiled test fixture')
            audit_runtime(root)
            for name in ['tableo.sqlite', 'data/backup.json', 'reservations.csv', 'plan.pdf']:
                path = root / name
                path.write_bytes(b'PRIVATE SENTINEL')
                with self.assertRaises(ValueError):
                    audit_runtime(root)
                path.unlink()

if __name__ == '__main__':
    unittest.main()
