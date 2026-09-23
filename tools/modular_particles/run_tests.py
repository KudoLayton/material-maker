"""Run modular particle tests in a new isolated Godot 4.7.2 project.

Never imports the working Material Maker project or overwrites existing build data.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--test', default='gpu_probe')
    parser.add_argument('--headless', action='store_true')
    parser.add_argument('--runtime', type=Path, help='Test a flat addon checkout in the temporary project only')
    args = parser.parse_args()
    engine = Path(args.godot).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'):
        raise SystemExit('Godot 4.7.2 stable required, got ' + version)
    project = Path(tempfile.mkdtemp(prefix='mm-modular-particles-'))
    print('PROJECT:', project, flush=True)
    (project / 'project.godot').write_text('''config_version=5
[application]
config/name="Modular Particle Tests"
config/use_custom_user_dir=true
config/custom_user_dir_name="mm-modular-tests/%s"
[display]
window/size/viewport_width=128
window/size/viewport_height=128
[rendering]
renderer/rendering_method="gl_compatibility"
environment/defaults/default_clear_color=Color(0,0,0,1)
''' % project.name, encoding='utf-8')
    # Forward+ selected explicitly for GPU tests, GL avoids GPU requirements for unit tests.
    for path in ['test/modular_particles', 'addons/mm_gpu_particles', 'addons/material_maker/particles/modular']:
        if (ROOT / path).exists():
            shutil.copytree(ROOT / path, project / path, ignore=shutil.ignore_patterns('.git', '.godot', '__pycache__'))
    if args.runtime:
        runtime = args.runtime.resolve()
        required = ['effect.gd', 'particles_3d.gd', 'value_codec.gd', 'gpu_state.gd',
                    'scheduler.gd', 'multimesh_lifetime.gd', 'plugin.gd', 'plugin.cfg']
        if any(not (runtime / name).is_file() for name in required):
            raise SystemExit('Incomplete runtime checkout: ' + str(runtime))
        for source in [*runtime.glob('*.gd'), runtime / 'plugin.cfg']:
            shutil.copy2(source, project / 'addons/mm_gpu_particles' / source.name)
        print('RUNTIME OVERRIDE (temporary copy only):', runtime, flush=True)
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    commands = [
        [str(engine), '--headless', '--path', str(project), '--editor', '--import'],
        [str(engine), '--path', str(project), '--script', f'test/modular_particles/{args.test}.gd'],
    ]
    commands[1] += ['--headless'] if args.headless else ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--position', '-32000,-32000', '--max-fps', '60']
    for i, command in enumerate(commands):
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, creationflags=flags, timeout=120)
        (project / f'run-{i}.log').write_text(result.stdout, encoding='utf-8')
        print(result.stdout, flush=True)
        if result.returncode or 'SCRIPT ERROR:' in result.stdout or 'ERROR:' in result.stdout or 'was leaked' in result.stdout or 'were leaked' in result.stdout:
            raise SystemExit(result.returncode or 1)
    if 'PASS' not in result.stdout:
        raise SystemExit('Test did not report PASS')


if __name__ == '__main__':
    main()
