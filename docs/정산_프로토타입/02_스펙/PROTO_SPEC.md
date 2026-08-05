# PROTO_SPEC.md — 돈 정산 로직 프로토타입 (발표용) v3

> ⚠️ 확정 사항의 정본은 `docs/DECISIONS.md`다. 이 문서와 충돌하면 그쪽이 이긴다.
>
> **목적**: 발표용 프로토타입. 전체 프로젝트 중 "돈 정산 로직"만 떼어 ver1→ver5로 점진 구현한다.
> **이 문서의 용도**: Claude Code 세션에 물려줄 작업 스펙. CLAUDE.md, `docs/DECISIONS.md`, **CURVE_DESIGN.md**(설계 근거 문서)와 함께 로드할 것.
> 작성: 진모 / 2026-07-17 → v2 갱신 2026-07-18 → **v3 갱신 2026-08-06**
>
> **v2 변경 요약**: ver3를 즉시분배+선형에서 **스트리밍(베스팅) 분배 + 볼록결합 환급 커브**로 교체 (설계 유도·증명은 CURVE_DESIGN.md).
> 기대값 표 전면 교체 (T1 dust-free / T2 커브 단위 / T3 dust 검증 3종). Move `Table` 순회 불가 대응(vector 병행),
> finalize 가드, claim 시점, ver1 엣지케이스 추가.
>
> **v3 변경 요약**: 확정 결정 D-05·D-06·D-08 반영.
> ① **커브 입력 = 완주일수 `k = d − 1`** (D-05) — T1/T2/T3/V4 기대값 전면 재생성. T3는 3인 구성에서 dust가 구조적으로 0이 되므로 **4인으로 교체**.
> ② **α = 0.2 확정** (`alpha_bp = 2000`, D-06) — 미확정 표기 전부 제거.
> ③ **PENDING 상태 + `withdraw` 신설** (D-08) — §4-1.
> ④ 대시보드(읽기 전용 FE) 계약용 **조회 함수 목록** 명문화 — §4-2.
> 미확정 항목은 더 이상 이 문서에 두지 않는다. 임시 규칙(T-01~T-04)과 후속 과제는 `docs/DECISIONS.md` §2·§4가 관리한다.

---

## 0. 스코프 — 뭘 만들고, 뭘 안 만드나

### 만드는 것
- Sui Move 패키지 `contracts/godsaeng` 안의 **정산 로직 + 테스트**
- ver1 → ver5 순차 구현 (각 버전 = 커밋/PR 단위)
- **테스트 실행 출력이 곧 발표 데모임** — 풀시나리오 테스트에 집중

### 안 만드는 것 (프로토에서 명시적 제외)
- ❌ 시간 검증 (`Clock` 미사용) — 오라클이 `submit_results` 호출할 때마다 day가 넘어가는 **수동 day 카운터** 방식
- ❌ 체크인 인증/검증 로직 전부 (오라클 = 나, 수동 호출)
- ❌ FE/BE — 컨트랙트 + 테스트만
- ❌ 최소인원, 공개/비공개, 화이트리스트
- ❌ 중도 "이탈"(자발적 탈퇴) — ver4의 중도 "참여"와 다름, 로드맵으로

---

## 1. 공통 설계 (전 버전 공유)

### 1-1. 상태 모델 (개념)
```
Challenge (shared object)
├── oracle: address          # 결과 제출 권한자 = 방 생성자
├── alpha_bp: u64            # 커브 파라미터 (basis point 0~10000). 확정값 2000 = α 0.2 (D-06)
├── total_days: u64          # 예: 5 (데모용으로 짧게)
├── current_day: u64         # submit_results마다 +1
├── daily_drip: u64          # [ver3+] 전역 일일 방출량 (MIST). 단조증가만 함
├── acc_per_share: u128      # [ver4] 지분당 누적 배당 (×SCALE 1e12)
├── vault: Balance<SUI>      # 예치금 전부 보관
├── participants: Table<address, Participant>
├── participant_list: vector<address>   # ★ Table은 키 순회 불가 → 순회용 vector 병행 유지 (join 시 push)
└── status: PENDING | ACTIVE | ENDED    # [D-08] PENDING = 첫 결과 제출 전 (§4-1)

Participant
├── stake: u64               # 예치액 (MIST)
├── start_day: u64           # ver4용, 기본 1
├── acc_entry: u128          # [ver4] 참여 시점의 acc_per_share 스냅샷
├── failed_day: u64          # 0 = 생존 중
└── claimable: u64           # 정산 누적액 (pull 패턴용)
```

### 1-2. 함수 인터페이스 (전 버전 동일 시그니처 유지 목표)
- `create_challenge(total_days, alpha_bp, ...) → Challenge 생성` (status = PENDING)
- `join(challenge, coin)` — Coin<SUI>를 vault에 합치고 Participant 등록 + participant_list에 push. **status에 따라 의미가 둘로 갈린다** (§4-1)
- `withdraw(challenge) → Coin<SUI>` — **[D-08] PENDING에서만.** 예치금 전액 반환 + Table/vector에서 제거 (§4-1)
- `submit_results(challenge, failed_addresses)` — **오라클 전용**. 그날 탈락자 명단 제출(빈 vector 가능), day+1, (ver3+) 일일 스트리밍 정산 수행
  - **운영 규칙: 탈락자가 없는 날도 빈 명단으로 반드시 호출** — 총 D회 호출이 종료의 전제. 수동 day 카운터라 호출 = day 진행
- `finalize(challenge)` — **가드: `assert!(current_day == total_days)`** (스트림 완납 전 종료 시 보존 법칙 깨짐). 종료 처리(status=ENDED) + 성공자 원금을 claimable에 합산
- `claim(challenge)` — **status == ENDED 에서만 허용.** 각자 자기 claimable을 Coin으로 찾아감 (**pull 패턴, 루프 분배 금지**). 탈락자의 환급분도 종료 후에만 claim 가능 (진행 중 현금화 차단)

### 1-3. 수치 처리 규칙
- 금액 단위: MIST (1 SUI = 10^9 MIST). 전부 u64
- 비율 계산: **곱셈 전부 먼저, 나눗셈은 마지막 1회** (절단 오차 최소화). 중간값은 u128 캐스팅 기본 — ver3 커브 분자는 u64 상한 근접이 실제로 발생함 (선택이 아니라 필수)
- 정수 나눗셈은 내림(floor). **drip은 스트림 편입 시점에 1회 절단** (`daily_drip += forfeit / 잔여일수`) — 테스트 기대값은 이 규약 기준
- **잔여(dust)**: 분배 후 남는 dust는 vault에 잔류. 상계: **dust < total_days × (인원 + 1) MIST** (일일 절단 횟수 합산 근거는 CURVE_DESIGN §10)

### 1-4. 불변 법칙 (모든 버전의 최종 테스트)
> **∑(모든 참가자 수령액) + dust = ∑(모든 참가자 예치액)**, 그리고 **dust ≤ total_days × (인원+1) MIST**
> 두 번째 assert가 있으면 "dust인 줄 알았는데 로직 버그"인 경우까지 잡힌다 (이중 검증)

---

## 2. ver1 — 기본형 (균등 베팅, flat 몰수)

### 규칙
- 전원 같은 금액 예치, 같은 기간, 중도참여/이탈 없음
- 탈락 시점 무관 **전액 몰수** (flat)
- 종료 시: 몰수 총액을 **성공자에게 균등 분배** + 원금 반환

### 수식
```
성공자 수령액 = stake + (몰수총액 / 성공자수)
탈락자 수령액 = 0
```

### 테스트 시나리오 (기대값 하드코딩)
| 설정 | A, B, C 각 10 SUI 예치, total_days=5 |
|---|---|
| 진행 | B day2 탈락, C day4 탈락, A 완주 |
| 기대 | A = 10 + 20 = **30 SUI**, B = **0**, C = **0** |
| 보존 | 30 = 30 ✓ |

### 엣지케이스 (v2 추가 — 원칙: "챌린지 불성립 시 돈은 원위치")
- **전원 탈락**: 성공자수 = 0 → `몰수총액/성공자수`는 0으로 나누기. **각자 원금 반환** (챌린지 무효). → 임시 규칙 **T-01 / T-02** (DECISIONS.md §2). ver3 이후의 실제 동작은 §4의 전멸 엣지케이스를 따른다
- **전원 성공**: 몰수 0 → 전원 원금만 반환. 분배 로직이 몰수 0에서 abort 없이 통과하는지 테스트

### 구현 순서
1. create_challenge + join → "vault = 30 SUI" 테스트
2. submit_results (day 카운터 + failed_day 기록) → "중복 제출/이미 탈락자 재제출 방지" 테스트
3. finalize + claim → 위 기대값 테스트 + 이중 claim 방지 + 전원탈락/전원성공 엣지 테스트

---

## 3. ver2 — 금액반영형 (가변 베팅, 지분 가중 분배)

### 규칙
- 사람마다 다른 금액 예치. 나머지는 ver1과 동일
- 몰수 총액을 성공자의 **예치금 지분 비례**로 분배 (균등 분할은 최소 베팅이 우월전략이 되어 커밋먼트 장치가 자기파괴됨 — 근거는 CURVE_DESIGN §3)

### 수식
```
성공자 i의 분배액 = 몰수총액 × stake_i / (성공자 stake 총합)
성공자 수령액 = stake_i + 분배액_i
```

### 테스트 시나리오
| 설정 | A=20, B=10, C=30, D=10 예치 (총 70), total_days=5 |
|---|---|
| 진행 | B day2 탈락, C day4 탈락 / A, D 완주 |
| 몰수 | 10 + 30 = 40 |
| 기대 | A = 20 + 40×20/30 = **46.66...**, D = 10 + 40×10/30 = **23.33...** (MIST 정수 나눗셈, dust 발생 확인) |
| 보존 | A수령 + D수령 + dust = 70 ✓ |

---

## 4. ver3 — 성과반영형 (볼록 커브 + 스트리밍 일일정산) ★프로토의 핵심 [v2 전면 교체]

### 규칙
1. **볼록결합 환급 커브**: day d 탈락자의 환급률. **[D-05] 커브 입력은 탈락일 d가 아니라 완주일수 `k = d − 1`이다**
   ```
   R(k) = α·(k/D) + (1−α)·(k/D)²,  k = d − 1     # α = alpha_bp/10000, 확정값 0.2
   환급 = stake × R(k),  몰수 = stake − 환급
   ```
   α<1이면 "늦게 탈락할수록 더 챙김(공정성)"을 유지하면서 "하루 더 버티는 가치가 뒤로 갈수록 커짐(인센티브)"이 성립. 유도·증명은 CURVE_DESIGN §6, 인덱싱 유도는 §12.
   경계: `k=0`(day1 탈락) → 환급 0 / `k=D−1`(마지막 날 탈락) → 환급 < stake / **완주자는 이 함수를 타지 않고 finalize에서 원금 전액**
2. **스트리밍(베스팅) 분배**: day d의 몰수액을 즉시 분배하지 않고 **day d부터 종료일까지 (D−d+1)일에 걸쳐 균등 방출**
   ```
   탈락 발생 시: daily_drip += 몰수액 / (D − d + 1)     # 편입 시 1회 절단
   매일 정산:    그날 생존자에게 daily_drip을 지분 비례 적립
   ```
   모든 스트림의 종점이 D로 같으므로 전역 변수 daily_drip 하나로 O(1) — pool을 day별로 추적하지 않는다
3. **그날 탈락자는 그날 배당에서 제외** (탈락과 동시에 자격 상실). 이미 적립된 배당은 이후 탈락해도 회수하지 않음
4. 성공자의 원금 + 탈락자의 환급분은 finalize 때 claimable에 합산 (배당은 매일 적립되어 있음)

### 순수 함수 (반드시 격리 — 테스트 = 수식 검산)
```
public fun calc_refund(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    // [D-05] 내부에서 k = d − 1로 변환 (d=0은 방어적으로 k=0)
    // stake × [alpha_bp·k·D + (10000−alpha_bp)·k²] / (10000·D²)
    // 분자를 u128로 누적 → 나눗셈은 마지막 1회. u128 필수 (분자가 u64 상한 근접)
    // alpha_bp 확정값: 2000 (α = 0.2, D-06)
}
public fun calc_forfeit(stake, d, total_days, alpha_bp): u64 = stake − calc_refund(...)
```

### ★ Move 구현 주의 (Solidity와 다른 함정)
- **`Table`은 키 순회 불가** → 일일 지분 분배는 `participant_list: vector<address>`를 돌며 Table에서 꺼내 갱신. 프로토 인원(3~5명)에선 충분. acc_per_share 최적화는 ver4로 미룸 (스코프 방어)
- drip 분배 시 "생존자 stake 총합"도 vector 순회로 그날그날 계산 (탈락자 제외 반영)

### 테스트 3종 (기대값은 아래 숫자 그대로 하드코딩)

**T1. 로직 검증 — dust 0 케이스** (α=1.0, alpha_bp=10000)
| 설정 | D=5, A/B/C 각 10 SUI. B day2 탈락, C day4 탈락 |
|---|---|
| day2 | B 탈락 (k=1, 환급 2) → 몰수 8 SUI → drip += 8/4 = 2.0 SUI. 생존자 A,C 각 +1.0 |
| day3 | drip 2.0 → A +1.0, C +1.0 |
| day4 | C 탈락 (k=3, 환급 6) → 몰수 4 SUI → drip += 4/2 = 2.0, drip=4.0. 생존자 A만 +4.0 |
| day5 | drip 4.0 → A +4.0 |
| 기대 | **A = 20.0 SUI / C = 8.0 SUI / B = 2.0 SUI** |
| 보존 | 20.0 + 8.0 + 2.0 = 30, **dust = 0** (α=1에서 drip 증가분이 항상 stake/D로 일정 — CURVE_DESIGN §12-3 명제 10) |

> 이 표가 발표의 킬러 슬라이드: "C는 탈락했지만 생존 기간의 배당 2.0은 가져간다 + 완주자 A는 C가 못 받은 스트림 잔여분까지 흡수한다"

**T2. 커브 단위 테스트** (calc_refund 단독 검산, **α=0.2, alpha_bp=2000**, D=5, stake=10 SUI)
| d (탈락일) | 1 | 2 | 3 | 4 | 5 | 완주 |
|---|---|---|---|---|---|---|
| k = d−1 | 0 | 1 | 2 | 3 | 4 | 5 |
| 환급 (SUI) | 0.00 | 0.72 | 2.08 | 4.08 | 6.72 | 10.00 |

(전부 MIST 정수로 정확 — 손검산: R(k) = 0.2(k/5) + 0.8(k/5)², 분자 10000k+8000k², 분모 250000.
day1 탈락 = 하루도 성공 못 함 → 0. day5(마지막 날) 탈락은 완주자와 3.28 SUI 차이 — 마지막 날 무임승차 제거)

**T3. dust 검증** (α=1.0, D=5, **A/B/C/E 4인** 각 10 SUI, **B day3만 탈락**)

> **왜 4인인가**: D-05의 부수 성질(명제 10) 때문에 α=1·3인 균등에서는 모든 나눗셈이 정확히 떨어져 dust가 0이 된다.
> 지분 분배에서 절단이 발생하려면 **생존자가 3명 이상**이어야 하므로 참가자를 4인으로 늘렸다.

| day3 | B 탈락 (k=2, 환급 4) → 몰수 6e9 MIST → drip = 6e9/3 = **2,000,000,000** (여기선 정확히 떨어짐) |
|---|---|
| day3~5 | 생존자 A,C,E 지분합 30e9 → acc += floor(2e9 × 1e12 / 30e9) = **66,666,666,666**/일 × 3일 |
| | 개인 배당 = floor(10e9 × 199,999,999,998 / 1e12) = **1,999,999,999** (절단은 정산 시 1회) |
| 기대 | A = C = E = **11,999,999,999 MIST**, B = **4,000,000,000 MIST** |
| 보존 | 합 39,999,999,997 + **dust 3 MIST** = 40 SUI ✓, dust 3 ≤ 상계 5×(4+1)=25 ✓ |

### 전멸 엣지케이스 (임시 규칙 T-01 / T-02 — DECISIONS.md §2)
- 최후 생존자들이 같은 날 동시 탈락하면 잔여 스트림의 수령자가 없음
- **임시 규칙 (프로토)**: `submit_results`에서 생존자 0 감지 시 조기 ENDED 전환, 미방출 스트림 잔액은 vault 잔류(dust 취급, 보존 테스트에서 별도 항으로 검증)
- 기대값 (α=1.0, D=5, 3인 각 10 SUI, day3 동시 탈락): 각자 **4.0 SUI** 환급, vault 잔류 **18.0 SUI**
- 대안 후보: "수령자 없는 몰수는 불성립" — 잔액을 그날 탈락자들에게 지분 비례 반환 (CURVE_DESIGN §10). 확정 시 교체
- **D-05로 심각도 상승**: day1 전멸이면 k=0이라 전원 환급 0 + 전액 vault 잔류 + `claim`이 `ENothingToClaim`으로 abort한다 (DECISIONS.md §4)

---

## 4-1. [D-08] PENDING 상태와 `withdraw`

### 왜 있는가

D-07이 성공의 정의를 **grace 0(무관용)**으로 확정했다. 여기에 D-05가 겹치면 day1 탈락자의 환급이 정확히 0이 되어 "가혹하다"는 반문이 생긴다. PENDING 구간이 그 반문을 닫는다: **빠질 기회를 명시적으로 줬는데 안 빠졌다**가 되므로, day1 탈락자의 환급 0이 가혹함이 아니라 본인 선택의 결과가 된다. 펀드의 청약 기간 / 소비자법의 청약 철회기간에 대응하는 구조다.

### 상태 머신

```
PENDING ──첫 submit_results──> ACTIVE ──finalize 또는 전멸──> ENDED
   │                              │
   │ join   (start_day = 1)       │ join (start_day = current_day + 1, ver4 중도참여)
   │ withdraw (전액 반환)          │ withdraw ✗ (EWithdrawClosed)
```

- **PENDING** = 첫 결과 제출 전. 돈이 아직 잠기지 않은 구간. `current_day = 0`
- **첫 `submit_results` 호출이 돈이 잠기는 순간**이다 (PENDING → ACTIVE). 이 전환은 되돌릴 수 없다
- ENDED에서만 `claim` 가능

### `join`의 이중 의미

`join`은 status에 따라 뜻이 갈린다. 함수는 하나지만 의미가 둘이라는 점을 문서화해 둔다.

| status | 의미 | `start_day` | 철회 |
|---|---|---|---|
| PENDING | **정식 참여** | 1 | 가능 (`withdraw`) |
| ACTIVE | **중도 참여** (ver4) | `current_day + 1` | 불가 — 이미 스트림이 흐르고 있어 자발적 이탈은 별도 설계 영역(로드맵) |

### `withdraw` 스펙

```
public fun withdraw(ch: &mut Challenge, ctx: &mut TxContext): Coin<SUI>
```

- 가드: `assert!(status == PENDING, EWithdrawClosed)` + `assert!(participants.contains(sender), ENotParticipant)`
- 예치금 **전액** 반환 (수수료·페널티 없음)
- **Table과 vector의 정합성을 반드시 함께 유지한다** — `participants.remove` + `participant_list`에서도 제거. `swap_remove`는 O(1)이지만 순서가 바뀐다 (순서 의존 로직이 없어 안전)
- Move 함정: `Participant`는 `drop` 능력이 없는 struct이므로 `remove` 후 반드시 분해(destructure)해야 컴파일된다 — 언어가 "상태를 슬쩍 버리는" 실수를 막는 지점

### 테스트 3종

| # | 시나리오 | 기대 |
|---|---|---|
| W1 | PENDING에서 C가 철회 → 남은 2인으로 D=5 진행 (B day1 탈락) | C 전액 10 SUI 반환, vault 20 SUI, 인원 2, status 여전히 PENDING. 이후 A = 20 SUI, **B = 0** (k=0 → 환급 0), dust 0 |
| W2 | 첫 `submit_results` 후 `withdraw` 시도 | `EWithdrawClosed`로 abort |
| W3 | 철회 후 같은 주소가 재참여 | 중복참여 가드와 충돌하지 않음. 인원 3, vault 30 SUI, `start_day = 1`(정식 참여) |

---

## 4-2. 조회 함수 (대시보드 계약)

읽기 전용 대시보드(D-09)는 트랜잭션을 만들지 않고 RPC 폴링으로 아래 함수만 읽는다. **8/9 인터페이스 프리즈(D-13) 대상**이며, 이후 시그니처 변경 금지.

| 함수 | 반환 | 비고 |
|---|---|---|
| `status(ch)` | `u8` | 0 = PENDING, 1 = ACTIVE, 2 = ENDED |
| `total_days(ch)` | `u64` | |
| `current_day(ch)` | `u64` | 0 = 시작 전 |
| `alpha_bp(ch)` | `u64` | 커브 그래프 렌더용 |
| `daily_drip(ch)` | `u64` | 전역 일일 방출량 (MIST) |
| `vault_value(ch)` | `u64` | 보존 법칙 표시용 |
| `participant_count(ch)` | `u64` | |
| `participant_addresses(ch)` | `vector<address>` | **진입점** — 이걸 받아 주소별로 아래 4개를 조회한다 |
| `stake_of(ch, who)` | `u64` | |
| `start_day_of(ch, who)` | `u64` | 중도 참여자 식별 |
| `failed_day_of(ch, who)` | `u64` | 0 = 생존 중, n = day n 탈락 |
| `claimable_of(ch, who)` | `u64` | 확정 환급 + 누적 배당 |

**FE 주의**: `claim`에는 `assert!(claimable > 0)`이 있어 **day1 탈락자(k=0, 환급 0)는 claim이 abort한다.** `claimable_of == 0`인 참가자에게 claim 관련 UI를 띄우면 안 된다 (DECISIONS.md §4).

---

## 5. ver4 — 참가자유형 (중도 참여) — 스트레치 골

### 규칙
- ver3 + 챌린지 진행 중 신규 참여 (예: day15에 join). 참여자마다 `start_day` → 커브는 개인 타임라인 기준
- **v2 노트**: 스트리밍 채택으로 이 버전이 오히려 쉬워짐 — `daily_drip`이 acc_per_share 패턴의 "일일 보상액"에 그대로 꽂힘:
  ```
  acc_reward_per_share (u128, SCALE 1e12): 매일 acc += daily_drip × SCALE / 생존자 stake 총합
  개인 배당 = stake × (acc_탈락또는종료시점 − acc_참여시점) / SCALE
  ```
  중간 진입자가 진입 이전 배당을 못 받는 게 수학적으로 자동 보장 (Aave/MasterChef 정석 패턴)
- 임시 규칙 **T-03**(중도참여자의 D 정의 = `D − start_day + 1`) / **T-04**(참여 마감선 τ 미구현) — 후속 확정 대상 (DECISIONS.md §2·§4)

### 테스트
- **V4-1** A, B day1 참여(각 10), C day3 참여(10), B day2 탈락 → C가 day2 배당을 못 받는지 검증이 핵심.
  기대: **A = 15.0 / C = 13.0 / B = 2.0 SUI, dust 0**
  (스펙 스케치의 "B day4 탈락"으로는 C 참여 전 배당이 없어 검증이 공허 → B 탈락을 day2로 당겨 참여 전 배당이 실재하도록 조정)
- **V4-2** 위에서 C가 day4 추가 탈락 — 개인 타임라인 커브 검증.
  C: `start_day=3`, `d_개인=2`, `D_개인=3` → [D-05] `k_개인=1` → 환급 = 10×1/3 = 3,333,333,333
  기대: **A = 23,666,666,666 / C = 4,333,333,333 / B = 2e9 MIST, dust 1**

---

## 6. ver5 — 커스터마이징 (포맷 선택)

### 규칙
- 방 생성자가 config로 포맷 선택: `stake_mode(균등/가변)`, `alpha_bp(커브 강경도 — v2에서 이미 파라미터화됨)`, `settlement(종료일괄/스트리밍)`, `join(마감/오픈)`
- ver1~4는 이 config의 특수 케이스 — ver4까지 만들면 ver5는 분기 정리에 가까움

### 주의 (스코프 방어)
- **ver5 추상화를 먼저 설계하지 말 것.** ver1을 구체적으로 짜고 일반화는 필요가 보일 때만. 발표는 config 조합 슬라이드 + 대표 조합 1~2개 테스트면 충분

---

## 7. 개발 순서 & Git 전략

| 순서 | 작업 | 커밋/PR |
|---|---|---|
| 0 | Sui CLI 설치, `sui move new godsaeng`, 샘플 테스트 초록불 | `chore: init move package` |
| 1 | ver1 (테스트 먼저 → 구현) + 엣지 2종 | `feat: ver1 basic settlement` |
| 2 | ver2 | `feat: ver2 weighted distribution` |
| 3 | ver3 ★ — T2(커브 단위) → T1(로직) → T3(dust) 순서로 | `feat: ver3 streaming settlement with convex curve` |
| 4 | (여유 시) ver4 | `feat: ver4 mid-join with acc_per_share` |
| 5 | (여유 시) ver5 config 정리 / 아니면 설계 문서만 | `feat: ver5 configurable formats` |

- 브랜치: `prototype/money-logic` 하나로, 버전마다 커밋 잘게 → 일요일 밤 PR 하나로 팀 공유 (커밋 히스토리 = 발표 자료)
- **우선순위: ver3까지가 필수** (핵심 차별점). 버전 하나에 90분 이상 막히면 스킵 판단

---

## 8. 금융공학 튜닝 포인트 (진모 몫 — 프로토 이후)

1. **alpha_bp 정밀 캘리브레이션**: 현재 확정값 0.2(D-06)는 직관 기반이다. `godsaeng_sim.py`의 몬테카를로 hazard를 실측 이탈률(유사 서비스 공개 통계)로 맞추고 payoff 왜곡 점검 → 재조정. 근거·한계는 CURVE_DESIGN §9
2. ver4 중도참여자의 D(기간) 정의(**T-03**)와 참여 마감선 τ(**T-04**)
3. 전멸 규칙 확정 (**T-01 / T-02**) — D-05로 심각도 상승 (day1 전멸 시 전원 환급 0)
4. ~~성공의 정의 확정 시 "탈락일 d" 재정의~~ → **완료**. D-07(grace 0) 확정 → D-05(커브 입력 `k = d−1`) 적용 → 기대값 표 전면 재생성

> 1~3은 `docs/DECISIONS.md` §2·§4가 정본으로 관리한다.

---

## 9. Claude Code 세션 지침 (이 문서를 읽는 AI에게)

- 이 스펙은 **발표용 프로토타입**이다. 확정값은 `docs/DECISIONS.md`, 구현 스펙은 이 문서가 정본이다. Clock/시간검증/인증을 제안하지 마라
- **ver3는 반드시 스트리밍 분배로 구현하라. 즉시 분배(그날 몰수 전액을 그날 분배)로 구현하는 것은 v1 스펙이며 폐기됐다**
- 설계 근거가 궁금하면 CURVE_DESIGN.md를 읽어라 (커브 유도, 명제와 증명, dust 상계 근거)
- 각 버전은 "테스트 먼저(기대값은 위 표의 숫자 그대로) → 구현 → 통과 → 커밋" 순서로 진행하라
- 커브/분배 수식은 순수 함수로 격리하라. **확정값은 `docs/DECISIONS.md`를 따르라. 수치 변경 시 `03_시뮬레이터/run.py`로 먼저 검증하라** (run.py는 `challenge.move` 로직의 파이썬 미러로, 연산 순서·절단 시점까지 1:1 대응한다)
- **Sui Move의 Table은 순회 불가** — participant_list vector를 병행 유지하라. u64 오버플로 가능성이 있는 곱셈은 u128 캐스팅 기본
- 버전 하나 끝날 때마다: ① 방금 쓴 Move 문법 중 Solidity와 다른 것 요약 ② 다음 버전에서 바뀔 부분 브리핑
