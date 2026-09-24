"""Windows installer behavior tests in disposable projects and real CLI exports."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'skills/godot-modular-vfx/scripts/Install-VfxEffect.ps1'


def digest(data): return hashlib.sha256(data).hexdigest()


def snapshot(path):
    return {p.relative_to(path).as_posix(): digest(p.read_bytes()) for p in path.rglob('*') if p.is_file()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--shell', default='powershell.exe')
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='mm-vfx-install-'))
    print('WORKSPACE:', root, flush=True)
    count = 0

    def cli(command, *extra, gpu=False):
        nonlocal count
        count += 1
        flags = ['--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--position', '-32000,-32000'] if gpu else ['--headless']
        report = root / f'cli-{count}.json'
        result = subprocess.run([str(args.app.resolve()), '--log-file', str(root / f'cli-{count}.log'), *flags, '--', '--mpfx-command', command, *map(str, extra), '--report', str(report)], capture_output=True, timeout=120)
        if result.returncode: raise AssertionError('CLI failed: ' + str(report))
        assert json.loads(report.read_text(encoding='utf-8'))['ok']

    def project(name):
        path = root / name
        path.mkdir()
        (path / 'project.godot').write_text('config_version=5\n[rendering]\nrenderer/rendering_method="forward_plus"\n', encoding='utf-8')
        (path / 'user.txt').write_text('do not touch', encoding='utf-8')
        return path

    def install(game, bundle=None, apply=False, recover=False, success=True):
        nonlocal count
        count += 1
        command = [args.shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(SCRIPT), '-Project', str(game)]
        if recover: command += ['-Recover']
        else: command += ['-Bundle', str(bundle)] + (['-Apply'] if apply else [])
        result = subprocess.run(command, capture_output=True, text=True, timeout=60)
        (root / f'install-{count}.log').write_text(result.stdout + result.stderr, encoding='utf-8')
        if (result.returncode == 0) != success:
            raise AssertionError(f'Unexpected installer exit {result.returncode}: {root / ("install-"+str(count)+".log")}\n{result.stdout}\n{result.stderr}')
        parsed = json.loads(result.stdout)
        assert parsed['ok'] == success
        print(f'PASS {count}: installer success={success} apply={apply} recover={recover}', flush=True)
        return parsed

    a = root / 'fountain.mpfx'
    b = root / 'burst.mpfx'
    cli('create', '--template', 'basic_fountain', '--output', a)
    cli('create', '--template', 'sphere_burst', '--output', b)
    bundle_a, bundle_b = root / 'bundle-a', root / 'bundle-b'
    cli('export', '--input', a, '--output', bundle_a, '--effect-id', 'fountain', gpu=True)
    cli('export', '--input', b, '--output', bundle_b, '--effect-id', 'burst', gpu=True)
    game = project('게임 space')
    original = snapshot(game)
    install(game, bundle_a)
    assert snapshot(game) == original, 'dry-run wrote files'
    install(game, bundle_a, apply=True)
    assert not (game / 'effects/modular_particles/fountain/demo.tscn').exists()
    assert original.items() <= snapshot(game).items()
    install(game, bundle_b, apply=True)
    before = snapshot(game / 'effects/modular_particles/burst')
    runtime_before = snapshot(game / 'addons')
    document = json.loads(a.read_text(encoding='utf-8'))
    document['emitter']['rate'] = 23.0
    a.write_text(json.dumps(document), encoding='utf-8')
    cli('export', '--input', a, '--output', bundle_a, '--effect-id', 'fountain', gpu=True)
    install(game, bundle_a, apply=True)
    assert snapshot(game / 'effects/modular_particles/burst') == before
    assert snapshot(game / 'addons') == runtime_before
    assert original.items() <= snapshot(game).items()
    installed = json.loads((game / '.mm-vfx/manifest.json').read_text(encoding='utf-8'))
    assert set(installed['effects']) == {'fountain', 'burst'}
    for path, expected in installed['effects']['fountain']['files'].items(): assert digest((game / path).read_bytes()) == expected
    # Force a real mid-publish I/O failure: allow manifest reads/backups but
    # deny replacement after effect.res has already been published.
    document['emitter']['rate'] = 47.0
    a.write_text(json.dumps(document), encoding='utf-8')
    cli('export', '--input', a, '--output', bundle_a, '--effect-id', 'fountain', gpu=True)
    before_effects = snapshot(game / 'effects')
    before_manifest = (game / '.mm-vfx/manifest.json').read_bytes()
    lock_command = (f"$f=[IO.File]::Open('{game / '.mm-vfx/manifest.json'}',[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); "
                    f"try {{ & '{SCRIPT}' -Project '{game}' -Bundle '{bundle_a}' -Apply; $code=$LASTEXITCODE }} finally {{ $f.Dispose() }}; exit $code")
    forced = subprocess.run([args.shell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', lock_command], capture_output=True, text=True, timeout=60)
    (root / 'forced-failure.log').write_text(forced.stdout + forced.stderr, encoding='utf-8')
    assert forced.returncode == 1 and 'rolled back' in forced.stdout, forced.stdout + forced.stderr
    assert snapshot(game / 'effects') == before_effects
    assert (game / '.mm-vfx/manifest.json').read_bytes() == before_manifest
    assert not (game / '.mm-vfx/transaction').exists()
    # User edits remain untouched when an update is rejected.
    particles = game / 'effects/modular_particles/fountain/particles.tscn'
    particles.write_bytes(particles.read_bytes() + b'\n; user modification\n')
    before = snapshot(game)
    install(game, bundle_a, apply=True, success=False)
    assert snapshot(game) == before
    # Same runtime can be adopted; incompatible or partial addon cannot be overlaid.
    adopt = project('adopt')
    shutil.copytree(bundle_a / 'addons', adopt / 'addons')
    install(adopt, bundle_a, apply=True)
    runtime = adopt / 'addons/mm_gpu_particles/effect.gd'
    runtime.write_bytes(runtime.read_bytes() + b'\n# local edit\n')
    before = snapshot(adopt)
    install(adopt, bundle_b, apply=True, success=False)
    assert snapshot(adopt) == before
    collision = project('collision')
    unmanaged = collision / 'effects/modular_particles/fountain/effect.res'
    unmanaged.parent.mkdir(parents=True)
    unmanaged.write_bytes(b'user-owned')
    before = snapshot(collision)
    install(collision, bundle_a, success=False)
    assert snapshot(collision) == before
    # Linked ancestor and forged export traversal are rejected without writes.
    linked = root / 'linked'
    subprocess.run([args.shell, '-NoProfile', '-NonInteractive', '-Command', f'New-Item -ItemType Junction -Path "{linked}" -Target "{game}" | Out-Null'], check=True, capture_output=True)
    install(linked, bundle_a, success=False)
    forged = root / 'forged'
    shutil.copytree(bundle_a, forged)
    bad = json.loads((forged / 'mm_particles_manifest.json').read_text(encoding='utf-8'))
    bad['files']['../project.godot'] = '0' * 64
    (forged / 'mm_particles_manifest.json').write_text(json.dumps(bad), encoding='utf-8')
    install(collision, forged, success=False)
    # Simulate interruption after the first publish; recovery also covers
    # entries not published yet and refuses subsequent concurrent user edits.
    recovery = project('recovery')
    tx = recovery / '.mm-vfx/transaction'
    entry_path = 'effects/modular_particles/test/particles.tscn'
    target = recovery / entry_path
    target.parent.mkdir(parents=True)
    target.write_bytes(b'published')
    backup = tx / ('backup/' + entry_path)
    backup.parent.mkdir(parents=True)
    backup.write_bytes(b'original')
    journal = {'format':'mm_vfx_transaction','version':1,'project':str(recovery),'entries':[{'path':entry_path,'before':digest(b'original'),'after':digest(b'published')}]}
    (tx / 'journal.json').write_text(json.dumps(journal), encoding='utf-8')
    install(recovery, bundle_a, success=False)
    install(recovery, recover=True)
    assert target.read_bytes() == b'original' and not tx.exists()
    tx.mkdir()
    backup.parent.mkdir(parents=True)
    backup.write_bytes(b'original')
    target.write_bytes(b'concurrent user edit')
    (tx / 'journal.json').write_text(json.dumps(journal), encoding='utf-8')
    before = snapshot(recovery)
    install(recovery, recover=True, success=False)
    assert snapshot(recovery) == before
    print(f'MODULAR_INSTALL PASS operations={count} root={root}', flush=True)


if __name__ == '__main__': main()
