# DEPLOYMENT.md — 배포 정보 (정본)

> **이 파일이 배포 정보의 유일한 정본이다.**
> 로컬 메모, 카톡, 개인 코드에 적힌 ID는 전부 사본일 뿐이며 이 파일과 다르면 이 파일이 맞다.
> 재배포 시 규칙: **① 이 파일 갱신 → ② PR → ③ 단톡 통보.** 셋 다 해야 완료.

---

## 패키지 (Sui Testnet)

| 항목 | 값 |
|---|---|
| 네트워크 | Sui **Testnet** |
| 배포일 | 2026-08-09 |
| 배포자 | 진모 |

```
Package ID
0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60

오라클 주소 (진모)
0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65

UpgradeCap (재배포 대신 업그레이드할 때 필요)
0x3b113944d8f3e3d71c77955cb2b3c5c7fc1a4fc3ddbbce967e0140ece674d410
```

패키지는 하나지만 **방(Challenge)은 여러 개 팔 수 있다.** 용도별로 아래에 나눠 적는다.
헷갈리면 돈이 아니라 시간을 잃는다 — 특히 빈 방에 submit하면 그 방은 영구히 못 쓰게 된다.

---

## 방 ① 검증 / 리허설용 ★ 지금 쓸 방

개발·리허설 중에는 **이 방을 쓴다.**

| 항목 | 값 |
|---|---|
| 생성일 | 2026-08-10 |
| 용도 | `read_state.ts` 검증, 유안의 `seed`/`submit` 시험, 승준의 대시보드 개발 |
| 파라미터 | `total_days = 5`, `alpha_bp = 2000` (α=0.2) |
| 예치 | 3인 × 0.1 SUI = vault 0.3 SUI |
| 상태 | PENDING (아직 submit 전) |

```
Challenge ID (shared object)
0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0

참가자 Table ID
0xaebe1b278a63696fb7572ca419cf5336b5a669420346d062ac36bffbc37b6ebc
```

참가자 3인:

| 별칭 | 주소 | 비고 |
|---|---|---|
| `sleepy-axinite` | `0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65` | 오라클 = 방 생성자 |
| `verify-b` | `0x6a2b4679cbcf6d22d4d2cb42546949943da857bc6056060823d73548352a4c0b` | 검증용 고정 주소 |
| `verify-c` | `0xdf0fe9e4caced8d87a2cbfad4b6ede2663be3a0952ef4e1d69d154168bbd20a3` | 검증용 고정 주소 |

> `verify-b` / `verify-c`의 키는 진모의 로컬 키스토어(`~/.sui/sui_config/sui.keystore`)에만 있다.
> faucet CLI가 폐지되어 새 주소를 즉석에서 채울 수 없으므로 **이 두 주소를 계속 재사용한다** (D-24).

---

## 방 ② 최초 생성분 — ⚠️ 사용 금지

```
Challenge ID  0xfb1eb049655a716a4270e977f948f02da07bfb60736acf7fe1dc08a66c78c6b7
Table ID      0xca4d8522d37c09d0e8f6ac5a98ee8673c8da2d408a9dacc80d531c3b1fd75f80
```

- **참가자 0명인 빈 방이다.** 아무도 join하지 않았다
- **이 ID로 `submit_results`를 호출하면 안 된다.** 생존자 지분합이 0이라 전멸로 판정되어
  즉시 `ENDED`로 잠기고 되돌릴 수 없다. 가드는 넣지 않기로 했다 (D-22)
- 읽기 전용 테스트에는 써도 무방하다 (빈 방 표시가 어떻게 나오는지 확인 용도)

---

## 방 ③ 데모용

`scripts/seed.ts`(유안)로 만든 방. 대시보드(승준) 연동 대상이자, 오라클 스크립트가
실제 테스트넷에서 5일 전체 시나리오를 도는지 확인한 첫 검증 사이클이기도 하다.

| 항목 | 값 |
|---|---|
| 생성일 | 2026-08-15 |
| 용도 | 승준의 대시보드 연동 대상, `seed.ts`/`submit.ts` 실측 검증 |
| 파라미터 | `total_days = 5`, `alpha_bp = 2000` (α=0.2, D-06·D-14) |
| 예치 | 3인 × 0.02 SUI = vault 0.06 SUI |
| 상태 | **ENDED** — day1 B탈락 / day3 C탈락 / A완주 시나리오로 5일 + finalize까지 완주시킨 결과다. **검증 기준점(D-27)이라 claim·submit 금지.** |

```
Challenge ID (shared object)
0x2f6f1b3230edaee98446d931dfb757c4a9f0ff97a14f232ea09877cb79447424

참가자 Table ID
0x67d6158137dc2878fce0160620b39bc3cc37d99af2323197a65f25fbf9cc671e
```

참가자 3인:

| 별칭 | 주소 | 비고 |
|---|---|---|
| `yuan-oracle` | `0xb222c9e1592675d4666ea416c5d7b4acf272ed01ac23dc7248bd76fa2b3f1041` | 오라클 = 방 생성자 (A, 완주) |
| `demo-b` | `0x2a024743f3e3bc4cc1ab2b683531c54448dcd7ce124eecb0fed103dca7d56a11` | B, day1 탈락 |
| `demo-c` | `0x8dcb2df7fc5cfa04338116567ba6d18e85bffdb3fc7f403565e540e3bc5a1524` | C, day3 탈락 |

> `demo-b`/`demo-c`의 키는 유안의 로컬 키스토어에만 있다 (D-24와 같은 이유로 고정 주소 재사용 전제).

**실측 결과** (`npm run read-state -- 0x2f6f1b32...`, 참고용 — 보존 법칙 검산 완료, dust=0):

| 참가자 | stake (MIST) | failed_day | claimable (MIST) |
|---|---|---|---|
| A (`yuan-oracle`) | 20,000,000 | 0 (완주) | 51,840,000 |
| B (`demo-b`) | 20,000,000 | 1 | 0 |
| C (`demo-c`) | 20,000,000 | 3 | 8,160,000 |
| 합계 | 60,000,000 | | 60,000,000 |

ENDED 상태라 참가자별 탈락일·claimable이 이미 다 채워져 있다 — 대시보드 개발 시 빈 PENDING 방보다
이쪽이 실제로 보여줄 값이 있어 더 유용할 것이다. 새 방이 필요하면 유안에게 `npm run seed` 재실행 요청.

> ⚠️ **이 방은 claim도 submit도 하지 마라.** D-27의 기준점이라 상태를 그대로 보존해야 한다.
> vault를 건드리면 `verify_onchain.py`의 "vault == 예치총합(무claim)" 검증이 깨진다.

---

## 방 ④ 통합 리허설용 — 리허설 완료

방③은 이미 ENDED라 더 이상 상태가 안 바뀐다. 대시보드 폴링(승준)이 "submit 누르면 화면이
바뀐다"를 검증하려면 **살아있는 방**이 필요해서 새로 팠다. 3자 통합 리허설을 이 방으로 진행했고,
5일 시나리오를 관통시켜 종료했다 (D-29).

| 항목 | 값 |
|---|---|
| 생성일 | 2026-08-17 |
| 용도 | 3자 통합 리허설 — 대시보드 폴링 검증 |
| 파라미터 | `total_days = 5`, `alpha_bp = 2000` (α=0.2, D-06·D-14) |
| 예치 | 3인 × 0.02 SUI = vault 0.06 SUI |
| 상태 | **ENDED** — 통합 리허설 완주 (D-29). 검증이 끝나 vault를 회수해도 무방하다 |

```
Challenge ID (shared object)
0xe11d89849787da8a028e515a17f2615ecf52da8d75415cbe983daa04f68bc4eb

참가자 Table ID
0xef0d10c257907eb5254202767e734e21fd729777522942dec1bc4a7c3331a3ea
```

참가자 3인 (방③과 동일한 A/B/C 주소를 재사용):

| 별칭 | 주소 | 비고 |
|---|---|---|
| `yuan-oracle` | `0xb222c9e1592675d4666ea416c5d7b4acf272ed01ac23dc7248bd76fa2b3f1041` | 오라클 = 방 생성자 (A) |
| `demo-b` | `0x2a024743f3e3bc4cc1ab2b683531c54448dcd7ce124eecb0fed103dca7d56a11` | B |
| `demo-c` | `0x8dcb2df7fc5cfa04338116567ba6d18e85bffdb3fc7f403565e540e3bc5a1524` | C |

5일 시나리오 관통 결과는 방③과 동일하다 — A=51,840,000 / B=0 / C=8,160,000 MIST, dust 0.
`verify_onchain.py` 대조 통과(exit 0). 같은 파라미터에서 독립 재현된 것이다 (D-29).

리허설은 끝났으므로 **이 방은 더 이상 쓸 일이 없다.** 검증이 완료된 방이라 vault 회수는 자유다.

> ⚠️ **방③에는 절대 submit 하지 마라.** 실측 검증 결과가 담긴 기준점이라 상태 그대로 보존해야 한다.
> ⚠️ 빈 방 `0xfb1eb0...`은 submit하는 순간 영구히 잠긴다 (D-22).

---

## 방 ⑤ 발표 실연용 ★ 실연 전까지 손대지 말 것

D-18(사전 세팅)에 따라 실연용 방은 리허설 방을 재사용하지 않고 새로 판 것이다.
방④는 리허설로 이미 ENDED가 되어 실연에 쓸 수 없다.

| 항목 | 값 |
|---|---|
| 생성일 | 2026-08-18 |
| 용도 | 발표 실연 |
| 파라미터 | `total_days = 5`, `alpha_bp = 2000` (α=0.2, D-06·D-14) |
| 예치 | 3인 × 0.02 SUI = vault 0.0600 SUI |
| 상태 | **PENDING** — day 0 / 5 (submit 전) |

```
Challenge ID (shared object)
0x7c754bb6a665a579103a678f7431a75d1b89ed1d682087e5b4ef4d52d535a1aa

참가자 Table ID
0x0ae1fd7b348841ffbb3921a7a3d9c0e18804a1c9938326f96e6973becc7daa64
```

참가자 3인 (방③·④와 동일한 A/B/C 주소를 재사용):

| 별칭 | 주소 | 비고 |
|---|---|---|
| `yuan-oracle` | `0xb222c9e1592675d4666ea416c5d7b4acf272ed01ac23dc7248bd76fa2b3f1041` | 오라클 = 방 생성자 (A) |
| `demo-b` | `0x2a024743f3e3bc4cc1ab2b683531c54448dcd7ce124eecb0fed103dca7d56a11` | B |
| `demo-c` | `0x8dcb2df7fc5cfa04338116567ba6d18e85bffdb3fc7f403565e540e3bc5a1524` | C |

`npm run read-state -- 0x7c754bb6...`로 참가자 3명·PENDING·day 0/5·vault 0.0600 SUI·
전원 claimable 0 확인 완료 (2026-08-18).

> ⚠️ **실연 전까지 `submit_results`를 호출하지 마라.** 한 번 진행되면 되돌릴 수 없고,
> PENDING 상태로 복구할 방법이 없다. 리허설·시험은 끝났으니 이 방으로 다시 할 이유가 없다.

---

## 사용 규칙

- **코드에 ID를 하드코딩하지 않는다.** 각자 파트에서 config 파일 / 환경변수 등 한 군데로 모아두고 거기서만 읽는다.
  - 파일 이름·형식은 각자 재량 (예: `frontend/src/config.ts`, `scripts/.env`)
  - 목적: 재배포 시 각자 한 줄만 고치면 되게
- 배포 ID는 **프리즈 대상이 아니다.** 재배포는 언제든 가능하며, 위 3단계 절차만 지키면 된다. (프리즈 범위는 `DECISIONS.md` 참조)

---

## 참가자 Table 조회 주의

`Table<address, Participant>`는 Sui에서 **dynamic field**로 저장된다.
따라서 Table 오브젝트를 그냥 읽어서는 **참가자 내용이 나오지 않는다** (껍데기 + 개수만 나옴).

조회는 2단계:

1. `listDynamicFields(Table ID)` → 엔트리 오브젝트 ID 목록
2. 그 ID들을 `batchGetObjects` → 실제 Participant 값

→ 이 로직은 **`scripts/read_state.ts`로 공용화 완료**다 (담당: 진모, D-21).
직접 짜지 말고 `import { readState } from '.../read_state'` 로 가져다 쓸 것.

```bash
cd scripts && npm install
npm run read-state -- 0xcc48adc4201a352cc20008f31b5d330211d6baa8406a60d12637eb07af76d9a0
```

⚠️ **JSON-RPC는 죽었다** (D-23). `SuiClient`가 아니라 `SuiGrpcClient`를 써야 한다.
함정 2개(생성자 옵션은 `baseUrl`, `core.getObject()` 대신 `ledgerService` + readMask `json`)는
`read_state.ts` 상단 주석과 `frontend/README.md`에 적어 두었다.

---

## 재배포 / 업그레이드 절차

`Published.toml`이 커밋되어 있으므로 **그냥 `sui client publish`를 하면 거부된다**:

```
Your package is already published. You have to manually remove the publication entry to publish again.
```

둘 중 하나를 택한다.

| 방법 | 절차 | 결과 |
|---|---|---|
| **재배포** (새 주소) | `contracts/godsaeng/Published.toml`에서 `[published.testnet]` 블록 삭제 → `sui client publish` → 새 `Published.toml` 커밋 | Package ID가 **바뀐다**. 전원 config 갱신 필요 |
| **업그레이드** (주소 유지) | 위 UpgradeCap으로 `sui client upgrade` | `original-id` 유지, `published-at`만 변경 |

어느 쪽이든 끝나면 **① 이 파일 갱신 → ② PR → ③ 단톡 통보**.

> 로컬 Sui CLI는 1.75.2(프로토콜 129)이고 testnet은 132다. 재배포 시 의존성 검증 오류가 나면
> CLI를 먼저 업데이트할 것.

---

## 배포 이력

| 날짜 | 변경 사유 | Package ID (앞 8자리) |
|---|---|---|
| 2026-08-09 | 최초 Testnet 배포 (ver1~4) | `0x11615c35` |

재배포는 아직 없다. 빈 방 가드는 미도입으로 종결되어(D-22) 이 시점에 재배포 예정도 없다.

## 방 생성 이력

| 날짜 | 방 | 용도 | 상태 |
|---|---|---|---|
| 2026-08-09 | `0xfb1eb049…` | 최초 생성 | 참가자 0명 · **사용 금지** |
| 2026-08-10 | `0xcc48adc4…` | 검증 / 리허설 | 3인 참여 · PENDING |
| 2026-08-15 | `0x2f6f1b32…` | 데모용(대시보드 연동 + 오라클 스크립트 실측 검증) | 3인 참여 · ENDED · **검증 기준점, 보존** |
| 2026-08-17 | `0xe11d8984…` | 통합 리허설(대시보드 폴링 검증) | 3인 참여 · ENDED |
| 2026-08-18 | `0x7c754bb6…` | 발표 실연용 | 3인 참여 · PENDING · **실연 전 submit 금지** |
