# User Parameters: 게임에서 효과 제어하기

Godot **4.7.2 stable / Forward+ / Vulkan** 전용입니다. User 값은 **효과 노드 인스턴스 전체가 공유하는 읽기 전용 입력**입니다. 입자별 Attribute, Module Input, 게임 전역 변수와는 다릅니다.

## 바로 실행

- Material Maker: **`MaterialMaker/Open user_parameters.cmd`** 또는 `examples/modular_particles/user_parameters.mpfx`를 엽니다.
- Godot: **`GodotUserParametersExample/project.godot`**를 가져와 F5로 실행합니다. Material Maker나 autoload는 필요 없습니다.
- Left/Right를 선택하고 Speed/Gravity/Tint를 바꿉니다. 같은 `effect.res`를 사용하는 두 노드가 서로 독립적으로 바뀝니다.
- Reset은 선택한 노드만 효과 기본값으로 복원합니다. `Animate left User.Speed`는 매 프레임 게임 코드가 왼쪽 노드만 제어하는 예입니다. 정확한 기본값을 유지하려면 먼저 Animate를 끄세요.
- Speed는 새로 태어나는 입자에, Gravity와 Tint는 살아 있는 입자의 다음 Update에도 적용됩니다. 값을 바꿔도 시뮬레이션을 다시 시작하지 않습니다.

예제는 기존 기본 6모듈을 사용합니다. `User.Speed`(float, 3)는 Cone의 **Speed Min/Max 두 입력이 공유**하고, `User.Gravity`(vec3, `[0,-9.81,0]`)는 Gravity 입력, `User.Tint`(vec4, `[1,1,1,1]`)는 Color over Life의 Multiplier에 연결됩니다. 기존 mmtest/basic_fountain/box_turbulence/sphere_burst는 변경하지 않았습니다.

## Material Maker 편집

1. 왼쪽 **User Parameters (effect instance)** 패널에서 Add를 누릅니다.
2. 이름은 `Speed`처럼 입력합니다. `User.` 접두사는 표시용입니다. 대소문자를 구분하며 영문/숫자/밑줄만 허용하고 첫 글자는 영문/밑줄이어야 합니다. 같은 효과 안에서 이름은 유일합니다.
3. 타입과 JSON 기본값을 지정합니다. 지원 타입: `float`, `int`, `uint`, `bool`, `vec2`, `vec3`, `vec4`.
4. 스택의 모듈 인스턴스를 선택하고, 아래 Module Input 행의 **Source**에서 `Constant` 대신 `User.Speed` 등을 선택합니다. 정확히 같은 타입만 목록에 나옵니다.
5. 같은 이름만으로는 연결되지 않습니다. 바인딩은 **User의 고정 ID**로 해당 모듈 인스턴스에 저장됩니다. 같은 모듈 정의의 다른 인스턴스는 별도로 선택하세요.
6. 연결된 입력의 상수 편집은 비활성화됩니다. **Edit User**로 기본값을 수정합니다. Source를 Constant로 되돌리면 기존 입력 상수값을 다시 사용합니다.
7. Rename/Value/Type/Delete, 바인딩 변경은 Undo/Redo를 지원합니다. `.mpfx`에 Save하세요. 기본값/이름 변경은 정상 Preview의 GPU 입자 상태를 유지합니다.

Uses와 선택 설명/툴팁에서 Stage, 모듈 인스턴스, 입력 ID를 확인합니다. **참조 중인 User 삭제와 타입 변경은 차단**됩니다. 비활성 인스턴스의 참조도 먼저 해제해야 합니다. 이름 변경은 ID와 연결을 유지합니다.

이름이 같은 `User.Position`, `Module.Position`, `Particle.Position`, `Particle.Custom.Position`, `Context.delta`는 서로 다른 공간입니다. User는 Module Output의 쓰기 대상이 아니며, `.mmg` 라이브러리 그래프에 효과별 User 연결을 저장하지 않습니다. 그래프에서는 기존 Module Read를 사용하고, 효과 스택에서 그 입력의 Source를 지정합니다.

## Godot Inspector

`MMGPUParticles3D`에 내보낸 효과를 할당하면 **User Parameters** 그룹에 타입별 값이 표시됩니다. 노드별 override만 저장하며 공유 효과 리소스의 기본값은 바꾸지 않습니다. Inspector의 되돌리기 기능으로 효과 기본값을 복원할 수 있고, 변경/Undo/Redo와 씬 저장·재열기를 지원합니다.

플러그인 체크박스는 이 그룹 표시나 게임 실행의 필수 조건이 아닙니다. 효과를 교체하면 목록이 갱신됩니다. 저장된 알 수 없는 ID 또는 타입이 바뀐 override는 실행에 적용하지 않습니다. 에디터에서 시뮬레이션을 보려면 Preview In Editor를 켜세요.

## 게임 코드

```gdscript
@onready var left: MMGPUParticles3D = $Left
@onready var right: MMGPUParticles3D = $Right

func _ready() -> void:
    assert(left.set_user_parameter("User.Speed", 6.0))
    assert(left.set_user_parameter("User.Gravity", Vector3(0, -4, 0)))
    assert(left.set_user_parameter("User.Tint", Color(1, 0, 0, 1)))
    right.set_user_parameter("User.Tint", Vector4(0, 0, 1, 1))
    # right의 Speed/Gravity와 공유 effect 리소스는 바뀌지 않음.

func restore_speed() -> void:
    left.reset_user_parameter("User.Speed")
    print(left.get_user_parameter("User.Speed"))
```

- 이름 API는 **`User.Name` 전체 문자열**을 받습니다. 알 수 없는 이름/잘못된 값의 setter/reset은 `false`, getter는 `null`을 반환합니다.
- 이름 변경에도 안정적인 코드는 `effect.user_parameters`에서 ID를 얻어 `set_user_parameter_by_id(id, value)`, `get_user_parameter_by_id(id)`, `reset_user_parameter_by_id(id)`를 사용하세요.
- 벡터는 Vector2/3/4 또는 같은 길이의 숫자 배열로 설정합니다. vec4는 Color도 받으며 채널을 그대로 사용합니다. getter는 벡터 타입을 반환합니다.
- bool은 bool만 허용합니다. int/uint는 정수 범위(int32/uint32), float/벡터는 유한한 float32 범위를 검사합니다. NaN/무한대/범위 초과/잘못된 타입은 적용하지 않습니다.
- 기존 `set_parameter("instance_id/input_id", value)`는 **Constant 입력에만** 사용합니다. User에 연결된 입력에는 `false`를 반환합니다. User API가 모든 연결 입력에 같은 값을 전달합니다.
- 값 설정은 CPU 측 작은 override를 변경하고 다음 시뮬레이션 Step에 기존 parameter buffer로 전달합니다. 셰이더 재컴파일, GPU 상태 재할당, 입자 재시작, 런타임 GPU readback을 하지 않습니다. Pause 상태에서는 다음 Step까지 입자 결과가 바뀌지 않습니다.

## 저장·마이그레이션·문제 진단

- User를 사용하지 않는 기존 `.mpfx`/`MMParticleEffect` **v1은 그대로 읽고 실행**합니다. 패널을 열기만 해서는 마이그레이션하지 않습니다.
- 최초 성공한 User 추가로 문서가 **v2**가 됩니다. v2 문서는 `user_parameters`, 인스턴스별 `input_bindings`를 저장하고 내보낸 효과도 format 2와 SPIR-V를 포함합니다. User를 모두 제거해도 자동으로 v1으로 낮추지 않습니다.
- 이전 런타임은 v2를 지원하지 않습니다. 새 `addons/mm_gpu_particles`와 효과 리소스를 함께 배포하세요. [설치 안내](GODOT_PARTICLES_PLUGIN.md)를 참고하세요.
- Missing User/타입 불일치/잘못된 참조는 진단하고 컴파일·Export를 차단합니다. 조용히 Constant로 대체하지 않으며, 편집기의 마지막 정상 Preview는 유지합니다. 올바른 User로 다시 연결하거나 Constant로 명시적으로 해제하세요.
- 새 빈 폴더에 Export하는 것이 안전합니다. 재내보내기는 manifest checksum으로 수정된 파일을 보호하며, 기존 `project.godot`은 덮어쓰지 않습니다. User demo 제어 스크립트도 보호 대상입니다.
- User 정의가 있는 v2 내보내기의 demo는 두 노드와 제어 UI를 제공합니다. Speed/Gravity/Tint에는 전용 컨트롤을, 다른 User에는 JSON 입력을 사용합니다. 실제 게임에는 `particles.tscn`만 배치하고 게임 로직에서 API를 호출해도 됩니다.
