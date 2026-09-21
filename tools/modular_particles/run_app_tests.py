"""Isolated full Material Maker integration tests; never reuse existing build dirs."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True)
    parser.add_argument('--test', default='test_editor')
    parser.add_argument('--keep-going', action='store_true')
    args = parser.parse_args()
    engine = Path(args.godot).resolve()
    version = subprocess.check_output([str(engine), '--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'):
        raise SystemExit('Godot 4.7.2 stable required: ' + version)
    project = Path(tempfile.mkdtemp(prefix='mm-modular-app-'))
    print('PROJECT:', project, flush=True)
    for directory in ['addons', 'material_maker', 'splash_screen', 'test', 'demo']:
        shutil.copytree(ROOT / directory, project / directory, ignore=shutil.ignore_patterns('.git', '.godot', '__pycache__'))
    for source in ROOT.iterdir():
        if source.is_file() and source.suffix in ['.godot', '.gd', '.uid', '.tscn', '.tres', '.png', '.ico', '.import', '.cfg']:
            shutil.copy2(source, project / source.name)
    extension = project / 'addons/godotsteam/godotsteam.gdextension'
    if extension.exists():
        extension.rename(extension.with_suffix('.disabled'))
    config = project / 'project.godot'
    content = re.sub(r'config/custom_user_dir_name="[^"]+"', f'config/custom_user_dir_name="mm-modular-tests/{project.name}"', config.read_text(encoding='utf-8'))
    config.write_text(content, encoding='utf-8')
    commands = [('import', ['--headless', '--editor', '--import'])]
    requested = args.test.split(',')
    if args.test in ['all', 'legacy:all']:
        requested = ['legacy:' + path.stem for path in sorted((ROOT / 'test/particles').glob('test_*.gd'))]
        if args.test == 'all': requested = ['test_editor', 'test_module_rename', 'test_graph_backend', 'test_mmtest', 'test_export'] + requested
    for test in requested:
        folder = 'test/particles' if test.startswith('legacy:') else 'test/modular_particles'
        name = test.removeprefix('legacy:')
        entry = [f'{folder}/{name}.tscn'] if (project / folder / (name + '.tscn')).exists() else ['--script', f'{folder}/{name}.gd']
        commands.append((test, entry + ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--position', '-32000,-32000', '--max-fps', '60']))
    outcomes = {}
    for index, (test, arguments) in enumerate(commands):
        # Each test gets fresh settings; no remembered project/layout/Library
        # state leaks from an earlier UI test into the next one.
        config.write_text(content.replace('mm-modular-tests/' + project.name, 'mm-modular-tests/' + project.name + '/' + str(index)), encoding='utf-8')
        log = project / f'run-{index}.log'
        with log.open('w', encoding='utf-8') as output:
            with subprocess.Popen([str(engine), '--path', str(project), *arguments], stdout=output, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as result:
                started = time.monotonic()
                while result.poll() is None:
                    time.sleep(0.2)
                    if 'SCRIPT ERROR:' in log.read_text(encoding='utf-8', errors='replace') or time.monotonic() - started > 360:
                        result.kill()
                        result.wait()
                        break
        text = log.read_text(encoding='utf-8', errors='replace')
        failed = result.returncode or 'SCRIPT ERROR:' in text or 'Parse Error:' in text or 'FAIL:' in text
        print(f'{test}: log={log}', flush=True)
        if failed:
            print('\n'.join(text.splitlines()[-80:]), flush=True)
            outcomes[test] = {'passed': False, 'log': str(log)}
            if not args.keep_going or index == 0: raise SystemExit(f'Failed; see {log}')
            continue
        if index:
            print('\n'.join(line for line in text.splitlines() if 'MODULAR_' in line or 'PARTICLE_' in line), flush=True)
            legacy_pass = re.search(r'^PARTICLE_[^\n]*(?:passed|0 failures|failures=\[\s*\]|RUNTIME_TESTS:\s*\[\s*\])', text, re.MULTILINE)
            if 'PASS' not in text and not legacy_pass:
                outcomes[test] = {'passed': False, 'log': str(log)}
                if not args.keep_going: raise SystemExit('Test did not finish; see ' + str(log))
                continue
            outcomes[test] = {'passed': True, 'log': str(log)}
        # Full logs retain pre-existing MM import/HDR/MTL and shutdown warnings.
        # Standalone runtime tests use the stricter no-error/no-RID-leak runner.
    (project / 'app-results.json').write_text(json.dumps(outcomes, indent=2), encoding='utf-8')
    failures = [name for name, result in outcomes.items() if not result['passed']]
    print(f'TEST SUMMARY: {len(outcomes)-len(failures)}/{len(outcomes)} passed; failed={failures}', flush=True)
    if failures: raise SystemExit(1)


if __name__ == '__main__':
    main()
