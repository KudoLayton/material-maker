# Modular VFX 편집 스킬 설치 (Codex / Pi)

스킬 이름은 **`godot-modular-vfx`**입니다. 다른 Godot 프로젝트에서 효과 원본 제작·모듈 편집·User 바인딩·2D/3D GPU 컴파일·안전한 설치를 안내합니다. `MMGPUParticles2D`와 `MMGPUParticles3D`가 같은 v3 시뮬레이션을 사용합니다.

## 준비

- 이 포크의 CLI 지원 포터블 Material Maker **폴더 전체**. `MaterialMaker.exe`, 예제와 모듈 sidecar를 함께 유지하세요.
- 게임 실행: Godot **4.7.2 stable / Forward+ / Vulkan·D3D12 (Windows x64)**. [양쪽 백엔드 지원·검증](RENDERING_BACKENDS.md).
- Export helper의 기본값은 Vulkan입니다. D3D12 컴파일은 `-RenderingDriver d3d12`를 사용하며 실제 backend가 다르면 성공으로 처리하지 않습니다.
- CLI/스킬 실행: Windows PowerShell 5.1 또는 PowerShell 7. Python·개발 소스 checkout은 필요 없습니다.
- `npx` 설치 단계에만 Node.js/npm과 네트워크가 필요합니다. 이 명령은 앱·Godot·효과 애드온을 설치하지 않습니다.
- 효과 원본 `.mpfx`는 **v2**, 신규 컴파일 리소스는 **v3**입니다. CLI 계약과 모듈·export manifest 형식은 각각 v1입니다. 원본의 version을 3으로 바꾸지 마세요.
- 새 애드온은 기존 v2 컴파일 리소스를 **3D에서만** 계속 실행합니다. 2D에는 원본 재내보내기가 필요하고, 이전 애드온은 v3를 거부합니다. 애드온 충돌을 강제 덮어쓰기로 해결하지 않습니다.
- 2D도 Forward+가 필요하며 위치·속도·중력/User vec3는 Vector3를 유지합니다. Material Maker의 편집 미리보기는 3D입니다. [2D 좌표·외형·제약](VFX_2D_EXPORT.md).

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

2D 요청 예시:

> $godot-modular-vfx 같은 .mpfx를 2D 불꽃으로 내보내 주세요. 100 pixels/unit, Y 반전, Alpha 합성으로 하고 C:/Art/fire.png를 사용하세요. User.Gravity는 Vector3로 게임 코드에서 제어하겠습니다.

스킬 helper의 출력 기본값은 3D이며 2D는 아래처럼 지정합니다. 부모 폴더와 입력 파일은 먼저 준비하세요.

```powershell
& ./.agents/skills/godot-modular-vfx/scripts/Invoke-Vfx.ps1 -Command export -InputFile C:/Work/fire.mpfx -Output C:/Work/staging-fire2d -EffectId fire2d -RenderTarget 2d -PixelsPerUnit 100 -FlipY true -BlendMode alpha -Sprite C:/Art/fire.png
```

`-Sprite`는 생략 가능하며 PNG는 `sprite.res`로 내장됩니다. `-FlipY`는 문자열 `true`/`false`입니다. 2D 전용 옵션은 `-RenderTarget 2d` 없이 사용할 수 없습니다. 2D/3D 출력은 서로 다른 staging 폴더를 사용하세요.

스킬은 원본을 편집한 후 별도 staging으로 내보내고 게임 설치 변경사항을 dry-run으로 보여줍니다. 실제 게임에는 `effects/modular_particles/<id>/particles.tscn`을 해당 2D/3D 씬에 배치합니다. 공유 애드온 충돌이 있으면 자동 교체하지 않습니다.

## 오프라인 / 포터블 스킬

포터블 앱의 `skills/godot-modular-vfx/`에는 빌드 시점의 스킬이 동봉됩니다. 이 저장소의 원본 스킬을 수정해도 기존 포터블/다른 프로젝트의 설치본은 자동 갱신되지 않습니다. `npx skills add <로컬 skills 폴더> --skill godot-modular-vfx --agent codex pi` 또는 검토 후 에이전트별 프로젝트 스킬 폴더로 복사할 수 있습니다. 이 방식은 원격 설치 검증을 대신하지 않습니다.

포터블 앱에 동봉된 helper는 그 앱을 상대 경로로 찾습니다. `npx`로 복사한 스킬에는 앱이 없으므로 `MM_VFX_APP` 또는 명시적 `-App`이 필요합니다. 원본 편집·호출 결과·충돌 복구 상세는 스킬의 `references/`와 [MODULAR_VFX_CLI.md](MODULAR_VFX_CLI.md)를 참고하세요.

## 기존 배포의 실제 설치 검증

아래는 기존 배포의 원격 설치·에이전트 발견 검증 이력입니다. 현재 원본 스킬의 2D·v3 보완 및 helper 회귀 결과는 [검증 기록](test/modular_particles/VALIDATION.md)을 참고하세요. 원본 갱신만으로 원격 설치나 기존 포터블 스킬이 갱신되지는 않습니다.

`skills 1.7.0`, Node.js `v26.7.0`, npm `12.0.2`에서 아래 명령으로 **격리 프로젝트에만** 원격 설치했습니다. 이 자동 검증의 `--yes`는 기존 동명 스킬이 없는 새 프로젝트에서 사용했습니다.

```powershell
npx --yes skills@1.7.0 add KudoLayton/material-maker --skill godot-modular-vfx --agent codex pi --copy --yes --json
npx --yes skills@1.7.0 list --agent codex pi --json
```

Codex `0.155.1`의 실제 skills/list와 Pi `0.87.1`의 실제 RPC get_commands에서 설치된 스킬의 발견·메타데이터 파싱을 확인했습니다. 사용자 전역 스킬/에이전트 설정은 변경하지 않았습니다. LLM 자율 제작 평가는 별개로 미실행입니다.

설치된 스킬 helper로 효과 두 개를 제작·설치한 독립 게임이 Godot 편집기와 Windows Release에서 각각 **31개 GPU 검사**를 통과했습니다. Windows Git의 CRLF 변환은 LF 정규화로 비교했으며, 두 에이전트 설치본은 byte 단위로 동일합니다.

검증 기록과 테스트 산출물 위치는 [VALIDATION.md](test/modular_particles/VALIDATION.md)에 기록합니다. 네트워크·지원 에이전트·CLI 버전이 다르면 `--help`로 확인하고 미검증 결과를 성공으로 간주하지 마세요.
