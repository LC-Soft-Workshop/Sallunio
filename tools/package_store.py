"""Build an unsigned Microsoft Store MSIX using an audited Windows runtime.

Official identity values must come from Partner Center. This tool never installs
a package, changes certificate trust, reads user data or publishes a submission.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

from package_release import audit_runtime, audit_material_icons

ASSETS = {'Square44x44Logo.png', 'Square150x150Logo.png', 'StoreLogo.png'}
FOUNDATION = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
UAP = 'http://schemas.microsoft.com/appx/manifest/uap/windows10'
RESCAP = 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities'

def manifest(identity, version):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]{2,49}', identity.get('name', '')):
        raise ValueError('Identité Name officielle attendue.')
    if not identity.get('publisher', '').startswith('CN='):
        raise ValueError('Identité Publisher officielle attendue.')
    if not identity.get('publisherDisplayName', '').strip():
        raise ValueError('PublisherDisplayName officiel attendu.')
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Version major.minor.patch attendue.')
    ET.register_namespace('', FOUNDATION)
    ET.register_namespace('uap', UAP)
    ET.register_namespace('rescap', RESCAP)
    def f(name): return '{' + FOUNDATION + '}' + name
    root = ET.Element(f('Package'), {'IgnorableNamespaces': 'uap rescap'})
    ET.SubElement(root, f('Identity'), {
        'Name': identity['name'], 'Publisher': identity['publisher'],
        'Version': version + '.0', 'ProcessorArchitecture': 'x64'})
    properties = ET.SubElement(root, f('Properties'))
    for key, value in {
        'DisplayName': identity.get('displayName', 'Sallunio'),
        'PublisherDisplayName': identity['publisherDisplayName'],
        'Logo': 'Assets/StoreLogo.png',
        'Description': 'Plans de salle, mobilier et réservations',
    }.items():
        ET.SubElement(properties, f(key)).text = value
    resources = ET.SubElement(root, f('Resources'))
    ET.SubElement(resources, f('Resource'), {'Language': 'fr-FR'})
    dependencies = ET.SubElement(root, f('Dependencies'))
    ET.SubElement(dependencies, f('TargetDeviceFamily'), {
        'Name': 'Windows.Desktop', 'MinVersion': '10.0.19041.0',
        'MaxVersionTested': '10.0.26100.0'})
    ET.SubElement(dependencies, f('PackageDependency'), {
        'Name': 'Microsoft.VCLibs.140.00.UWPDesktop',
        'MinVersion': '14.0.30704.0',
        'Publisher': 'CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'})
    applications = ET.SubElement(root, f('Applications'))
    app = ET.SubElement(applications, f('Application'), {
        'Id': 'Tableo', 'Executable': 'sallunio.exe', 'EntryPoint': 'Windows.FullTrustApplication'})
    ET.SubElement(app, '{' + UAP + '}VisualElements', {
        'DisplayName': identity.get('displayName', 'Sallunio'),
        'Description': 'Plans de salle, mobilier et réservations',
        'BackgroundColor': 'transparent',
        'Square150x150Logo': 'Assets/Square150x150Logo.png',
        'Square44x44Logo': 'Assets/Square44x44Logo.png'})
    caps = ET.SubElement(root, f('Capabilities'))
    ET.SubElement(caps, '{' + RESCAP + '}Capability', {'Name': 'runFullTrust'})
    ET.indent(root)
    return ET.tostring(root, encoding='utf-8', xml_declaration=True)

def package(root, identity_file, assets, sdk=None):
    identity = json.loads(identity_file.read_text(encoding='utf-8'))
    version = re.search(r'^version:\s*([\d.]+)', (root/'pubspec.yaml').read_text(), re.M)[1]
    source = root/'build/windows/x64/runner/Release'
    files = audit_runtime(source)
    audit_material_icons(source)
    found = {p.name for p in assets.iterdir() if p.is_file()}
    if not ASSETS.issubset(found):
        raise ValueError('Logos Store manquants.')
    executable = sdk
    if executable is None:
        kits = Path('C:/Program Files (x86)/Windows Kits/10/bin')
        versions = sorted((p for p in kits.glob('10.*') if (p/'x64/makeappx.exe').is_file()),
                          key=lambda p: tuple(map(int, p.name.split('.'))))
        if not versions: raise FileNotFoundError('SDK Windows / makeappx introuvable.')
        executable = versions[-1]/'x64/makeappx.exe'
    output = root/'output/store'/f'Sallunio-{version}-x64.msix'
    if output.exists(): raise FileExistsError('Paquet existant conservé : choisir un autre dossier de travail.')
    output.parent.mkdir(parents=True, exist_ok=True)
    (root/'tmp').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='store-stage-', dir=root/'tmp') as directory:
        stage = Path(directory)
        for name in sorted(files):
            target = stage/name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source/name, target)
        (stage/'Assets').mkdir()
        for name in sorted(ASSETS):
            shutil.copy2(assets/name, stage/'Assets'/name)
        xml = manifest(identity, version)
        (stage/'AppxManifest.xml').write_bytes(xml)
        result = subprocess.run([str(executable), 'pack', '/d', str(stage), '/p', str(output)],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
    with zipfile.ZipFile(output) as archive:
        expected = files | {'Assets/' + name for name in ASSETS} | {
            'AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml'}
        if set(archive.namelist()) != expected:
            raise ValueError('Contenu MSIX inattendu.')
        if archive.read('AppxManifest.xml') != xml:
            raise ValueError('Identité MSIX différente.')
    report = {
        'file': output.name, 'version': version + '.0',
        'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'storeId': identity.get('storeId'), 'identity': identity['name'],
        'signed': False, 'installedTested': False, 'submitted': False,
        'note': 'Paquet validé par makeappx ; signature Store, test installé et certification restant à effectuer.'}
    output.with_suffix('.verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return output

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', required=True, type=Path)
    parser.add_argument('--assets', required=True, type=Path)
    args = parser.parse_args()
    package(Path(__file__).resolve().parents[1], args.identity, args.assets)
