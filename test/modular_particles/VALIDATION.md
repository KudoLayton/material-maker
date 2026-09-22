# 검증 기록

대상: Godot `4.7.2.stable.official.ed1daf0bf`, Windows, Forward+, Vulkan 1.4.341, NVIDIA GeForce RTX 3070.

**최종 수용 완료: 기능 구현, 독립 Windows 실행 및 모든 앱 기능 검사를 검증했습니다. 클립보드 재검사도 통과했습니다. 아래의 기존 Material Maker 종료 경고는 별도로 남아 있습니다.**

## 통과한 검사

| 영역 | 결과 |
|---|---|
| `test_compiler` | 23 checks: 33 vec4, bit-exact uint, scoped inputs, 비활성화, 오류 위치/타입/순환, 순서/명시적 write, 사용자 ID와 kernel token 충돌 방지 |
| `gpu_probe`, `test_shader` | 실제 main RD → MultiMesh / 간접 명령 버퍼 연결 및 GLSL 실행 통과 |
| `test_runtime` | GPU readback 기반 영속성·재사용·capacity 초과·수명·정수·Local/World·재시작/seed·rate/burst·catchup 통과 |
| `test_render` | 31 checks: 3 재질 모드, Color/CustomData 실제 pixel, 다중 surface, AABB, 반복 rebuild/부분 실패/노드 제거 |
| `test_editor` | 24 checks: 기존 캔버스, 스택 undo/redo, 저장/재저장/열기, stable ID, Library snapshot/revision, live input, 오류 시 정상 Preview 보존, 기존 ptex 탭 |
| `test_graph_backend` | 6 checks: 중첩 Curve/FBM/Evaluate/Quaternion GPU 실행; 서로 다른 Curve 및 중복 모듈 namespace; procedural/typed 노드 재생성 후 동일 source hash |
| `test_mmtest` | 36 checks: reference hash, 원본 재컴파일, 128개 GPU 상태 4시점 비교 |
| `test_export` | 25 checks: 재내보내기, checksum, 사용자 파일/설정 보존, 충돌 무변경, SPIR-V 직렬화, 실패 시 이전 결과 보존 |
| Standalone + Windows Release | 각 5 checks, `editor=true`/`false`: precompiled bytecode, 초기화, 128 indirect instances, 화면 pixel, pause. ERROR/RID leak 없음 |
| `test_performance` | 132 checks: 100,000 입자, 사용자 vec4 32개 전체 첫/마지막 슬롯 roundtrip, 생존 수, GPU timestamp |

순수 런타임 검사기는 `ERROR`, script error 및 누수 출력을 실패로 처리합니다. Material Maker 전체 앱에는 원래의 HDR/누락 MTL import 경고 및 종료 시 detached preview/local RD 관련 누수 로그가 남아 있습니다. 기존 ptex 앱 테스트에서도 같은 종류를 확인했습니다. 전체 앱의 이 경고들을 새 런타임이 누수 없이 종료한다는 증거와 혼동하지 않습니다.

## mmtest 수치 비교

원본 및 보존 사본 SHA-256:

`4822ae43ec54de6f73d55b8f5c359f66df653a95c13e5b4e90079f3222b60932`

원본 `.ptex`를 새로 컴파일한 start/process 본문을 **테스트 전용** GPU oracle에서 실행합니다. 원본의 이전 속도 적분 순서를 재현하며, 실제 런타임/내보내기는 이 legacy shader 변환을 사용하지 않습니다.

동일 seed, 128개, step 1/10/20/40:

- Age, Scale, Spherical UV: 차이 0.
- InitialVelocity 최대 절대차: `9.54e-7`.
- Position 최대 절대차: `0.000992` (허용 0.003).
- Velocity/Curl 최대 절대차: `0.01703` (허용 0.03).

중앙차분 간격 0.0001의 Curl이 작은 부동소수점 오차를 증폭합니다. 비트 단위 일치라고 주장하지 않습니다. 20번째 step 화면도 확인했습니다. 샘플은 자동 변환기가 아닌 여섯 모듈의 명시적 재작성입니다. 재생성 스크립트 `--check`도 통과했습니다.

## 성능

별도 프로세스에서 21 step warmup 후 139 GPU timestamp 샘플. 100,000개 활성 입자, 기본 Attribute 외 사용자 vec4 32개, 총 153 scalar components. 모든 사용자 필드를 매 step 읽고 씁니다.

| 측정 | 중앙값 | 평균 | p95 |
|---|---:|---:|---:|
| GPU 시뮬레이션/압축/드로우 데이터 작성 | 1.578 ms | 1.836 ms | 2.265 ms |
| Render thread 명령 제출 | 0.068 ms | 0.069 ms | 0.077 ms |

추적한 버퍼 크기: **70,000,152 bytes** (약 66.76 MiB). 텍스처, 드라이버/파이프라인 부가 메모리는 제외합니다. 타이밍 중 readback과 실제 raster draw는 제외하므로 전체 효과 FPS나 다른 GPU의 성능 보장은 아닙니다.

## 기존 파티클 회귀 / 클립보드 재검증

**31개 앱 기능 검사 모두 통과 확인**: 전체 실행 30/31에 더해, 남았던 `legacy:test_app`을 별도 재실행하여 통과했습니다. 신규 앱 검사 4/4, 기존 파티클 검사 27/27입니다. 단일 실행에서 31/31을 얻었다는 의미는 아닙니다.

- 기존 compiler 184 assertions, 인터페이스 GPU shader 118개, 추가 GPU 조합 191개, 포트 UI 163 checks를 포함합니다.
- 기존 UI 테스트 5개는 `window.quit()` coroutine을 기다리지 않고 SceneTree를 바로 종료하던 테스트 teardown 문제를 수정했습니다. 기능 assertion은 바꾸지 않았고, 수정 후 모두 통과했습니다.
- 이전 `legacy:test_app` 실패는 `DisplayServer.clipboard_set/get`의 `Unable to open clipboard` 뒤 발생했습니다. 별도 Windows API probe도 `OpenClipboard(NULL) = false`, **Win32 error 5 (Access denied)**를 확인했습니다. probe는 내용을 읽거나 수정하지 않았습니다.
- 사용자가 Windows 복사·붙여넣기 정상 동작을 확인한 후, 같은 검사를 수정 없이 새 격리 프로젝트에서 재실행했습니다. **`PARTICLE_APP_TESTS: passed`, `TEST SUMMARY: 1/1 passed; failed=[]`**, exit code 0을 확인했습니다. 재실행 로그에는 클립보드 오류나 script error가 없습니다.
- 시스템 설정 변경이나 검사 skip 없이 검증했습니다. 기존 앱 종료 시 RID/ObjectDB 누수 로그는 앞서 설명한 별도 사항으로 남아 있으며, 오류 없는 독립 런타임 종료와 구분합니다.

```powershell
python tools/modular_particles/run_app_tests.py --godot $GODOT --test legacy:test_app
```

## 로컬 증거 위치

임시 파일은 OS 정리로 없어질 수 있으므로 위 명령으로 재생성할 수 있습니다.

- 최신 신규 앱 4/4: `%TEMP%/mm-modular-app-ckltxdta/run-1.log` ~ `run-4.log`; 실제 배포 가능한 프로젝트는 `standalone/project.godot`.
- 전체 회귀 최초 실행 30/31: `%TEMP%/mm-modular-app-w3qpqlju/app-results.json` 및 `run-*.log`.
- 마지막 클립보드 회귀 재검사 1/1 통과: `%TEMP%/mm-modular-app-n4yn5v6e/app-results.json`, `run-1.log`.
- Windows 검증: `%TEMP%/mm-modular-export-8e3n49fd/` (`release-engine.log`, `windows/ModularParticles.exe`). 이 EXE는 검사 후 자동 종료하는 **검증 빌드**입니다.
- 성능: `%TEMP%/mm-modular-particles-p4nwi6xy/performance.json`.
- 최종 compiler: `%TEMP%/mm-modular-particles-gqq3bw49/run-1.log`.

기존 사용자 `.ptex` 및 기존 빌드/설치 파일은 덮어쓰지 않았습니다. 위 기능 테스트/효과 Windows export는 새 임시 디렉터리에서 실행했습니다. `git diff --check`도 통과했습니다.

## 추가 요청: 일반 실행용 Material Maker 배포

최초 일반 실행용 배포 폴더: `build/modular-release-20260922-075916/` (Rename 기능 포함 최신 빌드는 아래 참조).

- `MaterialMaker/MaterialMaker.exe`: 공식 4.7.2 Windows x64 Release. 일반 `parse_args` 시작 경로와 외부 `.mpfx` 명령행 열기를 검증했습니다.
- `verification/app-process.log`: **MODULAR_RELEASE PASS checks=21 editor=false**. 런타임 원문, I/O schema/preview shader, Library, GPU Preview, 그래프 캔버스, 저작 저장/열기, 패키지 안에서 Compute 컴파일/독립 효과 Export, 기존 ptex 편집기 확인.
- `MaterialMaker/Open mmtest.cmd`: 예제 바로 열기. 기존 설치본과 설정을 공유하지 않습니다.
- `GodotExample/project.godot`: 해당 Release 앱이 직접 내보낸 완성 예제.
- `GodotAddon.zip`: 런타임 8파일의 SHA256가 효과 export manifest와 일치함을 검사했습니다.
- `START_HERE.txt`, `GODOT_PARTICLES_PLUGIN.md`: 실행/프로젝트 통합/선택적 플러그인 활성화/Inspector/API 안내.

해당 GodotExample을 새 프로젝트로 복사하여 **EditorPlugin 활성화 상태**로 import, 독립 실행 5 checks, Windows export 후 실제 release 실행 5 checks를 통과했습니다. 로그: `%TEMP%/mm-modular-export-jnpxlhk7/`. 독립 실행에는 ERROR/RID leak가 없습니다. MM 전체 앱의 기존 HDR/종료 누수 경고는 별도입니다.

재현 도구: `tools/modular_particles/build_windows.py` (항상 새 출력 폴더), `verify_export.py --enable-plugin`. 이 빌드는 `.gd` 원문을 포함하여 **배포된 Material Maker에서도 효과를 내보낼 수 있습니다**. 원본 `parse_args.gd`는 수정하지 않으며, 빌드 사본에만 명시적 검증 플래그로 동작하는 고정 observer를 포함합니다. 정상 실행은 자동 종료하지 않습니다.

## 추가 요청: 모듈 Rename / F2 포함 빌드

Rename 배포: `build/modular-release-20260922-084010/` (입력 삭제 포함 최신 빌드는 아래 참조). 기존 배포 폴더와 설치본은 유지했습니다.

- UI: 선택된 공유 모듈 정의를 Rename 버튼 또는 스택 포커스 F2로 변경. 이름 선택/포커스, Enter와 확인 버튼, 공백 제거, 빈 이름 거부, 취소, Undo/Redo 지원. `.mpfx` 및 `.mmg`에 유지됩니다. 외부 Library 파일과 다른 효과를 자동 수정하지 않습니다.
- `test_module_rename`: **38 checks** 통과. 동일 정의의 복수 인스턴스/선택 목록 갱신, 안정 ID·입력·그래프·stage 보존, shader hash 불변, 프리뷰 재시작 없음, 반복/수정키 및 스택 밖 F2 무시, 저장·재열기와 `.mmg` roundtrip/reimport 포함.
- 회귀: `test_editor` 24, `test_graph_backend` 6, `test_export` 25 checks 통과. 이번 변경에서 전체 32개 앱 스위트를 재실행했다는 의미는 아닙니다.
- 실제 Windows Release: **MODULAR_RELEASE PASS checks=51 editor=false**. 공유 Rename 검사를 실제 패키지에서도 실행하고, 이름 변경 후 저장/재열기/Compute 컴파일/독립 Export 및 기존 ptex 편집기를 검증했습니다.
- 해당 빌드의 `GodotExample`을 새 격리 프로젝트로 복사하여 EditorPlugin 활성화 import, 독립 실행 5 checks 및 Windows Release 실행 5 checks 통과. 이 독립 런타임 로그에는 ERROR/RID leak가 없습니다. MM 전체 앱의 기존 종료 경고는 여전히 별도입니다.
- `START_HERE.txt`와 `MaterialMaker/MODULAR_PARTICLES.md`에 사용법을 동봉했습니다. 앱 폴더 전체를 유지해 사용하세요.

증거:

- 소스 UI/Export: `%TEMP%/mm-modular-app-y1lyc6j5/run-1.log`, `run-2.log`.
- 기존 편집기/그래프 회귀: `%TEMP%/mm-modular-app-_y848jsr/run-2.log`, `run-3.log`.
- 실제 배포 EXE: 최신 배포의 `verification/app-process.log`, `verification/app/release-smoke.json`.
- 실제 Rename 창/이름 반영 화면: `verification/app/rename-dialog.png`, `material-maker.png`.
- 독립 Godot 검증: `%TEMP%/mm-modular-export-fu2p2kj6/`; 로그 사본은 Rename 배포의 `verification/godot/`.

## 추가 요청: Module Input 삭제

**최신 배포: `build/modular-release-20260922-092746/`**. 이전 EXE/사용자 문서는 그대로 유지했습니다. private 런타임 submodule은 `41a62fee`로 유지하며 이번 변경은 Material Maker 편집기와 검사/문서에만 있습니다.

- 입력 행에 **Delete** 버튼 추가. 연결/비연결/중첩 Read를 현재 그래프에서 찾아 사용 중이면 삭제를 거부하고 참조 경로를 안내합니다. 아직 저장하지 않은 Read도 검사합니다.
- 같은 모듈의 Spawn/Update 인스턴스에서 해당 입력값만 정리합니다. 비활성 인스턴스를 포함하고 다른 모듈/입력은 보존합니다. Undo/Redo로 정의·순서·인스턴스별 값을 복구/재삭제합니다.
- shader hash가 같아도 입력 버퍼 구성이 달라지면 Preview를 갱신합니다. 일반 숫자 입력 변경은 시뮬레이션을 재생성하지 않습니다.
- `test_module_input_delete`: **36 checks** 통과. 삭제 버튼, stale/loading callback 보호, 연결/비연결/중첩/typed IR 참조, 공유 값 정리, Undo/Redo, preview layout, `.mpfx` 재열기, `.mmg` 저장/reimport를 검증했습니다.
- 회귀: 기존 editor **24**, Rename **38**, graph backend **6**, exporter **25** checks 통과. 이번 작업에서 전체 앱 스위트를 재실행했다는 의미는 아닙니다.
- 실제 Windows Release: **MODULAR_RELEASE PASS checks=82 editor=false**. 동일 삭제 검사를 실제 EXE에서 실행하고 저장·재열기·독립 효과 내보내기까지 확인했습니다. 테스트용 모듈은 최종 Godot 예제를 만들기 전에 제거합니다.
- 해당 GodotExample의 플러그인 활성화 import, 독립 실행 **5 checks**, Windows export 후 실제 실행 **5 checks** 통과. 독립 런타임은 ERROR/RID leak 없이 종료했습니다.
- 전체 Material Maker 로그에는 기존 종료 누수 경고와 Windows `Unable to open clipboard` 로그가 남습니다. 이번 삭제 기능 검사는 클립보드 내용을 사용하지 않으며, 이를 클립보드 기능의 정상 검증으로 주장하지 않습니다.

최초 패키지 검사는 입력 삭제가 기존 mmtest Update 모듈의 uniform offset을 바꿔 shader hash도 바뀌는 정상 상황을 잘못 가정한 테스트가 실패했습니다. 같은 hash/다른 layout 검사는 독립된 무참조 테스트 모듈로 격리하고, assertion을 유지한 채 소스/새 패키지 모두 재검증했습니다.

증거:

- 입력 삭제/그래프/exporter: `%TEMP%/mm-modular-app-zi8qnwem/run-1.log` ~ `run-3.log`.
- 기존 editor/Rename: `%TEMP%/mm-modular-app-2shub7o4/run-2.log`, `run-3.log`.
- 실제 EXE: 최신 배포의 `verification/app-process.log`, `verification/app/release-smoke.json`.
- UI 화면: `verification/app/input-delete.png`, `material-maker.png`.
- 독립 Godot: `%TEMP%/mm-modular-export-noqyfo8n/`; 로그 사본은 최신 배포의 `verification/godot/`.
