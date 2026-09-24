# Modular VFX 편집 스킬 설치 (Codex / Pi)

스킬 이름은 **`godot-modular-vfx`**입니다. 다른 Godot 프로젝트에서 효과 원본 제작·모듈 편집·User 바인딩·GPU 컴파일·안전한 설치를 안내합니다.

## 준비

- 이 포크의 CLI 지원 포터블 Material Maker **폴더 전체**. `MaterialMaker.exe`, 예제와 모듈 sidecar를 함께 유지하세요.
- 게임 실행: Godot **4.7.2 stable / Forward+ / Vulkan**.
- CLI/스킬 실행: Windows PowerShell 5.1 또는 PowerShell 7. Python·개발 소스 checkout은 필요 없습니다.
- `npx` 설치 단계에만 Node.js/npm과 네트워크가 필요합니다. 이 명령은 앱·Godot·효과 애드온을 설치하지 않습니다.
- 효과 원본 `.mpfx`와 컴파일 리소스는 **v2만** 지원합니다. v1 자동 변환은 하지 않습니다.

## npx skills로 설치

설치할 **게임 프로젝트 루트**에서 실행하세요. 전역 설정을 변경하지 않는 프로젝트 범위가 기본입니다.

```powershell
node --version
npm --version
npx skills --help
npx skills add KudoLayton/material-maker --skill godot-modular-vfx --agent codex pi --copy
```

대화형 확인에서 프로젝트 범위와 설치 대상을 확인하세요. 위 명령은 Windows 링크 권한에 의존하지 않도록 `--copy`를 사용합니다. 기존 동명 스킬이 있다면 비교·백업 후 명시적으로 결정하고 무조건 덮어쓰지 마세요. `--global`과 `--all`은 필요하지 않습니다.

공식 CLI 기준 설치 위치:
- Codex: `.agents/skills/godot-modular-vfx/`
- Pi: `.pi/skills/godot-modular-vfx/`

확인:

```powershell
npx skills list --agent codex pi
$env:MM_VFX_APP = 'C:/Tools/MaterialMaker/MaterialMaker.exe'
& ./.agents/skills/godot-modular-vfx/scripts/Invoke-Vfx.ps1 -Command capabilities
```

`MM_VFX_APP`은 위 예시에서는 현재 PowerShell 세션에만 적용합니다. 같은 세션에서 에이전트를 실행하거나 요청에 앱 경로를 알려주세요. 임의로 시스템 전역 환경변수를 변경할 필요는 없습니다.

Codex를 새 세션으로 열어 `$godot-modular-vfx`를 호출합니다. Pi는 새 세션 또는 `/reload` 후 `/skill:godot-modular-vfx`를 사용합니다. 파일 설치와 에이전트 인식은 별개이므로 두 가지를 확인하세요.

## 요청 예시

> $godot-modular-vfx 이 프로젝트에 초당 60개 분수 효과를 만들어 주세요. User.Speed와 User.Tint를 게임 코드에서 조절하고 싶습니다. 앱은 C:/Tools/MaterialMaker/MaterialMaker.exe 입니다.

스킬은 원본을 편집한 후 별도 staging으로 내보내고 게임 설치 변경사항을 dry-run으로 보여줍니다. 실제 게임에는 `effects/modular_particles/<id>/particles.tscn`을 배치합니다. 공유 애드온 충돌이 있으면 자동 교체하지 않습니다.

## 오프라인 / 포터블 스킬

포터블 앱의 `skills/godot-modular-vfx/`가 동일한 스킬 원본입니다. `npx skills add <로컬 skills 폴더> --skill godot-modular-vfx --agent codex pi` 또는 검토 후 에이전트별 프로젝트 스킬 폴더로 복사할 수 있습니다. 이 방식은 원격 설치 검증을 대신하지 않습니다.

포터블 앱에 동봉된 helper는 그 앱을 상대 경로로 찾습니다. `npx`로 복사한 스킬에는 앱이 없으므로 `MM_VFX_APP` 또는 명시적 `-App`이 필요합니다. 원본 편집·호출 결과·충돌 복구 상세는 스킬의 `references/`와 [MODULAR_VFX_CLI.md](MODULAR_VFX_CLI.md)를 참고하세요.

## 실제 설치 검증

`skills 1.7.0`, Node.js `v26.7.0`, npm `12.0.2`에서 아래 명령으로 **격리 프로젝트에만** 원격 설치했습니다. 이 자동 검증의 `--yes`는 기존 동명 스킬이 없는 새 프로젝트에서 사용했습니다.

```powershell
npx --yes skills@1.7.0 add KudoLayton/material-maker --skill godot-modular-vfx --agent codex pi --copy --yes --json
npx --yes skills@1.7.0 list --agent codex pi --json
```

Codex `0.155.1`의 실제 skills/list와 Pi `0.87.1`의 실제 RPC get_commands에서 설치된 스킬의 발견·메타데이터 파싱을 확인했습니다. 사용자 전역 스킬/에이전트 설정은 변경하지 않았습니다. LLM 자율 제작 평가는 별개로 미실행입니다.

설치된 스킬 helper로 효과 두 개를 제작·설치한 독립 게임이 Godot 편집기와 Windows Release에서 각각 **31개 GPU 검사**를 통과했습니다. Windows Git의 CRLF 변환은 LF 정규화로 비교했으며, 두 에이전트 설치본은 byte 단위로 동일합니다.

검증 기록과 테스트 산출물 위치는 [VALIDATION.md](test/modular_particles/VALIDATION.md)에 기록합니다. 네트워크·지원 에이전트·CLI 버전이 다르면 `--help`로 확인하고 미검증 결과를 성공으로 간주하지 마세요.
