# Locked In — scripts (오라클 / 데모 자동화)

> **Locked In** — *Locked in. Paid out.*
> 한글 병기 **갓생 내기**. 기술 부제는 **시간가중 차등 몰수 습관 챌린지 프로토콜**.
>
> 이름이 바뀐 것은 프로젝트 명칭뿐이다.
> **패키지 식별자는 `godsaeng`으로 남아 있다. 배포본과 묶여 있어 변경하지 않는다**
> (Move 패키지 `godsaeng`, 모듈 `challenge`, npm 패키지 `godsaeng-scripts` — D-15 인터페이스 프리즈 / D-27 재배포 없음).
>
> 명칭 체계의 정본은 `docs/DECISIONS.md` D-30이다. 이 블록은 그 사본이며, 어긋나면 그쪽이 맞다.

**담당: 유안 (C)** / 마감: 8/17
(단 `read_state.ts`는 공용 조회 모듈이라 진모가 작성 — D-21)

> 👉 **이 파트를 처음 보면 [`QUICKSTART.md`](./QUICKSTART.md)부터 보라.**
> 명령어를 순서대로 복붙하면 첫 조회까지 나온다. 이 문서는 그 다음에 읽는 참조용이다.
> `온보딩기록.md`는 착수 당시의 기록이라 나중에 봐도 된다.

## 세팅

```bash
cd scripts
npm install
cp .env.example .env      # 값의 정본은 docs/DEPLOYMENT.md (D-20)
```

Node 20 이상. 실행은 `tsx`로 하며 빌드 단계가 없다.

```bash
npm run read-state -- 0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
npm run typecheck
```

`.env`는 gitignore 대상이다. **개인키를 절대 커밋하지 말 것.**

## 만드는 것

| 파일 | 내용 | 상태 |
|---|---|---|
| `read_state.ts` | Challenge ID → 방 정보 + 참가자 배열 (조회 공용 모듈) | ✅ 완료 (진모) |
| `seed.ts` | 방 생성 + 3인 join 자동화 | 미착수 |
| `submit.ts` | day별 탈락자 제출 | 미착수 |
| `demo.ts` | 위 전체 순차 실행. day 간격 인자 (기본 6초 — 대시보드 폴링 5초가 따라올 수 있는 속도) | 미착수 |

`finalize` / `claim`도 `demo` 흐름에 포함된다.

## 스택
TypeScript + `@mysten/sui`의 **`SuiGrpcClient`**.

---

# ⚠️ 착수 전 반드시 읽을 것

아래 셋은 전부 **실측으로 확인된 것**이고, 8/9 회의에서 정한 내용 중 일부를 뒤집는다.

## 1. testnet faucet CLI는 폐지되었다

```
$ sui client faucet --address 0x6a2b4679…
For testnet tokens, please use the Web UI: https://faucet.sui.io/?address=0x6a2b4679…
(exit: 1)
```

CLI로는 한 방울도 안 나온다. **브라우저에서 캡차를 통과해야만** 받을 수 있어서 스크립트로 자동화할 수 없다.

→ **"리허설마다 새 주소를 만들고 faucet으로 채운다"는 흐름은 폐기한다** (D-24).
대신 **검증용 주소 2개를 고정해 두고 계속 재사용**한다:

| 별칭 | 주소 |
|---|---|
| `verify-b` | `0x6a2b4679cbcf6d22d4d2cb42546949943da857bc6056060823d73548352a4c0b` |
| `verify-c` | `0xdf0fe9e4caced8d87a2cbfad4b6ede2663be3a0952ef4e1d69d154168bbd20a3` |

충전은 이미 SUI를 가진 주소에서 `pay-sui`로 분배한다. 한 트랜잭션으로 여러 주소에 동시에 보낼 수 있다:

```bash
sui client pay-sui \
  --input-coins <보유코인ID> \
  --recipients <주소1> <주소2> \
  --amounts 200000000 200000000 \
  --gas-budget 10000000
```

잔고가 마르면 그때만 Web UI로 한 번 채우면 된다.

## 2. 코인 split 문제의 확정 해법은 PTB다

회의에서 정한 **"faucet 복수 수령으로 코인 오브젝트를 늘린다"는 대책은 faucet 폐지로 무효**다.

대신 PTB에서 **가스 코인을 직접 쪼개면** 코인 오브젝트가 1개뿐이어도 동작한다.
쪼갠 결과를 같은 트랜잭션 안에서 바로 `join`에 넘긴다:

```bash
sui client ptb \
  --split-coins gas "[100000000]" \
  --assign stake \
  --move-call <PKG>::challenge::join @<CHALLENGE_ID> stake.0 \
  --gas-budget 30000000
```

`sui client split-coin`이 실패하던 원인(쪼갤 코인 = 가스 코인)이 구조적으로 사라진다.
실제로 코인이 1개뿐인 `verify-b` / `verify-c`가 이 방식으로 join에 성공했다.

→ **`seed.ts`는 이 패턴 기준으로 설계한다.** "새 주소 생성 → faucet" 흐름은 넣지 말 것.
TypeScript SDK에서는 `Transaction`의 `splitCoins(tx.gas, [amount])` 결과를 `moveCall` 인자로 넘기면 된다.

## 3. JSON-RPC는 죽었다 — `SuiGrpcClient`를 써라

공개 풀노드의 JSON-RPC가 폐지되어 `SuiClient`는 **모든 메서드가 `MethodNotFound`**로 실패한다 (D-23).

함정 2개:

1. 생성자 옵션은 `url`이 아니라 **`baseUrl`**이다.
   틀리면 `TypeError: Cannot read properties of undefined (reading 'endsWith')`라는 엉뚱한 에러가 난다
2. **`client.core.getObject()`를 쓰지 마라.** readMask에 `bcs`만 요청해서 타입 태그가 붙은 원시 BCS를 주고,
   파싱하면 필드가 밀려서 조용히 틀린 값이 나온다. `ledgerService` + readMask **`json`**을 쓸 것

조회는 직접 짜지 말고 `read_state.ts`를 import해서 쓴다:

```ts
import { readState, createSuiClient } from './read_state';

const client = createSuiClient({ network: 'testnet' });
const snap = await readState(client, CHALLENGE_ID);
console.log(snap.participants);   // address / stake / failedDay / claimable
```

---

## 데모 시나리오 기본값

D=5, 3인 참여. day1 B탈락 / day3 C탈락 / A완주 (회의 확정 시나리오).

검증용 방은 3인 × **0.1 SUI**로 만들어져 있다 (`docs/DEPLOYMENT.md` 방 ①).

## 주의

- **`submit_results`는 탈락자가 없는 날도 빈 vector로 반드시 호출**해야 한다 (호출 = day 진행).
  총 D회 호출이 종료의 전제다
- 첫 `submit` 호출이 PENDING → ACTIVE 전환점이다. 그 전까지만 `withdraw` 가능
- 🔴 **빈 방에 `submit_results`를 호출하지 말 것.** 참가자가 0명이면 생존자 지분합이 0이라
  전멸로 판정되어 즉시 `ENDED`로 잠기고 **되돌릴 수 없다.** 컨트랙트 가드는 넣지 않기로 했다 (D-22).
  반드시 `create_challenge` → 참가자 `join` 완료 → 그다음 `submit_results` 순서로 진행할 것.
  실행 전 `read_state.ts`로 참가자 수를 확인하는 습관을 들이면 안전하다
  - 특히 최초 생성분 `0xfb1eb0…`이 실제로 빈 방이다. **이 ID로 submit하면 그대로 터진다**
- 배포 좌표와 방 ID의 정본은 `docs/DEPLOYMENT.md`다 (D-20). 코드에 하드코딩하지 말고 `.env`에서 읽을 것
