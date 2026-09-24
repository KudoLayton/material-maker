"""Check local skill links plus real portable helper calls, using no game project."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / 'skills/godot-modular-vfx'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--shell', default='powershell.exe')
    args = parser.parse_args()
    for file in SKILL.rglob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', file.read_text(encoding='utf-8')):
            if '://' not in target:
                assert (file.parent / target.split('#')[0]).is_file(), f'Broken reference: {file}: {target}'
    metadata = (SKILL / 'agents/openai.yaml').read_text(encoding='utf-8')
    assert '$godot-modular-vfx' in metadata and 'allow_implicit_invocation: true' in metadata
    work = Path(tempfile.mkdtemp(prefix='mm-vfx-skill-'))
    source = work / '한글 space.mpfx'
    count = 0

    def run(command, extra=(), expected=0, environment=False):
        nonlocal count
        count += 1
        env = os.environ.copy()
        env.pop('MM_VFX_APP', None)
        call = [args.shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SKILL / 'scripts/Invoke-Vfx.ps1'), '-Command', command, *map(str, extra)]
        if environment: env['MM_VFX_APP'] = str(args.app.resolve())
        else: call += ['-App', str(args.app.resolve())]
        result = subprocess.run(call, env=env, capture_output=True, text=True, timeout=210)
        (work / f'call-{count}.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        assert result.returncode == expected, result.stdout + result.stderr
        report = json.loads(result.stdout)
        assert report['ok'] == (expected == 0)
        print(f'PASS {count}: {command} exit={expected}', flush=True)
        return report

    assert run('capabilities', environment=True)['data']['effect_version'] == 2
    run('create', ['-Template', 'basic_fountain', '-Output', source])
    original = source.read_bytes()
    run('create', ['-Template', 'sphere_burst', '-Output', source], expected=5)
    assert source.read_bytes() == original
    run('inspect', ['-InputFile', source])
    run('validate', ['-InputFile', source])
    run('export', ['-InputFile', source, '-Output', work / 'export space', '-EffectId', 'helper-test', '-Capacity', '256'])
    run('validate', ['-InputFile', work / 'missing.mpfx'], expected=5)
    run('inspect', ['-InputFile', source, '-Report', source], expected=1)
    assert source.read_bytes() == original
    print(f'MODULAR_SKILL_HELPER PASS calls={count} shell={args.shell} workspace={work}', flush=True)


if __name__ == '__main__': main()
