"""Read-only checks of prior deliveries and exact new skill/runtime packaging."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--protected', type=Path, required=True)
    args = parser.parse_args()
    protected = json.loads(args.protected.read_text(encoding='utf-8-sig'))
    for entry in protected: assert sha(Path(entry['Path'])) == entry['Hash'].lower(), entry['Path']
    app = args.build / 'MaterialMaker'
    package = json.loads((app / 'vfx-package.json').read_text(encoding='utf-8'))
    assert package['document_version'] == package['effect_version'] == 2
    assert package['cli_contract_version'] == 1
    expected_runtime = {name:sha(ROOT / 'addons/mm_gpu_particles' / name) for name in package['runtime_files']}
    assert expected_runtime == package['runtime_files']
    assert hashlib.sha256(json.dumps(expected_runtime, sort_keys=True, separators=(',', ':')).encode()).hexdigest() == package['runtime_id']
    skill = ROOT / 'skills/godot-modular-vfx'
    files = {p.relative_to(skill).as_posix():sha(p) for p in skill.rglob('*') if p.is_file()}
    packaged_skill = app / package['skill']
    assert files == {p.relative_to(packaged_skill).as_posix():sha(p) for p in packaged_skill.rglob('*') if p.is_file()}
    manifests = {}
    for example in ['GodotExample','GodotBasicExample','GodotUserParametersExample']:
        bundle = args.build / example
        manifest = json.loads((bundle / 'mm_particles_manifest.json').read_text(encoding='utf-8'))
        assert manifest['version'] == 1
        for relative, checksum in manifest['files'].items():
            p = Path(relative)
            assert not p.is_absolute() and '..' not in p.parts
            assert sha(bundle / p) == checksum
        for name, checksum in expected_runtime.items(): assert sha(bundle / 'addons/mm_gpu_particles' / name) == checksum
        manifests[example] = len(manifest['files'])
    with zipfile.ZipFile(args.build / 'GodotAddon.zip') as archive:
        for info in archive.infolist():
            if not info.is_dir(): assert archive.read(info) == (args.build / 'GodotAddon' / info.filename).read_bytes()
    expected_reference = '4822ae43ec54de6f73d55b8f5c359f66df653a95c13e5b4e90079f3222b60932'
    assert sha(ROOT / 'test/modular_particles/fixtures/mmtest_reference.ptex') == expected_reference
    reference = Path('D:/Godot/Projects/gpu-vfx-pack/fx/mmtest/mmtest.ptex')
    if reference.exists(): assert sha(reference) == expected_reference
    link = subprocess.check_output(['git','-C',str(ROOT),'ls-files','-s','addons/mm_gpu_particles'],text=True).split()[1]
    private = subprocess.check_output(['git','-C',str(ROOT / 'addons/mm_gpu_particles'),'rev-parse','HEAD'],text=True).strip()
    assert link == private
    assert not subprocess.check_output(['git','-C',str(ROOT / 'addons/mm_gpu_particles'),'status','--porcelain'],text=True).strip()
    result = {'passed':True,'protected_files_unchanged':len(protected),'skill_file_checksums':files,
              'runtime_id':package['runtime_id'],'private_gitlink':link,'bundle_files':manifests,
              'addon_zip_matches':True,'legacy_reference_preserved':True}
    output = args.build / 'verification/skill-delivery-audit.json'
    with output.open('x',encoding='utf-8') as file: json.dump(result,file,indent=2)
    print('MODULAR_SKILL_AUDIT PASS',output,flush=True)


if __name__ == '__main__': main()
