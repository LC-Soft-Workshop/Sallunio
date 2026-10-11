"""Create a fresh release from an explicit list, never a user installation."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile
import argparse

RUNTIME_FILES = {
    'tableo.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat',
    *('data/flutter_assets/' + name for name in (
        'AssetManifest.bin', 'FontManifest.json', 'NativeAssetsManifest.json',
        'NOTICES.Z', 'fonts/MaterialIcons-Regular.otf',
        'packages/cupertino_icons/assets/CupertinoIcons.ttf',
        'shaders/ink_sparkle.frag', 'shaders/stretch_effect.frag')),
}

def audit_runtime(source):
    files = {p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file()}
    # Flutter's build-only manifest contains absolute development paths and must
    # never be shipped. Validate its schema before deliberately omitting it.
    if 'native_assets.json' in files:
        manifest = json.loads((source / 'native_assets.json').read_text(encoding='utf-8'))
        assets = manifest.get('native-assets', {}).get('windows_x64', {})
        entry = assets.get('package:sqlite3/src/ffi/libsqlite3.g.dart')
        if set(manifest) != {'format-version', 'native-assets'} or set(assets) != {'package:sqlite3/src/ffi/libsqlite3.g.dart'} or not isinstance(entry, list) or len(entry) != 2 or entry[0] != 'absolute' or not entry[1].replace('\\', '/').endswith('/sqlite3.dll'):
            raise ValueError('Manifest natif inattendu : livraison refusée.')
        files.remove('native_assets.json')
    unexpected, missing = files - RUNTIME_FILES, RUNTIME_FILES - files
    if unexpected or missing or any(p.is_symlink() for p in source.rglob('*')):
        raise ValueError(f'Livraison refusée : fichiers inattendus {sorted(unexpected)}, manquants {sorted(missing)}')
    return files

def package(root, local=False):
    version = re.search(r'^version:\s*([\d.]+)', (root / 'pubspec.yaml').read_text(), re.M)[1]
    assert f"const appVersion = '{version}';" in (root / 'lib/app_version.dart').read_text()
    source = root / 'build/windows/x64/runner/Release'
    files = audit_runtime(source)
    target = root / 'dist' / ('Tableo-test' if local else f'Tableo-{version}')
    archive = root / 'dist' / f'Tableo-Windows-{version}.zip'
    public_files = ['README.md', 'CHANGELOG.md', 'DONNEES-ET-MISES-A-JOUR.md', 'examples/modele-reservations.csv']
    expected = files | set(public_files)
    if local:
        if target.resolve().parent != (root/'dist').resolve() or target.is_symlink():
            raise ValueError('Dossier de test incorrect.')
        if target.exists():
            found = {p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()}
            if found - expected - {'LOCAL-TEST.txt'} or any(p.is_symlink() for p in target.rglob('*')):
                raise ValueError('Dossier de test contenant des fichiers inconnus : remplacement refusé.')
        target.mkdir(parents=True, exist_ok=True)
        for name in sorted(expected):
            dest=target/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source/name if name in files else root/name,dest)
        (target/'LOCAL-TEST.txt').write_text(f'Test local de Tableo {version}. Non publié. Les prochains essais remplacent uniquement les fichiers de ce dossier.\n',encoding='utf-8')
        print(target)
        return
    if target.exists() or archive.exists():
        raise FileExistsError('Livraison déjà présente : aucun fichier existant ne sera remplacé.')
    target.mkdir(parents=True)
    for name in sorted(files):
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, dest)
    for name in public_files:
        dest = target / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / name, dest)
    expected = files | set(public_files)
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED) as z:
        for name in sorted(expected):
            z.write(target / name, f'{target.name}/{name}')
    with zipfile.ZipFile(archive) as z:
        assert set(z.namelist()) == {f'{target.name}/{name}' for name in expected}
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n', encoding='utf-8')
    print(archive)

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--local',action='store_true',help='Actualiser le seul dossier de test, sans créer une nouvelle version ni archive.')
    package(Path(__file__).resolve().parents[1],local=parser.parse_args().local)
