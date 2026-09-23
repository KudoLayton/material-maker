# Modular VFX 명령행 (계약 v1)

이 포크의 최신 포터블 Material Maker가 필요합니다. 일반 Material Maker 배포에는 이 CLI가 없습니다.
Godot 4.7.2 stable, 효과 원본/리소스 **v2만** 지원합니다. `.mmg`와 export manifest는 각각 별도 형식 v1입니다.

```powershell
$App = 'C:/Tools/MaterialMaker/MaterialMaker.exe'
# GUI를 열지 않고 조회/문서 검사 (GPU shader 검증이 아님)
& $App --headless -- --mpfx-command capabilities --report C:/Work/capabilities.json
& $App --headless -- --mpfx-command create --template basic_fountain --output C:/Work/fountain.mpfx
& $App --headless -- --mpfx-command inspect --input C:/Work/fountain.mpfx
& $App --headless -- --mpfx-command validate --input C:/Work/fountain.mpfx --report C:/Work/validation.json

# 실제 GPU 컴파일과 SPIR-V export. 게임 프로젝트가 아닌 별도 staging 폴더를 사용합니다.
& $App --rendering-method forward_plus --rendering-driver vulkan -- --mpfx-command export --input C:/Work/fountain.mpfx --output C:/Work/staging-fountain --effect-id fountain --capacity 4096 --report C:/Work/export.json
```

폴더는 예시이며 실제 경로로 바꾸세요. GUI Windows exe를 스크립트에서 호출할 때에는 프로세스 종료를 기다리고 exit code와 report를 함께 확인하세요. `--` 뒤에는 CLI 인수만 넣습니다. Godot `--headless`/renderer 옵션은 앞에 넣습니다.

## 명령

- `capabilities`: 앱/엔진 식별값, CLI 및 최신 포맷 계약, template 5종, 기본 모듈 12종, 공유 런타임 파일 checksum과 `runtime_id`.
- `create --template NAME --output ABSOLUTE_FILE`: 패키지 template를 최신 `.mpfx`로 복사합니다. 부모 폴더가 필요하며 기존 파일을 덮어쓰지 않습니다.
- `inspect --input ABSOLUTE_FILE`: 형식 검사 후 원본 구조를 `data`로 반환합니다.
- `validate --input ABSOLUTE_FILE`: 실제 loader/compiler로 그래프·타입·바인딩을 검사합니다. `gpu_compiled=false`이며 GPU 실행 가능성을 보장하지 않습니다.
- `export --input FILE --output DIRECTORY --effect-id ID [--capacity N]`: 실제 GPU 컴파일 후 manifest 기반으로 export합니다. Capacity 기본은 문서의 `preview_capacity`, 없으면 4096입니다. 양의 정수와 GPU 안전 한도를 검사합니다.
- 모든 명령은 선택적 `--report ABSOLUTE_NEW_FILE`을 지원합니다. report는 입력/출력과 분리하고 부모 폴더를 미리 생성하세요. 기존 report는 보호하며 새 이름을 사용합니다.

Template: `basic_fountain`, `box_turbulence`, `sphere_burst`, `user_parameters`, `mmtest`.
Effect ID: 1~64자의 소문자 영문·숫자·`_`·`-`, Windows 예약 이름 금지. 출력은 `effects/modular_particles/<id>/`와 공유 `addons/mm_gpu_particles/`입니다. GUI의 기존 ID 없는 출력 경로는 유지합니다. 한 staging 폴더의 ID는 바꿀 수 없습니다.

## 결과 계약

엔진 로그와 별도로 `MM_VFX_REPORT {JSON}` 한 줄을 출력합니다. report 파일에는 접두사 없이 JSON만 저장합니다.

- `contract_version: 1`, `command`, `ok`, `exit_code`, `diagnostics`, `data`.
- diagnostics: `stage`, `message`, 가능한 경우 compiler의 `module`, `node`; 경고는 `severity: warning`.
- export의 `data.manifest.files`는 파일별 SHA-256이며 `data.gpu_compiled=true`입니다.
- 잘못된 CLI 인수처럼 report 경로 검증 전 실패한 경우 JSON 보고서는 stdout만 제공될 수 있습니다. 종료코드가 성공이 아니면 산출물을 사용하지 마세요.

| 코드 | 의미 |
|---|---|
| 0 | 성공 |
| 2 | 잘못된 인수/옵션/경로/ID |
| 3 | 포맷·JSON·문서·그래프·shader compile·capacity 오류 |
| 4 | 엔진/GPU/renderer 환경 부족 |
| 5 | 파일 충돌·읽기/쓰기·report 오류 |

구버전 자동 승격, GUI fallback, 최근 파일/환경설정 저장, 사용자 코드/프로젝트 설정 덮어쓰기는 하지 않습니다. 읽기/출력 경로에 링크·`..`를 허용하지 않습니다. Export 충돌은 manifest 삭제나 강제 덮어쓰기 대신 새 staging 폴더로 해결하세요.

## 개발 검증

```powershell
python tools/modular_particles/run_cli_tests.py --godot C:/Godot/Godot_v4.7.2-stable_win64_console.exe
# 동일 계약을 실제 배포 EXE로 검사 (source checkout을 실행 프로젝트에 복사하지 않음)
python tools/modular_particles/run_cli_tests.py --godot C:/Godot/Godot_v4.7.2-stable_win64_console.exe --app C:/Tools/MaterialMaker/MaterialMaker.exe
```

Python은 개발 테스트에만 필요합니다. CLI 사용에는 필요하지 않습니다.
