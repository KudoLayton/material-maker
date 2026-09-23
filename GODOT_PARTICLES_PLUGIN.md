# Godot에서 Modular GPU Particles 사용하기

## 역할과 필수 조건

- **효과 편집:** 별도 Material Maker 앱에서 `.mpfx` 모듈 그래프를 편집합니다.
- **게임 실행:** Godot 애드온의 `MMGPUParticles3D` 노드가 내보낸 `MMParticleEffect`를 실행합니다.
- Godot 안에 그래프 편집 Dock을 추가하는 플러그인은 아닙니다. `.mpfx`/`.ptex`를 Godot에서 직접 실행하지 않습니다.
- **Godot 4.7.2 stable, Forward+, Vulkan**이 필요합니다. Compatibility/Mobile 또는 다른 Godot 버전은 지원하지 않습니다.

## 가장 빠른 시작: 완성된 Godot 예제

빌드 폴더에서 원하는 독립 예제의 `project.godot`을 Godot 4.7.2로 가져온 뒤 **F6**으로 `effects/modular_particles/demo.tscn` 또는 **F5**로 프로젝트를 실행합니다.

- **`GodotUserParametersExample/project.godot`**: User.Speed/Gravity/Tint 실시간 제어, 같은 효과의 두 노드 독립 override와 Reset.
- **`GodotBasicExample/project.godot`**: 새 기본 모듈(Initialize/Cone/Gravity/Solve/Color/Scale)의 128개, 2초 반복 burst.
- **`GodotExample/project.godot`**: 기존 mmtest의 128개, 0.7초 반복 burst.

세 폴더는 각각 독립 프로젝트이며 Material Maker나 별도 autoload가 필요하지 않습니다. 같은 효과 경로를 사용하므로 예제들을 기존 프로젝트의 같은 폴더에 덮어쓰지 마세요.

## 내 게임 프로젝트에 넣기 (권장)

1. 게임 프로젝트의 Renderer를 **Forward+**로 설정합니다.
2. 내보낸 폴더 또는 선택한 `GodotUserParametersExample`/`GodotBasicExample`/`GodotExample`에서 다음 폴더를 게임 프로젝트 **루트**에 복사합니다.
   - `addons/mm_gpu_particles/`
   - `effects/modular_particles/`
3. `effects/modular_particles/particles.tscn`을 자신의 3D 씬으로 드래그합니다.
4. 게임 씬에 `Camera3D`를 두고 실행합니다. 이 particles 씬 자체에는 카메라가 없습니다.

**기존 `project.godot`은 복사해서 덮어쓰지 마세요.** 이미 같은 애드온/효과 경로가 있으면 먼저 내용을 확인하세요. 효과 리소스가 참조하는 `res://addons/mm_gpu_particles/` 경로는 유지해야 합니다.

`GodotAddon.zip`에는 실행 코드만 있습니다. ZIP을 프로젝트 루트에 풀면 `addons/mm_gpu_particles/plugin.cfg` 경로가 되어야 합니다. 애드온만 설치하고 효과를 할당하지 않으면 입자가 나오지 않습니다. 처음에는 위의 **애드온 + 효과 폴더 함께 복사** 방식을 권장합니다.

## 플러그인 활성화와 노드 직접 만들기

`Project → Project Settings → Plugins`에 **Modular GPU Particles**가 표시됩니다. 활성화해도 됩니다. 다만 노드/리소스는 `class_name`으로 등록되므로 플러그인 체크박스는 실행의 필수 조건이 아니며, 전용 Dock이나 autoload도 만들지 않습니다.

직접 구성하려면:

1. Add Node에서 **MMGPUParticles3D**를 추가합니다.
2. Inspector의 **Effect**에 `effects/modular_particles/effect.res`를 할당합니다.
3. **Capacity**를 설정합니다. mmtest는 `128`이면 됩니다.
4. 에디터 안에서 움직이는 모습을 보려면 **Preview In Editor**를 켭니다. 기본값은 꺼져 있습니다.
5. **Visibility Aabb**를 효과 전체를 포함하도록 지정합니다. 범위가 작으면 화면에서 사라질 수 있습니다.
6. 필요하면 **Simulation Space**(Local/World), **Mesh**, **Draw Material**을 지정합니다. 기본은 쿼드입니다.

생성 목록에 노드가 바로 보이지 않으면 파일 스캔이 끝날 때까지 기다리거나 프로젝트를 다시 엽니다.

## Material Maker에서 효과를 수정한 뒤

1. `MaterialMaker/MaterialMaker.exe`를 실행합니다. **`Open basic_fountain.cmd`** 등으로 예제를 바로 열 수도 있습니다.
2. 새 효과: **File → New Modular GPU Particles**. 새 기본 6모듈 스택으로 시작합니다.
3. 기존 효과: **File → Load**. 기본 모듈 예제 3종, `user_parameters.mpfx`, 기존 `examples/modular_particles/mmtest.mpfx`가 있습니다.
4. **Browse Library…**에서 기본 12종을 추가하고 Spawn/Update 그래프를 편집한 뒤 `.mpfx`를 저장합니다. [모듈 목록과 순서](STANDARD_PARTICLE_MODULES.md)를 참고하세요.
5. 탭의 **Export**로 **빈 폴더**에 내보냅니다.
6. 생성된 `addons/mm_gpu_particles/`와 `effects/modular_particles/`를 위 설명처럼 게임에 넣습니다.

재내보내기는 manifest의 checksum으로 사용자 수정/미관리 파일을 보호합니다. 충돌 시 새 빈 폴더로 내보내세요. 기존 게임 프로젝트 전체를 덮어쓰거나 manifest를 삭제해 강제로 우회하지 마세요. 이 버전은 출력 폴더당 하나의 효과를 관리합니다.

## 코드로 제어하기

```gdscript
@onready var particles: MMGPUParticles3D = $Particles

func start_effect() -> void:
    particles.restart()  # 상태/시드를 초기화하고 다시 방출

func control_examples() -> void:
    particles.pause()     # 시간과 시뮬레이션 일시 정지
    particles.play()      # 재개 + 방출 활성화
    particles.stop()      # 새 방출만 중단; 살아 있는 입자는 계속 갱신
    particles.emit_burst(32)
    particles.set_parameter("mmtest_initialize/velocity", 8.0)
```

입력 키는 **모듈 인스턴스 ID / 입력 ID**입니다. 위 키는 동봉된 mmtest 예제용이며 새로 만든 모듈은 다른 ID를 사용합니다. `set_parameter()`는 잘못된 ID/타입이면 `false`를 반환합니다. 새 효과의 실제 입력은 `particles.effect.parameters`의 `id`, `name`, `type`으로 확인하세요. 표준 모듈도 같은 API를 사용하며 이름으로 Attribute를 자동 바인딩하지 않습니다.

## User 값과 Inspector

User가 있는 효과는 노드 Inspector의 **User Parameters** 그룹에서 타입별 override를 편집합니다. 씬에 노드별로 저장하며 공유 `effect.res` 기본값은 바꾸지 않습니다. 되돌리기는 효과 기본값을 복원합니다.

```gdscript
$Particles.set_user_parameter("User.Speed", 6.0)
$Particles.set_user_parameter("User.Gravity", Vector3(0, -4, 0))
$Particles.set_user_parameter("User.Tint", Color(1, 0, 0, 1))
$Particles.reset_user_parameter("User.Speed")
```

ID 기반 `*_by_id` API도 지원합니다. User에 연결된 입력은 기존 `set_parameter()`로 덮어쓸 수 없으며 `false`를 반환합니다. 값 변경은 다음 Step에 기존 buffer로 전달하여 재시작/셰이더 재컴파일 없이 적용합니다. v1 효과는 계속 지원하지만 **v2 효과는 새 애드온과 함께** 배포해야 합니다. [User 편집·타입·마이그레이션 안내](USER_PARTICLE_PARAMETERS.md)를 참고하세요.

## 주의 사항

- `effect.res`에는 미리 컴파일한 SPIR-V가 포함됩니다. 게임에서는 Material Maker/원본 그래프/그래프 compiler가 필요 없습니다.
- 일반 Godot Windows Export로 배포할 수 있습니다. `addons/mm_gpu_particles`와 효과 리소스를 export에 포함해야 합니다.
- 가산/불투명/컷아웃을 지원합니다. 투명 depth sorting, 충돌, 서브이미터, 외부 텍스처/베이크 Buffer 입력은 v1 범위 밖입니다.
- Capacity를 넘긴 새 입자는 버립니다. 32개 Attribute가 상한은 아니지만 GPU 메모리/버퍼 안전 한도가 있습니다.
- Godot/Material Maker의 기존 설치 파일은 이 빌드로 교체하지 않습니다. 새 앱은 별도 사용자 설정 폴더를 사용합니다.
