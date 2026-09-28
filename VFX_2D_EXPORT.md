# 같은 그래프를 Godot 2D로 내보내기

Godot **4.7.2 stable / Windows x64 / Forward+ / Vulkan·D3D12**가 필요합니다. 기본 `GPUParticles2D`를 대체하는 셰이더 변환 기능이 아니라, 기존 Compute 애드온에 **MMGPUParticles2D** 출력을 추가합니다. 엔진 수정은 없습니다.

## 빠른 시작

1. 기존 `.mpfx`를 열고 평소처럼 그래프를 편집합니다. 편집기 미리보기는 계속 3D입니다.
2. **Export → 2D — MMGPUParticles2D**를 선택합니다.
3. Pixels Per Unit, Flip Y, Blend Mode, 선택적 PNG를 설정하고 빈 폴더로 내보냅니다.
4. 결과의 `addons/mm_gpu_particles/`와 `effects/modular_particles/`를 게임에 복사하고 `particles.tscn`을 2D 씬에 배치합니다. 기존 `project.godot`을 덮어쓰지 마세요.
5. 독립 출력의 `demo.tscn`에는 Camera2D가 있습니다. `particles.tscn`에는 카메라가 없습니다.

배포의 `Godot2DExample`은 PNG 포함 예제, `Godot2DUserParametersExample`은 두 노드의 독립 User 제어 예제입니다. 각 폴더의 `project.godot`을 열고 F5로 실행합니다.

## 시뮬레이션 공유와 버전

- `.mpfx` 저작 형식은 **v2 유지**, 신규 컴파일 효과는 **v3**입니다.
- 동일한 v3 `effect.res`와 SPIR-V를 MMGPUParticles3D/2D 모두 사용할 수 있습니다. Spawn/Update·난수·Attribute·파라미터는 동일하고 마지막 출력 패킹만 다릅니다.
- 위치·속도·중력은 여전히 Vector3, 회전은 quaternion입니다. User.Gravity에 Vector2를 넣으면 타입 오류입니다.
- 기존 v2 `effect.res`는 새 애드온의 3D 노드에서 계속 실행합니다. 2D에서는 원본 `.mpfx`를 재내보내야 합니다. 이전 애드온은 v3를 거부하므로 새 애드온과 함께 배포하세요.
- `.ptex`의 Godot 기본 particles 셰이더 내보내기는 변경하지 않았습니다.

## 좌표·외형

| 설정 | 동작 |
|---|---|
| Pixels Per Unit | 기본 100. `(x,y,z)`를 픽셀 크기로 변환하며 시뮬레이션 값은 바꾸지 않습니다. |
| Flip Y | 기본 true. 기본 투영은 `(100x,-100y)`입니다. |
| Local | 노드/부모의 이동·회전·스케일을 따라갑니다. |
| World | 기존 3D와 같이 방출원 **위치만** 반영합니다. 방출된 입자는 노드 이동·회전·스케일을 따라가지 않습니다. 정지 중에도 출력 역변환을 갱신합니다. |
| Visibility Rect | Local에서는 로컬 픽셀, World에서는 해당 Canvas 좌표. 기본 ±10,000px. 효과 전체를 포함하도록 수동 지정합니다. |
| Blend Mode | Effect 기본값 / Alpha / Additive / Opaque / Cutout. Cutout 임계값 0.5. |
| Texture | 없으면 원본 quad/round_quad. 있으면 단일 이미지. 크기는 원본 quad_size × Scale × Pixels Per Unit입니다. |
| Draw Material | CanvasItemMaterial 또는 canvas_item ShaderMaterial만 허용합니다. |

Z는 시뮬레이션에는 남아 있지만 화면 깊이에는 쓰지 않습니다. quaternion/scale의 XY basis를 직교 투영하므로 3D 기울기는 찌그러지거나 선으로 보일 수 있습니다. 3D billboard·조명은 적용하지 않습니다. 기본 재질은 unshaded이며 Color, CustomData/INSTANCE_CUSTOM, Canvas modulate/self_modulate와 노드 z_index를 사용합니다. 개별 입자 깊이/Y 정렬은 없습니다.

PNG는 `sprite.res`에 이미지 데이터를 포함해 저장합니다. 원본 PNG 경로·import 캐시 없이 실행할 수 있습니다. 입력 제한은 PNG 64MiB, 한 변 8192px, 총 16메가픽셀입니다. 스프라이트 시트는 지원하지 않습니다.

## 게임 코드

```gdscript
@onready var particles: MMGPUParticles2D = $Particles

func start() -> void:
    particles.restart()
    particles.set_user_parameter("User.Gravity", Vector3(0, -4, 0))
    particles.set_user_parameter("User.Tint", Color(1, 0.5, 0, 1))
```

기존 play/pause/stop/restart/emit_burst, set_parameter, User 이름·ID 기반 set/get/reset 및 Inspector override API를 그대로 사용합니다. User 연결 입력은 set_parameter로 덮어쓸 수 없습니다. Editor Preview는 기본 꺼짐입니다. 같은 효과를 공유해도 상태와 override는 노드마다 독립입니다.

## CLI

```powershell
.\MaterialMaker.exe --rendering-method forward_plus --rendering-driver vulkan -- `
  --mpfx-command export --input D:/fx/fire.mpfx --output D:/export/fire2d `
  --effect-id fire2d --render-target 2d --pixels-per-unit 100 --flip-y true `
  --blend-mode alpha --sprite D:/art/particle.png
```

새 옵션은 모두 선택 사항입니다. render-target을 생략하면 기존처럼 3D입니다. 3D에 2D 전용 옵션을 지정하면 오류입니다. UI와 CLI는 동일한 옵션 검증 및 컴파일/내보내기 경로를 사용합니다.

Manifest에 출력 차원을 기록합니다. 기존 manifest는 3D로 해석하며 다른 차원으로 같은 폴더를 덮어쓰지 않습니다. checksum 충돌 시 새 폴더를 사용하세요. 기존 프로젝트 설정과 사용자 수정 파일은 보호됩니다.

## 성능·한계

2D Canvas MultiMesh는 GPU indirect count를 사용하지 않으므로 **Capacity 전체를 제출**합니다. 죽은 슬롯은 GPU에서 면적 0으로 초기화합니다. 정상 경로에 입자별 CPU loop, GPU readback, sync는 없습니다. 2D 레코드는 64 bytes, 3D는 기존 80 bytes입니다. 필요 이상으로 큰 Capacity는 피하세요.

지원 밖: Mobile/Compatibility/Web, 자동 vec2 그래프 변환, 2D 편집 미리보기, 충돌, 스프라이트 시트, 입자별 투명 정렬. [실행 환경](RENDERING_BACKENDS.md)과 [검증 기록](test/modular_particles/VALIDATION.md)을 참고하세요.
