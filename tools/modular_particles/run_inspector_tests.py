"""Exercise actual Godot Inspector controls in a new, disposable editor project."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(command, project, name, marker=None):
    log = project / (name + '.log')
    with log.open('w', encoding='utf-8') as output:
        with subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
            started = time.monotonic()
            while process.poll() is None:
                time.sleep(0.2)
                text = log.read_text(encoding='utf-8', errors='replace')
                if 'SCRIPT ERROR:' in text or 'FAIL:' in text or time.monotonic()-started > 240:
                    process.kill()
                    process.wait()
                    break
    text = log.read_text(encoding='utf-8', errors='replace')
    print(f'{name}: {log}', flush=True)
    print('\n'.join(line for line in text.splitlines() if 'MODULAR_' in line), flush=True)
    if process.returncode or 'ERROR:' in text or 'leaked' in text or (marker and marker not in text):
        print(text[-12000:], flush=True)
        raise SystemExit('Inspector verification failed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--runtime', type=Path, default=ROOT / 'addons/mm_gpu_particles')
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'):
        raise SystemExit('Godot 4.7.2 stable required')
    project = Path(tempfile.mkdtemp(prefix='mm-user-inspector-'))
    print('PROJECT:', project, flush=True)
    # A fresh portable editor also isolates EditorSettings (custom_user_dir only
    # isolates game user data). Never toggle self-contained mode on an installed engine.
    portable = project / '.test-engine'
    portable.mkdir()
    (portable / '.gdignore').write_text('', encoding='utf-8')
    (portable / '_sc_').write_text('', encoding='utf-8')
    shutil.copy2(engine, portable / engine.name)
    if engine.name.endswith('_console.exe'):
        gui = engine.with_name(engine.name.replace('_console.exe', '.exe'))
        shutil.copy2(gui, portable / gui.name)
    engine = portable / engine.name
    addon = project / 'addons/mm_gpu_particles'
    addon.mkdir(parents=True)
    for source in [*args.runtime.glob('*.gd'), args.runtime / 'plugin.cfg']:
        shutil.copy2(source, addon / source.name)
    test = project / 'addons/inspector_test'
    test.mkdir()
    shutil.copy2(ROOT / 'test/modular_particles/test_user_inspector_plugin.gd', test / 'plugin.gd')
    (test / 'plugin.cfg').write_text('[plugin]\nname="Isolated Inspector Test"\ndescription="Test only"\nauthor="Tests"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
    config = f'''config_version=5
[application]
config/name="Isolated User Inspector Test"
config/use_custom_user_dir=true
config/custom_user_dir_name="mm-modular-tests/{project.name}"
[rendering]
renderer/rendering_method="forward_plus"
'''
    (project / 'project.godot').write_text(config, encoding='utf-8')
    base = [str(engine), '--path', str(project)]
    run(base + ['--headless', '--editor', '--import'], project, 'import')
    # The addon checkbox is deliberately OFF; @tool/class_name must suffice.
    (project / 'project.godot').write_text(config + '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/inspector_test/plugin.cfg")\n', encoding='utf-8')
    run(base + ['--editor', '--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan',
                '--position', '80,80', '--resolution', '1500x1000', '--max-fps', '60'],
        project, 'inspector', 'MODULAR_USER_INSPECTOR PASS')


if __name__ == '__main__':
    main()
