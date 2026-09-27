# Vulkan・D3D12 지원 및 릴리스 검증

## 지원 계약

**Godot 4.7.2 stable / Windows x64 / Forward+ / 효과 v2**에서 **Vulkan과 D3D12를 동등한 기능 지원·회귀 보장 대상**으로 둡니다. D3D12는 더 이상 미검증 옵션이 아닙니다.

- 애드온 runtime, Compute/storage buffer, GPU 생존 압축, MultiMesh indirect draw, Local/World, Color/CustomData, additive/opaque/cutout, User API/Inspector, 자원 재생성·해제를 포함합니다.
- Godot 편집기에서의 게임 실행 및 Windows Release export를 모두 확인합니다.
- 한쪽의 기능 회귀도 수정 대상입니다. 두 백엔드의 필수 검증을 모두 통과해야 지원 검증 완료로 표시합니다. skip, headless 실행, 다른 backend로 fallback은 통과가 아닙니다.
- Compatibility/OpenGL, Mobile, Metal, 다른 엔진 버전 및 Windows 외 플랫폼은 이 보장 범위 밖입니다. GPU는 해당 Godot backend와 애드온의 compute/buffer 한도를 충족해야 합니다.
- 모든 제조사·드라이버 조합의 무결함, 동일 FPS, bit-identical 부동소수점 결과를 보증한다는 의미는 아닙니다. 이번 실장비 검증은 RTX 3070이며 AMD/Intel은 미검증입니다.

엔진 패치나 런타임 ABI 변경은 필요하지 않았습니다. SPIR-V 효과는 두 백엔드에서 공용이며, D3D12의 GPU 변환은 Godot이 처리합니다.

## 사용

게임 프로젝트의 Advanced Project Settings에서 `rendering/rendering_device/driver.windows`를 `d3d12`로 설정하고 편집기를 다시 시작하세요. 기존 `project.godot`을 예제 것으로 덮어쓰지 않습니다. 원본 설정 변경 없이 실행할 수도 있습니다.

```powershell
& $GODOT --path C:/MyGame --rendering-method forward_plus --rendering-driver d3d12
& C:/MyGame/windows/Game.exe --rendering-method forward_plus --rendering-driver d3d12
# 저작 앱도 D3D12로 실행 가능 (기존 기본 backend는 강제로 바꾸지 않음)
& C:/Tools/MaterialMaker/MaterialMaker.exe --rendering-method forward_plus --rendering-driver d3d12
# 최신 배포 helper로 D3D12에서 컴파일/내보내기
& '<skill>/scripts/Invoke-Vfx.ps1' -Command export -RenderingDriver d3d12 -InputFile C:/Work/fx.mpfx -Output C:/Work/staging -EffectId fx
```

실제 선택 결과는 `RenderingServer.get_current_rendering_driver_name()`과 시작 로그의 `D3D12 ... - Forward+ - Using Device ...`로 확인합니다. 요청한 플래그만으로 D3D12 사용을 단정하지 않습니다. CLI export의 `data.rendering_driver`도 실제 backend이며 helper는 요청과 다르면 실패합니다.

## 필수 회귀 명령

정확한 4.7.2 stable console editor, 같은 버전의 Windows x64 debug/release templates, Python 3, PowerShell, 최신 포터블 빌드를 준비합니다. submodule은 `git submodule update --init`으로 준비하세요.

```powershell
python tools/modular_particles/verify_backends.py `
  --godot C:/Godot/Godot_v4.7.2-stable_win64_console.exe `
  --templates C:/Godot/export_templates/4.7.2.stable `
  --build C:/Deliveries/modular-release-YYYYMMDD-HHMMSS
```

이 명령은 두 드라이버 각각에 대해 다음을 실행하며 하나라도 실패하면 nonzero로 종료합니다.

1. GPU probe, shader compilation, runtime, render, User GPU, 10만 입자/32 vec4 테스트.
2. 기본 모듈 GPU·성능·예제 테스트.
3. 임시 portable editor의 실제 Inspector 위젯, Undo/Redo, revert, 씬 저장/재열기.
4. 독립 애드온의 편집기 실행 및 Windows Release 실행.
5. 배포 EXE의 실제 CLI 계약 검사 및 요청 backend 확인.
6. 배포 스킬로 두 효과 제작→해당 backend에서 export→다중 효과 안전 설치→독립 게임 편집기/Release 실행.

`build_windows.py`도 이 전체 매트릭스를 **필수 단계로 자동 실행**합니다(우회/skip 옵션 없음). 실패하면 `BUILD_IN_PROGRESS.txt`를 남기고, 두 backend를 통과해야 `build-info.json`의 `backend_verification`을 기록하고 완료 표시를 합니다.

초기의 fallback 방지 단위 검사까지 **23 gates**입니다. 완료된 `results.json`에서 `passed=true` **및** `complete=true`를 확인하세요. 개별 gate 성공 또는 중간 상태는 전체 통과가 아닙니다. 실제 프로젝트·전역 editor 설정·기존 배포 파일은 변경하지 않고 새 임시 폴더를 사용합니다.

교차 backend 이식성 확인: `verify_skill_delivery.py --rendering-driver d3d12 --export-driver vulkan ...` 또는 반대 조합으로 실행합니다. 본래 효과 자원을 backend별로 다시 저작할 필요는 없습니다.

단독 애드온 검사와 backend 확인은 private runtime의 `RENDERING_BACKENDS.md`, 상세 이력과 산출물 위치는 [VALIDATION.md](test/modular_particles/VALIDATION.md)를 참조하세요. 전체 Material Maker UI/기존 셰이더 테스트는 `run_app_tests.py --test all --rendering-driver d3d12`로 추가 실행할 수 있습니다.

## 확인된 장비

- 2026-09-27, Godot `4.7.2.stable.official.ed1daf0bf`.
- Windows 11 Pro `10.0.26200` x64, NVIDIA GeForce RTX 3070, GPU driver `32.0.16.1088`.
- Vulkan `1.4.341` 및 D3D12 `12_0`.
- 양쪽 각각 runtime **31**, render **31**, User **139**, 10만 입자 **132**, 표준 GPU **155**/성능 **10**/예제 **42**, Inspector **56** PASS.
- 독립 애드온 editor/Release 각각 **7**, 두 효과·세 인스턴스 게임 각각 **31** PASS.

독립 runtime 및 Release 검사는 ERROR·누수에 엄격합니다. 전체 저작 앱 검사에는 기존 HDR/MTL import·종료 경고가 별도로 남을 수 있으므로 독립 애드온 결과와 혼동하지 않습니다. 측정된 성능 수치는 특정 장비의 관측값이며 다른 장비의 성능 계약이 아닙니다.
