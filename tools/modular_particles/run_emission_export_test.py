"""Run emission UI output with only the standalone addon, no MM autoloads."""
import argparse
from pathlib import Path
import shutil
import tempfile
from verify_export import run

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--effects', required=True, type=Path,
                        help='Isolated test_emission_ui project containing emission-v1/v2.res')
    args = parser.parse_args()
    project = Path(tempfile.mkdtemp(prefix='mm-emission-standalone-'))
    print('PROJECT:', project, flush=True)
    shutil.copytree(ROOT / 'addons/mm_gpu_particles', project / 'addons/mm_gpu_particles',
                    ignore=shutil.ignore_patterns('.git', '__pycache__'))
    for version in (1, 2):
        shutil.copy2(args.effects / f'emission-v{version}.res', project)
    shutil.copy2(ROOT / 'test/modular_particles/standalone_emission.gd', project / 'verify.gd')
    (project / 'project.godot').write_text('''config_version=5
[application]
config/name="Emission Standalone Test"
config/use_custom_user_dir=true
config/custom_user_dir_name="mm-modular-tests/''' + project.name + '''"
[rendering]
renderer/rendering_method="forward_plus"
''', encoding='utf-8')
    base = [str(args.godot.resolve()), '--path', str(project)]
    run(base + ['--headless', '--editor', '--import'], project, 'import')
    run(base + ['--script', 'res://verify.gd', '--rendering-method', 'forward_plus',
                '--rendering-driver', 'vulkan', '--position', '-32000,-32000', '--max-fps', '60'],
        project, 'gpu-runtime', 'MODULAR_STANDALONE_EMISSION PASS')


if __name__ == '__main__':
    main()
