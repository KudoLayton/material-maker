"""Source-free author/export/install/game execution using the delivered skill and app.
Only this test harness and the standalone GPU assertion scene come from checkout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from verify_export import run

ROOT = Path(__file__).resolve().parents[2]


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    parser.add_argument('--templates', type=Path, required=True)
    parser.add_argument('--skill', type=Path, help='Optional npx-installed skill instead of bundled copy')
    args = parser.parse_args()
    app = args.build.resolve() / 'MaterialMaker/MaterialMaker.exe'
    skill = args.skill.resolve() if args.skill else app.parent / 'skills/godot-modular-vfx'
    package = json.loads((app.parent / 'vfx-package.json').read_text(encoding='utf-8'))
    root = Path(tempfile.mkdtemp(prefix='mm-vfx-delivery-'))
    print('WORKSPACE:', root, flush=True)
    env = os.environ.copy()
    env.pop('MM_VFX_APP', None)
    game = root / 'game'
    game.mkdir()
    settings = 'mm-modular-tests/' + root.name
    (game / 'project.godot').write_text(f'''config_version=5
[application]
config/name="Independent Skill Game"
run/main_scene="res://verify.tscn"
config/use_custom_user_dir=true
config/custom_user_dir_name="{settings}"
[display]
window/size/viewport_width=960
window/size/viewport_height=640
[rendering]
renderer/rendering_method="forward_plus"
environment/defaults/default_clear_color=Color(0,0,0,1)
''', encoding='utf-8')
    project_hash = sha(game / 'project.godot')
    steps = []

    def invoke(script, *flags):
        index = len(steps)
        cmd = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(skill / 'scripts' / script), *map(str, flags)]
        if script == 'Invoke-Vfx.ps1' and args.skill: cmd += ['-App', str(app)]
        result = subprocess.run(cmd, cwd=root, env=env, capture_output=True, text=True, timeout=210)
        log = root / f'helper-{index}.log'
        log.write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode: raise SystemExit(f'Helper failed: {log}')
        data = json.loads(result.stdout)
        assert data['ok']
        steps.append({'script':script,'arguments':list(map(str,flags)),'log':str(log)})
        return data

    # No -App or environment override: packaged helper must locate enclosing app.
    cap = invoke('Invoke-Vfx.ps1','-Command','capabilities')['data']
    assert cap['runtime_id'] == package['runtime_id']
    assert cap['runtime_files'] == package['runtime_files']
    assert cap['document_version'] == cap['effect_version'] == 2
    for name, template in [('fountain','user_parameters'),('burst','sphere_burst')]:
        source = root / (name + '.mpfx')
        invoke('Invoke-Vfx.ps1','-Command','create','-Template',template,'-Output',source)
        document = json.loads(source.read_text(encoding='utf-8'))
        if name == 'fountain':
            next(p for p in document['user_parameters'] if p['name']=='Speed')['default'] = 4.0
            document['emitter']['rate'] = 60.0
        else:
            document['emitter'].update(rate=0.,duration=0.5,loop=False,bursts=[{'time':0.,'count':12}])
        source.write_text(json.dumps(document,indent=2)+'\n',encoding='utf-8')
        invoke('Invoke-Vfx.ps1','-Command','validate','-InputFile',source)
        bundle = root / ('staging-' + name)
        invoke('Invoke-Vfx.ps1','-Command','export','-InputFile',source,'-Output',bundle,'-EffectId',name,'-Capacity','256')
        invoke('Install-VfxEffect.ps1','-Bundle',bundle,'-Project',game)
        invoke('Install-VfxEffect.ps1','-Bundle',bundle,'-Project',game,'-Apply')
    assert sha(game / 'project.godot') == project_hash
    assert not (game / 'addons/material_maker').exists()
    assert not list(game.rglob('*.mpfx'))
    for name in ['fountain','burst']:
        assert not (game / f'effects/modular_particles/{name}/demo.tscn').exists()
    shutil.copy2(ROOT / 'test/modular_particles/standalone_skill_smoke.gd',game / 'verify.gd')
    (game / 'verify.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://verify.gd" id="1"]\n[node name="Verify" type="Node"]\nscript=ExtResource("1")\n',encoding='utf-8')
    base = [str(args.godot.resolve()),'--path',str(game)]
    graphics = ['--rendering-method','forward_plus','--rendering-driver','vulkan','--position','-32000,-32000','--max-fps','60']
    run(base + ['--headless','--editor','--import'],game,'import')
    run(base + graphics,game,'editor-runtime','MODULAR_SKILL_GAME PASS')
    assert (args.templates / 'version.txt').read_text().strip() == '4.7.2.stable'
    (game / 'windows').mkdir()
    (game / 'export_presets.cfg').write_text('''[preset.0]
name="Windows"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=".mm-vfx/*"
export_path="windows/SkillGame.exe"
[preset.0.options]
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
''' + ''.join(f'custom_template/{kind}="{(args.templates.resolve() / ("windows_"+kind+"_x86_64.exe")).as_posix()}"\n' for kind in ['debug','release']),encoding='utf-8')
    run(base + ['--headless','--export-release','Windows'],game,'export')
    release_log = game / 'release-engine.log'
    run([str(game / 'windows/SkillGame.exe'),'--log-file',str(release_log),*graphics],game,'windows-runtime')
    text = release_log.read_text(encoding='utf-8')
    assert 'MODULAR_SKILL_GAME PASS' in text and 'editor=false' in text and 'ERROR:' not in text and 'leaked' not in text
    assert sha(game / 'project.godot') == project_hash
    image = Path(os.environ['APPDATA']) / settings / 'skill-game.png'
    shutil.copy2(image,root / 'skill-game.png')
    summary = {'passed':True,'app':str(app),'skill':str(skill),'package':package,'project':str(game),'steps':steps,'source_free_game':True,'project_settings_unchanged':True,'editor_runtime':True,'windows_release':True}
    (root / 'verification.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print('MODULAR_SKILL_DELIVERY PASS',root,flush=True)


if __name__ == '__main__': main()
