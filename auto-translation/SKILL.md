---
name: auto-translation
description: Figma 화면의 한글 텍스트를 추출하고 도메인 용어집과 사용자 수정 기준으로 영문 번역을 검수한 뒤 Lokalise 키 생성과 Google Sheets 기록을 진행한다. Use when the user asks for "번역 자동화", "figma 번역", "$auto-translation", or Figma-to-Lokalise translation work.
---

# Auto Translation Skill

Figma → 번역 검수 → Lokalise 키 생성 플로우를 자동화한다.

## 키 네이밍 컨벤션

- **필드명, 선택지 등 공통 용어**: `common_PascalCase`
  - 예: `common_VirtualAccount`, `common_ChannelName`
- **플레이스홀더**: `msgPlaceholder_DomainName`
  - 예: `msgPlaceholder_Channel`
- **에러 메시지**: `msgError_DomainName`
  - 예: `msgError_InvalidEmail`
- **툴팁**: `msgTooltip_DomainName`
  - 예: `msgTooltip_VirtualAccount`
- **기타 안내 문구**: `msgType_DomainName`

컨벤션 규칙: camelCase_PascalCase

## 실행 흐름

이 스킬이 트리거되면 아래 순서로 실행한다.

### 0단계: 스킵 목록 + 단어장 + 환경 변수 확인

스킬 디렉토리의 `skip-list.json`을 로드한다. 이 파일에 있는 텍스트는 검수 없이 자동 스킵된다.

**도메인 단어장 로드:**
스킬 디렉토리의 `domain-glossary.md`를 참조해 번역 제안 시 우선 적용한다. Lokalise 용어집보다 높은 우선순위를 가진다.

**사용자 수정 기준 로드:**
스킬 디렉토리의 `user-corrections.md`를 함께 로드한다. `domain-glossary.md`와 충돌 시 이 파일이 우선한다.

단어장에 있는 용어가 텍스트에 포함되면 번역 제안 시 자동 반영하고, 검수 화면에 표시한다:
```
단어장 매칭: 송금 → Pay-out ✓
사용자 수정: 수취인 → Receiver ✓
```

스킵 시 항목별로 이번만 스킵할지, 영구 스킵 목록에 추가할지 즉시 선택한다 (세션 종료 시 일괄 처리 방식 대신). 자세한 인터랙션은 5단계 참조.

### 0-1단계: 환경 변수 확인

아래 환경 변수가 설정되어 있는지 확인한다.

```
FIGMA_TOKEN          - Figma Personal Access Token
LOKALISE_TOKEN       - Lokalise API Token
LOKALISE_PROJECT_ID  - Lokalise 프로젝트 ID
GOOGLE_SHEETS_WEBHOOK - Google Apps Script Web App URL (시트 기록용)
```

인증 정보는 아래 순서로 확인한다.

1. 프로젝트 루트의 `./.codex/lokalise.json`
2. `~/.codex/secrets/lokalise.json`
3. 현재 shell 환경 변수
4. 마이그레이션 fallback: `~/.claude/settings.json`

프로젝트 로컬 파일이 있으면 그 파일을 우선 사용한다. 토큰 값은 출력하거나 repo 파일에 저장하지 않는다.

secret 파일 예시:
```json
{
  "FIGMA_TOKEN": "...",
  "LOKALISE_TOKEN": "...",
  "LOKALISE_PROJECT_ID": "...",
  "GOOGLE_SHEETS_WEBHOOK": "..."
}
```

프로젝트 로컬 파일은 별도 보관용이며, 이 저장소 안에 두되 커밋하지 않는다.

모든 경로에서 누락된 필수 값이 있으면 즉시 중단하고 설정 방법을 안내한다:
```
export FIGMA_TOKEN=your_token
export LOKALISE_TOKEN=your_token
export LOKALISE_PROJECT_ID=your_project_id
```

### 1단계: 입력 받기

사용자에게 Figma URL을 요청한다. **여러 개를 한 번에 받을 수 있다.**

```
Figma URL을 입력해주세요. 여러 개면 줄바꿈으로 구분해서 주세요.
```

URL이 여러 개면 순서대로 처리하고, 시트 기록은 마지막에 일괄 처리한다.
각 URL에서 file_key와 node-id를 추출한다:
- `figma.com/design/:fileKey/...?node-id=:nodeId` 형식
- node-id의 `-`는 `:`로 변환

### 2단계: Figma 텍스트 추출

Figma URL에 `node-id`가 있으면 해당 노드만 Figma API로 가져온다. `node-id`가 없으면 사용자에게 프레임/레이어 이름을 요청한 뒤 파일 전체 구조에서 해당 노드를 찾는다.

- `node-id`가 있는 경우: `FIGMA_API_URL="https://api.figma.com/v1/files/{file_key}/nodes?ids={node_id}"`
- `node-id`가 없는 경우: `FIGMA_API_URL="https://api.figma.com/v1/files/{file_key}"`, `frame_name`은 사용자 입력값

```bash
curl -H "X-Figma-Token: $FIGMA_TOKEN" \
  "$FIGMA_API_URL" \
  | python3 -c "
import json, sys

data = json.load(sys.stdin)

def first_document_node(payload):
    nodes = payload.get('nodes') or {}
    for item in nodes.values():
        doc = item.get('document')
        if doc:
            return doc
    return payload.get('document')

def find_frame(node, name):
    if not node:
        return None
    if node.get('name', '').lower() == name.lower():
        return node
    for child in node.get('children', []):
        result = find_frame(child, name)
        if result:
            return result
    return None

def extract_texts(node, results=None):
    if results is None:
        results = []
    if node.get('type') == 'TEXT':
        text = node.get('characters', '').strip()
        if text:
            results.append({
                'id': node.get('id'),
                'name': node.get('name'),
                'text': text
            })
    for child in node.get('children', []):
        extract_texts(child, results)
    return results

root = first_document_node(data)
frame_name = '{frame_name}'
target = root if not frame_name else find_frame(root, frame_name)

if not target:
    print(json.dumps({'error': 'Frame not found'}))
else:
    texts = extract_texts(target)
    print(json.dumps(texts, ensure_ascii=False))
"
```

추출 결과를 파싱해 텍스트 목록을 만든다. 중복 텍스트는 제거한다.
`node-id` 없이 프레임을 찾지 못하면 사용자에게 정확한 이름을 다시 요청한다.

### 3단계: Lokalise 데이터 로드 (용어집 + 기존 키)

용어집과 기존 키를 동시에 로드해 번역 제안과 중복 감지에 활용한다.

#### 3-1. 기존 키 인덱스 구축

Lokalise list API는 한 페이지에 최대 500개만 반환한다. `x-pagination-page-count` 응답 헤더를 확인해 모든 페이지를 읽는다. 한 페이지만 읽으면 기존 키 중복 감지가 누락될 수 있다.

```bash
python3 -c "
import json, os, urllib.parse, urllib.request

token = os.environ['LOKALISE_TOKEN']
project_id = os.environ['LOKALISE_PROJECT_ID']

def fetch_page(page):
    query = urllib.parse.urlencode({
        'limit': 500,
        'page': page,
        'include_translations': 1,
    })
    url = f'https://api.lokalise.com/api2/projects/{project_id}/keys?{query}'
    req = urllib.request.Request(url, headers={'x-api-token': token})
    with urllib.request.urlopen(req) as res:
        return json.load(res), int(res.headers.get('x-pagination-page-count', '1'))

keys = []
page = 1
while True:
    data, page_count = fetch_page(page)
    keys.extend(data.get('keys', []))
    if page >= page_count:
        break
    page += 1

# 한글 번역 → {key_name, en_translation} 인덱스
ko_to_existing = {}
for k in keys:
    ko = next((t['translation'] for t in k.get('translations', []) if t['language_iso'] == 'ko'), '')
    en = next((t['translation'] for t in k.get('translations', []) if t['language_iso'] == 'en'), '')
    if ko:
        ko_to_existing[ko.strip()] = {
            'key': k['key_name']['web'],
            'en': en
        }

print(json.dumps(ko_to_existing, ensure_ascii=False))
"
```

#### 3-2. 용어집 인덱스 구축

용어집은 두 방향이 혼재한다:
- **기존 용어**: `term = 영문`, `description = 한글` (예: `Account Name → 가상계좌명`)
- **신규 용어**: `term = 한글`, `description = 영문` (예: `송금 → Pay-out`)

양방향을 `한글 → 영문` 방향으로 통일해서 인덱싱한다.

```bash
python3 -c "
import json, os, unicodedata, urllib.parse, urllib.request

token = os.environ['LOKALISE_TOKEN']
project_id = os.environ['LOKALISE_PROJECT_ID']

def fetch_page(page):
    query = urllib.parse.urlencode({'limit': 500, 'page': page})
    url = f'https://api.lokalise.com/api2/projects/{project_id}/glossary-terms?{query}'
    req = urllib.request.Request(url, headers={'x-api-token': token})
    with urllib.request.urlopen(req) as res:
        return json.load(res), int(res.headers.get('x-pagination-page-count', '1'))

terms = []
page = 1
while True:
    data, page_count = fetch_page(page)
    terms.extend(data.get('data', data.get('glossary_terms', [])))
    if page >= page_count:
        break
    page += 1

def is_korean(text):
    return any('HANGUL' in unicodedata.name(c, '') for c in text if c.strip())

ko_to_en = {}
for t in terms:
    term = t.get('term', '').strip()
    desc = t.get('description', '').strip()
    if not term or not desc:
        continue
    if is_korean(term):
        # term이 한글 → description이 영문
        ko_to_en[term] = desc
    else:
        # term이 영문 → description이 한글
        ko_to_en[desc] = term

print(json.dumps(ko_to_en, ensure_ascii=False))
"
```

### 4단계: 번역 제안 생성

추출된 텍스트 목록, 용어집, 기존 키를 바탕으로 번역 제안을 생성한다.

각 텍스트에 대해:
1. **기존 키 매칭**: 한글 번역이 정확히 일치하는 기존 키가 있으면 재사용 후보로 표시
2. **유사 키 매칭**: 정확 일치가 없어도, 한글 텍스트의 핵심 단어가 포함된 기존 키를 검색해 후보로 제공 (예: "서비스 시작일자" → "서비스 시작일" 매칭)
3. **용어집 매칭**: 텍스트에 용어집 단어가 포함되어 있으면 해당 번역을 우선 적용
4. **텍스트 유형 판별**: 문맥을 보고 common / msgPlaceholder / msgError / msgTooltip 등 구분
5. **키 이름 제안**: 컨벤션에 맞는 Lokalise 키 이름 생성
6. **영문 번역 제안**: 자연스럽고 일관된 영문 번역 생성
7. **신규 키 원칙**: 기존 키가 없으면 `skip`이 아니라 새 키 제안을 기본값으로 둔다. `skip`은 skip-list에 명시된 값, 숫자/코드/패턴 문자열, 또는 사용자가 직접 스킵을 요청한 경우에만 사용한다.

### 5단계: 검수 루프 (항목별 인터랙션)

검수는 먼저 `기존 키 후보` 표를 보여주고, 다음으로 `스킵 후보`, 마지막으로 `신규 키 후보` 표를 따로 보여준다. 사용자는 번호를 지정해 `번역 수정`, `키 수정`, `스킵`, `승인`을 요청할 수 있다.

표는 마크다운 표보다 스크린샷처럼 정렬된 고정폭 텍스트 표를 우선 사용한다. 전체 표를 fenced code block 안에 넣고, 공백 패딩으로 열을 맞춘다. `키 제안` 열은 가능한 한 말줄임 없이 보여준다.

권장 열:
- `번호` 3칸
- `국문` 20칸
- `영문 번역 제안` 24칸
- `키 제안` 48칸
- `상태` 10칸
- 필요 시 `판단 근거` 16칸

첫 번째 표는 `기존 키 후보`만 포함한다.
두 번째 표는 `스킵 후보`만 포함한다.
세 번째 표는 `신규 키 후보`만 포함한다.
두 표 모두 아래처럼 간결하게 유지한다:

예시:

기존 키:

```text
No  국문                 영문 번역 제안              키 제안                                           상태
01  서비스 시작일자      Service Start Date         common_ServiceStartDate                           기존 키 후보
02  조회                 Search                     common_SearchList                                 기존 키 후보
```

기존 키 후보의 `키 제안`은 반드시 Lokalise에 실제로 존재하는 키 이름이어야 한다. 유사 의미를 추론해 새 이름을 적지 않는다.

스킵:

```text
No  국문                 영문 번역 제안              키 제안                                           상태
11  플홀                 -                          skip                                              스킵 후보
12  YYYY.MM.DD - ...     -                          skip                                              스킵 후보
```

신규 키:

```text
No  국문                 영문 번역 제안              키 제안                                           상태
21  케이뱅크             K Bank                     common_KBank                                      신규 키 후보
22  월렛거래번호         Wallet Transaction Number  common_WalletTransactionNumber                    신규 키 후보
```

표를 보여준 뒤, 사용자가 지정한 번호만 순서대로 세부 검수한다. 번호가 없으면 세부 검수로 진행하지 않는다.
신규 후보는 항상 키 제안을 함께 보여준다. 키 제안은 기존 키 재사용이 아니라면 새 이름이어야 한다.

**기존 키가 없는 경우 (신규):**
```
─────────────────────────────────────────────
[3/12] 검수 중  🆕 신규
─────────────────────────────────────────────
원문 (KO): 가상계좌 번호를 입력해주세요
번역 제안: Please enter the virtual account number
키 제안:   msgPlaceholder_VirtualAccountNumber
용어집 매칭: 가상계좌 → Virtual Accounts ✓

[a] 승인  [e] 번역 수정  [k] 키 수정  [s] 스킵  [?] 유사 키 검색  [q] 종료
```

**`[?]` 유사 키 검색 선택 시:**

원문의 핵심 단어를 추출해 기존 Lokalise 키의 KO 번역과 부분 매칭해 후보를 보여준다.

```
🔍 유사 키 검색 결과: "가상계좌 번호를 입력해주세요"
──────────────────────────────────────────
1. common_VirtualAccountNumber
   KO: 가상계좌 번호
   EN: Virtual Account Number
2. msgPlaceholder_VirtualAccountName
   KO: 가상계좌명을 입력해주세요
   EN: Please enter your virtual account name.
──────────────────────────────────────────
[1/2] 번호로 재사용  [n] 신규 키 유지  [s] 스킵
```

- 번호 선택 시: 해당 기존 키 재사용 처리
- `n`: 원래 신규 키 제안으로 돌아가 승인/수정 계속
- `s`: 스킵 처리 (skip-list 추가 여부 물어봄)

**기존 키가 있는 경우 (중복 감지):**
```
─────────────────────────────────────────────
[4/12] 검수 중  ⚠️ 기존 키 발견
─────────────────────────────────────────────
원문 (KO): 취소
기존 키:   common_Cancel
기존 번역: Cancel

[r] 기존 키 재사용  [n] 새 키로 생성  [s] 스킵  [q] 종료
```

- **a / r (승인/재사용)**: 승인 또는 기존 키 재사용 (Lokalise 등록 없이 참조만)
- **e (번역 수정)**: 번역문 직접 입력. 입력 후 수정된 번역을 기반으로 키 이름을 **자동으로 새로 제안**한다. 사용자는 제안된 키를 승인하거나 직접 수정할 수 있다.
  ```
  현재 번역: MID Review Status
  새 번역 입력: > MID Screening Status

  번역 수정됨: MID Screening Status
  키 자동 제안: common_MIDScreeningStatus
  이 키로 승인하시겠습니까? [y] 승인  [n] 직접 입력
  >
  ```
- **k (키 수정)**: 키 이름 직접 입력 (번역 수정 없이 키만 변경할 때)
- **n (새 키 생성)**: 기존 키 무시하고 새로 생성
- **s (스킵)**: 이 항목을 건너뜀. 스킵 즉시 아래와 같이 추가 선택을 받는다:
  ```
  ⏭ 스킵
  이 항목을 영구 스킵 목록에도 추가할까요?
  [y] 영구 추가  [n] 이번만 스킵
  ```
  - `y` 선택 시: `skip-list.json`의 `exact` 배열에 즉시 추가
  - `n` 선택 시: 이번 세션만 스킵 (파일 변경 없음)
- **q (종료)**: 지금까지 승인된 것만 처리하고 종료

검수가 완료되면 승인 목록을 한번에 보여주고 최종 확인을 받는다.

### 6단계: Lokalise 키 생성

승인된 항목들을 Lokalise API로 일괄 등록한다.

```bash
# 키 생성 payload 구성
python3 -c "
import json

approved = {approved_items}

keys = []
for item in approved:
    keys.append({
        'key_name': item['key'],
        'platforms': ['web', 'ios', 'android', 'other'],
        'translations': [
            {'language_iso': 'ko', 'translation': item['original']},
            {'language_iso': 'en', 'translation': item['translation']}
        ]
    })

print(json.dumps({'keys': keys}, ensure_ascii=False))
" | curl -s -X POST \
  -H "x-api-token: $LOKALISE_TOKEN" \
  -H "Content-Type: application/json" \
  -d @- \
  "https://api.lokalise.com/api2/projects/$LOKALISE_PROJECT_ID/keys"
```

이미 존재하는 키 이름이면 API가 에러를 반환한다. 에러 발생 시 사용자에게 알리고 키 이름 수정 여부를 묻는다.

### 7단계: 용어집 업데이트

번역 과정에서 새로 등장한 용어 (기존 용어집에 없는 단어)를 추출해 용어집에 추가한다.

새 용어 기준:
- 고유명사, 기능명, 도메인 특화 단어
- 앞으로도 일관되게 번역해야 할 단어

```bash
curl -s -X POST \
  -H "x-api-token: $LOKALISE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "terms": [
      {
        "term": "{korean_term}",
        "description": "{english_translation}",
        "translatable": true,
        "tags": ["auto-added"]
      }
    ]
  }' \
  "https://api.lokalise.com/api2/projects/$LOKALISE_PROJECT_ID/glossary-terms"
```

### 8단계: Google Sheets 기록

Lokalise 등록이 완료된 후, **신규 등록된 키만** Google Sheets에 기록한다.
`GOOGLE_SHEETS_WEBHOOK` 환경 변수가 없으면 이 단계는 건너뛴다.

기록 대상:
- **신규 (New)**: 이번 세션에서 Lokalise에 새로 등록된 키만 기록 (재사용 키는 기록하지 않음)

```bash
python3 -c "
import json, subprocess, os

figma_url = '{figma_url}'
date = '{date}'  # YYYY-MM-DD
new_items = {new_items}    # [{key, ko, en}, ...]

rows = []
for item in new_items:
    rows.append([figma_url, date, 'New', item['key'], item['ko'], item['en']])

payload = json.dumps({'rows': rows}, ensure_ascii=False)
# Google Apps Script returns 302 → must POST first, then GET the redirect URL
r1 = subprocess.run(
    ['curl', '-s', '-D', '-', '--max-redirs', '0', '-X', 'POST',
     os.environ['GOOGLE_SHEETS_WEBHOOK'],
     '-H', 'Content-Type: application/json', '-d', payload],
    capture_output=True, text=True
)
location = next((l.split(':', 1)[1].strip() for l in r1.stdout.split('\n') if l.lower().startswith('location:')), None)
if location:
    r2 = subprocess.run(['curl', '-s', '-L', location], capture_output=True, text=True)
    print(r2.stdout)
else:
    print('webhook 오류: redirect URL 없음')
"
```

### 9단계: 완료 리포트

```
─────────────────────────────────────────────
✓ 완료
─────────────────────────────────────────────
총 추출: 12개
승인:    9개  → Lokalise 키 생성 완료
스킵:    2개
실패:    1개  (중복 키: msgPlaceholder_Channel)

용어집 추가: 2개
  - 가상계좌 → VirtualAccount
  - 채널 → Channel

📊 Google Sheets 기록 완료
  - 신규: 6개
─────────────────────────────────────────────
```

## 주의사항

- Figma 텍스트 중 숫자, 특수문자만 있는 경우 건너뜀
- 이미 영문인 텍스트는 번역 불필요로 표시하고 사용자가 선택
- Lokalise에 이미 존재하는 키는 덮어쓰지 않고 사용자에게 알림
- 용어집은 신중하게 추가: 사용자가 명시적으로 추가 의사를 밝힌 항목만 등록
