# Godot 파티클 노드 확장

Material Maker 소스나 실행 파일을 수정하지 않고, 노드 그래프를 Godot의 파티클 `ShaderMaterial`로 내보냅니다. GPUParticles3D용이며 시뮬레이션 미리보기는 제공하지 않습니다.

## 설치

1. Material Maker를 종료합니다.
2. 이 폴더의 `nodes/*.mmg`를 Material Maker 실행 파일 옆의 `nodes` 폴더에 복사합니다. 폴더가 없으면 생성합니다. 기존 파일을 덮어쓸 필요는 없습니다.
3. Material Maker를 실행하고 라이브러리 패널의 라이브러리 불러오기 기능으로 `particles.json`을 추가합니다. JSON 파일은 계속 접근할 수 있는 위치에 보관합니다.
4. `examples/blank.ptex` 또는 `examples/gravity.ptex`를 엽니다. 예제는 노드 정의를 포함하므로 라이브러리 설치 전에도 열 수 있습니다.

소스 프로젝트를 Godot 실행 파일로 실행할 때는 해당 Godot 실행 파일 옆의 `nodes`를 사용합니다. 에디터 도구 실행 문맥(`Engine.is_editor_hint()`)에서는 프로젝트의 `material_maker/nodes`를 사용합니다. 이 저장소의 기본 `addons/material_maker/nodes` 파일은 변경하지 않습니다. 확장을 제거할 때는 직접 복사한 `mm_particle_*.mmg`와 추가한 사용자 라이브러리만 제거합니다.

## 사용

- `Particles 3D Output`의 Start 입력은 초기 위치·속도입니다. Update 입력은 매 프레임 가속도입니다. Appearance 입력은 초기화와 업데이트 모두에서 평가하는 색상·균일 크기입니다.
- 위치·속도·가속도는 Vector 노드를, 크기·시간은 Scalar 노드를 사용합니다. 초기 크기 1, 흰색, 나머지 값 0이 기본값입니다.
- `Life Fraction`은 0~1의 정규화된 수명입니다. Mix의 Weight에 연결하면 수명에 따라 색상·크기를 보간할 수 있습니다. Mix는 Weight를 0~1로 제한합니다.
- `Age`는 파티클 경과 시간(초), `Delta`는 프레임 시간(초)입니다. 초기화에서는 모든 상태 입력이 0입니다. 업데이트에서는 해당 단계 시작의 위치·속도와 이번 프레임 시간을 반영한 나이를 읽습니다.
- `Godot 4 → Particles 3D`로 내보내면 같은 폴더에 `.gdshader`와 `.tres`가 생성됩니다. 두 파일을 함께 보관하고 `.tres`를 GPUParticles3D의 `process_material`에 지정합니다. 재내보내기는 같은 이름의 결과 파일을 갱신합니다.
- 파티클 개수·수명·방출 타이밍은 Godot에서 설정합니다. Draw Pass의 메시 재질에서 **Vertex Color → Use as Albedo**를 활성화해야 파티클 색상이 보입니다. 알파를 사용하는 경우 해당 메시 재질의 투명도도 설정합니다.

`examples/gravity.ptex`는 속도 `(1, 4, 0)`, 가속도 `(0, -3, 0)`으로 움직이며 주황색에서 투명한 파란색으로, 크기 0.35에서 0으로 변합니다. Godot에서 수명을 2초로 설정해 확인할 수 있습니다.

## 바로 실행하는 예제

`examples/godot/project.godot`를 Godot에서 열고 실행합니다. 검증된 `gravity.gdshader`와 `gravity.tres`가 포함되어 있어 Material Maker 설치 전에도 결과를 볼 수 있습니다. 그래프를 수정한 뒤 이 폴더의 `gravity.tres` 위치로 다시 내보내면 예제에 반영됩니다.

## 지원 범위

- 제공된 파티클 노드끼리의 연결을 지원합니다. 기존 텍스처·버퍼 노드와 임의의 Custom Shader는 지원 범위 밖입니다.
- 기존 앱의 Color 포트를 Vector 저장에 재사용합니다. 앱이 허용하는 자동 색상 변환이 벡터 연산에도 적절하다는 뜻은 아닙니다. 스칼라로 벡터를 곱할 때는 Scale Vector를, 벡터를 만들 때는 Compose Vector를 사용합니다.
- Divide의 분모는 0이 아니어야 하며 Clamp의 Minimum은 Maximum 이하여야 합니다. 앱의 연결·타입 검사 UI는 바꾸지 않습니다.
- 미리보기에서 상태 입력은 0을 반환합니다. 출력 노드의 미리보기는 회색이며 시뮬레이션 결과가 아닙니다.
- `CUSTOM.x`는 경과 시간 저장용으로 예약합니다. 회전·비균일 크기·사용자 상태·서브이미터·충돌·외부 uniform은 제공하지 않습니다.
- 초기 위치·속도에는 방출 변환을 적용합니다. 이후 위치·속도·가속도는 Godot의 시뮬레이션 좌표계입니다. `local_coords=true`이면 로컬, false이면 월드 좌표를 사용합니다. 파티클 메시의 방향은 축 정렬이며 방출기의 회전·크기를 메시 방향에 유지하지 않습니다.
- 이동은 Godot의 속도 적분에 맡기며, 템플릿에서는 가속도에 의한 속도만 갱신합니다. 크기는 프레임마다 절대값으로 설정합니다.
- 각 단계에서 출력 입력의 계산식을 모두 평가합니다. 계산 노드는 상태를 직접 변경하지 않으며, 해당 단계의 출력만 적용됩니다.

## 개발 및 검증

배포 파일의 원본은 `tools/build_package.py`입니다. 노드 정의를 바꾼 뒤 실행해 `.mmg`, 라이브러리, 예제 파일을 함께 갱신합니다. 사용자는 Python 없이 배포 파일만 설치합니다.

```powershell
python extensions/godot_particles/tools/build_package.py
python -m unittest discover -s extensions/godot_particles/tests -p test_package.py
python extensions/godot_particles/tools/validate.py --godot C:/path/to/godot_console.exe
```

통합 검증은 저장소를 `build/particle-validation/project`에 복사하고 별도 사용자 설정 경로로 실행합니다. 기존 앱의 사용자 설정과 원본 소스 파일은 변경하지 않습니다. 실제 GPU가 필요하며 창은 화면 밖에 배치합니다. 로그, 내보낸 결과와 렌더링 이미지는 `build/particle-validation` 아래에 남습니다. 기준 엔진은 Godot 4.7이며 다른 마이너 버전은 별도 검증이 필요합니다.

검증 엔진: Godot 4.7.2, Vulkan Mobile, NVIDIA GeForce RTX 3070. 기본값·단계 간 공유·상태 입력·저장 후 재열기·라이브러리 로딩·모든 노드 출력의 셰이더 컴파일과 색상·크기 GPU 수치 검증을 포함합니다. 검증용 복사본에서는 Steam 초기화만 비활성화하며, 원본 앱의 코드는 수정하지 않습니다.

최종 결과: 패키지 테스트 3개, 통합 확인 79개 통과. 독립 Godot 예제 실행도 오류 없이 완료했습니다.
