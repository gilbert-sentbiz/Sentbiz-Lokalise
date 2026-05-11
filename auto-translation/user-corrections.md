# 사용자 번역 수정 기준

번역 작업 중 사용자가 직접 지정한 번역 규칙.
`domain-glossary.md`와 동일하게 적용하되, 충돌 시 이 파일이 우선한다.

## 용어 수정 기준 (KO → EN)

| 한글 | 영문 | 주의사항 |
|------|------|----------|
| 사용자 | Member | User 아님. UI 맥락에서 항상 Member 사용 |
| 정률수수료 | Rate Fee | Percentage Fee 아님 |
| 정율 | Rate | Percentage-based 아님. 단독 사용 시 Rate |
| 정률 | Rate | 단독 사용 시 Rate. 조합어(정률수수료)는 Rate Fee |
| 정률/건당 | Rate/Per Transaction | |
| 수취인 | Receiver | Recipient 아님 |
| 환전 | Conversion | Exchange 아님. 단, 환전수수료가 전환 수수료(common_ConversionFee)와 충돌 시 제품 국문 수정으로 해결 |
| 다건 | Bulk | Multiple 아님 |

## 적용 이력

| 날짜 | 수정 내용 |
|------|-----------|
| 2026-05-07 | 사용자→Member, 정률수수료→Rate Fee, 정율→Rate, 수취인→Receiver, 환전→Conversion, 다건→Bulk |
