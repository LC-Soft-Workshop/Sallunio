"""Closed source publication list; never use blanket git add."""
from pathlib import Path
import subprocess
import sys

EXACT = {
    '.gitignore', '.gitattributes', '.metadata', 'README.md', 'CHANGELOG.md',
    'DONNEES-ET-MISES-A-JOUR.md', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
    'examples/modele-reservations.csv', 'test/fixtures/logo-fiches.png', 'test/flutter_paths.dart',
    'test/fixtures/reservations.csv',
    'windows/CMakeLists.txt', 'windows/flutter/CMakeLists.txt',
    'windows/runner/resources/app_icon.ico',
    'tools/publication_files.py', 'tools/package_release.py',
    'tools/test_publication.py', 'tools/release_notes.py', '.github/workflows/release.yml',
    '.githooks/pre-commit', '.githooks/pre-push',
}

def allowed(name):
    p = Path(name)
    if name in EXACT:
        return True
    if len(p.parts) == 2 and p.parts[0] == 'lib' and p.suffix == '.dart':
        return True
    if len(p.parts) == 2 and p.parts[0] == 'test' and p.name.endswith('_test.dart'):
        return True
    return len(p.parts) == 3 and p.parts[:2] == ('windows', 'runner') and (
        p.suffix in {'.cpp', '.h', '.rc', '.manifest'} or p.name == 'CMakeLists.txt')

def candidates(root):
    found = set()
    for directory in ['lib', 'test', 'windows/runner']:
        for p in (root / directory).rglob('*'):
            name = p.relative_to(root).as_posix()
            if p.is_file() and not p.is_symlink() and allowed(name):
                found.add(name)
    for name in EXACT:
        p = root / name
        if p.is_file() and not p.is_symlink():
            found.add(name)
    return sorted(found)

def audit(names):
    rejected = [name for name in names if not allowed(name)]
    if rejected:
        raise ValueError('Publication refusée : ' + ', '.join(rejected))

if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    if '--tracked' in sys.argv:
        names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().strip('\0').split('\0')
        audit(names)
        print(f'{len(names)} fichiers suivis autorisés.')
    else:
        print('\n'.join(candidates(root)))
