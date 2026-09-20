# Material Maker 파티클 셰이더 확장

기존 Material Maker의 그래프 편집기, Library, Hierarchy, 서브그래프, 노출 파라미터와 사용자 노드 편집 기능으로 Godot 4.7 파티클 셰이더를 만듭니다. 별도의 파티클 그래프 화면은 사용하지 않습니다. 결과물은 GPUParticles의 `process_material`에 지정하는 **ShaderMaterial**이며 ParticleProcessMaterial 인스펙터를 복제하는 기능은 아닙니다.

## 시작하기

1. 확장 빌드의 `material_maker.exe`에서 **File → New Particle Shader**를 선택합니다.
2. 같은 캔버스의 **Start Output**은 초기화, **Process Output**은 매 프레임 처리입니다.
3. 기존 Library의 **Uniform / Grayscale Uniform**, **Math / Vec3 Math**, **Combine / Decompose**, Noise 등으로 계산을 구성합니다. 필요한 상태만 **Particles → Read**로 가져옵니다.
4. 원하는 계산을 출력의 COLOR, VELOCITY, MASS, TRANSFORM 등에 연결합니다. 연결하지 않은 상태는 바꾸지 않습니다.
5. 노드들을 선택하고 기존 **Create subgraph**를 사용합니다. 입력·출력·파라미터를 노출하고 기존 방식으로 라이브러리에 저장할 수 있습니다. 출력 두 개는 최상위에 남습니다.
6. 기존 Export 메뉴에서 **Godot 4/Particles**를 선택합니다. `.gdshader`, `.tres`, 필요한 `_texture_N.res`를 함께 보관합니다. Godot에서는 `.tres`를 사용합니다.

`examples/particles`의 blank, gravity, collision, subparticle, library_module, library_gravity 예제를 사용할 수 있습니다. `godot/project.godot`는 실제 파티클 실행 예제입니다.

## 기존 노드 활용

파티클의 `float`, `vec3`, `vec4`는 기존 Grayscale(`f`), Color(`rgb`), RGBA(`rgba`) 포트를 그대로 사용합니다. **Random → Vec3 Math → VELOCITY**처럼 기존 노드와 파티클 입출력을 직접 연결할 수 있습니다. 숫자·색상 간 변환은 Material Maker의 기존 규칙을 따릅니다.

- **Evaluate Function**: 특정 분기를 명시한 Coordinates에서 평가할 때 사용합니다. 일반 수학 계산에는 필요하지 않습니다. SDF와 3D 함수는 해당 차원의 좌표를 지정합니다.
- **Value to Function**: 신규 노드는 SDF·3D 함수 타입 연결에 사용합니다. 공통 숫자 타입은 직접 연결합니다. 이전 그래프의 Grayscale/Color/RGBA 어댑터도 계속 읽고 편집할 수 있습니다.
- **Custom Shader**: 기존 노드 편집기에서 Grayscale/Color/RGBA로 입력·출력·코드·함수를 편집합니다. 파티클 상태는 Read 노드를 입력에 연결합니다. 예전 `particle_float`, `particle_vec3`, `particle_vec4`는 호환 별칭으로 읽으며, 기존 포트와 표현식은 편집·저장 시 보존합니다.
- 일반 이미지와 정적 Buffer/Fast Blur 결과는 텍스처 리소스로 내보냅니다. 베이크 후에도 파티클마다 다른 좌표에서 샘플링할 수 있습니다. 버퍼의 해상도와 픽셀 형식, 알파를 보존합니다.

파티클 상태, 런타임 uniform 또는 시간에 따라 달라지는 내용을 정적 버퍼로 베이크할 수는 없습니다. 해당 연결은 오류에 노드 경로를 표시합니다. 베이크에 사용한 편집 파라미터를 변경하면 다시 내보내야 합니다. 임의의 사용자 셰이더가 Godot 파티클 단계에서 지원하지 않는 기능을 사용하면 컴파일 오류가 표시됩니다.

## 기존 기능과 보완 노드

| 작업 | 기본적으로 사용할 기존 기능 |
|---|---|
| float 값 | Simple → Uniform → Grayscale |
| 색상·RGBA 값 | Simple → Uniform |
| 부호가 있는 vec3 값·계산 | Filter → Math → Vec3, Clamp 끄기 |
| 성분 조합·분해 | Filter → Combine / Decompose (R/G/B/A는 X/Y/Z/W에 대응) |
| 계산·사용자 함수 | Math / Vec3 Math, 기존 Custom Shader |
| 그래프·서브그래프 설정 | Remote의 Named Parameter / Linked Control |
| 모듈화·재사용 | Create subgraph 후 기존 사용자 Library에 저장 |
| 이미지 읽기·좌표 변경 | Image, Transform, Custom UV |

Color는 vec3이므로 음수나 1보다 큰 값도 계산할 수 있습니다. RGB/RGBA를 Grayscale에 연결하면 RGB 평균으로 변환합니다. 수학 결과를 잘라내지 않으려면 Math의 Clamp를 끕니다.

추가 노드는 기존 분류에서 찾습니다. 일반 재질용 공통 노드 체계를 새로 만드는 기능은 아니며, 이번 확장의 지원 범위는 파티클 셰이더 내보내기입니다.

| 라이브러리 경로 | 보완 기능 |
|---|---|
| Simple → Constant → Typed | bool·정수·vec2·정수/불리언 벡터·행렬의 리터럴 |
| Filter → Math → Typed | 추가 타입의 수학·비트·행렬 연산 |
| Filter → Math → Compare | 숫자 비교 또는 벡터 전체의 동등 비교, bool 출력 |
| Filter → Combine / Decompose → Typed | 기존 노드가 다루지 않는 벡터 성분·행렬 열 |
| Filter → Math → Type Cast | 명시적 셰이더 형 변환. 벡터→float는 첫 성분이며 RGB 평균과 다름 |
| Filter → Math → Matrix Transform | mat4 × vec4 계산. 이미지 UV Transform과 다른 기능 |
| Filter → Math → Select | 실행 중 bool 조건에 따른 값 선택. 기존 Switch는 편집 설정으로 경로 선택 |
| Miscellaneous → Typed Parameter | 외부 파라미터 이름, 공통·추가 타입, 배열·Godot hint 지정 |
| Miscellaneous → Array Element / Texture Sample | 배열 원소 또는 sampler 리소스의 명시적 좌표·LOD 샘플링 |
| Miscellaneous → Evaluate Function / Value to Function | 명시적 좌표 평가 또는 SDF·3D 함수 연결 |

신규 보완 노드에서는 기존 기능과 겹치는 상수·float/vec3 연산·vec3/vec4 조합을 선택하지 않습니다. float·vec3의 clamp·mix는 기존 수학 노드와 서브그래프로 구성합니다. 기존 타입을 반드시 셰이더 리터럴로 넣어야 하면 Custom Shader를 사용합니다. vec4 전체 성분을 보존하는 수학 연산은 Typed Math에서 제공합니다.

Particles에는 Read, Write, Random, Execution의 Start Entry / Process Entry / Emit만 있습니다. 파티클 전용 Custom Shader 항목은 없으며 기존 Custom Shader를 사용합니다.

## 파라미터와 Remote

일반 float 파라미터는 **Remote → Named Parameter**로 정의하고 기존 노드의 숫자 설정에 `$이름` 표현식으로 사용합니다. **Linked Control**은 기존 노드의 설정을 연결하여 조절합니다. 서브그래프의 Parameters도 기존 방식으로 노출하고 라이브러리에 저장할 수 있습니다.

Remote와 기존 노드의 숫자·색상 설정은 Material Maker 내부 편집용입니다. 편집 중에는 기존 uniform 갱신 방식을 유지하고, 파티클 내보내기에서는 현재 값을 `const`로 고정합니다. Godot Inspector에 내부 설정이 나타나지 않으며 값을 변경하면 다시 내보내야 합니다.

Godot에서 실행 중 조절할 값은 **Miscellaneous → Typed Parameter**로 만듭니다. `Name`에 `velocity`처럼 유효한 셰이더 식별자를 입력하고 노드 출력을 계산에 연결합니다. Godot Inspector에는 `Velocity`처럼 Godot의 기본 이름 표시 규칙으로 나타납니다. 이번 구현에는 Typed Parameter를 `$이름`으로 참조하는 기능이 없으며, Remote의 기존 `$이름` 동작은 유지합니다.

Typed Parameter는 float(Grayscale), vec3(Color), vec4(RGBA)와 bool·정수·vec2·불리언/정수 벡터·행렬·배열·sampler를 지원합니다. 단일 값은 타입별 입력란에서, 배열 기본값은 JSON으로 편집합니다. vec3/vec4의 각 성분은 음수와 1보다 큰 값도 입력할 수 있습니다. 텍스처는 Resource 또는 Paths(JSON)에 경로를 입력합니다. Parameter는 항상 외부 uniform으로 내보내므로 Export 체크박스가 없습니다.

같은 이름과 같은 정의는 Start·Process·서브그래프에서 하나의 파라미터를 공유합니다. 이름이 같지만 타입·기본값·힌트·리소스 정의가 다르면 오류를 표시합니다. 이름의 범위는 전체 셰이더이므로 라이브러리 모듈을 여러 번 사용할 때도 이 규칙을 따릅니다. 외부 값에 따라 변하는 계산은 정적 Buffer로 베이크할 수 없습니다.

중력 예제는 Typed Parameter의 `launch_speed`(float), `gravity`(vec3)와 기존 Vec3 Math로 구성되어 있습니다. 기존 **Uniform**은 일정한 색상의 이미지를 출력하고, **Remote**는 그래프 설정을 모아 제어하며, **Typed Parameter**는 내보낸 Godot 재질의 외부 조절값을 정의합니다.

## 샘플링 좌표

Start Output과 Process Output의 마지막 `Sampling UV : vec2` 입력에서 각 단계의 기본 좌표를 지정합니다. 비워 두면 `(0, 0)`이며 기존 연결 포트 번호는 바뀌지 않습니다. UV를 사용하지 않는 Random·수학 계산은 이 입력을 연결할 필요가 없습니다.

Sampling UV는 해당 단계 진입 시의 상태로 한 번 계산합니다. 이후 Write로 파티클 상태를 바꾸어도 그 단계의 기본 UV는 고정됩니다. UV 입력을 만드는 계산 자체의 기본 좌표는 `(0, 0)`이며, 아직 실행되지 않은 Emit 결과는 사용할 수 없습니다. Process에서는 프레임마다 다시 계산합니다.

예를 들어 위치에서 만든 vec2를 Sampling UV에 연결하고 `Noise → Colorize → COLOR`를 직접 연결하면 위치별 색상을 계산합니다. Transform 등 기존 좌표 변환 노드는 전달된 UV를 기존 방식으로 변환합니다. 같은 Noise를 서로 다른 좌표에서 평가하려면 각 분기에 Evaluate Function과 Coordinates를 연결합니다. 명시한 좌표가 단계 기본 UV보다 우선합니다. 이 좌표는 Material Maker의 계산 설정이며 Godot 파티클 속성으로 내보내지 않습니다.

## 포트 색상과 타입 표시

파티클 값 포트에는 `VELOCITY : vec3`, `TRANSFORM : mat4`, `Value : float[4]`처럼 정확한 타입이 표시됩니다. 배열은 원소 타입과 같은 색상을 사용합니다.

| 타입 | 색상 |
|---|---|
| float / vec3 / vec4 | 기존 Grayscale 회색 / Color 청록색 / RGBA 파란색 |
| vec2 | 청록색 |
| bool, bvec | 노란색 |
| int, uint, ivec, uvec | 구리색 |
| mat | 보라색 |
| sampler | 분홍색 |
| exec | 밝은 회색 |

공통 숫자 타입은 기존 노드와 같은 연결 타입입니다. 정수·불리언·vec2·행렬·배열·샘플러·실행 연결은 각각의 타입을 유지합니다. SDF·3D Texture는 함수 계약이 다르므로 반환 자료형만 같다고 숫자 포트와 합치지 않습니다.

## 상태·실행 순서

Godot 4.7의 단계별 내장 변수와 쓰기 권한, USERDATA1~6, 행렬, render mode, uniform과 배열, 서브파티클 방출을 지원합니다. Start 전용·Process 전용 입력을 잘못 연결하면 오류를 표시합니다. 같은 계산 노드를 두 출력에서 사용하는 경우 단계별로 평가합니다.

출력에 연결된 값들은 같은 시점의 상태에서 계산한 뒤 기록합니다. 순차적인 상태 기록이나 방출은 해당 단계의 **Entry → Write / Emit → Output** 실행 연결로 표현합니다. Enabled로 조건부 실행을 지정하며, Emit의 Success는 방출 실행 이후에 사용합니다. 실행 연결도 서브그래프로 묶을 수 있습니다.

`CUSTOM`이나 `USERDATA`에 숨겨진 나이·수명 상태를 예약하지 않습니다. 위치 초기화에는 필요한 경우 `EMISSION_TRANSFORM`을 명시적으로 연결합니다. 속도 적분과 어트랙터는 Godot의 기본 동작 및 Start Output의 render mode 설정을 따릅니다.

## Uniform·미리보기·호환성

Typed Parameter의 단일 수치 기본값은 셰이더 uniform 선언에 포함합니다. 수치 배열 기본값과 텍스처 연결은 `.tres`에 저장하므로 해당 파일을 사용해야 합니다.

외부 텍스처 uniform은 Start Output의 **Godot Project Directory**와 프로젝트 안의 `res://...` 경로를 지정합니다. 기존 Image·Buffer 노드는 텍스처 리소스를 함께 내보냅니다. 이 내부 텍스처 바인딩은 `texture_1`, `texture_2`처럼 단순한 이름으로 Inspector에 남습니다. 명시적 Parameter 이름과 충돌하지 않으며 같은 텍스처를 여러 단계에서 사용하면 공유합니다.

파티클 시뮬레이션 미리보기는 없습니다. 상태에 의존하지 않는 기존 이미지 노드는 기존 미리보기를 사용할 수 있습니다. 파티클 값은 이미지 미리보기에서 평가하지 않습니다. 개수·수명·Draw Pass·충돌체·Sub Emitter 연결은 Godot에서 설정합니다.

이전 Typed Uniform은 저장 형식과 명시적 이름을 유지한 채 Typed Parameter로 열립니다. 이전 내보내기의 자동 생성된 내부 숫자 파라미터 이름은 제거됩니다. Godot에서 그 이름에 override를 설정했다면 Typed Parameter를 만들고 새 이름으로 옮겨야 합니다.

이전 통합 그래프의 노드·타입 선택·연산·포트 연결은 유지합니다. 신규 메뉴에서 제외한 노드도 기존 파일과 사용자 라이브러리에서 계속 읽고 편집할 수 있으며, 자동으로 다른 노드로 교체하지 않습니다. 사용자 지정 이름과 셰이더 코드는 유지합니다.

새 문서는 기존 `.ptex` 그래프 형식에 파티클 노드를 포함합니다. 확장 빌드로 열어야 합니다. 이전 별도 편집기의 `type: particle_graph` 파일은 자동 변환하지 않으며 이전 설치본에서 열 수 있습니다. 이전 구현 전체는 Git 태그 **particle-editor-prototype**에 보존되어 있습니다. `extensions/godot_particles`는 초기 파일 기반 확장의 기록이며 새 구현의 설치 경로가 아닙니다.

## 개발·검증·빌드

```powershell
python tools/particles/generate_library.py
python tools/particles/generate_examples.py
python tools/particles/validate.py --godot <Godot-4.7.2.exe>
python tools/particles/publish_examples.py
python tools/particles/validate.py --godot <Godot-4.7.2.exe>
python tools/particles/build_windows.py --godot <Godot-4.7.2.exe> --template <windows_release_x86_64.exe> --stock D:/material_maker_1_7_windows --output D:/material_maker_integrated_windows
```

검증은 별도 설정 폴더와 `build/particle-integration`의 복사본을 사용합니다. 일반 재질·그래프 편집, 라이브러리 저장과 재사용, 중첩 서브그래프와 파라미터, Godot GPU 타입 검사, 텍스처 정밀도, 실제 상태·충돌·방출 및 라이브러리 모듈의 파티클 렌더링을 검사합니다. `publish_examples.py`는 회귀 fixture에서 생성한 그래프를 기존 계산 노드·Typed Parameter 중심의 공개 예제로 구성합니다. 갱신 후 다시 검증하면 공개 예제의 내보내기를 `exported/published`에 생성합니다. Windows 빌드는 이 검증된 리소스를 Godot 데모에 포함합니다. 기존 설치본은 덮어쓰지 않습니다.

## 파티클별 난수

라이브러리의 **Particles → Random**을 추가합니다. 출력은 `float`, `vec2`, `vec3`, `vec4` 중 선택할 수 있으며 기본값은 `vec3`, 범위는 0~1, Seed Offset은 0입니다. UV나 텍스처가 필요하지 않습니다.

- `particle_id` 입력을 비우면 `NUMBER`, `system_seed` 입력을 비우면 `RANDOM_SEED`를 사용합니다. 슬롯 번호를 기준으로 고정하려면 `INDEX`를 `particle_id`에 연결합니다.
- `seed`, `minimum`, `maximum` 입력을 비우면 같은 행의 `Input default` 숫자 설정을 사용합니다. 입력을 연결하면 해당 숫자 설정은 무시됩니다. 벡터의 범위 설정은 모든 성분에 적용되며, 범위 포트에 벡터를 연결하면 성분별로 지정할 수 있습니다.
- 동일한 입력은 Start와 Process에서 동일한 값을 반환합니다. 노드를 복제해도 같습니다. 다른 값을 원하면 Seed Offset을 다르게 설정합니다. 매 프레임 자동으로 변하지 않습니다.
- 내부적으로 Godot `ParticleProcessMaterial`의 해시와 `rand_from_seed` 방식으로 성분별 난수를 차례대로 생성합니다. 초기 상태는 `hash(particle_id + 1u + system_seed + seed)`입니다. Seed Offset 0은 Godot의 초기화 방식과 같지만, 실제 머티리얼 속성값은 이후 난수 호출 순서에 따라 달라집니다.
- 벡터 출력은 각 성분의 난수입니다. 단위 방향 벡터나 구면 균일 분포를 의미하지 않습니다.

일반 노드와 동일하게 서브그래프로 묶고 라이브러리에 저장해 재사용할 수 있습니다. 파티클 실행 시 계산되는 값이므로 정적 텍스처 베이크의 입력으로는 사용할 수 없습니다.

화면의 `Seed Offset`은 노드별 추가 시드이며, `System Seed (RANDOM_SEED)`는 Godot이 제공하는 시스템 시드입니다. 출력은 `Random Value` 하나뿐입니다. 저장 파일의 기존 `seed` 키와 계산 방식은 유지됩니다.
