# frontend — 읽기 전용 대시보드

**담당: 승준 (B)** / 마감: 8/17

## 만드는 것
Sui Testnet의 Challenge 객체를 **읽어서 화면에 뿌리기만** 한다.

- 참가자 목록 + 상태 (대기 / 생존 / 탈락)
- 탈락자의 확정 환급액, 각자 누적 claimable
- 현재 day / 전체 day, 챌린지 상태 (PENDING / ACTIVE / ENDED)
- (여유되면) 커브 그래프 위에 각 참가자 점 찍기 — 우리 차별점이 눈에 보이는 유일한 지점

## 만들지 않는 것
지갑 연결, 트랜잭션 서명, 참여·claim 버튼, 로그인, 반응형, 다크모드, 백엔드 연동.
**쓰기는 전부 `scripts/`가 CLI로 한다.**

## 스택
Vite + React + TypeScript, `@mysten/sui`의 **`SuiGrpcClient`** (읽기 전용), 폴링 5초.

`dapp-kit`은 쓰지 않는다 — 지갑 연동을 안 하므로 필요 없다 (D-17).

## ⚠️ 착수 전 반드시 읽을 것 — 함정 2개

모르고 시작하면 원인 불명으로 몇 시간 날린다. 둘 다 실측으로 확인된 것이다.

**(1) `SuiClient`(JSON-RPC)는 죽었다. `SuiGrpcClient`를 써라.**

공개 풀노드의 JSON-RPC가 폐지되어 `SuiClient`는 `getObject`·`getDynamicFields`·`getBalance` 등
**모든 메서드가 `MethodNotFound`로 실패**한다 (D-23). 그리고 gRPC 클라이언트의 생성자 옵션은
`url`이 아니라 **`baseUrl`**이다. 이걸 틀리면 아래처럼 원인을 짐작할 수 없는 에러가 난다:

```
TypeError: Cannot read properties of undefined (reading 'endsWith')
```

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';

const client = new SuiGrpcClient({
  network: 'testnet',
  baseUrl: 'https://fullnode.testnet.sui.io:443',   // ← url 아님
});
```

**(2) `client.core.getObject()`를 쓰지 마라. 조용히 틀린 값이 나온다.**

이 래퍼는 readMask에 `bcs`만 요청해서 "타입 태그가 앞에 붙은" 원시 BCS를 준다.
그대로 파싱하면 필드가 통째로 밀려서 `alpha_bp`에 `6513693456844128674` 같은 값이 들어온다.
**에러가 나지 않고 틀리기 때문에** 화면에 이상한 숫자가 뜰 때까지 눈치채지 못한다.

`ledgerService`를 직접 호출하고 readMask에 **`json`**을 넣어라:

```ts
const res = await client.ledgerService.getObject({
  objectId,
  readMask: { paths: ['object_id', 'object_type', 'json'] },
}).response;
```

돌아오는 `json`은 protobuf `Value`라 `{ kind: { oneofKind: 'stringValue', ... } }`로 한 겹 싸여 있다.
벗기는 함수까지 `scripts/read_state.ts`에 있으니 **직접 짜지 말고 그걸 재사용할 것**:

```ts
import { readState, createSuiClient, mistToSui } from '<read_state 경로>';

const snap = await readState(createSuiClient({ network: 'testnet' }), CHALLENGE_ID);
// snap.challenge.currentDay / vault / status, snap.participants[].stake / failedDay / claimable
```

`scripts/`는 별도의 npm 패키지라 `frontend/`에서 그냥 상대경로로 import하면 Vite가 못 찾는다.
셋 중 편한 걸 고르면 된다 — ① `vite.config.ts`에 `resolve.alias`로 경로를 걸거나
② 파일을 `frontend/src/`로 복사하거나 ③ 나중에 공용 패키지로 빼거나.
지금은 ①이나 ②로 충분하다. **어느 쪽이든 조회 로직을 다시 짜지는 말 것** — 함정 2개를 또 밟게 된다.

u64·u128은 전부 `bigint`로 온다. 화면에 찍을 때만 `mistToSui()`를 쓰고, 계산에는 쓰지 말 것.

## 컨트랙트 조회 함수 (8/9 확정)
`status` / `total_days` / `alpha_bp` / `daily_drip` / `participant_addresses`
/ `stake_of` / `start_day_of` / `failed_day_of` / `claimable_of`
/ `vault_value` / `participant_count` / `current_day`

`participant_addresses`로 주소 목록을 받아 주소별로 나머지를 조회하는 구조다.

## 주의
- **day1 탈락자는 claimable이 0이라 claim이 abort된다.** claim 버튼/표시를 띄우면 안 된다
- 패키지 주소·Challenge 객체 ID는 `docs/DEPLOYMENT.md`가 정본이다 (D-20).
  개발 중에는 **검증용 방 `0xcc48adc4…`**를 쓸 것 — 참가자 3인이 이미 들어가 있다.
  최초 생성분 `0xfb1eb0…`은 참가자 0명이라 화면이 텅 빈다
