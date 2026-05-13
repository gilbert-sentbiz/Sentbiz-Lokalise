# Auto Translation Skill

Figma 화면의 한글 텍스트를 추출해 영문 번역 후 Lokalise에 자동 등록하는 Codex 스킬입니다.

## 플로우

1. Figma URL 입력
2. 텍스트 노드 전체 추출
3. 용어집 기반 번역 제안 생성
4. 터미널에서 항목별 검수 (승인 / 수정 / 스킵)
5. 승인 항목 → Lokalise 키 자동 생성 + 번역 등록
6. 신규 용어 → Lokalise 용어집 자동 반영

## 설치

### 1. 파일 복사

```bash
mkdir -p ~/.codex/skills
cp -R auto-translation ~/.codex/skills/
```

### 2. 환경 변수 설정

```bash
export FIGMA_TOKEN=your_figma_personal_access_token
export LOKALISE_TOKEN=your_lokalise_api_token
export LOKALISE_PROJECT_ID=your_lokalise_project_id
```

- **FIGMA_TOKEN**: [Figma 계정 설정](https://www.figma.com/settings) → Personal access tokens에서 발급
- **LOKALISE_TOKEN**: Lokalise → Account Settings → API tokens에서 발급
- **LOKALISE_PROJECT_ID**: Lokalise 프로젝트 Settings → General에서 확인

권장 저장 위치는 `~/.codex/secrets/lokalise.json`입니다.

```json
{
  "FIGMA_TOKEN": "...",
  "LOKALISE_TOKEN": "...",
  "LOKALISE_PROJECT_ID": "...",
  "GOOGLE_SHEETS_WEBHOOK": "..."
}
```

Codex 실행 환경에 위 변수가 없더라도 스킬은 `~/.codex/secrets/lokalise.json`을 먼저 참고합니다. 이 파일이 없을 때만 마이그레이션 fallback으로 `~/.claude/settings.json`을 확인합니다. 토큰 값은 저장소에 커밋하지 않습니다.

### 3. 실행

Codex에서 아래 중 하나로 트리거:

```
$auto-translation
번역 자동화
figma 번역
```

## 포함 파일

| 파일 | 설명 |
|------|------|
| `SKILL.md` | 스킬 본체 |
| `domain-glossary.md` | 도메인 단어장 (번역 우선 적용) |
| `skip-list.json` | 자동 스킵 목록 (숫자, 패턴 등) |

## 주의사항

- `session-state.json`은 실행 시 자동 생성되는 파일로 git에 포함하지 않습니다
- Lokalise 키는 덮어쓰지 않으며, 중복 시 사용자에게 알림
- 용어집 추가는 사용자가 명시적으로 승인한 항목만 등록
