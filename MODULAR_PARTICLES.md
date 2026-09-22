# Modular GPU Particles v1

Godot **4.7.2 stable / Forward+ / Vulkan** 전용입니다. 기존 `.ptex` 파티클 셰이더 편집기는 유지하며, 새 `.mpfx` 문서는 별도 Compute 시뮬레이션과 `MMGPUParticles3D`를 사용합니다. 엔진 소스 변경은 없습니다.

## 소스 받기

이 public 저장소에는 private 런타임의 **submodule 참조만** 들어 있습니다. `KudoLayton/godot-modular-gpu-particles` 접근 권한이 필요합니다.

```powershell
git clone --recurse-submodules git@github.com:KudoLayton/material-maker.git
# 이미 clone했다면 Material Maker 저장소에서:
git submodule update --init --recursive
```

`addons/mm_gpu_particles`가 초기화된 다음 Godot import/검사/빌드를 실행하세요. 권한이 없는 public clone만으로는 이 포크를 실행·빌드할 수 없습니다. 런타임 코드를 수정할 때는 private 저장소에 먼저 커밋·push한 뒤 이 저장소의 submodule commit을 갱신합니다. `git submodule update --remote`로 임의 최신 버전을 사용하지 말고 고정된 commit을 사용하세요.

## 사용

1. 이 소스 버전의 Material Maker에서 **File → New Modular GPU Particles**를 선택합니다.
2. 또는 **File → Load**로 `material_maker/examples/modular_particles/mmtest.mpfx`를 엽니다.
3. Spawn/Update 스택에서 모듈을 선택합니다. 기존 MM 그래프 캔버스와 Library 노드를 그대로 사용합니다.
4. `Read`, `Write binding`, `Add Module Input`으로 Attribute와 입력을 연결합니다. 입력 값은 JSON 스칼라/배열로 입력 후 Enter로 확정합니다.
5. Up/Down, Copy, On/Off, Remove, Undo/Redo를 지원합니다. 모듈 이름은 **스택에서 선택 → Rename 또는 F2 → 이름 입력 → Enter/Rename**으로 변경합니다. Preview는 내보내기와 같은 런타임입니다. 휠로 확대/축소합니다.
6. `Emitter settings`에서 방출·수명·렌더 설정 JSON을 편집합니다. 그래프 오류는 Stage/인스턴스/노드 위치를 표시하며 마지막 정상 Preview를 유지합니다.
7. `Save`는 저작용 `.mpfx`, `Save .mmg`는 재사용 모듈 스냅샷을 저장합니다. `Import .mmg`로 명시적으로 모듈을 갱신합니다. 외부 Library 변경을 자동 반영하지 않습니다.
8. `Export`에서 빈 출력 폴더를 선택합니다. 생성된 `project.godot`을 Godot 4.7.2로 열고 실행하거나 `particles.tscn`을 게임 씬에 인스턴스화합니다.

### Namespace와 바인딩 구분

| 표시 | 뜻 |
|---|---|
| `Module.Position` | 모듈 인스턴스의 공통 입력값 |
| `Particle.Position` | 기본 입자 위치 Attribute |
| `Particle.Custom.Position` | 이름만 Position인 별도의 사용자 정의 Attribute |
| `Context.delta` | 시뮬레이션 컨텍스트 값 |

단수형 `Particle`을 사용합니다. `Read`와 `Write`는 역할이며 같은 Attribute를 출력에 연결해도 namespace는 바뀌지 않습니다. 이름을 `Position`이나 `Particle.Position`으로 정해도 타입/바인딩을 추론하지 않습니다. Module Input의 Attribute 바인딩 기능을 추가한 것은 아닙니다.

- Attribute 트리는 **Namespace / Name / Type·ID** 열입니다. 사용자 Attribute의 **Name 열만** 원래 이름으로 편집합니다. namespace/타입/ID 배지는 저장 이름에 섞이지 않습니다.
- Attribute를 선택하거나 입력값에 포커스를 주면 상세 설명에서 전체 이름·ID·종류·역할을 확인합니다. 노드와 포트에도 툴팁을 제공합니다.
- `Renderer`는 실제 렌더 용도입니다. 기본 Position/Rotation/Scale/Color 및 설정된 `INSTANCE_CUSTOM` 대상을 구분합니다. `Particle.Custom`은 사용자 정의라는 뜻이지, 영원히 렌더에 연결할 수 없다는 뜻은 아닙니다.
- `Module Output`의 **Not registered / Unconnected — existing value preserved / Connected**는 포트 미등록/등록 후 미연결/와이어 연결을 뜻합니다. 렌더 바인딩과는 별개입니다.
- 같은 namespace 안의 동명 항목은 읽기 전용 `[#ID]` 배지로 구분합니다. 접두사 충돌 시 길이를 늘립니다. 긴 이름은 목록에서 생략하고 툴팁으로 전체를 표시합니다. 왼쪽 패널은 스크롤할 수 있습니다.
- 정의 ID가 없으면 `Missing`으로 표시하고 기존 오류를 유지합니다. 같은 이름의 다른 항목으로 자동 연결하지 않습니다. 문서 컨텍스트가 없는 Library 미리보기는 저장된 이름을 쓰면서 정의 확인 불가를 안내합니다.
- 이 표시는 직렬화하지 않는 UI 정보입니다. 기존 `.mpfx`/`.mmg`, stable ID, shader, GPU layout, 런타임 parameter API를 변경하지 않습니다. 중첩 그래프/이름 변경/Undo·Redo/import 후에도 현재 정의를 기준으로 표시합니다.

### 모듈 이름 변경

- F2는 **Spawn/Update 스택에 키보드 포커스가 있을 때만** 동작합니다. 그래프 노드 이름 변경과는 별개입니다.
- 현재 효과의 **모듈 정의 이름**을 바꿉니다. Copy/Add로 만든 같은 정의의 인스턴스는 모두 같은 이름으로 표시됩니다. 인스턴스별 별칭이 아닙니다.
- 빈 이름은 허용하지 않으며 앞뒤 공백을 제거합니다. Cancel로 취소하고 Undo/Redo로 되돌릴 수 있습니다.
- Save 후 `.mpfx`를 다시 열어도 유지됩니다. `Save .mmg`에도 새 이름이 들어갑니다. 기존 Library 파일, 파일명, 다른 효과는 자동 변경하지 않습니다.
- 모듈/입력/Attribute ID, 연결과 생성 셰이더는 유지되며 이름 변경만으로 GPU Preview를 재시작하지 않습니다.

### Module Input 삭제

- 모듈을 선택하고 입력 행의 **Delete** 버튼을 누릅니다.
- 같은 모듈의 그래프에 해당 입력을 읽는 Read 노드가 있으면 삭제하지 않고 아래 상태 영역에 참조 노드 경로를 표시합니다. **연결되지 않은 Read와 중첩 그래프 안의 Read도 먼저 삭제**해야 합니다. 다른 모듈의 같은 ID나 Attribute Read는 삭제를 막지 않습니다.
- 현재 효과의 공유 모듈 입력 정의와 모든 Spawn/Update 인스턴스의 해당 입력값을 함께 지웁니다. 비활성 인스턴스도 정리하지만 다른 입력이나 다른 모듈은 변경하지 않습니다.
- **Undo/Redo**로 입력 정의·순서·인스턴스별 값을 함께 복구/재삭제합니다. Save 후 `.mpfx`를 다시 열어도 유지되고 `Save .mmg`에도 반영됩니다. 외부 Library 파일은 자동 수정하지 않습니다.
- 삭제로 입력 버퍼 구성이 바뀌면 GPU Preview를 갱신합니다. 일반적인 입력값 변경은 기존처럼 시뮬레이션을 재시작하지 않습니다.

기존 설치된 Material Maker 실행 파일은 수정하지 않았습니다. 아래 빌드 도구로 새 실행용 패키지를 만들 수 있습니다. 빌드는 런타임 `.gd` 원문을 보존하여 배포된 MM 실행 파일에서도 효과를 다시 내보낼 수 있게 합니다. 원문이 없는 다른 패키지는 exporter가 거부합니다. 빌드/검증 도구는 선택적 GodotSteam 확장을 **임시 사본에서만** 제외합니다.

## Windows 포터블 빌드

```powershell
python tools/modular_particles/build_windows.py --godot $GODOT --templates $TEMPLATES
```

`$GODOT`은 4.7.2 console executable, `$TEMPLATES`는 `version.txt`와 Windows x64 debug/release 템플릿이 있는 `4.7.2.stable` 폴더입니다. `--output`을 지정하면 반드시 아직 없는 폴더여야 합니다. 기존 컴파일된 HTML 문서는 `--docs`로 읽기 전용 복사할 수 있습니다.

출력은 새 `build/modular-release-날짜-시간/` 폴더입니다.

- `MaterialMaker/MaterialMaker.exe`: 일반 실행용 앱. Godot Editor 없이 실행합니다.
- `MaterialMaker/Open mmtest.cmd`: 동봉 예제를 바로 엽니다.
- `GodotExample/project.godot`: 앱의 Export로 생성한 독립 Godot 예제.
- `GodotAddon.zip`: 프로젝트 루트에 풀 수 있는 런타임 애드온.
- `verification/`: 실제 Release EXE에서 열기/Preview/저장/내보내기를 확인한 로그.

앱은 기존 Material Maker와 별도 설정 폴더를 사용합니다. EXE만 이동하지 말고 `MaterialMaker` 폴더 전체를 유지하세요. **Godot 플러그인 설치와 사용법은 [GODOT_PARTICLES_PLUGIN.md](GODOT_PARTICLES_PLUGIN.md)**를 참고하세요.

## 데이터와 실행 규칙

- `.mpfx`: format/version/target, Attribute 정의, 모듈 정의 스냅샷, Spawn/Update 인스턴스 목록, Emitter/Renderer 설정.
- ID는 표시 이름과 분리됩니다. 이름 변경으로 저장 위치나 연결을 바꾸지 않습니다.
- Attribute: `float`, `int`, `uint`, `bool`, `vec2`, `vec3`, `vec4`. GPU에서는 32-bit word 기반 SoA이며 정수는 float 변환 없이 보존합니다.
- 기본 Attribute: Position, Velocity, quaternion Rotation, Scale, Color, Age, Lifetime, Alive, ParticleID, CustomData. Age/ParticleID는 읽기 전용입니다.
- 사용자 Attribute 개수에 32개 제한은 없습니다. GPU 용량과 **버퍼당 128 MiB**의 보수적인 안전 한도를 검증합니다.
- 각 모듈은 진입 시 상태를 읽고 출력을 함께 반영합니다. 다음 모듈은 갱신된 상태를 읽습니다. 모듈 순서가 실행 순서입니다. 위치 적분도 명시적인 Update 모듈입니다.
- 한 정의를 여러 번 인스턴스화할 수 있습니다. 입력 키는 `instance_id/input_id`, 생성 함수는 인스턴스별 namespace로 분리됩니다. 숫자 입력 변경은 시뮬레이션 재생성 없이 전달됩니다.
- GPU에서 빈 슬롯 선택, Spawn, Update, 생존 압축, MultiMesh 간접 드로우 수 갱신을 수행합니다. Prefix scan은 결정적인 슬롯 순서를 사용합니다.
- 정상 실행 경로에는 입자별 CPU 루프, GPU readback, `sync()`가 없습니다. 테스트만 GPU 데이터를 읽습니다.
- 고정 step은 1/60초, 프레임당 최대 8 step입니다. 초과 시간은 `clock.dropped_time`으로 기록합니다. capacity 초과 요청은 버리며 ID sequence는 진행합니다.
- Local/World, rate, timed bursts, duration/loop, 수명, seed, play/pause/stop/restart를 지원합니다. Stop은 새 방출만 중단하고 살아 있는 입자는 계속 갱신합니다.

```gdscript
$Particles.play()
$Particles.pause()
$Particles.stop()
$Particles.restart()
$Particles.emit_burst(128)
$Particles.set_parameter("mmtest_initialize/velocity", 8.0)
```

## 그래프와 렌더 범위

지원: 기존 Math/Vector/Random, Curve, FBM, 명시적 좌표 Evaluate Function, quaternion, 중첩 MM 서브그래프와 named module bindings.

v1 제외: 기존 particle built-in 직접 참조, 외부 텍스처/베이크 Buffer·Sampler·배열, 충돌·서브이미터, 투명 depth sorting, 자동 `.ptex` 변환. 지원하지 않는 연결은 진단하며 조용히 다른 값으로 대체하지 않습니다. 하위 compiler의 명시적 write-step IR도 테스트하지만 UI 모듈은 하나의 Module Output으로 상태를 반영합니다.

렌더: 기본 쿼드/원형 알파 쿼드 또는 런타임 `mesh`, 다중 surface, Transform/Color/INSTANCE_CUSTOM, billboard, additive/opaque/cutout, 사용자 `draw_material` 및 `visibility_aabb`. AABB는 사용자가 충분히 크게 지정해야 합니다. Editor 내 시뮬레이션은 기본 비활성이고 `preview_in_editor`로 켭니다.

**4.7.2 고정 이유:** 간접 MultiMesh 해제 시 해당 엔진 버전에서 소유권을 잃는 command buffer를 `multimesh_lifetime.gd`가 render thread에서 회수합니다. 여전히 renderer 소유인 RID를 해제하지 않으며 다른 엔진 버전에는 이 우회 처리를 적용하지 않습니다.

## 내보내기와 파일 보호

출력 폴더당 하나의 효과를 관리합니다.

- `addons/mm_gpu_particles/`: Material Maker에 의존하지 않는 런타임.
- `effects/modular_particles/effect.res`: 타입·레이아웃·입력·설정·원문 hash와 **미리 컴파일한 SPIR-V**.
- `particles.tscn`, `demo.tscn`, `effect.glsl.txt`: 인스턴스 씬, 데모, 진단용 원문.
- `mm_particles_manifest.json`: exporter 소유 파일의 SHA-256.

기존 `project.godot`과 무관한 파일은 덮어쓰지 않습니다. 기존 대상 파일이 manifest 소유이고 checksum이 그대로일 때만 갱신합니다. 사용자 수정/미관리 파일 충돌은 **아무 파일도 바꾸기 전에** 거부합니다. 임시 staging에서 컴파일·저장하고 manifest를 마지막에 반영합니다. 게시 실패 시 rollback하며, rollback 실패 시 복구용 backup을 남기고 위치를 보고합니다. 관리 경로의 링크도 거부합니다.

Windows Release에서 Godot Editor나 MM autoload 없이 실행을 검증했습니다. 컴파일된 effect를 실행할 때 Material Maker, 그래프 compiler, 원본 `.mpfx`가 필요하지 않습니다.

## mmtest 예제

원본 `D:/Godot/Projects/gpu-vfx-pack/fx/mmtest/mmtest.ptex`는 수정하지 않았습니다. 고정된 검증 사본은 `test/modular_particles/fixtures/mmtest_reference.ptex`입니다. 범용 변환기가 아닌 명시적 재작성입니다.

| Stage | 모듈 | 역할 |
|---|---|---|
| Spawn | Initialize Particle | 랜덤 방향, Velocity, InitialVelocity, InitialScale |
| Spawn | Spherical UV | 방향으로부터 vec2 UV 저장 |
| Update | Integrate Previous Velocity | 이전 프레임 속도로 위치 적분; 새 입자 첫 프레임 제외 |
| Update | Normalized Age | Age / Lifetime |
| Update | Velocity and Scale over Life | 원본 Curve를 초기 속도·크기에 적용 |
| Update | Curl Noise XY | FBM 중앙차분 간격 0.0001, frequency 0.25, strength 2 |

128개, 0.7초 반복 burst, 초기 speed 10, scale `[1,1,1]`. 모듈별 `.mmg`는 예제 옆 `modules/`에 있습니다. Sample의 InitialScale은 Spawn 시점 값을 저장합니다.

## 검증 명령

아래 명령은 `material-maker` 디렉터리 기준입니다. `$GODOT`은 정확한 4.7.2 console executable 경로입니다. 모두 새 임시 디렉터리를 생성하며 기존 `build/`를 재사용하지 않습니다.

```powershell
python tools/modular_particles/run_tests.py --godot $GODOT --test test_compiler --headless
# GPU 검사: gpu_probe, test_shader, test_runtime, test_render, test_performance
python tools/modular_particles/run_tests.py --godot $GODOT --test test_runtime
python tools/modular_particles/run_tests.py --godot $GODOT --test test_performance
python tools/modular_particles/run_app_tests.py --godot $GODOT --test test_namespace_model,test_namespace_editor
python tools/modular_particles/run_app_tests.py --godot $GODOT --test test_module_rename,test_module_input_delete
python tools/modular_particles/run_app_tests.py --godot $GODOT --test all --keep-going
# 위 test_export가 생성한 PROJECT/standalone을 지정
python tools/modular_particles/verify_export.py --godot $GODOT --bundle $BUNDLE --templates $TEMPLATES
python tools/modular_particles/build_mmtest_example.py --source D:/Godot/Projects/gpu-vfx-pack/fx/mmtest/mmtest.ptex --check
```

`--templates`는 설치된 4.7.2.stable 템플릿을 읽기만 합니다. 시스템 템플릿이나 기존 배포 파일을 덮어쓰지 않습니다. `run_app_tests --test legacy:all` 또는 쉼표로 구분한 테스트 목록도 사용할 수 있습니다. 실제 결과와 남은 검증은 [검증 기록](test/modular_particles/VALIDATION.md)을 참고하세요.
