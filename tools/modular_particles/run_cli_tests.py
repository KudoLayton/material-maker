"""Isolated source/packaged CLI contract tests. Never imports the working project."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--app', type=Path, help='Optional packaged executable; no source copy')
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='mm-vfx-cli-'))
    print('PROJECT:', root, flush=True)
    settings_file = None
    settings_before = None
    if args.app:
        base = [str(args.app.resolve())]
        build_info = args.app.resolve().parents[1] / 'build-info.json'
        if build_info.exists():
            info = json.loads(build_info.read_text(encoding='utf-8'))
            settings_file = Path(info['release_smoke']['userdata']) / 'mm_config.ini'
            settings_before = settings_file.read_bytes() if settings_file.exists() else None
    else:
        project = root / 'app'
        project.mkdir()
        for directory in ['addons', 'material_maker', 'splash_screen', 'test', 'demo']:
            shutil.copytree(ROOT / directory, project / directory,
                            ignore=shutil.ignore_patterns('.git', '.godot', '__pycache__'))
        for source in ROOT.iterdir():
            if source.is_file() and source.suffix in ['.godot', '.gd', '.uid', '.tscn', '.tres', '.png', '.ico', '.import', '.cfg']:
                shutil.copy2(source, project / source.name)
        extension = project / 'addons/godotsteam/godotsteam.gdextension'
        if extension.exists(): extension.rename(extension.with_suffix('.disabled'))
        config = project / 'project.godot'
        text = re.sub(r'config/custom_user_dir_name="[^"]+"',
                      f'config/custom_user_dir_name="mm-modular-tests/{root.name}"', config.read_text(encoding='utf-8'))
        config.write_text(text, encoding='utf-8')
        base = [str(args.godot.resolve()), '--path', str(project)]
        result = subprocess.run(base + ['--headless', '--editor', '--import'], capture_output=True, text=True, timeout=240)
        (root / 'import.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode or 'SCRIPT ERROR:' in result.stdout + result.stderr:
            raise SystemExit('Import failed: ' + str(root / 'import.log'))
    source = root / '한글 space.mpfx'
    sequence = 0

    def run(command, extra=(), expected=0, gpu=False, report=True):
        nonlocal sequence
        sequence += 1
        report_file = root / f'report-{sequence}.json'
        engine_log = root / f'engine-{sequence}.log'
        graphics = ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--position', '-32000,-32000', '--max-fps', '60'] if gpu else ['--headless']
        cmd = base + ['--log-file', str(engine_log), *graphics, '--', '--mpfx-command', command, *map(str, extra)]
        if report: cmd += ['--report', str(report_file)]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        output = result.stdout + result.stderr
        if engine_log.exists(): output += engine_log.read_text(encoding='utf-8', errors='replace')
        (root / f'run-{sequence}.log').write_text(output, encoding='utf-8')
        records = [line.removeprefix('MM_VFX_REPORT ') for line in output.splitlines() if line.startswith('MM_VFX_REPORT ')]
        if result.returncode != expected or not records or 'ERROR:' in output or 'leaked' in output:
            raise SystemExit(f'CLI {command} expected={expected} actual={result.returncode}: {root / ("run-"+str(sequence)+".log")}')
        data = json.loads(records[-1])
        assert data['exit_code'] == expected and data['ok'] == (expected == 0)
        if report and report_file.exists(): assert json.loads(report_file.read_text(encoding='utf-8')) == data
        print(f'PASS {sequence}: {command} exit={expected}', flush=True)
        return data

    cap = run('capabilities')['data']
    assert cap['document_version'] == cap['effect_version'] == 2 and len(cap['modules']) == 12
    assert len(cap['runtime_id']) == 64
    run('create', ['--template', 'basic_fountain', '--output', source])
    assert json.loads(source.read_text(encoding='utf-8'))['version'] == 2
    before = source.read_bytes()
    run('create', ['--template', 'sphere_burst', '--output', source], 5)
    assert source.read_bytes() == before
    inspected = run('inspect', ['--input', source])['data']
    validated = run('validate', ['--input', source])['data']
    assert not validated['gpu_compiled'] and validated['effect_version'] == 2
    for version in [None, 1, 3]:
        invalid = dict(inspected)
        if version is None: invalid.pop('version')
        else: invalid['version'] = version
        path = root / f'version-{version}.mpfx'
        path.write_text(json.dumps(invalid), encoding='utf-8')
        run('validate', ['--input', path], 3)
    broken = root / 'broken.mpfx'
    broken.write_text('{ invalid', encoding='utf-8')
    run('inspect', ['--input', broken], 3)
    run('inspect', ['--input', root / 'missing.mpfx'], 5)
    run('validate', ['--input', 'relative.mpfx'], 2)
    run('not-a-command', expected=2)
    run('capabilities', ['--capacity', '10'], 2)
    run('inspect', ['--input', source, '--input', source], 2)
    run('export', ['--input', source, '--output', root / 'no-gpu', '--effect-id', 'fountain'], 4)
    assert not (root / 'no-gpu').exists()
    for effect_id in ['../bad', 'Upper', 'con']:
        run('export', ['--input', source, '--output', root / 'bad-id', '--effect-id', effect_id], 2)
    assert not (root / 'bad-id').exists()
    out = root / 'export'
    export = run('export', ['--input', source, '--output', out, '--effect-id', 'fountain', '--capacity', '256'], gpu=True)['data']
    assert export['gpu_compiled']
    for path, digest in export['manifest']['files'].items():
        assert hashlib.sha256((out / path).read_bytes()).hexdigest() == digest
    scene = (out / 'effects/modular_particles/fountain/particles.tscn').read_text(encoding='utf-8')
    assert 'res://effects/modular_particles/fountain/effect.res' in scene
    run('export', ['--input', source, '--output', out, '--effect-id', 'fountain'], gpu=True)
    # A bound User type mismatch is a located compiler diagnostic, not a crash.
    user_source = root / 'users.mpfx'
    run('create', ['--template', 'user_parameters', '--output', user_source])
    users = json.loads(user_source.read_text(encoding='utf-8'))
    users['user_parameters'][0]['type'] = 'vec3'
    users['user_parameters'][0]['default'] = [1, 2, 3]
    user_source.write_text(json.dumps(users), encoding='utf-8')
    bad_binding = run('validate', ['--input', user_source], 3)
    assert any('type mismatch' in d['message'] for d in bad_binding['diagnostics'])
    # Existing report paths are never overwritten, including when source equals report.
    run('inspect', ['--input', source, '--report', source], 5, report=False)
    assert source.read_bytes() == before
    before = {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()}
    run('export', ['--input', source, '--output', out, '--effect-id', 'other'], 5, gpu=True)
    assert before == {str(p.relative_to(out)): p.read_bytes() for p in out.rglob('*') if p.is_file()}
    managed = out / 'effects/modular_particles/fountain/particles.tscn'
    managed.write_bytes(managed.read_bytes() + b'\n; user edit\n')
    run('export', ['--input', source, '--output', out, '--effect-id', 'fountain'], 5, gpu=True)
    assert managed.read_bytes().endswith(b'; user edit\n')
    if not args.app:
        appdata = Path.home() / 'AppData/Roaming/mm-modular-tests' / root.name
        assert not (appdata / 'mm_config.ini').exists(), 'CLI must not save preferences'
    if settings_file:
        assert (settings_file.read_bytes() if settings_file.exists() else None) == settings_before, 'Packaged CLI changed preferences'
    print(f'MODULAR_CLI PASS commands={sequence} project={root}', flush=True)


if __name__ == '__main__': main()
