# Frontend Handoff Guide

> BlockBlock Summer 2026 Web3 Challenge Dashboard
> 담당: 승준
> 현재 상태: **Sui Testnet 읽기 전용 대시보드 구현 + 5초 Polling 완료**

이 문서는 현재까지 구현된 프론트엔드 구조와 실행 방법을 정리한 인수인계 문서입니다.

새로 프로젝트를 생성하는 방법은 [`QUICKSTART.md`](./QUICKSTART.md)를 참고하고,
**이미 구현된 현재 프론트엔드를 실행하거나 이어서 작업하려면 이 문서를 보면 됩니다.**

---

## 1. 현재 구현 상태

현재 프론트엔드는 다음 기능까지 구현되어 있습니다.

* Vite + React + TypeScript 프로젝트 구성
* `@mysten/sui` 설치
* Sui Testnet 연결
* `SuiGrpcClient` 기반 Challenge 상태 조회
* Challenge 기본 정보 표시

  * status
  * current day / total days
  * vault
* 참가자 목록 조회 및 렌더링

  * address
  * stake
  * failed day
  * refund rate
  * refund principal
  * claimable
  * participant status
* 시간가중 환급 커브 계산
* 5초마다 온체인 상태 자동 갱신(Polling)

현재 프론트엔드는 **읽기 전용 Dashboard**입니다.

다음 기능은 의도적으로 구현하지 않습니다.

* Wallet Connect
* 지갑 서명
* Challenge 생성
* Challenge 참여
* Oracle 결과 제출
* Claim transaction
* 로그인
* Backend API

온체인 쓰기 작업은 `scripts/`의 CLI 스크립트에서 수행합니다.

---

## 2. 로컬에서 실행하는 방법

Repository 최신 상태를 받습니다.

```bash
git switch main
git pull origin main
```

프론트엔드 폴더로 이동합니다.

```bash
cd frontend
```

Dependency를 설치합니다.

```bash
npm install
```

개발 서버를 실행합니다.

```bash
npm run dev
```

정상적으로 실행되면 다음과 비슷하게 출력됩니다.

```text
VITE ready

Local: http://localhost:5173/
```

브라우저에서 아래 주소로 접속합니다.

```text
http://localhost:5173
```

> 현재 프로젝트는 이미 Vite 초기화가 완료되어 있으므로
> **`npm create vite`를 다시 실행할 필요가 없습니다.**

---

## 3. 현재 주요 파일 구조

```text
frontend/
├── src/
│   ├── App.tsx
│   ├── config.ts
│   ├── curve.ts
│   ├── read_state.ts
│   ├── main.tsx
│   └── ...
│
├── package.json
├── package-lock.json
├── vite.config.ts
├── QUICKSTART.md
└── FRONTEND_GUIDE.md
```

각 파일의 역할은 다음과 같습니다.

### `src/App.tsx`

현재 Dashboard의 메인 화면입니다.

역할:

* Challenge 상태 조회
* React state 관리
* 5초 Polling
* Challenge 정보 출력
* Participant table 출력
* Refund 정보 출력

---

### `src/config.ts`

Sui Network 및 Object ID를 관리합니다.

예시:

```ts
export const NETWORK = 'testnet' as const;

export const GRPC_URL =
  'https://fullnode.testnet.sui.io:443';

export const PACKAGE_ID =
  '...';

export const CHALLENGE_ID =
  '...';

export const POLL_INTERVAL = 5000;
```

### 중요

Package ID / Challenge ID 등의 **정본(Source of Truth)은**

```text
docs/DEPLOYMENT.md
```

입니다.

재배포로 ID가 변경되면 `docs/DEPLOYMENT.md`를 먼저 확인한 뒤
`src/config.ts`를 갱신해야 합니다.

ID를 `App.tsx` 등에 직접 하드코딩하지 마세요.

---

### `src/read_state.ts`

Sui 온체인 상태 조회를 담당합니다.

원본:

```text
scripts/read_state.ts
```

프론트에서는 해당 파일을 복사해서 사용하고 있습니다.

주요 기능:

```ts
createSuiClient()
readState()
mistToSui()
shortAddress()
```

그리고 다음 타입을 제공합니다.

```ts
ChallengeSnapshot
ChallengeState
ParticipantState
```

현재 구조는 대략 다음과 같습니다.

```text
Sui Testnet
      ↓
SuiGrpcClient
      ↓
readState()
      ↓
ChallengeSnapshot
      ↓
React App
```

---

## 4. Sui 조회 시 반드시 지켜야 하는 사항

### 4-1. `SuiClient`를 사용하지 않는다

JSON-RPC 방식은 사용하지 않습니다.

```ts
// 사용하지 않음
SuiClient
```

대신:

```ts
SuiGrpcClient
```

를 사용합니다.

---

### 4-2. `client.core.getObject()`를 사용하지 않는다

다음 코드는 사용하지 마세요.

```ts
client.core.getObject(...)
```

BCS 데이터가 잘못 파싱되어 **에러 없이 잘못된 값이 나올 수 있습니다.**

Object를 직접 조회해야 한다면:

```ts
client.ledgerService.getObject({
  objectId,
  readMask: {
    paths: ['object_id', 'object_type', 'json'],
  },
});
```

방식을 사용해야 합니다.

하지만 해당 처리는 이미 `read_state.ts`에 구현되어 있으므로
가능하면 직접 다시 작성하지 말고 `readState()`를 사용하세요.

---

### 4-3. gRPC 생성자 옵션은 `baseUrl`

`SuiGrpcClient`를 직접 만들 경우:

```ts
new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',
});
```

처럼 `baseUrl`을 사용해야 합니다.

현재는 `createSuiClient()` wrapper가 이를 처리합니다.

---

## 5. `read_state.ts` 관련 주의사항

원본은:

```text
scripts/read_state.ts
```

입니다.

현재 프론트에는:

```text
frontend/src/read_state.ts
```

로 복사된 상태입니다.

`scripts/read_state.ts`에는 CLI 전용 코드가 포함되어 있기 때문에
브라우저에서 그대로 사용할 수 없습니다.

프론트 버전에서는 다음 배너 아래의 CLI 전용 부분을 제거한 상태입니다.

```ts
// ▼▼▼ 여기부터 파일 끝까지는 CLI 전용이다 ▼▼▼
```

CLI 부분에는 `process`, `dotenv` 등 Node.js 전용 코드가 포함되어 있습니다.

따라서 원본 `scripts/read_state.ts`가 변경되어 다시 복사해야 할 경우:

```bash
cp ../scripts/read_state.ts src/read_state.ts
```

이후 **CLI 전용 부분을 다시 제거해야 합니다.**

---

## 6. Participant 데이터

현재 참가자별로 다음 정보를 사용합니다.

```ts
address
stake
startDay
failedDay
claimable
```

`failedDay`의 의미:

```text
0 = 아직 탈락하지 않음
1 = Day 1 탈락
2 = Day 2 탈락
...
```

---

## 7. 환급 커브

환급 계산은:

```text
src/curve.ts
```

에서 처리합니다.

시간가중 환급 공식은:

```text
k = failedDay - 1

R(k)
= α × (k / D)
+ (1 - α) × (k / D)²
```

여기서:

```text
D = totalDays
α = alphaBp / 10000
k = 실제 완주일수
```

입니다.

중요한 점은:

```text
k = failedDay
```

가 아니라

```text
k = failedDay - 1
```

이라는 점입니다.

따라서 Day 1에 탈락한 참가자는:

```text
failedDay = 1
k = 0
refund rate = 0%
refund = 0
```

이 됩니다.

현재 `curve.ts`에는:

```ts
calcRefund()
refundRate()
```

두 함수가 구현되어 있습니다.

---

## 8. Refund와 Claimable 차이

두 값을 혼동하지 않도록 주의합니다.

### Refund Principal

프론트에서 시간가중 환급 커브를 이용해 계산한:

> 탈락자가 돌려받는 원금 부분

입니다.

### Claimable

컨트랙트가 가지고 있는:

> 실제로 해당 참가자가 수령할 수 있는 누적 정산 금액

입니다.

스트리밍 배당 등의 영향으로 두 값은 서로 다를 수 있습니다.

**실제 돈의 정답은 항상 온체인의 `claimable`입니다.**

프론트 계산값은 표시 및 설명용으로 사용합니다.

---

## 9. Day 1 탈락

Day 1 탈락자는:

```text
Refund Rate = 0%
Refund Principal = 0 SUI
Claimable = 0 SUI
```

가 될 수 있습니다.

이는 버그가 아니라 설계된 동작입니다.

Day 1 탈락자는 완주일수가:

```text
k = 1 - 1 = 0
```

이므로 원금이 전액 몰수됩니다.

---

## 10. Polling

Dashboard는 기본적으로:

```text
5초
```

마다 Sui Testnet 상태를 다시 조회합니다.

Polling interval은:

```ts
POLL_INTERVAL = 5000;
```

으로 `config.ts`에서 관리합니다.

따라서 Oracle 담당자가 `submit.ts`로 결과를 제출하면:

```text
Oracle submit
      ↓
Sui object 상태 변경
      ↓
최대 약 5초
      ↓
Frontend readState()
      ↓
Dashboard 자동 갱신
```

형태로 작동합니다.

페이지를 직접 새로고침할 필요는 없습니다.

---

## 11. 현재 확인된 데이터 Flow

```text
scripts/seed.ts
      ↓
Challenge + Participants 생성

Sui Testnet
      ↓
Challenge Object
      ↓
Participant Table / Dynamic Fields
      ↓
read_state.ts
      ↓
ChallengeSnapshot
      ↓
App.tsx
      ↓
Dashboard
```

Oracle 결과 제출 시:

```text
scripts/submit.ts
      ↓
Contract 상태 변경
      ↓
5초 Polling
      ↓
readState()
      ↓
Dashboard 업데이트
```

---

## 12. 다음 구현 우선순위

현재 핵심 데이터 기능은 대부분 구현되어 있습니다.

다음 우선순위는:

1. Oracle `submit.ts`와 실제 연동 테스트
2. Day 1 탈락자 화면 검증
3. Day 3 등 중간 탈락자 환급률 검증
4. Claimable 변화 검증
5. Challenge Status UI 개선
6. Participant Status Badge
7. Challenge Progress Bar
8. Web3 / DeFi 스타일 UI 디자인
9. 발표용 최종 Polish

기능 검증이 끝나기 전까지 디자인 변경으로 데이터 로직을 크게 건드리지 않는 것을 권장합니다.

---

## 13. 최종 발표에서 보여줄 핵심 장면

최종적으로 한 화면에 아래 두 상태가 함께 보이는 것이 목표입니다.

```text
Participant B
Day 1 탈락
Refund: 0%
→ 전액 몰수

Participant C
Day 3 탈락
Refund: 일부 지급
```

이를 통해 별도의 긴 설명 없이도:

> 오래 버틸수록 더 많은 금액을 돌려받는 시간가중 차등 몰수 구조

를 시각적으로 보여주는 것이 Dashboard의 핵심 목적입니다.

---

## 14. 개발 시 체크

작업 전:

```bash
git switch main
git pull origin main
```

새 작업을 시작할 경우 별도 브랜치를 생성합니다.

예:

```bash
git switch -c feat/frontend-ui
```

프론트 실행:

```bash
cd frontend
npm install
npm run dev
```

작업 후:

```bash
git status
git add frontend/
git commit -m "feat(dashboard): ..."
git push
```

### 주의

`node_modules/`는 Git에 올리지 않습니다.

`git status`에서 `node_modules`가 보인다면 `.gitignore`를 확인하세요.

---

## 15. 핵심 원칙

프론트 작업에서 아래 원칙을 유지합니다.

> **표시를 위한 계산은 프론트에서, 실제 돈의 이동과 정산은 온체인에서.**

그리고 Sui 조회 로직은 가능하면 새로 구현하지 않고:

```text
scripts/read_state.ts
```

를 기준으로 유지합니다.

현재 Dashboard의 우선 목표는 복잡한 기능 추가가 아니라:

> **온체인 상태 변화가 발표 화면에서 명확하게 보이는 것**

입니다.
