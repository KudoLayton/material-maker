"""Run Material Maker integration in an isolated copy with a real GPU renderer."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1]
REPO = PACKAGE.parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--skip-import', action='store_true', help='Reuse an existing validation import cache')
    args = parser.parse_args()
    target = REPO / 'build/particle-validation/project'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(REPO, target, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.git', '.godot', 'build', '__pycache__', '.codex', '.agents'))
    project = target / 'project.godot'
    text = project.read_text(encoding='utf-8')
    text = text.replace('config/name="Material Maker"', 'config/name="Material Maker Particle Validation"')
    text = text.replace('config/custom_user_dir_name="material_maker_2"',
                        'config/custom_user_dir_name="material_maker_particle_validation"')
    project.write_text(text, encoding='utf-8')
    steam = target / 'material_maker/steam.gd'
    steam.write_text(steam.read_text(encoding='utf-8').replace('func _ready():', 'func _ready():\n\tif true:\n\t\treturn'), encoding='utf-8')
    runtime = target.parent / 'runtime'
    runtime.mkdir(exist_ok=True)
    executable = Path(args.godot).resolve()
    binaries = [executable]
    if executable.stem.endswith('_console'):
        binaries.append(executable.with_name(executable.name.replace('_console.exe', '.exe')))
    for binary in binaries:
        destination = runtime / binary.name
        if not destination.exists() or destination.stat().st_mtime != binary.stat().st_mtime:
            shutil.copy2(binary, destination)
    shutil.copytree(PACKAGE / 'nodes', runtime / 'nodes', dirs_exist_ok=True)
    command = [str(runtime / executable.name), '--path', str(target)]
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    report_path = target / 'validation_outputs/report.json'
    if report_path.exists():
        report_path.unlink()
    if not args.skip_import:
        with (target.parent / 'import.log').open('w', encoding='utf-8') as log:
            imported = subprocess.run(command + ['--headless', '--editor', '--import'],
                                  stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=300)
        if imported.returncode:
            raise SystemExit('Import failed; see build/particle-validation/import.log')
    with (target.parent / 'integration.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command + ['--verbose', '--rendering-method', 'mobile', '--position', '-32000,-32000',
                                '--resolution', '960x640', '--max-fps', '60',
                                'res://extensions/godot_particles/tests/integration.tscn'],
                                stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=180)
    report_path = target / 'validation_outputs/report.json'
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {'failures': ['No integration report']}
    demo = target.parent / 'demo'
    shutil.copytree(PACKAGE / 'examples/godot', demo, dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns('.godot'))
    with (target.parent / 'demo.log').open('w', encoding='utf-8') as log:
        demo_result = subprocess.run([command[0], '--path', str(demo), '--rendering-method', 'mobile',
                                     '--position', '-32000,-32000', '--max-fps', '60', '--quit-after', '120'],
                                    stdout=log, stderr=subprocess.STDOUT, creationflags=flags, timeout=45)
    output = (target.parent / 'integration.log').read_text(encoding='utf-8')
    output += (target.parent / 'demo.log').read_text(encoding='utf-8')
    errors = [line for line in output.splitlines() if 'ERROR:' in line or 'Error at' in line]
    print('\n'.join(errors[-20:]))
    print('Results:', target / 'validation_outputs')
    raise SystemExit(result.returncode or demo_result.returncode or (1 if errors or report['failures'] else 0))


if __name__ == '__main__':
    main()
