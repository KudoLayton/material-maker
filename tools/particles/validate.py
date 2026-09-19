"""Validate the native compiler and editor without touching app user settings."""
import argparse
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    args = parser.parse_args()
    engine = Path(args.godot).resolve()
    if engine.name.endswith('_console.exe'):
        engine = engine.with_name(engine.name.replace('_console.exe', '.exe'))
    project = ROOT / 'build/particle-integration/unit'
    project.mkdir(parents=True, exist_ok=True)
    (project / 'project.godot').write_text('''config_version=5
[application]
config/name="Native Particle Validation"
[display]
window/size/viewport_width=1400
window/size/viewport_height=900
[rendering]
renderer/rendering_method="mobile"
''', encoding='utf-8')
    for path in ['addons/material_maker/particles', 'test/particles', 'material_maker/examples/particles']:
        shutil.copytree(ROOT / path, project / path, dirs_exist_ok=True)
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    failed = False
    for name in ['compiler']:
        log_path = project.parent / (name + '.log')
        with log_path.open('w', encoding='utf-8') as log:
            command = [str(engine), '--path', str(project), '--script', 'test/particles/test_' + name + '.gd']
            command += ['--headless'] if name == 'compiler' else ['--rendering-method', 'mobile', '--position', '-32000,-32000', '--max-fps', '60']
            try:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=60)
                failed |= result.returncode != 0
            except subprocess.TimeoutExpired:
                failed = True
        text = log_path.read_text(encoding='utf-8')
        for line in text.splitlines():
            if 'PARTICLE_' in line or 'SCRIPT ERROR:' in line:
                print(line)
        failed |= 'SCRIPT ERROR:' in text or 'PARTICLE_' not in text
    if failed:
        raise SystemExit(1)
    subprocess.run([__import__('sys').executable, str(ROOT / 'tools/particles/validate_integration.py'), '--godot', str(engine)], check=True)



if __name__ == '__main__':
    main()
