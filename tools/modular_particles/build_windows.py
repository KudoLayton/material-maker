"""Build a NEW portable Material Maker Windows release with modular particles.
The working project, installed templates, existing builds and user settings are
never overwritten. Runtime .gd sources are retained so packaged MM can export
standalone Godot effects. Runs the exported EXE, not just the source editor.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def run(command, cwd, log, marker=None, timeout=480):
    with log.open('w', encoding='utf-8') as output:
        with subprocess.Popen([str(p) for p in command], cwd=cwd, stdout=output, stderr=subprocess.STDOUT,
                              creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)) as process:
            start = time.monotonic()
            while process.poll() is None:
                time.sleep(0.25)
                text = log.read_text(encoding='utf-8', errors='replace')
                if 'SCRIPT ERROR:' in text or time.monotonic()-start > timeout:
                    process.kill()
                    process.wait()
                    break
    text = log.read_text(encoding='utf-8', errors='replace')
    print(f'LOG: {log}', flush=True)
    print('\n'.join(line for line in text.splitlines() if 'MODULAR_' in line), flush=True)
    if process.returncode or 'SCRIPT ERROR:' in text or 'FAIL:' in text or (marker and marker not in text):
        print(text[-14000:])
        raise SystemExit(f'Build/verification failed: {log}')
    return text


def prepare(project, settings_name):
    ignore = shutil.ignore_patterns('.git', '.godot', '__pycache__', 'godotsteam')
    for name in ['addons', 'material_maker', 'splash_screen', 'demo']:
        shutil.copytree(ROOT / name, project / name, ignore=ignore)
    for source in ROOT.iterdir():
        if source.is_file() and source.suffix in ['.godot','.gd','.uid','.tscn','.tres','.png','.ico','.import','.cfg']:
            shutil.copy2(source, project / source.name)
    config = project / 'project.godot'
    text = re.sub(r'config/custom_user_dir_name="[^"]+"', f'config/custom_user_dir_name="{settings_name}"', config.read_text(encoding='utf-8'))
    config.write_text(text, encoding='utf-8')
    # Stock release templates disable arbitrary command-line scene overrides.
    # Attach only a fixed embedded observer in this build copy. It verifies
    # the REAL normal startup/CLI path, without replacing the main scene.
    # The working source parse_args.gd remains unchanged.
    bootstrap = project / 'parse_args.gd'
    text = bootstrap.read_text(encoding='utf-8')
    anchor = 'func _ready():\n'
    if text.count(anchor) != 1: raise SystemExit('Unexpected parse_args entrypoint')
    hook = ('\tvar validation_args := OS.get_cmdline_user_args()\n'
            '\tif validation_args.size() == 2 and validation_args[0] == "--modular-build-check":\n'
            '\t\tvar observer = load("res://validation/release_smoke.tscn").instantiate()\n'
            '\t\tget_tree().root.add_child.call_deferred(observer)\n')
    bootstrap.write_text(text.replace(anchor, anchor + hook), encoding='utf-8')
    validation = project / 'validation'
    validation.mkdir()
    shutil.copy2(ROOT / 'test/modular_particles/test_release.gd', validation / 'release_smoke.gd')
    shutil.copy2(ROOT / 'test/modular_particles/rename_checks.gd', validation / 'rename_checks.gd')
    shutil.copy2(ROOT / 'test/modular_particles/input_delete_checks.gd', validation / 'input_delete_checks.gd')
    shutil.copy2(ROOT / 'test/modular_particles/namespace_checks.gd', validation / 'namespace_checks.gd')
    for helper in ['standard_checks.gd', 'standard_ui_checks.gd', 'user_ui_checks.gd', 'workspace_release_checks.gd']:
        shutil.copy2(ROOT / 'test/modular_particles' / helper, validation / helper)
    (validation / 'release_smoke.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://validation/release_smoke.gd" id="1"]\n[node name="ReleaseSmoke" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', required=True, type=Path)
    parser.add_argument('--templates', required=True, type=Path)
    parser.add_argument('--output', type=Path, help='Must not already exist')
    parser.add_argument('--docs', type=Path, help='Optional existing compiled HTML docs, copied read-only')
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.check_output([str(engine),'--version'], text=True).strip()
    if not version.startswith('4.7.2.stable.'): raise SystemExit('Godot 4.7.2 stable required')
    templates = args.templates.resolve()
    if (templates / 'version.txt').read_text().strip() != '4.7.2.stable': raise SystemExit('Template version mismatch')
    for kind in ['debug','release']:
        if not (templates / f'windows_{kind}_x86_64.exe').is_file(): raise SystemExit('Windows x64 templates required')
    if args.docs and not (args.docs / 'index.html').is_file(): raise SystemExit('Invalid HTML docs directory')
    output = (args.output or ROOT / 'build' / ('modular-release-' + datetime.now().strftime('%Y%m%d-%H%M%S'))).resolve()
    output.mkdir(parents=True, exist_ok=False)  # Never reuse any existing delivery folder.
    project = Path(tempfile.mkdtemp(prefix='mm-modular-build-'))
    app = output / 'MaterialMaker'
    app.mkdir()
    logs = output / 'verification'
    logs.mkdir()
    settings = 'material_maker_modular/' + output.name
    print(f'OUTPUT: {output}\nWORKSPACE: {project}', flush=True)
    (output / 'BUILD_IN_PROGRESS.txt').write_text('Not verified yet. See verification logs.\n', encoding='utf-8')
    prepare(project, settings)
    preset = f'''[preset.0]
name="Windows Modular"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.gd,*.cfg,*.json,*.mmg,*.mmn,*.mmt,*.gdshader,*.ptex,*.mpfx,*.tmpl,*.txt,*.glsl,*.html,*.css,*.rst"
exclude_filter="test/*,tools/*,export_presets.cfg,addons/godotsteam/*"
script_export_mode=0
export_path="{(app / 'MaterialMaker.exe').as_posix()}"
[preset.0.options]
custom_template/debug="{(templates / 'windows_debug_x86_64.exe').as_posix()}"
custom_template/release="{(templates / 'windows_release_x86_64.exe').as_posix()}"
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
'''
    (project / 'export_presets.cfg').write_text(preset, encoding='utf-8')
    base = [engine,'--path',project]
    run(base + ['--headless','--editor','--import'], project, logs / 'import.log')
    run(base + ['--headless','--export-release','Windows Modular'], project, logs / 'export.log')
    if not (app / 'MaterialMaker.exe').is_file(): raise SystemExit('Export did not create the executable')
    # Sidecars intentionally remain readable/editable, matching MM's release paths.
    for name in ['environments','examples','library','meshes']:
        shutil.copytree(ROOT / 'material_maker' / name, app / name, ignore=shutil.ignore_patterns('*.import','*.uid'))
    # Release nodes are generator definitions/templates, NOT the similarly
    # named material_maker/nodes directory containing graph UI controls.
    shutil.copytree(ROOT / 'addons/material_maker/nodes', app / 'nodes', ignore=shutil.ignore_patterns('*.import','*.uid'))
    if args.docs: shutil.copytree(args.docs, app / 'doc')
    shutil.copy2(ROOT / 'LICENSE.md', app / 'LICENSE.md')
    shutil.copy2(ROOT / 'MODULAR_PARTICLES.md', app / 'MODULAR_PARTICLES.md')
    shutil.copy2(ROOT / 'PARTICLE_WORKSPACE.md', app / 'PARTICLE_WORKSPACE.md')
    shutil.copy2(ROOT / 'MODULAR_VFX_CLI.md', app / 'MODULAR_VFX_CLI.md')
    shutil.copy2(ROOT / 'STANDARD_PARTICLE_MODULES.md', app / 'STANDARD_PARTICLE_MODULES.md')
    shutil.copytree(ROOT / 'material_maker/panels/modular_particles/standard', app / 'modules/standard_particles', ignore=shutil.ignore_patterns('*.uid'))
    for example in ['basic_fountain','box_turbulence','sphere_burst','user_parameters']:
        (app / ('Open ' + example + '.cmd')).write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0MaterialMaker.exe" --no-splash "%~dp0examples\\modular_particles\\' + example + '.mpfx"\r\n', encoding='ascii')
    (app / 'Open mmtest.cmd').write_text('@echo off\r\ncd /d "%~dp0"\r\nstart "" "%~dp0MaterialMaker.exe" --no-splash "%~dp0examples\\modular_particles\\mmtest.mpfx"\r\n', encoding='ascii')
    smoke = logs / 'app'
    smoke.mkdir()
    graphics = ['--rendering-method','forward_plus','--rendering-driver','vulkan','--position','-32000,-32000','--max-fps','60']
    run([app / 'MaterialMaker.exe','--no-splash',app / 'examples/modular_particles/mmtest.mpfx','--log-file',logs / 'app-engine.log',*graphics,'--','--modular-build-check',smoke], app, logs / 'app-process.log', 'MODULAR_RELEASE PASS')
    report = json.loads((smoke / 'release-smoke.json').read_text(encoding='utf-8'))
    if not report['passed'] or report['editor']: raise SystemExit('Release smoke verification did not pass')
    shutil.copytree(smoke / 'godot-example', output / 'GodotExample')
    shutil.copytree(smoke / 'godot-basic-example', output / 'GodotBasicExample')
    shutil.copytree(smoke / 'godot-user-example', output / 'GodotUserParametersExample')
    shutil.copy2(smoke / 'basic-128.mpfx', app / 'examples/modular_particles/basic-128.mpfx')
    addon = output / 'GodotAddon' / 'addons' / 'mm_gpu_particles'
    shutil.copytree(output / 'GodotExample/addons/mm_gpu_particles', addon)
    guide = ROOT / 'GODOT_PARTICLES_PLUGIN.md'
    if guide.exists():
        for target in [output,output / 'GodotAddon',output / 'GodotExample',output / 'GodotBasicExample',output / 'GodotUserParametersExample',app]:
            shutil.copy2(guide,target / guide.name)
            shutil.copy2(ROOT / 'STANDARD_PARTICLE_MODULES.md',target / 'STANDARD_PARTICLE_MODULES.md')
            shutil.copy2(ROOT / 'USER_PARTICLE_PARAMETERS.md',target / 'USER_PARTICLE_PARAMETERS.md')
    shutil.make_archive(str(output / 'GodotAddon'), 'zip', output / 'GodotAddon')
    (output / 'START_HERE.txt').write_text('''Modular GPU Particles — Godot 4.7.2 stable / Windows x64 / Forward+ / Vulkan

실행: MaterialMaker/Open basic_fountain.cmd 또는 MaterialMaker/MaterialMaker.exe
User 제어 예제: MaterialMaker/Open user_parameters.cmd
기존 mmtest 예제는 MaterialMaker/Open mmtest.cmd로 열 수 있습니다.
EXE만 복사하지 말고 MaterialMaker 폴더 전체를 유지하세요.

기본 모듈 12종: Browse Library…에서 이름/카테고리/Stage로 검색하세요.
Add Copy는 선택한 행 다음에 독립 그래프 복사본과 필요한 Attribute를 함께 추가합니다.
Initialize/Solve 같은 다른 모듈은 자동 추가하지 않습니다. 상태 영역의 순서 진단을 확인하세요.
Gravity/Curl/Drag → Solve Motion 순서로 배치하며 Color/Scale over Life는 초기값을 사용합니다.
Curve/Gradient는 모듈 그래프에서, 수식은 Code 입력 우클릭 → Edit text에서 편집합니다.
예제: basic_fountain, box_turbulence, sphere_burst (각 Open *.cmd 제공)
상세 기본값/단위/의존성: MaterialMaker/STANDARD_PARTICLE_MODULES.md
원본 기본 모듈 .mmg: MaterialMaker/modules/standard_particles (필요하면 Import .mmg)

모듈 이름 변경: Spawn/Update 스택에서 모듈 선택 → Rename 버튼 또는 F2
이름 입력 후 Enter 또는 Rename으로 확인합니다. Cancel로 취소합니다.
현재 효과에서 같은 모듈 정의를 사용하는 모든 인스턴스에 반영됩니다.
Undo/Redo를 지원하며, Save로 .mpfx 문서에 저장하세요.
Library .mmg 파일과 다른 효과는 자동으로 변경하지 않습니다.

Module Input 삭제: 입력 행의 Delete 버튼을 누르세요.
Read 노드가 참조 중이면 삭제하지 않고 상태 영역에 참조 위치를 안내합니다.
연결되지 않은 Read와 중첩 그래프 안의 Read도 먼저 지워야 합니다.
같은 모듈의 모든 인스턴스 입력값을 함께 정리하며 Undo/Redo로 복구합니다.
삭제 후 Save로 .mpfx 문서에 저장하세요.

Namespace 표시:
Module.Position = 모듈 입력, Particle.Position = 기본 입자 위치,
Particle.Custom.Position = 별도의 사용자 Attribute, Context.delta = 시뮬레이션 값.
이름으로 자동 바인딩하지 않습니다. Read/Write는 역할이고 namespace는 유지됩니다.
Attribute 트리의 Name 열만 편집하며, 선택 설명에서 Renderer/Module Output 상태를 확인하세요.
긴 이름과 전체 ID는 툴팁으로 확인하고, 왼쪽 패널은 필요하면 스크롤하세요.

User Parameters: 왼쪽 User 패널에서 이름/타입/기본값을 만들고,
각 Module Input Source를 Constant에서 같은 타입의 User로 바꿉니다.
User.Speed는 Cone Speed Min/Max를 공유하고 User.Gravity/Tint도 게임에서 제어합니다.
User 변경은 Undo/Redo/Save를 지원하며, 값/이름 변경은 Preview 입자 상태를 유지합니다.
사용 중인 User 삭제/타입 변경은 먼저 모든 참조를 해제해야 합니다.
효과 원본/런타임은 최신 v2만 지원합니다. 구버전 자동 변환은 제공하지 않습니다.
상세 사용법·Inspector·API·최신 포맷: USER_PARTICLE_PARAMETERS.md
명령행 제작·검증·컴파일/Export: MaterialMaker/MODULAR_VFX_CLI.md
파티클 도크·Looping/Burst/Custom·카메라·HDRI: MaterialMaker/PARTICLE_WORKSPACE.md

User 제어 Godot 예제: GodotUserParametersExample/project.godot
같은 효과의 두 노드를 Left/Right로 독립 제어합니다. Reset은 선택한 노드만 복원합니다.
Animate left User.Speed는 게임 코드의 실시간 갱신 예입니다.
새 기본 모듈 Godot 예제: GodotBasicExample/project.godot (128개 burst)
기존 mmtest Godot 예제: GodotExample/project.godot
Godot 4.7.2에서 열고 F5로 실행하세요.
기존 프로젝트: GodotAddon.zip을 프로젝트 루트에 풀거나 Export 결과의
addons/mm_gpu_particles 및 effects/modular_particles를 복사하고 particles.tscn을 배치하세요.
기존 project.godot을 덮어쓰지 마세요. 세부 안내: GODOT_PARTICLES_PLUGIN.md

기존 Material Maker 설치/설정과 기존 빌드는 변경하지 않았습니다.
검증 결과: verification/ 및 build-info.json
''', encoding='utf-8-sig')
    info = {'engine':version,'templates':str(templates),'workspace':str(project),'executable':str(app / 'MaterialMaker.exe'),
            'user_settings':settings,'release_smoke':report,'script_export_mode':'text (runtime sources available)',
            'exe_sha256':hashlib.sha256((app / 'MaterialMaker.exe').read_bytes()).hexdigest()}
    (output / 'build-info.json').write_text(json.dumps(info,indent=2,ensure_ascii=False), encoding='utf-8')
    (output / 'BUILD_IN_PROGRESS.txt').unlink()
    print(f'BUILT: {app / "MaterialMaker.exe"}\nGODOT: {output / "GodotExample/project.godot"}\nGODOT BASIC: {output / "GodotBasicExample/project.godot"}\nGODOT USER: {output / "GodotUserParametersExample/project.godot"}\nADDON: {output / "GodotAddon.zip"}', flush=True)


if __name__ == '__main__': main()
