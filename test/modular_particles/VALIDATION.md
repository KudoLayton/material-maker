# 검증 기록

대상: Godot `4.7.2.stable.official.ed1daf0bf`, Windows, Forward+, Vulkan 1.4.341, NVIDIA GeForce RTX 3070.

## 포터블 VFX CLI 검증

- 소스 실행 **25/25 명령 시나리오 PASS**, `mm-vfx-cli-ifjtdvw3`.
- 실제 Windows EXE **25/25 PASS**, `mm-vfx-cli-q2ka_48b`: capabilities/create/inspect/validate/export, 한글·공백 경로, 구버전·JSON·바인딩·옵션 오류, GPU 부재, 실제 Vulkan SPIR-V, 효과별 참조 경로/checksum, 재내보내기·ID 충돌·사용자 수정 보호. ERROR/leak 없이 종료했고 기존 환경설정 bytes가 유지됐습니다.
- 빌드 `build/modular-release-20260924-084846/MaterialMaker/MaterialMaker.exe`: GUI Release **260 checks PASS**, editor=false. CLI 사용법은 [MODULAR_VFX_CLI.md](../../MODULAR_VFX_CLI.md).
- 앞선 `084342` 빌드는 CLI template의 source/sidecar 경로 차이를 발견한 중간 산출물입니다. 삭제·덮어쓰지 않았으며 CLI 검증 완료 빌드는 `084846`입니다.
- 다중 효과 **게임 설치 helper**, 스킬 패키지 및 npx 설치는 아직 미완료입니다.

## 최신 효과 포맷 v2 전용 전환

- GUI·compiler·runtime에서 v1/버전 누락/미지원 미래 버전을 거부합니다. User 추가로 자동 승격하지 않습니다. `.mmg`와 export manifest의 별도 version 1은 유지합니다.
- 전체 앱 **48/48 PASS**, `mm-modular-app-lor3zwc0`: 신규 format editor **29 checks**, 실패한 파일 열기·clipboard·apply·save가 문서/탭/Undo/정상 GPU preview/저장 파일을 보존합니다. 기존 graph clipboard와 일반 Material 회귀도 통과했습니다.
- compiler **35**, User model **68**, User GPU runtime **139 PASS** (`mm-modular-particles-a1tzevrl`, `_pvw5g86`, `fwgi1cqa`). invalid sentinel 기본값을 가진 effect v2의 binary serialization/reload 검사 포함.
- private runtime `8ea4686`: 최신 v2 mmtest 재컴파일 + checksum 갱신. 독립 Godot editor/Windows Release **각 5 checks PASS**, `mm-modular-export-bw8193xs`, plugin enabled, ERROR/leak 없음.
- 최신 emitter 독립 GPU **PASS**, `mm-emission-standalone-lm3qov42`: 저장 효과로 연속 12 + 지연 burst 3 = GPU 15개.
- 기존 배포 파일과 외부 사용자 원본은 변경하지 않았습니다. 이 전환을 포함한 배포 EXE/CLI 검증은 위에 기록합니다. 스킬 설치는 아직 미검증입니다. 아래 구버전 지원 결과는 **과거 기록**이며 현재 지원 정책이 아닙니다.

## 파티클 작업 공간 이전 검증 (2026-09-23)

배포: **`build/modular-release-20260923-231142/MaterialMaker/MaterialMaker.exe`**. 사용법: [PARTICLE_WORKSPACE.md](../../PARTICLE_WORKSPACE.md).

| 영역 | 관측 결과 |
|---|---|
| 전체 앱 + legacy | **47/47 PASS**, `mm-modular-app-_3hvu1j2`; 기존 클립보드 검사도 통과 |
| 도킹·Module Inputs | **186 checks**, `mm-modular-app-gixt2wld`; 1440×960, 1024×720, 폭 170px, 1600×1000 / 125% 배율에서 좌표·스크롤·캡처 확인. 원래 재질/페인트 배치, 탭 전환/삭제, 도크 닫기/재열기 |
| 방출 UI | **50 checks**; Looping/Burst/Custom, 확인/취소/Undo/Redo, 유효성 검사, v1/v2 저장/compiled effect, GPU 7개 Burst, shader/버퍼/그래프/카메라/Pause 유지 |
| 카메라·환경 | **24 checks**; 기존 카메라 컨트롤러 MMB/Alt/Shift/Ctrl-wheel/Reset, HDRI pixel/투명 배경, 누락 HDRI의 로컬 폴백. 탭/도크 전환 후에도 GPU 상태 유지 |
| 실제 Windows Material Maker EXE | **260 checks, editor=false**, `verification/app-process.log`; 새 작업 공간 검사 14개, 기존 Release 검사 246개 포함 |
| EXE에서 내보낸 독립 프로젝트 | mmtest **5**, Basic **11**, User **27** checks 각각 editor/Windows release 통과, 플러그인 ON. `mm-modular-export-i2j_w0tu` / `180_nnku` / `6c8v2n_3` |
| 방출 독립 GPU | v1/v2 저장 효과만 로드해 연속 12개 + 지연 Burst 3개 = **GPU 15개** 확인, `mm-emission-standalone-93w56ixl` |
| Strict core | compiler **23**, User model **67**, GPU probe/shader PASS, runtime/render **각31**, User runtime **139**, performance **132** checks |
| Godot Inspector | **56 checks**, `mm-user-inspector-9i0tgxxl` |
| 기존 예제 생성기 | mmtest, 표준 12모듈, 기본 3예제, User 예제 `--check` PASS; 원본/예제 변경 없음 |
| 보존 감사 | 기존 EXE/시작 안내/예제 **27개 SHA-256 불변**, 원본 mmtest 및 fixture hash 일치, 세 bundle **13/13/14개** manifest 검증, ZIP/폴더 동일 |

Private 런타임 gitlink는 `60b6fb6e32ac56b0028d28d649ee5c54c68dd83b` 그대로이며 checkout도 clean입니다. 런타임 코드나 엔진 소스 변경 없이 authoring Preview 전용 재시작 경로를 사용합니다. 모든 import/테스트는 새 임시 프로젝트와 별도 사용자 설정에서 실행했고, 이전 빌드는 덮어쓰지 않았습니다.

실제 EXE 캡처: `verification/app/workspace-1024.png`, `workspace-1440.png`, `workspace-hdri.png`. 좁은 도크/배율 캡처와 결과: `verification/workspace/`. `verification/workspace-delivery-audit.json`은 보존/manifest 감사 결과입니다.

Strict/독립 검사에서는 ERROR·script error·누수를 실패로 처리해 통과했습니다. 전체 Material Maker 앱에는 기존 HDR/import 및 일부 종료 경고가 남으므로 ERROR-free를 주장하지 않습니다. 레이아웃 전환 후 orphan 패널 때문에 발생했던 종료 크래시는 숨긴 패널을 트리 안에 보관하여 해결했습니다. 도킹 컨트롤과 GPU SubViewport도 분리해 탭 이동으로 GPU가 종료되는 문제를 방지했습니다.

성능 참고(동일 RTX 3070): 100k/32 custom vec4 GPU median **1.566976 ms**, p95 **2.843392 ms**; 표준 Curl OFF/ON median **0.194656 / 0.768288 ms**. 측정 구간 readback/raster 없음; 환경별 성능 보장이 아닙니다.

재검증 명령:

```powershell
python tools/modular_particles/run_app_tests.py --godot $GODOT --test all --keep-going
python tools/modular_particles/run_emission_export_test.py --godot $GODOT --effects $EmissionUITestProject
python tools/modular_particles/build_windows.py --godot $GODOT --templates $Templates
python tools/modular_particles/verify_export.py --godot $GODOT --templates $Templates --bundle $Bundle --enable-plugin
```

아래는 이전 배포의 검증 기록입니다.

**이전 상태(2026-09-23, User Parameters): 클립보드가 허용되는 환경에서 기존 `legacy:test_app` 단독 **1/1**, 전체 앱 회귀 **44/44** 통과했습니다. 테스트/기능 코드를 변경하지 않았습니다. User 런타임·Inspector·독립 예제와 실제 Release EXE 246 checks도 통과했습니다. 이전 클립보드 접근 거부와 v1 검증 기록은 아래에 보존합니다.**

## User Parameters v2 검증과 클립보드 재검증

배포: `build/modular-release-20260923-111027/`. 실제 Material Maker EXE, `GodotUserParametersExample`, 기존 `GodotBasicExample`/`GodotExample`, `GodotAddon.zip`, 사용·마이그레이션 문서를 포함합니다. 코드가 동일한 상태에서 이전 클립보드 환경 실패를 재검증했습니다.

| 영역 | 관측 결과 / 임시 프로젝트 접미사 |
|---|---|
| 전체 앱 최신 | **44/44**, `mm-modular-app-je0tdibe`: User export25/UI59/binding11 및 기존 표준 모듈·legacy 검사 모두 통과. `run-18.log`: `PARTICLE_APP_TESTS: passed`; `app-results.json` 모두 passed |
| 클립보드 단독 최신 | **1/1**, `mm-modular-app-s2z0kowo`: 기존 `legacy:test_app` 수정 없이 복사·붙여넣기 통과. 별도 Win32 `OpenClipboard(NULL)` 3회 성공(error 0) |
| 이전 환경 실패 (보존) | 전체 `mm-modular-app-2pg_xskv` **43/44**, 단독 `mm-modular-app-aey6idao` 실패: 당시 Win32 `OpenClipboard(NULL)` 3회 Error 5(Access denied), 점유 HWND/PID 0. 내용은 읽지 않았고 권한/설정 변경이나 테스트 skip/mock/완화 없음 |
| 순수 compiler / User 모델 | 23 / 67 checks, `o6aroxha` / `4b3qi5sy` |
| GPU probe / shader | PASS, `8yvkjalr` / `61hl8hpp` |
| 기존 runtime / render | 각31 checks, `w77vg89p` / `09zwiukc` |
| User runtime | **139 checks**, `dzmpv3ru`: typed defaults/API/encoding, 인스턴스 독립성, 기존 state 유지, 실제 GPU 값 |
| 실제 Godot Inspector | **56 checks**, `mm-user-inspector-_8yr73hs`; 플러그인 체크박스 OFF, 타입별 실제 컨트롤·Undo/Redo·revert·씬 재열기 |
| 실제 Material Maker Release EXE | **246 checks, editor=false**. 공유 User UI59, v2 저장/재열기, sidecar User 예제와 GPU Preview, EXE에서 v1/v2 Export 포함 |
| EXE가 내보낸 User 프로젝트 | `mm-modular-export-azupghgq`: editor와 Windows release **각27 checks**, 플러그인 ON. 두 노드의 Speed/Gravity/Tint, reset, 게임 로직, 살아 있는 입자의 age/ID, GPU buffer/shader 동일성, 실제 빨강/파랑 pixel |
| EXE가 내보낸 기존 두 프로젝트 | Basic `b80jfi1j` **각11**, mmtest `znq_t0ck` **각5**, editor/Windows release 모두 통과 |
| 성능 | `g1rwvbdm`: 100k/32 custom vec4, 132 checks, GPU median **1.530176 ms**, p95 **2.201216 ms**, 측정 구간 readback/raster 없음 |
| 표준 모듈 성능 | 최신 전체 앱의 100k Curl OFF/ON median **0.19408 / 0.849952 ms**, p95 **0.197952 / 0.93536 ms**; 기능 회귀 통과이며 보편적 성능 보장은 아님 |

독립/strict 검사기는 ERROR·script error·누수 출력을 실패로 처리하며 위 결과는 해당 기준을 통과했습니다. **전체 Material Maker 앱**은 기존 HDR/import/종료 경고를 로그에 남길 수 있으므로 ERROR-free라고 주장하지 않습니다. 최신 클립보드 단독·전체 검사에는 이전 클립보드 접근 오류가 재현되지 않았습니다.

User 예제 및 기존 12개 모듈/3개 예제 생성기의 `--check`는 통과했습니다. User export는 v2/SPIR-V/manifest checksum, 재내보내기, 사용자 설정 보존, 수정된 demo 스크립트·잘못된 메타데이터의 원자적 거부를 검사합니다. 초기 standalone 검증의 잘못된 builtin ID와 가산 합산으로 흰색이 되던 demo Tint를 수정한 뒤 통과했습니다. 첫 release observer의 `res://` 예제 경로도 실제 배포 sidecar 경로로 고쳤으며, 실패 빌드 `110541`은 재사용하지 않았습니다.

배포 감사는 기존 EXE/빌드 안내/4개 기존 예제/원본 mmtest.ptex의 **33개 보호 파일 SHA-256 불변**, 세 bundle의 **14/13/13개 manifest checksum**, private checkout과 배포 런타임 파일 동일성, addon ZIP과 폴더 동일성을 확인했습니다. 최신 빌드의 `verification/user-delivery-audit.json` 및 각 검사 원본 로그를 참고하세요.

소스 기능 단위: User 문서 `f8be95f8`, 편집 UI `e6f9eeea`, 예제/export `1916001e`. private runtime gitlink는 `60b6fb6e32ac56b0028d28d649ee5c54c68dd83b`입니다. 런타임 구현 파일을 public 저장소에 복사하지 않습니다.

클립보드가 허용되는 실행 환경에서 아래 두 앱 검사를 그대로 재실행하여 각각 1/1, 44/44 통과를 확인했습니다. Inspector와 예제 생성 검사는 직전 배포 검증에서 통과했습니다. 검사를 변경하거나 생략하지 않았습니다.

```powershell
python tools/modular_particles/run_app_tests.py --godot $GODOT --test legacy:test_app
python tools/modular_particles/run_app_tests.py --godot $GODOT --test all --keep-going
python tools/modular_particles/run_inspector_tests.py --godot $GODOT
python tools/modular_particles/build_user_example.py --check
```

아래는 기존 v1/기본 모듈 검증 기록입니다.

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

입력 삭제 배포: `build/modular-release-20260922-092746/` (namespace 표시 포함 최신 빌드는 아래 참조). 이전 EXE/사용자 문서는 그대로 유지했습니다. private 런타임 submodule은 `41a62fee`로 유지하며 이번 변경은 Material Maker 편집기와 검사/문서에만 있습니다.

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
- 독립 Godot: `%TEMP%/mm-modular-export-noqyfo8n/`; 로그 사본은 입력 삭제 배포의 `verification/godot/`.

## 추가 요청: Namespace 표시와 바인딩 상태 구분

**최신 배포: `build/modular-release-20260922-212743/`**. Godot 4.7.2 / Forward+ / Vulkan 대상이며 private runtime submodule은 `41a62fee` 그대로입니다.

- Module Input은 `Module.Position`, 기본 Attribute는 `Particle.Position`, 사용자 Attribute는 `Particle.Custom.Position`, 컨텍스트는 `Context.delta`처럼 표시합니다. 단수 `Particle`을 사용합니다.
- `Read`/`Write` 역할, 실제 Renderer 용도, 출력 포트 등록/연결 상태는 namespace와 별도로 안내합니다. 사용자 vec4의 명시적인 INSTANCE_CUSTOM 지정도 ID로 확인합니다.
- Namespace/Name/Type·ID 트리, 원래 이름만 편집, 중복 ID 배지, 긴 이름 툴팁, 중첩·전환·Undo/Redo·import 갱신을 지원합니다. 표시 컨텍스트는 직렬화하지 않습니다.
- `.mpfx`/`.mmg` 버전, 원래 이름, stable ID, 포트 ID/타입, shader, Attribute/parameter layout, 런타임 API는 바꾸지 않았습니다. 이름 기반 자동 바인딩이나 새로운 입력 바인딩 기능은 추가하지 않았습니다.

| 검사 | 결과 |
|---|---|
| `test_namespace_model` | **29 checks**: 세 Position 구분, 현재 정의 이름, renderer/output 상태, readonly, 중복 Attribute/입력 이름·ID 접두사 충돌, Missing/fallback, 긴 한글/namespace처럼 보이는 이름, port ABI·직렬화·shader/layout 불변 |
| `test_namespace_editor` | **46 checks**: 실제 입력/트리/포트·툴팁, raw Name inline edit, 중첩/모듈 전환/연결·Unbind·Missing 갱신, Undo/Redo, `.mpfx`/`.mmg` roundtrip/import, dirty/history/preview 불변 및 GPU 구별 |
| 기존 편집기 회귀 | editor 24, Rename 38, input delete 36, graph backend 6, mmtest 36, exporter 25, 기존 port UI **163 checks** 모두 통과 |
| 실제 Release EXE | **MODULAR_RELEASE PASS checks=123 editor=false**: namespace 공유 UI/GPU 검사, raw 이름 저장·재열기, 기존 삭제/Rename 및 독립 효과 Export 포함 |
| 독립 Godot / Windows Release | plugin 활성화 import와 각 **5 checks** 통과, 독립 런타임 ERROR/RID leak 없음 |

GPU 구별 검사는 Module.Position `[5,6,7]`을 사용자 Position에 쓰고 다음 Update 모듈에서 다시 읽어 별도 Attribute로 복사합니다. GPU readback에서 사용자 Position과 복사 값은 `[5,6,7]`, 기본 Position과 MultiMesh 렌더 위치는 `[0,0,0]`으로 확인했습니다. 동일 이름이 자동으로 연결되지 않습니다.

전체 Material Maker의 기존 종료 경고는 별도입니다. 이번 작업에서 모든 legacy 앱 스위트를 재실행했다는 의미는 아니며, 위에 명시한 회귀 검사와 실제 Release를 검증했습니다. 테스트용 namespace 그래프는 최종 GodotExample을 내보내기 전에 원래 mmtest 효과로 복원합니다.

증거:

- namespace 모델/UI: `%TEMP%/mm-modular-app-juw68map/run-1.log`, `run-2.log`.
- 회귀 7/7: `%TEMP%/mm-modular-app-vo3n9kt4/app-results.json`, `run-1.log` ~ `run-7.log`.
- 최신 배포: `verification/app-process.log`, `verification/app/release-smoke.json`, `verification/app/namespaces.png`, `material-maker.png`.
- 독립 Godot: `%TEMP%/mm-modular-export-0vgwxvtk/`; 로그 사본은 위 Namespace 배포의 `verification/godot/`.

## 추가 요청: Niagara 참고 기본 모듈 12종

**배포: `build/modular-release-20260923-002432/`**. 사용법과 전체 기본값은 [STANDARD_PARTICLE_MODULES.md](../../STANDARD_PARTICLE_MODULES.md)에 있습니다.

- 검색 라이브러리, 독립 그래프 복사본, versioned role 기반 Attribute 자동 병합, 단일 Undo/Redo, 스택 오류/경고, 새 문서 기본 구성 및 예제 3종을 구현했습니다.
- 역할/입력을 참고한 독립 MM 그래프이며 UE 에셋/코드가 아닙니다. 가속도 누적 + 지수 Drag + Solve를 사용하고 Force/Mass는 도입하지 않았습니다.
- Source/Release에서 Curve·Gradient·3D Curl 및 Code 편집을 검증했습니다. 큰 그래프는 읽을 수 있는 배율로 Module Output부터 보여줍니다.
- 가독성 조정 중 기존 Canvas의 지연 redraw가 이미 해제된 generator를 참조하는 문제가 재현되었습니다. `_draw/_draw_port`의 수명 검사를 추가했고, 해제된 테스트 generator로 redraw하는 회귀 검사 및 실제 모듈 전환을 통과했습니다. 실패 로그는 숨기거나 검사에서 제외하지 않았습니다.

| 검사 | 최신 관측 결과 |
|---|---|
| Attribute/스냅샷 모델 | **27 checks**: 이름/ID 충돌 격리, role 공유, 중첩 typed ID 재매핑, 독립 복사, legacy/revision/일반 Attribute 호환, 원자적 거부 |
| 표준 스택 진단 | **25 checks**: 중복·누락·역순·비활성 Solve/Initialize, role/type, 연결된 Read/Write, custom 초기값 provider, Position writer 경고, legacy 무소급 |
| 12종 GPU 수치 | **155 checks**: 단계별 가속도/Drag/적분/누적값 초기화, 분포·seed, 음수 범위 양 끝값 clamp, 영벡터·0 반경/주파수, 비누적 외형, Kill/slot 재사용, Local/World, 서로 다른 Curve/Gradient/Curl 복사본 |
| 라이브러리 UI | **51 checks**: 검색·카테고리·Stage·상세·Enter·더블클릭·실제 Esc, 삽입 위치/단일 Undo, role 재사용, Rename/Input 삭제, 독립 Code 편집, mpfx/mmg 왕복, 오류 시 Preview 보존·Ready 경고 |
| 새 문서/예제 UI·GPU | **42 checks**: 기본 6모듈/4role, 독립 ID, 기존 Emitter/Renderer, 3예제 GPU/128 burst, 파일 보존, Kill Age, 읽기 쉬운 초기 화면·해제 generator redraw |
| 전체 앱 스위트 | 최신 `aph_7wsc`에서 **41/41** 통과(14 modular + 27 legacy). 클립보드 단독 `pxf__e4e`도 **1/1** 통과. 이전 `0wy8cxki`의 **40/41** 실패 기록은 아래에 보존 |
| 순수 compiler / runtime / render | **23 / 31 / 31 checks**, strict ERROR/leak 검사 통과 |
| 실제 Windows Material Maker | **MODULAR_RELEASE PASS checks=179 editor=false**. 정상 CLI 시작, 기존 Rename/Delete/Namespace, 라이브러리/새 문서, 12종 GPU 실행, 두 독립 효과 Export 포함 |
| GodotBasicExample | plugin 활성화 import, 독립 실행 **11 checks**, 실제 Windows EXE **11 checks**. SPIR-V, 128 indirect instances/pixels, pause, 수명/초기값/누적값/Curve/Gradient 확인. ERROR/leak 없음 |
| 기존 GodotExample(mmtest) | plugin 활성화 import, 독립 실행 및 실제 Windows EXE 각각 **5 checks**. ERROR/leak 없음 |

### 성능

RTX 3070, 100k 입자, 36 scalar components, Gravity/Drag/Solve + Box, 100 step 중 21 warmup 이후 79 GPU timestamp 샘플. 이전 전체 회귀 `0wy8cxki`의 관측값:

| 조건 | GPU 중앙값 | p95 | 추적 버퍼 |
|---|---:|---:|---:|
| Curl OFF | 0.192864 ms | 0.194624 ms | 23,200,260 bytes |
| Curl ON | 1.644032 ms | 2.349600 ms | 23,200,284 bytes |

최신 전체 재실행 `aph_7wsc`에서는 OFF 중앙값 **0.193152ms**/p95 **0.196256ms**, ON 중앙값 **0.850560ms**/p95 **0.955008ms**였습니다. 버퍼 크기와 샘플 수는 동일합니다.

raster draw/readback은 측정에서 제외했습니다. 최초 별도 실행 `q1ksu166`에서는 ON 중앙값 1.241120ms/p95 1.988960ms였습니다. 실행별 부하에 따라 달라지므로 전체 효과 FPS나 Niagara 대비 우위를 의미하지 않습니다.

### 클립보드 재검증 완료와 이전 실패 기록

- 이전 전체 실행 `0wy8cxki`의 `legacy:test_app`은 `clipboard_set/get: Unable to open clipboard` 뒤 복사·붙여넣기 assertion에서 실패했습니다. 별도 격리 재실행 `y2bycnsi`도 동일했습니다.
- 당시 내용을 읽거나 변경하지 않는 Win32 probe: **OpenClipboard(NULL)=false, GetLastError=5 (Access denied)**, locking window/PID 없음. 새 모듈의 Attribute나 GPU 처리 오류와 구분합니다.
- 이후 새 격리 프로젝트 `pxf__e4e`에서 같은 테스트를 재실행해 **exit 0, PARTICLE_APP_TESTS: passed, 1/1 통과**를 확인했습니다. 이어 전체 스위트 `aph_7wsc`도 **exit 0, 41/41 통과**했습니다. 두 재실행 로그에 클립보드 접근 오류가 없습니다.
- 소스 기준은 `a8ecb2d75c0f94496a6338378c065bae58322386`이며 테스트/구현 수정, skip/mock 또는 Windows 권한·설정 변경 없이 통과했습니다. 후속 변경은 검증 기록뿐입니다.

```powershell
python tools/modular_particles/run_app_tests.py --godot $GODOT --test legacy:test_app
python tools/modular_particles/run_app_tests.py --godot $GODOT --test all --keep-going
```

전체 MM 앱의 기존 HDR/종료 RID/ObjectDB 경고와 이전 클립보드 실패 로그는 보존합니다. 전체 앱의 통과는 이 경고까지 해결했다는 뜻이 아니며, 독립 Godot 예제의 strict 무오류·무누수 결과와 혼동하지 않습니다.

### 재현과 증거

- 최신 전체 앱 **41/41**: `%TEMP%/mm-modular-app-aph_7wsc/app-results.json`, `run-1.log`~`run-41.log`, `standard-performance.json`. 로그 사본은 배포의 `verification/source-regression-rerun/`.
- 클립보드 단독 **1/1**: `%TEMP%/mm-modular-app-pxf__e4e/app-results.json`, `run-1.log`. 로그 사본은 배포의 `verification/clipboard-rerun/`.
- 이전 전체 앱 **40/41**: `%TEMP%/mm-modular-app-0wy8cxki/app-results.json`; 배포의 기존 `verification/source-regression/`도 덮어쓰지 않고 보존했습니다.
- 배포 EXE SHA256은 재검증 전후 **b41c7f97851c6fc1dbd7403c9d4b0b5d5a14152e45769484461ed098adef037e**로 동일합니다.
- 이전 전체 통과: `%TEMP%/mm-modular-app-cbw31zpz/app-results.json`. 음수 범위 보완 후 GPU155/예제39/UI51은 `o05f73eq`; 가독성/수명 회귀 보완은 `zvwr4o1c`, `10_fep6u` 및 최종 전체 실행에서 확인했습니다.
- 순수 검사: `%TEMP%/mm-standard-runtime-cb483f99beff4951b3100ee4d59863bb/`; 원 실행은 `mm-modular-particles-c86hpk65`, `7z74pdd4`, `wzqof8p2`.
- 최종 EXE: 배포의 `verification/app-process.log`, `verification/app/release-smoke.json`, `verification/app/standard-library.png`, `verification/app/standard-editor.png`.
- 새 독립 Godot: `%TEMP%/mm-modular-export-og58tpcy/`; 기존 mmtest: `%TEMP%/mm-modular-export-w1jtxz09/`. 로그 사본은 배포의 `verification/godot-basic/`, `verification/godot-mmtest/`.
- `build_standard_modules.py --check`, `build_standard_examples.py --check`, `build_mmtest_example.py --check`를 통과했습니다. mmtest 원본 SHA는 위 기록과 동일합니다.
- private runtime submodule은 **41a62feed99567153bf4a3abd005595b0563c8b0** 그대로이며 public Git 트리에는 gitlink만 있습니다. Godot 엔진·UE 에셋·사용자 원본·이전 빌드/설정은 변경하지 않았습니다.
