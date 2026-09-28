"""Check local skill links plus real portable helper calls, using no game project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zlib
from render_backend import add_driver_argument

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / 'skills/godot-modular-vfx'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--shell', default='powershell.exe')
    add_driver_argument(parser)
    args = parser.parse_args()
    for file in SKILL.rglob('*.md'):
        for target in re.findall(r'\]\(([^)]+)\)', file.read_text(encoding='utf-8')):
            if '://' not in target:
                assert (file.parent / target.split('#')[0]).is_file(), f'Broken reference: {file}: {target}'
    skill_text = (SKILL / 'SKILL.md').read_text(encoding='utf-8')
    frontmatter = skill_text.split('---', 2)[1]
    assert re.search(r'^name: godot-modular-vfx$', frontmatter, re.M)
    description = re.search(r'^description: (.+)$', frontmatter, re.M).group(1)
    assert 1 <= len(description) <= 1024
    assert 'MMGPUParticles2D' in description and 'MMGPUParticles3D' in description
    assert 'document_version: 2' in skill_text and 'effect_version: 3' in skill_text
    metadata = (SKILL / 'agents/openai.yaml').read_text(encoding='utf-8')
    assert '$godot-modular-vfx' in metadata and 'allow_implicit_invocation: true' in metadata
    assert '2D/3D' in metadata
    work = Path(tempfile.mkdtemp(prefix='mm-vfx-skill-'))
    print('WORKSPACE:', work, flush=True)
    source = work / '한글 space.mpfx'
    count = 0

    def run(command, extra=(), expected=0, environment=False, culture=None):
        nonlocal count
        count += 1
        env = os.environ.copy()
        env.pop('MM_VFX_APP', None)
        call = [args.shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SKILL / 'scripts/Invoke-Vfx.ps1'), '-Command', command, *map(str, extra)]
        if environment: env['MM_VFX_APP'] = str(args.app.resolve())
        else: call += ['-App', str(args.app.resolve())]
        if command == 'export': call += ['-RenderingDriver', args.rendering_driver]
        if culture:
            # Exercise the helper under a decimal-comma culture, not just the caller's default.
            def quote(value): return "'" + value.replace("'", "''") + "'"
            flags = ' '.join(call[i] + ' ' + quote(call[i + 1]) for i in range(7, len(call), 2))
            script = (f'[Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo({quote(culture)}); '
                      f'& {quote(call[6])} {flags}; exit $LASTEXITCODE')
            call = call[:5] + ['-Command', script]
        result = subprocess.run(call, env=env, capture_output=True, text=True, timeout=210)
        (work / f'call-{count}.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        assert result.returncode == expected, result.stdout + result.stderr
        report = json.loads(result.stdout)
        assert report['ok'] == (expected == 0)
        if expected != 1:
            assert report['contract_version'] == 1 and report['command'] == command and report['exit_code'] == expected
        if command == 'export' and expected == 0:
            data = report['data']
            assert data['gpu_compiled'] and data['effect_version'] == 3 and data['rendering_driver'] == args.rendering_driver
            assert data['manifest']['effect_version'] == 3 and data['manifest']['render_target'] == data['render_target']
            for path, digest in data['manifest']['files'].items():
                assert hashlib.sha256((Path(data['output']) / path).read_bytes()).hexdigest() == digest, path
        print(f'PASS {count}: {command} exit={expected}', flush=True)
        return report

    cap = run('capabilities', environment=True)['data']
    assert cap['document_version'] == 2 and cap['effect_version'] == 3
    assert cap['render_targets'] == ['3d', '2d'] and cap['runtime_effect_versions'] == {'3d': [2, 3], '2d': [3]}
    assert cap['export_optional_options'] == ['render-target', 'pixels-per-unit', 'flip-y', 'blend-mode', 'sprite']
    run('create', ['-Template', 'basic_fountain', '-Output', source])
    original = source.read_bytes()
    assert json.loads(original)['version'] == 2
    run('create', ['-Template', 'sphere_burst', '-Output', source], expected=5)
    assert source.read_bytes() == original
    run('inspect', ['-InputFile', source])
    validated = run('validate', ['-InputFile', source])['data']
    assert validated['document_version'] == 2 and validated['effect_version'] == 3 and not validated['gpu_compiled']
    out3d = work / 'export space'
    flags3d = ['-InputFile', source, '-Output', out3d, '-EffectId', 'helper-test', '-Capacity', '256']
    exported = run('export', flags3d)['data']
    assert exported['render_target'] == '3d'
    run('export', flags3d + ['-RenderTarget', '3D'])
    assert 'particles_3d.gd' in (out3d / 'effects/modular_particles/helper-test/particles.tscn').read_text(encoding='utf-8')

    out2d = work / '2d defaults'
    flags2d = ['-InputFile', source, '-Output', out2d, '-EffectId', 'helper-2d', '-Capacity', '256', '-RenderTarget', '2d']
    default2d = run('export', flags2d)['data']
    assert default2d['render_target'] == '2d' and default2d['source_hash'] == exported['source_hash']
    scene2d = out2d / 'effects/modular_particles/helper-2d/particles.tscn'
    text = scene2d.read_text(encoding='utf-8')
    assert 'particles_2d.gd' in text and 'pixels_per_unit = 100' in text and 'flip_y = true' in text and 'blend_mode = 0' in text
    assert not (scene2d.parent / 'sprite.res').exists()

    # A small RGBA PNG at a Unicode/space path exercises quoting and embedded assets.
    sprite = work / '한글 sprite.png'
    def chunk(kind, data): return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    sprite.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 6, 0, 0, 0))
                       + chunk(b'IDAT', zlib.compress((b'\0' + b'\xff\x80\0\x80' * 2) * 2)) + chunk(b'IEND', b''))
    textured = run('export', flags2d + ['-PixelsPerUnit', '123.5', '-FlipY', 'FALSE', '-BlendMode', 'ALPHA', '-Sprite', sprite], culture='de-DE')['data']
    assert textured['source_hash'] == exported['source_hash']
    text = scene2d.read_text(encoding='utf-8')
    assert 'pixels_per_unit = 123.5' in text and 'flip_y = false' in text and 'blend_mode = 1' in text
    assert 'texture = ExtResource("3")' in text and 'sprite.res' in text
    assert (scene2d.parent / 'sprite.res').is_file() and str(sprite) not in text
    assert 'effects/modular_particles/helper-2d/sprite.res' in textured['manifest']['files']

    def snapshot(folder):
        return {p.relative_to(folder).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.rglob('*') if p.is_file()}

    protected3d, protected2d = snapshot(out3d), snapshot(out2d)
    for value in ['0', '-1', 'NaN', 'Infinity', '1e100']:
        run('export', flags2d + ['-PixelsPerUnit', value], expected=2)
    for name, value in [('-PixelsPerUnit', '100'), ('-FlipY', 'true'), ('-BlendMode', 'effect'), ('-Sprite', sprite)]:
        run('export', flags3d + [name, value], expected=2)
    for name, value in [('-RenderTarget', '2d'), ('-PixelsPerUnit', '100'), ('-FlipY', 'false'), ('-BlendMode', 'alpha'), ('-Sprite', sprite)]:
        run('validate', ['-InputFile', source, name, value], expected=2)
    run('export', flags2d + ['-Sprite', work / 'missing.png'], expected=5)
    run('export', flags3d + ['-RenderTarget', '2d'], expected=5)
    assert snapshot(out3d) == protected3d and snapshot(out2d) == protected2d
    scene2d.write_bytes(scene2d.read_bytes() + b'\n; user edit\n')
    edited = snapshot(out2d)
    run('export', flags2d, expected=5)
    assert snapshot(out2d) == edited, 'modified managed output was overwritten'
    run('validate', ['-InputFile', work / 'missing.mpfx'], expected=5)
    run('inspect', ['-InputFile', source, '-Report', source], expected=1)
    assert source.read_bytes() == original
    print(f'MODULAR_SKILL_HELPER PASS calls={count} shell={args.shell} driver={args.rendering_driver} workspace={work}', flush=True)


if __name__ == '__main__': main()
