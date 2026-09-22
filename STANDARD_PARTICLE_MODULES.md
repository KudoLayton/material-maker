# 기본 Particle 모듈 12종

Godot **4.7.2 stable / Forward+ / Vulkan**용입니다. Niagara의 기본 에셋에서 모듈 역할·입력·설명을 참고하여 **독립 작성한 Material Maker 그래프**입니다. UE 에셋/코드를 이식하지 않았으며 Niagara와 수치 호환을 보장하지 않습니다. Godot 엔진·GPU 런타임 ABI는 변경하지 않습니다.

## 시작하기

**File → New Modular GPU Particles**는 다음 구성으로 시작합니다.

```text
Spawn:  Initialize Particle → Add Velocity in Cone
Update: Gravity → Solve Motion → Color over Life → Scale over Life
```

Emitter/Renderer 기본값은 그대로입니다. 새 문서는 6개 모듈과 4개 공유 Custom Attribute를 갖습니다. 기존 `.mpfx`, `.mmg`, `.ptex`, mmtest 예제는 자동 변환하지 않습니다.

**Browse Library…**에서 이름/설명/태그, 카테고리, Stage로 검색하세요.
- **Add Copy / Enter / 더블클릭**: 선택한 스택 행 다음에 독립 그래프 복사본을 추가합니다. 선택이 없으면 끝입니다.
- **Esc / Cancel**: 문서·Undo 이력·Preview를 변경하지 않습니다.
- 현재 Stage와 맞지 않는 모듈은 설명만 볼 수 있습니다. 창을 닫고 Stage를 전환하세요.
- 필요한 Attribute는 자동 추가하거나 matching role을 재사용합니다. 다른 모듈을 자동 추가하거나 순서를 바꾸지 않습니다.
- 추가 전체가 **한 번의 Undo/Redo**입니다. 카탈로그 복사본끼리는 그래프·이름을 공유하지 않습니다.
- 기존 **Add/Copy**는 여전히 현재 문서의 같은 모듈 정의를 사용하는 인스턴스를 만듭니다. `Legacy` 카테고리에는 기존 Initialize Velocity / Integrate Velocity도 남아 있습니다.

큰 카탈로그 그래프는 라벨이 사라질 정도로 전체를 축소하지 않고 **Module Output(Write)**부터 읽기 쉬운 배율로 보여줍니다. 상단 줌 도구와 캔버스 이동으로 다른 노드를 살펴보세요.

입력값은 JSON 숫자/배열/`true`/`false`로 입력 후 Enter로 확정합니다. Read 노드가 참조하는 입력은 Delete할 수 없습니다. Curve/Gradient는 모듈 그래프의 기존 위젯에서 편집합니다. Typed Code 노드의 **Code 입력 우클릭 → Edit text**로 여러 줄 수식을 편집할 수 있습니다. 그래프 편집은 해당 문서 복사본에만 적용됩니다.

## 목록과 기본값

좌표는 현재 시뮬레이션 공간, **+Y 위 / 1단위=1m / 초 단위**입니다. UE의 Z-up/센티미터 값을 그대로 사용하지 마세요. 입력별 Local/World 변환은 제공하지 않습니다. Location 모듈은 현재 Position에 offset을 더하므로 World-space 생성 원점을 보존합니다.

| 모듈 | Stage | 입력 기본값 / 동작 |
|---|---|---|
| Initialize Particle | Spawn | Position Offset=(0,0,0)m, Velocity=(0,0,0)m/s, Color=(1,1,1,1), Scale=(1,1,1), Override Lifetime=false, Lifetime Min/Max=1s, Seed=0. 위치 offset·속도·색·크기·회전 identity 초기화, InitialColor/InitialScale 저장, 누적값 0. |
| Box Location | Spawn | Center=(0,0,0)m, 전체 Size=(1,1,1)m, Seed=0. 박스 **내부 균일 분포**. Size 절댓값 사용. |
| Sphere Location | Spawn | Center=(0,0,0)m, Radius=1m, Surface Only=false, Seed=0. 체적 균일 분포(`r∝u^(1/3)`) 또는 표면 균일 분포. 음수 반경은 0. |
| Add Velocity | Spawn | Velocity=(0,1,0)m/s를 현재 속도에 더함. |
| Add Velocity in Cone | Spawn | Axis=(0,1,0), **Half Angle=15도**, Speed Min/Max=3m/s, Seed=0. 입체각 균일 분포. 영벡터 axis는 +Y, 각도는 0~180도. |
| Gravity | Update | Gravity=(0,-9.81,0)m/s²를 Acceleration에 더함. delta를 여기서 곱하지 않음. |
| Drag | Update | Drag=1s⁻¹ 누적. 음수는 0. Solver에서 지수 감쇠 적용. |
| Curl Noise | Update | Strength=1, Frequency=0.5 noise units/m, Pan=(0,0.2,0) noise units/s, Seed=0. 3D curl 가속도 누적. Frequency≤0 또는 Strength=0이면 기여 없음. |
| Solve Motion | Update | 입력 없음. 현재 가속도·Drag·속도·위치와 Context.delta를 사용해 이동 후 누적값을 0으로 초기화. |
| Color over Life | Update | Color Multiplier=(1,1,1,1). 초기 Color × Multiplier × Gradient(t). 기본 Gradient는 흰색 불투명→흰색 투명. |
| Scale over Life | Update | Scale Multiplier=(1,1,1). 초기 Scale × Multiplier × Curve(t). 기본 Curve는 1→0. |
| Kill Particles | Update | Kill=false. `Alive = Alive && !Kill`. bool 연결을 입자별 조건 그래프로 바꿀 수 있음. 죽은 입자는 되살리지 않음. |

- Initialize의 Override Lifetime=false는 Emitter 수명을 그대로 사용합니다. true일 때 범위를 정렬하고 **음수 양 끝값을 0으로 고친 후** 균일 샘플링합니다. Cone 속도 범위도 같은 규칙입니다. 0 이하 수명은 기존 런타임 사망 규칙을 따릅니다.
- Initialize는 Age/ParticleID/Alive를 쓰지 않습니다. 생성된 첫 step에도 기존처럼 Age가 delta만큼 증가하고 Update가 실행됩니다.
- 랜덤은 ParticleID·시스템 seed·Module.Seed·샘플별 고정 offset으로 계산합니다. 같은 seed의 재시작은 재현됩니다. 동일한 입력의 복사본은 같은 랜덤 패턴을 낼 수 있으므로 다른 패턴은 Seed를 바꾸세요.
- `t=clamp(Age/max(Lifetime,1e-6),0,1)`. Color/Scale은 **매 프레임 초기값을 기준**으로 계산하므로 이전 프레임 값을 반복 곱하지 않습니다. Initial 값은 Initialize가 저장한 값이지 마지막 Spawn writer를 자동 추적한 값이 아닙니다.
- 색은 linear RGBA이며 HDR RGB나 사용자가 편집한 Curve 값에 별도 clamp를 강제하지 않습니다. 이 버전은 Module Input 자체에 Curve/Gradient 타입이나 Attribute binding을 추가하지 않습니다.

### 누적과 Solver

```text
a += Gravity + Curl 기여도
D += max(Drag, 0)
v1 = (v0 + a*dt) * exp(-max(D,0)*dt)
p1 = p0 + v1*dt
a = (0,0,0), D = 0
```

고정 dt는 기존 런타임의 1/60초입니다. Force/Mass 모델이나 Niagara Solver와 같은 수식이 아닙니다.

Curl은 기존 **TEX3D FBM / 비주기 Perlin / 2 octave / persistence 0.5**를 사용합니다. 세 채널 벡터 퍼텐셜의 편미분을 중앙차분(간격 0.01 noise unit, 총 12 scalar 샘플)으로 구합니다. 결과를 normalize하지 않으며 seed offset은 모든 입자에 공통인 공간장을 만듭니다. 그래프 안에서 FBM·offset·차분을 편집할 수 있습니다. 외부 텍스처나 bake Buffer는 필요 없습니다. 기존 mmtest의 XY curl과는 별도입니다.

## Namespace와 공유 Attribute

| 표시 | 타입 / 기본값 |
|---|---|
| Particle.Custom.Acceleration | vec3 / (0,0,0) |
| Particle.Custom.Drag | float / 0 |
| Particle.Custom.InitialColor | vec4 / (1,1,1,1) |
| Particle.Custom.InitialScale | vec3 / (1,1,1) |

이들은 일반 Custom Attribute입니다. 새 Builtin/Transient namespace가 아닙니다. **표시 이름이 아니라 `standard_role`과 stable ID**로 공유합니다. 사용자가 수동으로 만든 동명의 Acceleration/InitialColor 등과 자동 연결하지 않습니다. 이름을 바꾸어도 공유 관계는 유지되고, 중복 role·상이한 타입은 자동 병합하지 않습니다.

### 오류와 경고

- 활성 Gravity/Curl/Drag 뒤에는 동일 role을 사용하는 **활성 Solve Motion이 정확히 하나** 있어야 합니다.
- 표준 Initialize는 중복할 수 없고, 있으면 표준 Spawn Location/Velocity보다 앞에 둡니다.
- Color/Scale over Life에는 해당 Initial Attribute를 **실제로 쓰는 활성 Spawn 모듈**이 필요합니다. Initialize 또는 사용자 작성 모듈로 충족할 수 있습니다.
- 표준 모듈의 필수 Read/Write 연결이 끊기거나 role/type이 맞지 않으면 오류입니다. 연결되지 않은 Read나 등록만 된 Write는 충족하지 않습니다.
- Solve와 다른 Update Position writer를 함께 쓰면 중복 적분 가능성을 경고합니다. 위치 제한 같은 의도적인 후처리는 허용합니다.
- 오류 시 마지막 정상 Preview를 유지하고 Export는 막습니다. 경고만 있으면 Ready/Export를 유지합니다. On/Off·이동·삭제·Undo/Redo·Import 후 갱신하며 자동 수정하지 않습니다.
- 표준 메타데이터 없는 기존 모듈에는 이 순서 규칙을 소급하지 않습니다. 검사 대상은 계약/연결/순서이며 사용자 수식의 물리적 동등성까지 증명하지 않습니다.

## 저장·가져오기와 개발 인터페이스

`.mpfx`와 `.mmg`의 version 1 및 runtime parameter API는 유지합니다. 선택적 저작 정보:
- Attribute의 `standard_role`: `mm.standard.v1.acceleration`, `drag`, `initial_color`, `initial_scale`에 대응하는 versioned role 문자열.
- definition의 `standard_module`: `{catalog_id, revision:1, bindings}`. bindings는 전체 role 문자열→실제 Attribute ID입니다.
- definition의 `catalog_snapshot`: 카탈로그 복사본 표시. UI 로딩 정규화만으로 저장 데이터/Undo를 변경하지 않고 실제 그래프 편집부터 캡처합니다.
- `.mmg`의 `particle_module.attributes`: Read/Write 계약에 필요한 custom Attribute 정의 스냅샷.
- compiler 결과는 기존 `effect/errors`와 함께 `warnings`를 제공합니다.

Save .mmg → Import .mmg로 필요한 Attribute를 함께 옮길 수 있습니다. 표준 role은 기존 ID/타입을 검증해 재사용하고, 일반 Attribute는 stable ID와 타입이 맞을 때만 재사용합니다. 충돌은 전체 작업을 거부하며 이름으로 재연결하지 않습니다. 같은 module ID를 명시적으로 Import하면 기존 revision 갱신 동작을 유지합니다. 인스턴스 override와 무관한 모듈은 변경하지 않습니다. 외부 파일 변경을 기존 효과에 자동 반영하지 않습니다.

## 예제와 Godot 실행

`material_maker/examples/modular_particles/` (배포본에서는 `examples/modular_particles/`):
- **basic_fountain.mpfx**: 새 기본 스택, 초기값 기반 Color/Scale.
- **box_turbulence.mpfx**: Box + Add Velocity + Curl + Drag + Solve.
- **sphere_burst.mpfx**: 표면 128 burst, Curl, 모듈 그래프의 `Age >= Module.Kill Age` 조건. Kill Age=1.5초, 수명/반복 주기=2초이므로 반복 사이에 입자가 없는 구간이 있습니다.

배포본의 `Open *.cmd`로 열 수 있습니다. `modules/standard_particles/`에는 Import용 원본 12개 `.mmg`도 있습니다. 이 sidecar를 편집한다고 EXE 내 기본 카탈로그가 자동 갱신되지는 않습니다.

**GodotBasicExample/project.godot**은 새 기본 스택을 128 burst·2초로 Export한 독립 예제입니다. 저작 사본은 `examples/modular_particles/basic-128.mpfx`에 있습니다. 기존 mmtest는 **GodotExample/project.godot**에 별도로 유지합니다. 두 예제 모두 원본 그래프/compiler 없이 미리 컴파일한 SPIR-V를 실행합니다. 설치법은 [GODOT_PARTICLES_PLUGIN.md](GODOT_PARTICLES_PLUGIN.md)를 참고하세요.

## Niagara 참고 대응

로컬 `Engine/Plugins/FX/Niagara/Content/Modules`의 다음 에셋에서 역할/입력/설명을 확인했습니다. 파일·함수·셰이더 본문은 배포에 포함하지 않습니다.
- `Spawn/Initialization/V2/InitializeParticle` → Initialize Particle
- `Spawn/Location/{BoxLocation,SphereLocation,V2/ShapeLocation}` → Box/Sphere Location
- `Spawn/Velocity/{AddVelocity,AddVelocityInCone}` → 속도 모듈
- `Update/Forces/{GravityForce,Drag,V2/CurlNoiseForce}` → 가속도/Drag 누적 모듈
- `Solvers/SolveForcesAndVelocity` → 질량 없는 Solve Motion
- `Update/Color/ScaleColor`, `Update/Size/ScaleMeshSize` → 초기값 기반 Color/Scale over Life
- `Update/Lifetime/KillParticles` → Kill Particles

Spawn Rate/Burst는 기존 Emitter 설정을 사용합니다. 충돌, Event, Ribbon, Point Attraction/Vortex, 회전 모듈, Force/Mass, UE 에셋 변환기는 이번 범위에 없습니다.

## 재현 검증

Material Maker 저장소에서 PowerShell로 실행합니다. 모든 실행 테스트/빌드는 새 격리 디렉터리와 설정 폴더를 사용합니다.

```powershell
python tools/modular_particles/build_standard_modules.py --check
python tools/modular_particles/build_standard_examples.py --check
python tools/modular_particles/run_app_tests.py --godot $GODOT --test all --keep-going
python tools/modular_particles/run_tests.py --godot $GODOT --test test_compiler --headless
python tools/modular_particles/run_tests.py --godot $GODOT --test test_runtime
python tools/modular_particles/run_tests.py --godot $GODOT --test test_render
python tools/modular_particles/build_windows.py --godot $GODOT --templates $TEMPLATES
python tools/modular_particles/verify_export.py --godot $GODOT --templates $TEMPLATES --bundle $BUILD/GodotExample --enable-plugin
python tools/modular_particles/verify_export.py --godot $GODOT --templates $TEMPLATES --bundle $BUILD/GodotBasicExample --enable-plugin
```

`--check`는 원본을 쓰지 않습니다. 레시피를 수정한 개발자만 생성 스크립트의 `--update`로 해당 스크립트가 관리하는 파일을 명시적으로 갱신하세요. mmtest/사용자 문서는 대상이 아닙니다. GPU readback은 테스트에만 있으며 성능 측정은 raster draw/readback을 제외합니다. 실측 결과·로그·전체 MM의 기존 종료 경고 구분은 [소스 검증 기록](test/modular_particles/VALIDATION.md)에 남깁니다. 배포본에서는 최상위 폴더의 `verification/VALIDATION.md`와 로그 사본을 확인하세요. 미해결 외부 환경 검사도 이 기록에 명시합니다.
