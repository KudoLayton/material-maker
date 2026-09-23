"""Read-only audit of protected files, fixed private gitlink and new bundles."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PIN = '60b6fb6e32ac56b0028d28d649ee5c54c68dd83b'
REFERENCE_HASH = '4822ae43ec54de6f73d55b8f5c359f66df653a95c13e5b4e90079f3222b60932'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--protected', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    args = parser.parse_args()
    hashes = json.loads(args.protected.read_text(encoding='utf-8-sig'))
    for entry in hashes:
        assert digest(Path(entry['Path'])) == entry['Hash'].lower(), entry['Path']
    assert digest(args.reference) == REFERENCE_HASH
    assert digest(ROOT / 'test/modular_particles/fixtures/mmtest_reference.ptex') == REFERENCE_HASH
    gitlink = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-s', 'addons/mm_gpu_particles'], text=True)
    assert gitlink.startswith('160000 ' + PIN)
    assert not subprocess.check_output(['git', '-C', str(ROOT / 'addons/mm_gpu_particles'), 'status', '--porcelain'], text=True).strip()
    assert not subprocess.check_output(['git', '-C', str(ROOT), 'diff', 'HEAD', '--name-only', '--', 'material_maker/examples', 'test/modular_particles/fixtures'], text=True).strip()
    manifests = {}
    for name in ['GodotExample', 'GodotBasicExample', 'GodotUserParametersExample']:
        bundle = args.build / name
        manifest = json.loads((bundle / 'mm_particles_manifest.json').read_text(encoding='utf-8'))
        for relative, expected in manifest['files'].items():
            path = Path(relative)
            assert not path.is_absolute() and '..' not in path.parts
            assert digest(bundle / path) == expected, relative
        manifests[name] = len(manifest['files'])
        for source in (ROOT / 'addons/mm_gpu_particles').glob('*.gd'):
            target = bundle / 'addons/mm_gpu_particles' / source.name
            if target.exists(): assert digest(source) == digest(target)
    with zipfile.ZipFile(args.build / 'GodotAddon.zip') as archive:
        for entry in archive.infolist():
            if not entry.is_dir():
                assert archive.read(entry) == (args.build / 'GodotAddon' / entry.filename).read_bytes()
    result = {'protected_files_unchanged': len(hashes), 'reference_sha256': REFERENCE_HASH,
              'private_gitlink': PIN, 'private_checkout_clean': True,
              'original_examples_unchanged': True, 'bundle_manifest_counts': manifests,
              'runtime_matches_private_checkout': True, 'addon_zip_matches_folder': True}
    target = args.build / 'verification/workspace-delivery-audit.json'
    assert not target.exists(), 'Never overwrite an audit'
    target.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('WORKSPACE DELIVERY AUDIT PASS', target)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
