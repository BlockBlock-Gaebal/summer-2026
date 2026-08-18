# QUICKSTART — 대시보드 파트 (승준)

> **이 문서가 당신 파트의 시작점이다. 회의록(`docs/회의/2026-08-09.md`)의 숙제 항목보다 이 문서가 최신이다.**
> 회의 이후 체인 접근 방식이 바뀌었다(JSON-RPC 폐지 → gRPC). 충돌하면 이 문서를 따르라.

위에서부터 순서대로 따라가면 **4단계에서 참가자 표가 화면에 뜬다.** 거기까지가 1차 목표(최소 성립선)다.
각 단계에 **명령어 / 성공하면 이렇게 보인다 / 이 에러가 나면 이게 원인이다**가 붙어 있다.

---

## 🔴 시작 전에 딱 3가지만

1. **`SuiClient`가 아니라 `SuiGrpcClient`를 쓴다.** 공개 풀노드의 JSON-RPC가 폐지되어
   `SuiClient`는 모든 메서드가 `MethodNotFound`로 실패한다 (D-23).
2. **`client.core.getObject()`를 쓰지 마라.** 에러 없이 **틀린 값**이 나온다. 4단계에서 설명한다.
3. **지갑 연결·트랜잭션 전송은 만들지 않는다** (D-17). 화면은 읽기만 한다.
   `dapp-kit`도 필요 없다. 쓰기는 전부 유안의 CLI 스크립트가 한다.

---

## 1단계. Vite + React + TypeScript 프로젝트 생성

```bash
cd ~/projects/blockchain_club/summer-2026    # 각자 클론한 경로로
git checkout main
git pull

cd frontend
npm create vite@latest . -- --template react-ts
```

### ⚠️ 여기서 반드시 주의

`frontend/`에는 이미 `README.md`와 이 문서가 있어서 Vite가 이렇게 물어본다:

```
? Current directory is not empty. Please choose how to proceed:
❯ Remove existing files and continue
  Cancel operation
  Ignore files and continue
```

**반드시 `Ignore files and continue`를 고른다.**
`Remove existing files`를 고르면 README와 이 문서가 삭제된다.

이어서:

```bash
npm install
npm install @mysten/sui
npm run dev
```

**성공하면 이렇게 보인다**

```
  VITE v7.x.x  ready in 412 ms

  ➜  Local:   http://localhost:5173/
```

브라우저에서 열면 Vite + React 기본 화면이 뜬다.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| README가 사라졌다 | `Remove existing files`를 골랐다. `git checkout frontend/README.md frontend/QUICKSTART.md`로 복구 |
| `npm: command not found` | WSL 안에서 실행할 것 |
| 브라우저에서 접속이 안 됨 | WSL이면 `http://localhost:5173`이 그대로 된다. 안 되면 `npm run dev -- --host` |

---

## 2단계. 조회 로직 가져오기 + 클라이언트 설정

### 2-1. `read_state.ts`를 복사한다 ★ 확정 사항

```bash
cp ../scripts/read_state.ts src/read_state.ts
```

그리고 **`src/read_state.ts`를 열어서 아래 배너부터 파일 끝까지 통째로 지운다:**

```
// ═══════════════════════════════════════════════════════════════════════
// ▼▼▼ 여기부터 파일 끝까지는 CLI 전용이다 ▼▼▼
```

지워야 하는 이유: 그 아래는 Node 전용(`process`, `dotenv`)이라 브라우저에서 필요 없다.
위쪽(타입 + 조회 함수 + 표시 헬퍼)만 남으면 그대로 쓸 수 있다.

> **왜 복사인가 (확정).** `scripts/`는 별도 npm 패키지라 상대경로 import가 안 된다.
> `vite.config.ts`에 alias를 걸거나 공용 패키지로 빼는 방법도 있지만,
> **남은 기간 대비 과투자라 하지 않는다.** 복사본을 쓴다 (D-25).
> 대신 `read_state.ts`가 바뀌면 다시 복사해야 한다는 점만 기억할 것.

### 2-2. 설정을 한 곳에 모은다

ID를 코드 여기저기 하드코딩하지 않는다 (D-20). `src/config.ts`를 만든다:

```ts
// src/config.ts
// 값의 정본은 docs/DEPLOYMENT.md 다. 다르면 그쪽이 맞다.

export const NETWORK = 'testnet' as const;
export const GRPC_URL = 'https://fullnode.testnet.sui.io:443';

export const PACKAGE_ID =
  '0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60';

/** 개발·리허설용 방. 참가자 3인이 이미 들어가 있다 */
export const CHALLENGE_ID =
  '0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0';

/** 폴링 주기 (ms) */
export const POLL_INTERVAL = 5000;
```

> ⚠️ `0xfb1eb049…` 방은 참가자가 0명이라 화면이 텅 빈다. 개발 중에는 위 `0xcc48adc4…`를 쓸 것.

---

## 3단계. 첫 성공 — 콘솔에 찍기

`src/App.tsx`를 통째로 아래로 바꾼다:

```tsx
import { useEffect, useState } from 'react';
import { createSuiClient, readState, type ChallengeSnapshot } from './read_state';
import { NETWORK, GRPC_URL, CHALLENGE_ID } from './config';

// createSuiClient가 baseUrl 함정을 이미 처리해준다
const client = createSuiClient({ network: NETWORK, url: GRPC_URL });

export default function App() {
  const [snap, setSnap] = useState<ChallengeSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    readState(client, CHALLENGE_ID)
      .then((s) => {
        console.log('스냅샷:', s);
        setSnap(s);
      })
      .catch((e) => setError(String(e)));
  }, []);

  if (error) return <pre>에러: {error}</pre>;
  if (!snap) return <p>불러오는 중…</p>;
  return <pre>참가자 {snap.participants.length}명 — 콘솔을 확인하세요</pre>;
}
```

브라우저 개발자도구(F12) 콘솔을 연다.

**성공하면 이렇게 보인다**

화면에 `참가자 3명 — 콘솔을 확인하세요`, 콘솔에는:

```
스냅샷: {
  challenge: {
    id: "0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0",
    oracle: "0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65",
    alphaBp: 2000n,
    totalDays: 5n,
    currentDay: 0n,
    vault: 300000000n,
    status: 0,
    statusLabel: "PENDING",
    participantsTableId: "0xaebe1b278a63696fb7572ca419cf5336b5a669420346d062ac36bffbc37b6ebc",
    participantsSize: 3n,
    participantList: (3) ["0x982fcf…", "0x6a2b46…", "0xdf0fe9…"]
  },
  participants: (3) [
    { address: "0x982fcf…", stake: 100000000n, startDay: 1n, failedDay: 0n, claimable: 0n },
    …
  ],
  warnings: []
}
```

**여기까지 나왔으면 체인 연결은 끝난 것이다.** (완료 정의 1번 달성)

> 참가자 수가 3명이 아니어도 정상이다. 유안이 같은 방에서 join을 연습하면 4명, 5명으로 늘어난다.
> 확인할 것은 **숫자가 몇인지가 아니라 값이 실제로 들어오는지**다.
> 반대로 `alpha_bp`가 `2000n`, `total_days`가 `5n`이 아니면 뭔가 잘못된 것이다.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `MethodNotFound: JSON-RPC ... deprecated` | `SuiClient`를 쓴 것이다. `createSuiClient`(=`SuiGrpcClient`)를 쓸 것 |
| `TypeError: Cannot read properties of undefined (reading 'endsWith')` | gRPC 생성자에 `url`을 넘겼다. **`baseUrl`**이 맞다. `createSuiClient`를 쓰면 알아서 처리된다 |
| `process is not defined` | `read_state.ts`의 CLI 부분을 안 지웠다. 2-1로 돌아갈 것 |
| `Failed to resolve import "dotenv/config"` | 같은 원인. CLI 부분을 지울 것 |
| `alpha_bp`가 `6513693456844128674` 같은 값 | `client.core.getObject()`를 직접 쓴 것이다. 아래 4단계 경고 참조 |
| CORS 에러 | `baseUrl`이 `https://fullnode.testnet.sui.io:443`인지 확인 |

---

## 4단계. 참가자 목록 표 렌더 ★ 최소 성립선

`src/App.tsx`를 아래로 바꾼다. **여기까지가 1차 목표다.**

```tsx
import { useEffect, useState } from 'react';
import {
  createSuiClient, readState, mistToSui, shortAddress,
  type ChallengeSnapshot,
} from './read_state';
import { NETWORK, GRPC_URL, CHALLENGE_ID } from './config';

const client = createSuiClient({ network: NETWORK, url: GRPC_URL });

export default function App() {
  const [snap, setSnap] = useState<ChallengeSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    readState(client, CHALLENGE_ID).then(setSnap).catch((e) => setError(String(e)));
  }, []);

  if (error) return <pre>에러: {error}</pre>;
  if (!snap) return <p>불러오는 중…</p>;

  const { challenge: c, participants } = snap;

  return (
    <div style={{ padding: 24, fontFamily: 'sans-serif' }}>
      <h1>Locked In (갓생 내기)</h1>
      <p>
        {c.statusLabel} · day {String(c.currentDay)} / {String(c.totalDays)} ·
        vault {mistToSui(c.vault)} SUI
      </p>

      <table cellPadding={8}>
        <thead>
          <tr>
            <th align="left">주소</th>
            <th align="right">예치금</th>
            <th align="right">탈락일</th>
            <th align="right">claimable</th>
            <th align="left">상태</th>
          </tr>
        </thead>
        <tbody>
          {participants.map((p) => (
            <tr key={p.address}>
              <td><code>{shortAddress(p.address)}</code></td>
              <td align="right">{mistToSui(p.stake)} SUI</td>
              <td align="right">{p.failedDay === 0n ? '—' : String(p.failedDay)}</td>
              <td align="right">{mistToSui(p.claimable)} SUI</td>
              <td>{p.failedDay === 0n ? '생존' : `day${p.failedDay} 탈락`}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
```

**성공하면 이렇게 보인다**

```
Locked In (갓생 내기)
PENDING · day 0 / 5 · vault 0.3000 SUI

주소            예치금       탈락일   claimable    상태
0x982fcf…db65   0.1000 SUI      —    0.0000 SUI   생존
0x6a2b46…4c0b   0.1000 SUI      —    0.0000 SUI   생존
0xdf0fe9…20a3   0.1000 SUI      —    0.0000 SUI   생존
```

**🎉 여기가 최소 성립선이다.** 이 화면이 뜨면 PR을 올려도 된다.

### ⚠️ 절대 하지 말아야 할 것

```ts
// ❌ 이렇게 하면 에러 없이 틀린 값이 나온다
const obj = await client.core.getObject({ objectId: CHALLENGE_ID });
```

이 래퍼는 readMask에 `bcs`만 요청해서 **타입 태그가 앞에 붙은 원시 BCS**를 준다.
파싱하면 필드가 통째로 밀려서 `alpha_bp`에 `6513693456844128674` 같은 값이 들어온다.
**예외가 안 나기 때문에** 화면에 이상한 숫자가 뜰 때까지 눈치채지 못한다.

직접 조회해야 한다면 `ledgerService` + readMask **`json`**을 쓴다:

```ts
// ✅ 이게 맞다 (read_state.ts가 내부적으로 이렇게 한다)
const res = await client.ledgerService.getObject({
  objectId: CHALLENGE_ID,
  readMask: { paths: ['object_id', 'object_type', 'json'] },
}).response;
```

돌아오는 `json`은 protobuf `Value`라 `{ kind: { oneofKind: 'stringValue', … } }`로 싸여 있다.
벗기는 함수까지 `read_state.ts`에 있으니 **그냥 `readState()`를 쓰는 게 맞다.**

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `Do not know how to serialize a BigInt` | u64는 전부 `bigint`다. JSX에 그냥 넣으면 죽는다. `String(x)` 또는 `mistToSui(x)`로 감쌀 것 |
| `Cannot mix BigInt and other types` | `p.stake * 2` 같은 연산에서 숫자를 섞었다. `p.stake * 2n`처럼 `n`을 붙일 것 |
| 표가 비어 있음 | `0xfb1eb049…`(빈 방)를 보고 있다. `config.ts`의 `CHALLENGE_ID` 확인 |

---

## 5단계. 그 다음 순서

| 순위 | 항목 | 완료 정의 |
|---|---|---|
| ~~1~~ | ~~RPC 연결~~ | ✅ 3단계에서 완료 |
| ~~2~~ | ~~ID config 분리~~ | ✅ 2-2에서 완료 |
| ~~3~~ | ~~참가자 목록 표~~ | ✅ 4단계에서 완료 ← **최소 성립선** |
| 4 | 방 정보 표시 | `current_day`, vault, status를 보기 좋게 |
| 5 | claimable + 탈락일 + 환급률 | day1 탈락자가 0원으로 표시됨 |
| 6 | 폴링 | 유안이 submit하면 화면 값이 5초 안에 갱신됨 |
| 7 | 디자인 | 마지막. 데이터가 먼저 |

**PR은 단계별로 쪼갤 것.** 4~7을 한 PR로 묶지 말 것.

### 6번(폴링) 힌트

```tsx
useEffect(() => {
  let alive = true;
  const tick = () => {
    readState(client, CHALLENGE_ID)
      .then((s) => { if (alive) setSnap(s); })
      .catch((e) => { if (alive) setError(String(e)); });
  };
  tick();
  const id = setInterval(tick, POLL_INTERVAL);
  return () => { alive = false; clearInterval(id); };
}, []);
```

`alive` 플래그가 있는 이유: 컴포넌트가 사라진 뒤 응답이 도착해서 setState하면 경고가 난다.

### 5번(환급률) — 파생값은 프론트에서 계산한다 (D-19)

돈이 실제로 움직이는 계산만 온체인이고, 화면에 보여주기 위한 계산은 프론트가 한다.
컨트랙트에 뷰 함수를 추가하지 않는다 (추가하면 재배포가 필요해진다).

**수식** — 커브 입력은 탈락일 `d`가 아니라 **완주일수 `k = d − 1`**이다 (D-05).
day1에 탈락하면 완주일수가 0이라 환급이 0이다. 이게 정상 동작이다.

```
R(k) = α·(k/D) + (1−α)·(k/D)²        α = alpha_bp / 10000 = 0.2,  k = d − 1
```

정수 연산으로 옮기면 (컨트랙트와 절단 시점까지 동일):

```ts
// src/curve.ts
/** day d에 탈락한 사람의 환급액 (MIST). failedDay가 0이면 생존/완주라 전액 */
export function calcRefund(
  stake: bigint, failedDay: bigint, totalDays: bigint, alphaBp: bigint,
): bigint {
  if (failedDay === 0n) return stake;          // 생존 중 또는 완주 → 원금 전액
  const k = failedDay - 1n;                    // [D-05] 완주일수
  const D = totalDays;
  const numerator = alphaBp * k * D + (10000n - alphaBp) * k * k;
  return (stake * numerator) / (10000n * D * D);   // 나눗셈은 마지막 1회
}

/** 환급률 (0~1). 표시용 */
export function refundRate(failedDay: bigint, totalDays: bigint, alphaBp: bigint): number {
  if (failedDay === 0n) return 1;
  const k = Number(failedDay - 1n);
  const D = Number(totalDays);
  const a = Number(alphaBp) / 10000;
  const x = k / D;
  return a * x + (1 - a) * x * x;
}
```

**검산** — `stake = 10 SUI`, `D = 5`, `α = 0.2`일 때 (`docs/DECISIONS.md` §3과 일치해야 한다):

| 탈락일 d | 완주일수 k | 환급 |
|---|---|---|
| day1 | 0 | 0.00 SUI |
| day2 | 1 | 0.72 SUI |
| day3 | 2 | 2.08 SUI |
| day4 | 3 | 4.08 SUI |
| day5 | 4 | 6.72 SUI |
| 완주 | 5 | 10.00 SUI |

우리 검증용 방은 `stake = 0.1 SUI`라 위 값의 1/100이다 (day2 탈락 → 0.0072 SUI).

> ⚠️ **`claimable`과 헷갈리지 말 것.** 위 환급액은 "탈락자가 돌려받을 원금 몫"이고,
> `claimable`은 거기에 스트리밍 배당까지 합산된 **실제 수령액**이다. 화면에 둘 다 쓰려면
> 이름을 분명히 구분할 것. 돈의 정답은 항상 온체인 `claimable`이다.

### day1 탈락자 주의

`claimable`이 0이라 `claim`을 호출하면 abort된다 (`ENothingToClaim`).
**버그가 아니다.** 우리는 claim 버튼을 만들지 않으니(D-17) 화면에는
`0.0000 SUI` + "전액 몰수"로 표시만 하면 된다.

---

## 부록. 커밋 · 푸시 인증

GitHub는 비밀번호 인증을 받지 않는다. **토큰을 만들어 어딘가에 붙여넣지 말고** `gh`로 로그인한다.

```bash
sudo apt update && sudo apt install gh -y
gh auth login
```

선택지는 `GitHub.com` → `HTTPS` → `Yes` → `Login with a web browser`.
화면의 8자리 코드를 브라우저에 넣으면 끝이고, 이후 `git push`가 그냥 된다.

```bash
git checkout -b dashboard/participant-table
git add frontend/
git commit -m "feat(dashboard): 참가자 목록 표 렌더"
git push -u origin dashboard/participant-table
```

대시보드 파트는 셀프 머지가 허용된다 (팀 룰 §7-3).

> `node_modules/`는 gitignore에 등록돼 있다. `git status`에 보이면 안 된다.

## 부록. 자주 쓰는 값

| 이름 | 값 |
|---|---|
| gRPC 엔드포인트 | `https://fullnode.testnet.sui.io:443` |
| Package ID | `0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60` |
| 검증용 방 ★ | `0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0` |
| ⚠️ 빈 방 (쓰지 말 것) | `0xfb1eb049655a716a4270e977f948f02da07bfb60736acf7fe1dc08a66c78c6b7` |

정본은 `docs/DEPLOYMENT.md`다 (D-20). 값이 다르면 그쪽이 맞다.
