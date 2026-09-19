# Material Maker 파티클 셰이더 편집기

Godot 4.7의 `shader_type particles`를 Material Maker 안에서 편집하는 별도 빌드입니다. 결과는 GPUParticles3D/GPUParticles2D의 `process_material`에 넣는 **ShaderMaterial**입니다. Godot의 `ParticleProcessMaterial` 인스펙터를 복제하거나 기존 리소스를 자동 변환하는 기능은 아닙니다.

## 실행과 사용

1. `D:\material_maker_particles_windows\material_maker.exe`를 실행합니다.
2. **File → New Particle Shader**를 선택하거나 `examples/native_particles/*.ptex`를 엽니다.
3. **Start**와 **Process (Update)** 탭에서 각 단계의 그래프를 편집합니다. 왼쪽 목록을 검색하고 항목을 더블 클릭하면 노드가 추가됩니다.
4. 노드를 선택해 오른쪽에서 타입·상수·연산을 수정합니다. 문자열 입력은 Enter로 적용하며 Custom Code는 **Apply code**로 적용합니다.
5. **Validate**로 검사하고 **Shader Code**로 생성 코드를 확인합니다. 오류 항목을 더블 클릭하면 해당 단계와 노드로 이동합니다.
6. **Export**로 `.gdshader`와 `.tres`를 함께 저장한 뒤 Godot에서 `.tres`를 `process_material`에 지정합니다.

배포본의 `examples/native_particles/godot/project.godot`를 Godot 4.7에서 열고 F6 또는 F5로 실행하면 세 예제를 볼 수 있습니다. 소스의 데모에는 생성된 리소스가 없으므로 먼저 위 그래프를 데모 폴더에 Export해야 합니다.

편집기 안의 미리보기는 제공하지 않습니다. 노드 수·수명·Draw Pass·충돌체·Sub Emitter 연결은 Godot의 GPUParticles 노드에서 설정합니다. 충돌과 서브파티클은 실제 Godot 장면에서 확인해야 합니다.

## 지원 범위

- Godot 4.7 엔진 `shader_types.cpp`에서 추출한 각 단계의 입력 35개와 쓰기 권한을 사용합니다. Start의 `RESTART_*`, Process의 충돌·어트랙터 입력을 구분합니다.
- `TRANSFORM`, `COLOR`, `VELOCITY`, `MASS`, `ACTIVE`, `CUSTOM`, `USERDATA1`~`USERDATA6`에 명시적으로 씁니다. `AMOUNT_RATIO`는 엔진에 맞춰 float입니다.
- bool/int/uint, 벡터, 행렬, 텍스처, 공통 uniform 및 배열, 명시적 Convert, 행렬 조립·분해·변환, 기본 수학·비트 연산을 지원합니다.
- `collision_use_scale`, `disable_force`, `disable_velocity`, `keep_data`를 개별 선택합니다.
- `Emit Subparticle`은 실행 연결에서 한 번 호출되며 Enabled와 Success를 제공합니다. 모든 `FLAG_EMIT_*`를 읽고 Bit Or로 조합할 수 있습니다.
- Custom Code의 입력 이름·타입을 UI에서 지정하고 함수 본문을 작성합니다. 내장 상태는 Read 노드와 입력 포트로 전달합니다. 배열 전체를 Custom Code에 전달하는 인터페이스는 없으며 Array Get으로 요소를 꺼낼 수 있습니다.
- 저장·다시 열기, 단계별 화면 위치, Undo/Redo, 복사·붙여넣기·복제·삭제, 프레임 그룹을 지원합니다.

## 상태와 실행 순서

새 문서에는 Entry → Output만 연결되어 있습니다. Output에서 연결하지 않은 상태는 그대로 유지하며, 숨겨진 나이 변수·가속도·크기 조정·수명 종료 코드를 추가하지 않습니다. Godot 엔진 자체의 기본 속도 이동과 힘 적용은 선택한 render mode에 따릅니다.

Output의 입력은 같은 시점의 상태를 읽은 뒤 함께 기록합니다. 쓰고 난 값을 다음 계산에서 읽으려면 **Write / 해당 변수** 노드를 Entry → Write → Output 순서로 실행 연결합니다. Emit의 Success는 해당 Emit 실행 이후에만 사용할 수 있습니다. 실행 분기는 Enabled로 표현하며 실행 연결을 둘로 나누는 것은 허용하지 않습니다.

예제 `gravity.ptex`는 초기 속도와 가속도 적분을 명시합니다. `collision.ptex`는 COLLIDED에 따라 반사 속도를 선택합니다. `subparticle.ptex`는 위치와 회전·크기 플래그를 조합하며 부모 색으로 방출 성공을 표시합니다. 자식 이미터의 초기화와 그리기 재질은 Godot에서 별도로 구성해야 합니다.

## Uniform과 리소스

Uniform은 두 단계가 공유합니다. 숫자·벡터·행렬 기본값은 셰이더에, **배열 기본값은 `.tres`에** 기록합니다. Godot이 uniform 배열의 셰이더 내 기본값을 지원하지 않으므로 배열을 사용할 때는 함께 내보낸 `.tres`를 사용해야 합니다.

텍스처는 Uniforms의 **Godot project directory**에 대상 프로젝트 폴더를 지정하고 `res://textures/...` 경로를 입력합니다. 텍스처를 자동 복사하지 않으므로 내보낸 파일도 그 프로젝트에 넣어야 합니다. 배열 기본값과 텍스처 배열 경로는 JSON 목록으로 입력합니다. 행렬은 열 우선입니다. 서로 다른 정의의 동명 uniform이 있는 문서 사이의 붙여넣기는 오류로 중단합니다.

## 기존 버전과 구분

기존 `D:\material_maker_1_7_windows` 설치와 별개이며 설정은 `%APPDATA%\material_maker_particles`에 저장됩니다. 이전 파일 기반 확장의 그래프와 일반 재질 그래프는 기존 편집기로 열립니다. 새 파일은 `type: particle_graph`, `version: 1`인 `.ptex`이며 기존 배포본에서는 열 수 없습니다. 기존 그래프를 새 단계 구조로 자동 변환하지 않습니다.

## 개발과 검증

```powershell
python tools/particles/generate_examples.py
python tools/particles/validate.py --godot <Godot-4.7.2.exe>
python tools/particles/build_windows.py --godot <Godot-4.7.2.exe> --template <windows_release_x86_64.exe> --stock D:/material_maker_1_7_windows --output D:/material_maker_particles_windows
```

검증은 컴파일러 규칙, 전체 단계 입력과 타입·배열의 실제 GPU 컴파일, 편집기 저장·편집 이력, 예제 리소스 내보내기·다시 읽기, GPUParticles3D의 상태·충돌·서브파티클 렌더링을 포함합니다. 전체 앱 검사는 별도 validation 설정 폴더를 사용합니다. 로그와 검증 이미지는 `build/particle-native`에 생성됩니다.

기준 소스: [Godot 4.7 particle interface](https://github.com/godotengine/godot/blob/4.7/servers/rendering/shader_types.cpp), [uniform 배열 저장 형식](https://github.com/godotengine/godot/blob/4.7/servers/rendering/renderer_rd/storage_rd/material_storage.cpp).
