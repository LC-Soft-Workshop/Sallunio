import tempfile
import unittest
from pathlib import Path
from publication_files import audit
from package_release import RUNTIME_FILES, PUBLIC_FILES, audit_runtime, package

class PrivacyTests(unittest.TestCase):
    def test_local_build_reuses_one_folder_and_refuses_to_overwrite_user_data(self):
        workspace_tmp = Path(__file__).resolve().parents[1] / 'tmp'
        workspace_tmp.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=workspace_tmp) as directory:
            root=Path(directory)
            (root/'lib').mkdir()
            (root/'pubspec.yaml').write_text('version: 1.0.43+44\n')
            (root/'lib/app_version.dart').write_text("const appVersion = '1.0.43';")
            source=root/'build/windows/x64/runner/Release'
            for name in RUNTIME_FILES:
                path=source/name
                path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(b'compiled fixture')
            for name in PUBLIC_FILES:
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('Public fixture')
            package(root,local=True)
            (source/'sallunio.exe').write_bytes(b'updated fixture')
            package(root,local=True)
            target=root/'dist/Tableo-test'
            self.assertEqual((target/'sallunio.exe').read_bytes(),b'updated fixture')
            self.assertEqual([p.name for p in (root/'dist').iterdir()],['Tableo-test'])
            private=target/'tableo.sqlite'
            private.write_bytes(b'PRIVATE SENTINEL')
            with self.assertRaises(ValueError): package(root,local=True)
            self.assertEqual(private.read_bytes(),b'PRIVATE SENTINEL')

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
