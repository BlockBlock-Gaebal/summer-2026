# Locked In — QUICKSTART (오라클 / 데모 파트)

> 명칭과 식별자 규약은 `scripts/README.md` 참조.

> **이 문서가 당신 파트의 시작점이다. 회의록(`docs/회의/2026-08-09.md`)의 숙제 항목보다 이 문서가 최신이다.**
> 회의 이후 testnet 환경이 두 군데 바뀌어서, 회의에서 정한 방법 중 일부는 더 이상 동작하지 않는다.
> 충돌하면 이 문서를 따르라.

위에서부터 순서대로 따라가면 된다. 각 단계에 **명령어 / 성공하면 이렇게 보인다 / 이 에러가 나면 이게 원인이다**가 붙어 있다.
막히면 30분 룰 — 단톡에 그대로 붙여넣을 것.

---

## 🔴 시작 전에 딱 3가지만

1. **`0xfb1eb049…` 방에는 `submit_results`를 절대 호출하지 마라.** 참가자가 0명이라
   호출하는 순간 전멸로 판정되어 영구히 잠긴다. 되돌릴 수 없다. 연습은 `0xcc48adc4…`로 한다.
2. **faucet CLI는 죽었다.** `sui client faucet`은 안내문만 뱉고 끝난다. 주소를 새로 파도 채울 수가 없다.
3. **니모닉·개인키·토큰은 어디에도 붙여넣지 마라.** 단톡, 이슈, 커밋, AI 채팅창 전부 포함.
   공유해도 되는 건 **주소**(`0x…`)뿐이다. 주소는 공개 정보다.

---

## 0단계. 내 환경 확인

```bash
sui --version
node -v
sui client active-env
sui client active-address
sui client gas
```

**성공하면 이렇게 보인다**

```
sui 1.75.2-027e13b2c140
v20.20.2
testnet
0x여기에당신주소가나온다...
╭──────────────┬────────────────────┬──────────────────╮
│ gasCoinId    │ mistBalance (MIST) │ suiBalance (SUI) │
├──────────────┼────────────────────┼──────────────────┤
│ 0x…          │ 1000000000         │ 1.00             │
╰──────────────┴────────────────────┴──────────────────╯
```

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `sui: command not found` | WSL 안에서 실행해야 한다. PowerShell이면 `wsl` 먼저 치고 들어갈 것 |
| `active-env`가 `devnet` | `sui client switch --env testnet`. 우리는 testnet만 쓴다 (D-10) |
| `No gas coins are owned by this address` | 잔고 0이다. **2단계까지는 돈 없이도 된다.** 3단계에서 해결한다 |
| 주소가 아예 없다 | `sui client new-address ed25519 yuan` 으로 만든다. 출력되는 **복구 문구는 아무 데도 복사하지 말 것** |

---

## 1단계. 저장소 최신화 + 의존성 설치

```bash
cd ~/projects/blockchain_club/summer-2026    # 각자 클론한 경로로
git checkout main
git pull

cd scripts
npm install
cp .env.example .env
```

`.env`는 이미 값이 채워져 있다. 지금은 **`CHALLENGE_ID` 한 줄만** 아래로 바꾸면 된다:

```
CHALLENGE_ID=0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
```

`ORACLE_PRIVATE_KEY`는 **비워둔 채로 둔다.** 읽기 전용 스크립트는 키가 필요 없고,
쓰기는 지금 단계에서는 `sui` CLI가 알아서 서명한다.

**성공하면 이렇게 보인다**

```
added 27 packages, and audited 28 packages in 6s
found 0 vulnerabilities
```

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `npm: command not found` | WSL 안에서 실행할 것 |
| `EACCES` 권한 오류 | `sudo`를 붙이지 말고, 클론 경로가 `/home/<이름>/` 아래인지 확인 |
| `.env: No such file` | `scripts/` 안에서 실행했는지 확인 (`pwd`가 `.../summer-2026/scripts`여야 함) |

> `.env`와 `node_modules/`는 gitignore에 등록되어 있다. 실수로 커밋될 일은 없다.

---

## 2단계. 첫 성공 — 검증용 방 조회하기

**돈이 없어도 된다.** 읽기만 하는 단계다.

```bash
npm run read-state -- 0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
```

**성공하면 이렇게 보인다** (실제 출력 그대로다)

```
═══ 방 정보 ═══
  Challenge   : 0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
  상태        : PENDING (0)
  진행        : day 0 / 5
  α           : 0.2 (alpha_bp=2000)
  vault       : 0.3000 SUI (300000000 MIST)
  daily_drip  : 0.0000 SUI (0 MIST)
  오라클      : 0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65
  Table       : 0xaebe1b278a63696fb7572ca419cf5336b5a669420346d062ac36bffbc37b6ebc
  참가자 수   : 3

═══ 참가자 ═══
  주소                stake(SUI)  start  failed_day  claimable(SUI)  상태
  ─────────────────────────────────────────────────────────────────────────
  0x982fcf…db65         0.1000      1           0          0.0000  생존
  0x6a2b46…4c0b         0.1000      1           0          0.0000  생존
  0xdf0fe9…20a3         0.1000      1           0          0.0000  생존
  ─────────────────────────────────────────────────────────────────────────
  합계                    0.3000                             0.0000
```

**여기까지 나왔으면 세팅은 끝난 것이다.**

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `MethodNotFound: JSON-RPC ... deprecated` | 공개 풀노드의 JSON-RPC가 폐지됐다. `SuiClient`를 쓰는 코드를 직접 짰다면 `SuiGrpcClient`로 바꿔야 한다 (D-23). `read_state.ts`는 이미 대응돼 있다 |
| `TypeError: Cannot read properties of undefined (reading 'endsWith')` | gRPC 클라이언트 생성자 옵션을 `url`로 썼다. **`baseUrl`**이 맞다 |
| `조회 실패: Object 0x… not found` | Challenge ID 오타. 위 명령어를 그대로 복붙할 것 |
| `사용법: npm run read-state -- <CHALLENGE_ID>` | 인자를 안 넘겼다. `--` 를 빠뜨리면 npm이 인자를 안 넘겨준다 |
| 참가자가 0명으로 나오고 경고가 뜬다 | 빈 방(`0xfb1eb0…`)을 조회한 것이다. ID를 다시 확인 |

---

## 3단계. 내 주소에 SUI 채우기 (여기가 유일한 대기 구간)

**`verify-b` / `verify-c` 주소는 진모의 컴퓨터 키스토어에만 있다.** 다른 컴퓨터에서는 그 주소로 서명할 수 없다.
그러니 **당신 주소**를 쓴다.

### 3-1. 내 주소 확인

```bash
sui client active-address
```

### 3-2. 잔고가 0이면 — 진모에게 요청

**faucet은 죽었다.** 스스로 채울 방법이 없으므로 SUI를 가진 사람이 나눠줘야 한다.
단톡에 **주소만** 붙여넣고 요청한다:

```
@진모 testnet SUI 좀 보내주세요
0x여기에_당신_주소
```

> 진모가 실행할 명령어 (참고용, 유안은 실행하지 않는다):
> ```bash
> sui client pay-sui \
>   --input-coins 0x65cd8706005fc33b18bc40c5b43c311dea632703c16f9870b4edaba339f34afb \
>   --recipients 0x유안주소 \
>   --amounts 200000000 \
>   --gas-budget 10000000
> ```

0.2 SUI면 join 몇 번 + 가스로 충분하다.

### 3-3. 도착 확인

```bash
sui client gas
```

**성공하면** 코인이 하나 보이고 `suiBalance`가 `0.20`이다.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `sui client faucet`이 Web UI 링크만 출력 | 정상이다. faucet CLI는 폐지됐다 (D-24). 위 요청 방식을 쓸 것 |
| 아무리 기다려도 잔고 0 | 주소를 잘못 알려줬을 가능성. `sui client active-address` 결과와 단톡에 보낸 값을 대조 |

---

## 4단계. PTB로 join 직접 해보기 ★ `seed.ts`의 핵심 조각

`seed.ts`가 결국 자동화할 동작을 **손으로 한 번** 돌려본다. 이걸 이해하면 `seed.ts`는 쉽다.

```bash
sui client ptb \
  --split-coins gas "[100000000]" \
  --assign stake \
  --move-call 0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60::challenge::join \
      @0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0 stake.0 \
  --gas-budget 30000000
```

**이게 무슨 뜻인가**

| 조각 | 의미 |
|---|---|
| `--split-coins gas "[100000000]"` | 가스로 쓰는 코인에서 **0.1 SUI(=100,000,000 MIST)**를 쪼갠다 |
| `--assign stake` | 쪼갠 결과에 `stake`라는 이름을 붙인다 |
| `--move-call …::challenge::join @<방> stake.0` | 그 코인을 그대로 `join`에 넘긴다 |
| `stake.0` | `split-coins`는 배열을 주므로 첫 번째 코인을 가리킨다 |

**왜 이 방식인가.** 코인 오브젝트가 1개뿐이면 `sui client split-coin`이 실패한다
(쪼갤 코인 = 가스 코인이라 충돌). PTB에서 가스 코인을 직접 쪼개면 이 문제가 구조적으로 사라진다.
회의에서 정했던 "faucet 여러 번 받아서 코인 늘리기"는 faucet 폐지로 무효다 (D-24).

**성공하면 이렇게 보인다** (길게 나오는데, 볼 곳은 딱 두 줄이다)

```
Transaction Digest: 6ZZfJjTGbGDV7thkYFaFogJPLzmpjwuJxaHEGopnZmyt
...
│ Status: Success                                    │
...
│  │ Owner: Shared( … )                              │
```

`Status: Success`만 확인하면 된다.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `MoveAbort … 1` | `EAlreadyJoined` — 이미 그 주소로 참여했다. 한 주소는 한 번만 join된다. 정상 동작이다 |
| `MoveAbort … 2` | `EJoinClosed` — 방이 끝났거나 마지막 날을 넘겼다. 방 ID 확인 |
| `MoveAbort … 0` | `EZeroStake` — 예치액이 0이다. `--split-coins` 금액 확인 |
| `Insufficient gas` / `balance too low` | 잔고 부족. 3단계로 |
| `No gas coins` | 잔고 0. 3단계로 |
| `Error parsing PTB` | 따옴표 문제. `"[100000000]"` 의 큰따옴표를 빠뜨렸는지 확인 |

---

## 5단계. 변화를 눈으로 확인

```bash
npm run read-state -- 0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
```

**성공하면** 참가자가 **3명 → 4명**으로 늘어 있고, vault가 `0.3000 → 0.4000 SUI`가 된다.

```
  참가자 수   : 4
...
  0x982fcf…db65         0.1000      1           0          0.0000  생존
  0x6a2b46…4c0b         0.1000      1           0          0.0000  생존
  0xdf0fe9…20a3         0.1000      1           0          0.0000  생존
  0x당신…주소            0.1000      1           0          0.0000  생존      ← 새로 생김
  ─────────────────────────────────────────────────────────────────────────
  합계                    0.4000                             0.0000
```

**여기까지 됐으면 쓰기 트랜잭션까지 성공한 것이다.** 이제 스크립트로 옮기면 된다.

---

## 6단계. 내 연습방 만들기 (`submit` 연습에 필요)

`submit_results`는 **그 방의 오라클만** 호출할 수 있다. 오라클은 `create_challenge`를 부른 사람이다.
검증용 방(`0xcc48adc4…`)의 오라클은 진모라서 당신은 submit할 수 없다.
그러니 **당신이 오라클인 방**을 하나 판다.

```bash
sui client call \
  --package 0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60 \
  --module challenge --function create_challenge \
  --args 5 2000 \
  --gas-budget 30000000
```

**성공하면** `Status: Success`와 함께 `Created Objects`에 `…::challenge::Challenge`가 뜬다.
그 `ObjectID`가 **당신 연습방의 Challenge ID**다. 메모해두고 4단계 방식으로 join을 몇 번 시킨 뒤
`submit_results`를 연습하면 된다.

**🔴 join을 하기 전에는 절대 `submit_results`를 부르지 마라.** 참가자 0명 상태에서 부르면
그 방은 즉시 영구 잠김이다. 부르기 전에 항상 `read_state`로 참가자 수를 확인하는 습관을 들일 것.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `MoveAbort … 3` | `ENotOracle` — 그 방의 오라클이 아니다. 당신이 만든 방인지 확인 |
| `MoveAbort … 11` | `EInvalidAlpha` — `alpha_bp`가 10000을 넘었다. `2000`이 맞다 |
| `MoveAbort … 6` | `EAllDaysSubmitted` — 이미 5일치를 다 제출했다 |

---

## 7단계. 이제 만들 것

### `seed.ts` — 방 생성 + 3인 join 자동화

- 4단계의 PTB를 TypeScript SDK로 옮긴 것이다.
  `Transaction`에서 `const [coin] = tx.splitCoins(tx.gas, [100_000_000]);` 후 `tx.moveCall(...)`에 넘기면 된다
- **"새 주소 생성 → faucet" 흐름은 넣지 마라.** faucet이 죽어서 동작하지 않는다.
  이미 충전된 고정 주소를 재사용하는 구조로 짤 것
- **완료 정의**: 명령어 한 줄로 새 방 + 참가자 참여 상태가 만들어지고, 실행할 때마다 동일한 상태가 재현된다

### `submit.ts` — day별 탈락자 제출

- 시나리오: day1 B탈락 / day3 C탈락 / A완주
- 탈락자가 없는 날도 **빈 배열로 반드시 호출**해야 한다. 호출이 곧 day 진행이다 (시간 검증이 없다)
- 첫 호출이 `PENDING → ACTIVE` 전환점이고, 그 전까지만 `withdraw`가 가능하다
- **완료 정의**: 실행 후 `read_state`에서 `failed_day`와 `claimable` 변화가 확인된다

### 조회는 새로 짜지 마라

`read_state.ts`를 import해서 쓴다. JSON-RPC 폐지와 gRPC 함정 2개가 이미 처리돼 있다.

```ts
import { readState, createSuiClient } from './read_state';

const client = createSuiClient({ network: 'testnet' });
const snap = await readState(client, process.env.CHALLENGE_ID!);
console.log(snap.participants);   // address / stake / failedDay / claimable
```

---

## 부록 A. 커밋 · 푸시 인증

GitHub는 비밀번호 인증을 받지 않는다. **토큰을 만들어 어딘가에 붙여넣지 말고** `gh`로 로그인하면 된다.

```bash
# gh 설치 (Ubuntu / WSL)
sudo apt update && sudo apt install gh -y

# 안 되면 공식 저장소 추가 후 재시도
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md

gh auth login
```

`gh auth login` 선택지는 이렇게 고른다:

```
? What account do you want to log into?     GitHub.com
? What is your preferred protocol for Git operations?   HTTPS
? Authenticate Git with your GitHub credentials?        Yes
? How would you like to authenticate?       Login with a web browser
```

화면에 나오는 8자리 코드를 브라우저에 입력하면 끝이다. 이후 `git push`가 그냥 된다.

```bash
git checkout -b demo/seed-submit
git add scripts/seed.ts scripts/submit.ts
git commit -m "feat(scripts): seed/submit 스크립트"
git push -u origin demo/seed-submit
```

스크립트 파트는 셀프 머지가 허용된다 (팀 룰 §7-3). 단 PR은 만들어두자.

**이 에러가 나면**

| 증상 | 원인 / 해결 |
|---|---|
| `Support for password authentication was removed` | `gh auth login`을 안 했다 |
| `Permission denied` / 403 | 저장소 권한이 없다. 단톡에서 초대 요청 |
| `.env`가 커밋 목록에 보인다 | 있을 수 없지만, 보이면 즉시 중단하고 단톡에 알릴 것 |

## 부록 B. 자주 쓰는 값

| 이름 | 값 |
|---|---|
| Package ID | `0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60` |
| 검증용 방 ★ | `0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0` |
| 검증용 방 Table | `0xaebe1b278a63696fb7572ca419cf5336b5a669420346d062ac36bffbc37b6ebc` |
| ⚠️ 사용 금지 방 | `0xfb1eb049655a716a4270e977f948f02da07bfb60736acf7fe1dc08a66c78c6b7` |
| 오라클(진모) | `0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65` |

정본은 `docs/DEPLOYMENT.md`다 (D-20). 값이 다르면 그쪽이 맞다.

## 부록 C. MoveAbort 코드표

에러 메시지 끝의 숫자가 이것이다.

| 코드 | 이름 | 뜻 |
|---|---|---|
| 0 | `EZeroStake` | 예치액 0 |
| 1 | `EAlreadyJoined` | 이미 참여한 주소 |
| 2 | `EJoinClosed` | 참여 마감 (종료됐거나 마지막 날 초과) |
| 3 | `ENotOracle` | 오라클이 아님 |
| 4 | `ENotParticipant` | 참가자가 아닌 주소를 탈락자로 제출 |
| 5 | `EAlreadyFailed` | 이미 탈락 처리된 주소 |
| 6 | `EAllDaysSubmitted` | 이미 D일치 제출 완료 |
| 7 | `EChallengeNotOver` | 아직 D일이 안 끝났는데 finalize |
| 8 | `EAlreadyEnded` | 이미 종료된 방 |
| 9 | `ENotEnded` | 종료 전에 claim |
| 10 | `ENothingToClaim` | 받을 게 0 (day1 탈락자가 여기 걸린다 — 버그 아님) |
| 11 | `EInvalidAlpha` | `alpha_bp > 10000` |
| 12 | `EWithdrawClosed` | PENDING이 아닌데 withdraw |
