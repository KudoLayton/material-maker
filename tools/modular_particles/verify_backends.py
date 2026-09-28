"""Required Windows backend support matrix. No skips/fallbacks count as PASS.
Every child uses a fresh temporary project. Existing builds/settings are read-only.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--templates', type=Path, required=True)
    parser.add_argument('--build', type=Path, required=True, help='Portable build to verify source-free delivery')
    parser.add_argument('--runtime', type=Path, default=ROOT / 'addons/mm_gpu_particles')
    parser.add_argument('--evidence', type=Path, help='New output directory; existing paths are never overwritten')
    args = parser.parse_args()
    if args.evidence:
        evidence = args.evidence.resolve()
        evidence.mkdir(parents=True, exist_ok=False)
    else:
        evidence = Path(tempfile.mkdtemp(prefix='mm-backend-matrix-'))
    print('EVIDENCE:', evidence, flush=True)
    results = []

    def run(name, script, *arguments):
        command = [sys.executable, '-B', str(script), *map(str, arguments)]
        log = evidence / (name + '.log')
        with log.open('w', encoding='utf-8') as output:
            try:
                result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=1800)
                passed = result.returncode == 0
            except subprocess.TimeoutExpired:
                passed = False
        text = log.read_text(encoding='utf-8', errors='replace')
        # Keep the actual engine logs, not just the child's PASS summary, so
        # backend evidence survives cleanup of the disposable projects.
        for index, directory in enumerate(re.findall(r'^(?:PROJECT|WORKSPACE): (.+)$', text, re.MULTILINE)):
            project = Path(directory.strip())
            if not project.is_dir(): continue
            for source in project.rglob('*'):
                if source.is_file() and (source.suffix == '.log' or source.name in ['verification.json', 'app-results.json', 'user-inspector.png', 'skill-game.png']):
                    target = evidence / (name + '-evidence') / str(index) / source.relative_to(project)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
        results.append({'name': name, 'passed': passed, 'command': command, 'log': str(log)})
        (evidence / 'results.json').write_text(json.dumps({'passed': all(r['passed'] for r in results), 'complete': False, 'results': results}, indent=2), encoding='utf-8')
        print(name, 'PASS' if passed else 'FAIL', log, flush=True)
        print('\n'.join(line for line in text.splitlines() if 'MODULAR_' in line or 'TEST SUMMARY:' in line), flush=True)
        if not passed: raise SystemExit('Backend support gate failed: ' + str(log))

    run('backend-guard', TOOLS / 'test_render_backend.py')
    run('installer', TOOLS / 'test_install_vfx.py', '--app', args.build.resolve() / 'MaterialMaker/MaterialMaker.exe')
    for driver in ['vulkan', 'd3d12']:
        flags = ['--godot', args.godot.resolve(), '--rendering-driver', driver]
        for test in ['gpu_probe', 'test_shader', 'test_runtime', 'test_render', 'test_user_runtime', 'test_dimensions', 'test_runtime_2d', 'test_performance', 'test_performance_2d']:
            run(driver + '-' + test, TOOLS / 'run_tests.py', *flags, '--runtime', args.runtime.resolve(), '--test', test)
        run(driver + '-standard-modules', TOOLS / 'run_app_tests.py', *flags, '--runtime', args.runtime.resolve(),
            '--test', 'test_standard_gpu,test_standard_performance,test_standard_examples,test_export_2d')
        run(driver + '-inspector', TOOLS / 'run_inspector_tests.py', *flags, '--runtime', args.runtime.resolve())
        run(driver + '-addon-release', args.runtime.resolve() / 'tools/verify.py', *flags, '--templates', args.templates.resolve(), '--enable-plugin')
        run(driver + '-2d-release', TOOLS / 'verify_export.py', *flags, '--bundle', args.build.resolve() / 'Godot2DExample', '--templates', args.templates.resolve(), '--enable-plugin')
        run(driver + '-2d-user-release', TOOLS / 'verify_export.py', *flags, '--bundle', args.build.resolve() / 'Godot2DUserParametersExample', '--templates', args.templates.resolve(), '--enable-plugin')
        run(driver + '-cli', TOOLS / 'run_cli_tests.py', *flags, '--app', args.build.resolve() / 'MaterialMaker/MaterialMaker.exe')
        run(driver + '-skill-delivery', TOOLS / 'verify_skill_delivery.py', *flags, '--templates', args.templates.resolve(), '--build', args.build.resolve(), '--export-driver', driver)
    (evidence / 'results.json').write_text(json.dumps({'passed': True, 'complete': True, 'drivers': ['vulkan', 'd3d12'], 'results': results}, indent=2), encoding='utf-8')
    print('MODULAR_BACKEND_MATRIX PASS gates=' + str(len(results)), evidence, flush=True)


if __name__ == '__main__': main()
