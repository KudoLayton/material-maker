# Material Maker 파티클 셰이더 확장

기존 Material Maker의 그래프 편집기, Library, Hierarchy, 서브그래프, 노출 파라미터와 사용자 노드 편집 기능으로 Godot 4.7 파티클 셰이더를 만듭니다. 별도의 파티클 그래프 화면은 사용하지 않습니다. 결과물은 GPUParticles의 `process_material`에 지정하는 **ShaderMaterial**이며 ParticleProcessMaterial 인스펙터를 복제하는 기능은 아닙니다.

## 시작하기

1. 확장 빌드의 `material_maker.exe`에서 **File → New Particle Shader**를 선택합니다.
2. 같은 캔버스의 **Start Output**은 초기화, **Process Output**은 매 프레임 처리입니다.
3. 기존 Library의 **Particles**에서 Read, Write, Constant, Operator, Evaluate Function, Value to Function을 추가합니다. 기존 노드도 같은 Library에서 추가합니다.
4. 원하는 계산을 출력의 COLOR, VELOCITY, MASS, TRANSFORM 등에 연결합니다. 연결하지 않은 상태는 바꾸지 않습니다.
5. 노드들을 선택하고 기존 **Create subgraph**를 사용합니다. 입력·출력·파라미터를 노출하고 기존 방식으로 라이브러리에 저장할 수 있습니다. 출력 두 개는 최상위에 남습니다.
6. 기존 Export 메뉴에서 **Godot 4/Particles**를 선택합니다. `.gdshader`, `.tres`, 필요한 `_texture_N.res`를 함께 보관합니다. Godot에서는 `.tres`를 사용합니다.

`examples/particles`의 blank, gravity, collision, subparticle, library_module, library_gravity 예제를 사용할 수 있습니다. `godot/project.godot`는 실제 파티클 실행 예제입니다.

## 기존 노드 활용

기존 Grayscale/Color 노드의 포트는 좌표에서 값을 계산하는 함수입니다. 파티클의 숫자·벡터 포트와 구별합니다.

- **Evaluate Function**: Function에 기존 노드나 서브그래프를, Coordinates에 파티클 값으로 만든 좌표를 연결합니다. Grayscale은 float, Color는 vec3, RGBA는 vec4 값을 반환합니다. 좌표는 반드시 명시합니다. SDF와 3D 함수는 해당 차원의 좌표를 사용합니다.
- **Value to Function**: 파티클 값을 기존 노드의 함수 입력으로 전달합니다. 예를 들어 시간으로 만든 float 값을 Colorize에 전달하고 그 결과를 Evaluate하여 COLOR에 연결할 수 있습니다.
- **Custom Shader**: 기존 노드 편집기에서 입력·출력·코드·함수를 편집합니다. `particle_float`, `particle_vec3` 등의 타입을 사용하면 기존 수학 노드와 함께 파티클 값을 처리할 수 있습니다. 상태는 Read 노드에서 입력으로 전달합니다.
- 일반 이미지와 정적 Buffer/Fast Blur 결과는 텍스처 리소스로 내보냅니다. 베이크 후에도 파티클마다 다른 좌표에서 샘플링할 수 있습니다. 버퍼의 해상도와 픽셀 형식, 알파를 보존합니다.

파티클 상태, 런타임 uniform 또는 시간에 따라 달라지는 내용을 정적 버퍼로 베이크할 수는 없습니다. 해당 연결은 오류에 노드 경로를 표시합니다. 베이크에 사용한 편집 파라미터를 변경하면 다시 내보내야 합니다. 임의의 사용자 셰이더가 Godot 파티클 단계에서 지원하지 않는 기능을 사용하면 컴파일 오류가 표시됩니다.

## 포트 색상과 타입 표시

파티클 값 포트에는 `VELOCITY : vec3`, `TRANSFORM : mat4`, `value : float[4]`처럼 정확한 타입이 표시됩니다. 배열은 원소 타입과 같은 색상을 사용합니다.

| 타입 | 색상 |
|---|---|
| float / vec3 / vec4 | 기존 Grayscale 회색 / Color 청록색 / RGBA 파란색 |
| vec2 | 청록색 |
| bool, bvec | 노란색 |
| int, uint, ivec, uvec | 구리색 |
| mat | 보라색 |
| sampler | 분홍색 |
| exec | 밝은 회색 |

색상이 같아도 같은 연결 타입이라는 뜻은 아닙니다. 기존 함수 포트와 파티클 값 포트 사이에는 Evaluate Function 또는 Value to Function을 사용합니다. 기존 SDF·텍스처·Fill 포트 색상은 유지합니다.

## 상태·실행 순서

Godot 4.7의 단계별 내장 변수와 쓰기 권한, USERDATA1~6, 행렬, render mode, uniform과 배열, 서브파티클 방출을 지원합니다. Start 전용·Process 전용 입력을 잘못 연결하면 오류를 표시합니다. 같은 계산 노드를 두 출력에서 사용하는 경우 단계별로 평가합니다.

출력에 연결된 값들은 같은 시점의 상태에서 계산한 뒤 기록합니다. 순차적인 상태 기록이나 방출은 해당 단계의 **Entry → Write / Emit → Output** 실행 연결로 표현합니다. Enabled로 조건부 실행을 지정하며, Emit의 Success는 방출 실행 이후에 사용합니다. 실행 연결도 서브그래프로 묶을 수 있습니다.

`CUSTOM`이나 `USERDATA`에 숨겨진 나이·수명 상태를 예약하지 않습니다. 위치 초기화에는 필요한 경우 `EMISSION_TRANSFORM`을 명시적으로 연결합니다. 속도 적분과 어트랙터는 Godot의 기본 동작 및 Start Output의 render mode 설정을 따릅니다.

## Uniform·미리보기·호환성

Uniform 노드에서 타입·이름·배열 길이·기본값·힌트·텍스처 경로를 설정합니다. 배열 기본값은 JSON으로 입력합니다. 동일 이름의 uniform 정의가 서로 다르면 내보내기를 막습니다. 수치 배열과 기존 라이브러리 파라미터 기본값은 `.tres`에 저장하므로 해당 파일을 사용해야 합니다.

외부 텍스처 uniform은 Start Output의 **Godot project directory**와 프로젝트 안의 `res://...` 경로를 지정합니다. 기존 Image 노드는 텍스처 리소스를 함께 내보냅니다.

파티클 시뮬레이션 미리보기는 없습니다. 상태에 의존하지 않는 기존 이미지 노드는 기존 미리보기를 사용할 수 있습니다. 파티클 값은 이미지 미리보기에서 평가하지 않습니다. 개수·수명·Draw Pass·충돌체·Sub Emitter 연결은 Godot에서 설정합니다.

새 문서는 기존 `.ptex` 그래프 형식에 파티클 노드를 포함합니다. 확장 빌드로 열어야 합니다. 이전 별도 편집기의 `type: particle_graph` 파일은 자동 변환하지 않으며 이전 설치본에서 열 수 있습니다. 이전 구현 전체는 Git 태그 **particle-editor-prototype**에 보존되어 있습니다. `extensions/godot_particles`는 초기 파일 기반 확장의 기록이며 새 구현의 설치 경로가 아닙니다.

## 개발·검증·빌드

```powershell
python tools/particles/generate_library.py
python tools/particles/generate_examples.py
python tools/particles/validate.py --godot <Godot-4.7.2.exe>
python tools/particles/publish_examples.py
python tools/particles/build_windows.py --godot <Godot-4.7.2.exe> --template <windows_release_x86_64.exe> --stock D:/material_maker_1_7_windows --output D:/material_maker_integrated_windows
```

검증은 별도 설정 폴더와 `build/particle-integration`의 복사본을 사용합니다. 일반 재질·그래프 편집, 라이브러리 저장과 재사용, 중첩 서브그래프와 파라미터, Godot GPU 타입 검사, 텍스처 정밀도, 실제 상태·충돌·방출 및 라이브러리 모듈의 파티클 렌더링을 검사합니다. `publish_examples.py`는 검증된 그래프를 소스 예제로 갱신합니다. 기존 설치본은 덮어쓰지 않습니다.

## 파티클별 난수

라이브러리의 **Particles → Tools → Random**을 추가합니다. 출력은 `float`, `vec2`, `vec3`, `vec4` 중 선택할 수 있으며 기본값은 `vec3`, 범위는 0~1, Seed는 0입니다. UV나 텍스처가 필요하지 않습니다.

- `particle_id` 입력을 비우면 `NUMBER`, `system_seed` 입력을 비우면 `RANDOM_SEED`를 사용합니다. 슬롯 번호를 기준으로 고정하려면 `INDEX`를 `particle_id`에 연결합니다.
- `seed`, `minimum`, `maximum` 입력을 비우면 노드의 숫자 설정을 사용합니다. 벡터의 범위 설정은 모든 성분에 적용되며, 범위 포트에 벡터를 연결하면 성분별로 지정할 수 있습니다.
- 동일한 입력은 Start와 Process에서 동일한 값을 반환합니다. 노드를 복제해도 같습니다. 다른 값을 원하면 Seed를 다르게 설정합니다. 매 프레임 자동으로 변하지 않습니다.
- 내부적으로 Godot `ParticleProcessMaterial`의 해시와 `rand_from_seed` 방식으로 성분별 난수를 차례대로 생성합니다. 초기 상태는 `hash(particle_id + 1u + system_seed + seed)`입니다. Seed 0은 Godot의 초기화 방식과 같지만, 실제 머티리얼 속성값은 이후 난수 호출 순서에 따라 달라집니다.
- 벡터 출력은 각 성분의 난수입니다. 단위 방향 벡터나 구면 균일 분포를 의미하지 않습니다.

일반 노드와 동일하게 서브그래프로 묶고 라이브러리에 저장해 재사용할 수 있습니다. 파티클 실행 시 계산되는 값이므로 정적 텍스처 베이크의 입력으로는 사용할 수 없습니다.
