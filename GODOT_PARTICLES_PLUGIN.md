# Godot에서 Modular GPU Particles 사용하기

## 역할과 필수 조건

- **효과 편집:** 별도 Material Maker 앱에서 `.mpfx` 모듈 그래프를 편집합니다.
- **게임 실행:** Godot 애드온의 `MMGPUParticles3D` 노드가 내보낸 `MMParticleEffect`를 실행합니다.
- Godot 안에 그래프 편집 Dock을 추가하는 플러그인은 아닙니다. `.mpfx`/`.ptex`를 Godot에서 직접 실행하지 않습니다.
- **Godot 4.7.2 stable, Forward+, Vulkan**이 필요합니다. Compatibility/Mobile 또는 다른 Godot 버전은 지원하지 않습니다.

## 가장 빠른 시작: 완성된 Godot 예제

빌드 폴더의 **`GodotExample/project.godot`**을 Godot 4.7.2로 가져온 뒤 **F6**으로 `effects/modular_particles/demo.tscn`을 실행하거나 **F5**로 프로젝트를 실행합니다.

128개, 0.7초 반복 burst의 mmtest 효과가 들어 있습니다. 이 폴더는 독립 프로젝트이며 Material Maker나 별도 autoload가 필요하지 않습니다.

## 내 게임 프로젝트에 넣기 (권장)

1. 게임 프로젝트의 Renderer를 **Forward+**로 설정합니다.
2. 내보낸 폴더 또는 `GodotExample`에서 다음 폴더를 게임 프로젝트 **루트**에 복사합니다.
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

1. `MaterialMaker/MaterialMaker.exe`를 실행합니다. **`Open mmtest.cmd`**는 예제를 바로 엽니다.
2. 새 효과: **File → New Modular GPU Particles**.
3. 기존 효과: **File → Load**, 예제는 `examples/modular_particles/mmtest.mpfx`.
4. Spawn/Update 그래프를 편집하고 `.mpfx`를 저장합니다.
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

입력 키는 **모듈 인스턴스 ID / 입력 ID**입니다. 위 키는 동봉된 mmtest 예제용이며 새로 만든 모듈은 다른 ID를 사용합니다. `set_parameter()`는 잘못된 ID/타입이면 `false`를 반환합니다.

## 주의 사항

- `effect.res`에는 미리 컴파일한 SPIR-V가 포함됩니다. 게임에서는 Material Maker/원본 그래프/그래프 compiler가 필요 없습니다.
- 일반 Godot Windows Export로 배포할 수 있습니다. `addons/mm_gpu_particles`와 효과 리소스를 export에 포함해야 합니다.
- 가산/불투명/컷아웃을 지원합니다. 투명 depth sorting, 충돌, 서브이미터, 외부 텍스처/베이크 Buffer 입력은 v1 범위 밖입니다.
- Capacity를 넘긴 새 입자는 버립니다. 32개 Attribute가 상한은 아니지만 GPU 메모리/버퍼 안전 한도가 있습니다.
- Godot/Material Maker의 기존 설치 파일은 이 빌드로 교체하지 않습니다. 새 앱은 별도 사용자 설정 폴더를 사용합니다.
