# SentBiz 도메인 단어장

번역 제안 시 아래 매핑을 우선 적용한다.
키 이름은 이 번역을 기반으로 네이밍 규칙(camelCase_PascalCase)에 맞게 별도 생성한다.

## 핵심 도메인 용어 (KO → EN)

| 한글 | 영문 | 주의사항 |
|------|------|----------|
| 송금 | Pay-out | payout / Transfer 아님. 단, 조합어(송금 신청일)는 문맥에 따라 판단 |
| 이관 | Conversion | convert 아님 |
| 이관하기 | Convert | 동사형은 Convert |
| 거래 | Transaction | |
| 가상계좌 | Virtual Account | |
| 발급 | Issuance | issue 아님 |
| 고객사 | Client | customer / company 아님 |
| 상점 | Merchant | store 아님 |
| 모계좌 | Parent Account | |
| 원천사 | Source | |
| 채널 | Channel | |
| MID | MID | 그대로 사용 |

## 상태 용어 (KO → EN)

| 한글 | 영문 | 주의사항 |
|------|------|----------|
| 정상 | Active | Normal 아님 |
| 대기 | Pending | Waiting 아님 |
| 정지 | Suspended | |
| 해지 | Terminated | |
| 심사중 | Under Screening | |
| 심사완료 | Screening Complete | |
| 심사대기 | Screening Pending | |
| 조건부 승인 | Conditional Approval | |
| 비활성 | Inactive | |
| 인증형 | Authenticated | |
| 비인증형 | Non-authenticated | |
| 고정형 | Static | |
| 일회성 | Dynamic | |
| 요청형 | On Request | |
| 정지/휴업 | Suspended/Closed | |

## 사업자 용어 (KO → EN)

| 한글 | 영문 | 주의사항 |
|------|------|----------|
| 사업자번호 | Business Registration Number | |
| 사업자구분 | Business Type | |
| 개인사업자 | Sole Proprietor | Individual Business 아님 |
| 법인사업자 | Corporate | Corporation 아님 |
| PG용역위탁 | PG Service Delegation | |

## 주의사항

- `확인` 버튼 → **Confirm** (Lokalise 용어집에 "Validation"으로 잘못 등록됨, 무시)
- `송금`이 단독으로 쓰일 때 → **Pay-out**
- `송금`이 조합어로 쓰일 때 → 문맥 판단 필요 (예: 송금 신청일 → Pay-out Request Date)
