"""Create a fresh release from an explicit list, never a user installation."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile
import argparse
import struct

RUNTIME_FILES = {
    'sallunio.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/app.so', 'data/icudtl.dat',
    *('data/flutter_assets/' + name for name in (
        'AssetManifest.bin', 'FontManifest.json', 'NativeAssetsManifest.json',
        'NOTICES.Z', 'fonts/MaterialIcons-Regular.otf', 'assets/branding/sallunio.png',
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

def audit_material_icons(source):
    """Refuse stale subsets that cannot render the plan's toolbar icons."""
    data = (source / 'data/flutter_assets/fonts/MaterialIcons-Regular.otf').read_bytes()
    u16 = lambda at: struct.unpack_from('>H', data, at)[0]
    u32 = lambda at: struct.unpack_from('>I', data, at)[0]
    try:
        cmap = next(u32(12+n*16+8) for n in range(u16(4)) if data[12+n*16:16+n*16] == b'cmap')
        needed = {0xf04ba: 'Sélection', 0xf4a1: 'Affichage', 0xef56: 'Vider la salle', 0xf36e: 'Réglages'}
        present = set()
        for n in range(u16(cmap+2)):
            base = cmap + u32(cmap+8+n*8)
            fmt = u16(base)
            if fmt == 12:
                for group in range(u32(base+12)):
                    start, end, glyph = struct.unpack_from('>III', data, base+16+group*12)
                    present.update(code for code in needed if start <= code <= end and glyph+code-start > 0)
            elif fmt == 4:
                count = u16(base+6)//2
                for segment in range(count):
                    end = u16(base+14+segment*2)
                    start = u16(base+16+count*2+segment*2)
                    delta = u16(base+16+count*4+segment*2)
                    offset_at = base+16+count*6+segment*2
                    offset = u16(offset_at)
                    for code in needed:
                        if start <= code <= end:
                            glyph = (code+delta)&65535 if offset == 0 else u16(offset_at+offset+2*(code-start))
                            if glyph: present.add(code)
        missing = [needed[code] for code in needed if code not in present]
        if missing: raise ValueError('Police d’icônes incomplète : ' + ', '.join(missing))
    except (StopIteration, struct.error, IndexError) as error:
        raise ValueError('Police d’icônes invalide.') from error

PUBLIC_FILES = ['README.md', 'CHANGELOG.md', 'DONNEES-ET-MISES-A-JOUR.md',
                'MIGRATION-SALLUNIO.md', 'assets/branding/sallunio.png',
                'assets/branding/IDENTITE.md', 'examples/modele-reservations.csv']

def package(root, local=False):
    version = re.search(r'^version:\s*([\d.]+)', (root / 'pubspec.yaml').read_text(), re.M)[1]
    assert f"const appVersion = '{version}';" in (root / 'lib/app_version.dart').read_text()
    source = root / 'build/windows/x64/runner/Release'
    files = audit_runtime(source)
    if (root / 'lib/main.dart').exists():
        audit_material_icons(source)
    target = root / 'dist' / ('Tableo-test' if local else f'Sallunio-{version}')
    archive = root / 'dist' / f'Sallunio-Windows-{version}.zip'
    public_files = PUBLIC_FILES
    expected = files | set(public_files)
    if local:
        if target.resolve().parent != (root/'dist').resolve() or target.is_symlink():
            raise ValueError('Dossier de test incorrect.')
        if target.exists():
            found = {p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file()}
            if found - expected - {'LOCAL-TEST.txt', 'tableo.exe'} or any(p.is_symlink() for p in target.rglob('*')):
                raise ValueError('Dossier de test contenant des fichiers inconnus : remplacement refusé.')
        target.mkdir(parents=True, exist_ok=True)
        for name in sorted(expected):
            dest=target/name
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(source/name if name in files else root/name,dest)
        (target/'LOCAL-TEST.txt').write_text(f'Test local de Sallunio {version}. Non publié. Les prochains essais remplacent uniquement les fichiers de ce dossier.\n',encoding='utf-8')
        legacy_executable = target/'tableo.exe'
        if legacy_executable.is_file():
            legacy_executable.unlink()  # Controlled old runtime, after successful replacement.
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
