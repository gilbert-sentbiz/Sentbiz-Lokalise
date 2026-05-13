# Sentbiz-Lokalise

Sentbiz 번역 관련 Codex 스킬 모음입니다.

## 스킬 목록

| 스킬 | 설명 |
|------|------|
| [auto-translation](./auto-translation/) | Figma → 번역 검수 → Lokalise 자동 등록 |

## 스크립트

| 경로 | 설명 |
|------|------|
| [scripts/build_review_list.rb](./scripts/build_review_list.rb) | Figma/Lokalise를 조회해 전체 검수 리스트를 `output/`에 생성 |
| [scripts/apply_review.rb](./scripts/apply_review.rb) | 수정한 `review.json`을 읽어 최종 적용 결과를 `output/`에 생성 |

## 설치 방법

각 스킬 폴더의 README를 참고하세요.

## 검수 워크플로우

```bash
cd /Users/gilbert/Codex/Sentbiz-Lokalise
ruby scripts/build_review_list.rb --figma-url "https://www.figma.com/design/..."
```

생성된 `output/*-review.json`에서 각 항목의 `decision`, `en`, `key`, `note`를 수정한 뒤:

```bash
ruby scripts/apply_review.rb --review-json output/01-review.json
```

그러면 `output/*-applied.txt`, `output/*-applied.json`이 생성됩니다.
