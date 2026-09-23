# 파티클 작업 공간

Godot **4.7.2 stable / Forward+ / Vulkan** 전용입니다.

## 배치와 Module Inputs

`.mpfx` 탭은 재질/페인트와 별도의 레이아웃을 사용합니다.

- **좌상:** Module Inputs, Library, Hierarchy
- **좌하:** User Parameters, Attributes
- **중앙:** 기존 Material Maker 그래프
- **우상:** Effect Emission과 Module Stack
- **우하:** Particle Preview

도크를 좁혀도 Module Inputs는 중앙 그래프를 덮지 않습니다. 긴 이름은 줄임표와 툴팁으로 표시하고, 많은 입력은 세로로 스크롤합니다. 최소 폭보다 좁아지면 가로 스크롤을 사용할 수 있습니다. User 패널도 작은 도크 안에서 스크롤됩니다. 도크 경계 드래그, 탭 전환, 닫기/재열기와 레이아웃 초기화를 지원합니다. 원래 재질/페인트 배치는 따로 보존합니다.

## Effect Emission

오른쪽 Module Stack 위에 있습니다. 입력 후 **Apply Emission**을 누르세요. 설정이 길면 도크 안에서 스크롤하세요.

- **Looping:** Rate(초당 입자 수), Duration(주기). 지속 방출하고 반복합니다.
- **Burst:** Count(한 번에 방출할 입자 수), Duration(초), Repeat burst. 기본은 `t=0`에 한 번만 방출하며 Repeat를 켜면 Duration마다 반복합니다.
- **Custom:** 연속 방출과 Burst 혼합, 여러 Burst, 지연 Burst 등의 기존 스케줄입니다. 열기만 해서는 원본을 단순화하지 않습니다. **Advanced Emitter / Renderer…**에서 JSON을 편집하거나 모드를 선택해 명시적으로 변환합니다. Custom 변환에는 확인이 필요하며 Undo로 원래 스케줄을 복원할 수 있습니다.

Rate/Duration은 유한한 양수, Count는 양의 uint32 정수여야 합니다. 잘못된 입력은 적용하지 않습니다. 모드·주기·Burst 변경은 Preview 시뮬레이션을 한 번 다시 시작하지만 카메라와 Pause 상태를 보존합니다. Rate만 변경하면 시뮬레이션 시간도 유지합니다. 방출만 바꿀 때는 그래프나 GPU 파이프라인을 다시 만들지 않습니다.

설정은 `.mpfx`의 기존 `emitter`에 저장됩니다. 별도 모드 필드나 자동 v1→v2 변경이 없고, Undo/Redo·저장·재열기·Export가 같은 값을 사용합니다. 모듈 스택/Attribute/User 형식과 기존 예제는 그대로입니다.

## Particle Preview

Material Maker의 기본 카메라 컨트롤러와 EnvironmentManager를 공유합니다.

| 입력 | 동작 |
|---|---|
| MMB 또는 Alt+LMB 드래그 | 궤도 회전 |
| Shift+MMB / Shift+Alt+LMB | 패닝 |
| 휠 | 줌 |
| Ctrl+휠 | FOV |
| Reset View | 기본 카메라 복원 |

환경 목록은 Material Maker HDRI 프리셋입니다. **Clear Background**로 배경을 숨기거나 다시 표시할 수 있습니다. 환경·카메라 조작은 효과 문서를 변경하거나 시뮬레이션을 재시작하지 않습니다. 누락된 사용자 HDRI는 다운로드를 기다리지 않고 포함된 기본 HDRI(없으면 절차적 하늘)로 대체합니다.

Preview의 GPU/월드는 도크가 아니라 효과 탭이 소유합니다. 다른 탭으로 이동하거나 Preview 도크를 닫았다 열어도 카메라와 GPU 상태가 유지됩니다. 환경 선택과 Clear Background는 기존 Material Maker 설정 키를 사용합니다. 독립 Godot 효과의 게임 카메라/환경에는 영향을 주지 않습니다.

## 검증

[검증 기록](test/modular_particles/VALIDATION.md)에 앱·실제 Windows EXE·독립 Godot 결과와 캡처 위치를 기록합니다. 앱 UI 검사는 사용자 설정과 기존 빌드를 건드리지 않는 새 임시 프로젝트에서 실행합니다.
