# PROTO_SPEC.md — 돈 정산 로직 프로토타입 (발표용) v2

> **목적**: 다음 주 기획 발표용 프로토타입. 전체 프로젝트 중 "돈 정산 로직"만 떼어 ver1→ver5로 점진 구현한다.
> **이 문서의 용도**: Claude Code 세션에 물려줄 작업 스펙. CLAUDE.md, **CURVE_DESIGN.md**(설계 근거 문서)와 함께 로드할 것.
> 작성: 진모 / 2026-07-17 → **v2 갱신 2026-07-18**
>
> **v2 변경 요약**: ver3를 즉시분배+선형에서 **스트리밍(베스팅) 분배 + 볼록결합 환급 커브**로 교체 (설계 유도·증명은 CURVE_DESIGN.md).
> 기대값 표 전면 교체 (T1 dust-free / T2 커브 단위 / T3 dust 검증 3종). Move `Table` 순회 불가 대응(vector 병행),
> finalize 가드, claim 시점, ver1 엣지케이스 추가. ⚠️ = 회의 확정 대기 항목.

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
├── alpha_bp: u64            # 커브 파라미터 (basis point 0~10000). ⚠️ 회의 후 확정, 임시 10000(=순수 선형)
├── total_days: u64          # 예: 5 (데모용으로 짧게)
├── current_day: u64         # submit_results마다 +1
├── daily_drip: u64          # [ver3+] 전역 일일 방출량 (MIST). 단조증가만 함
├── vault: Balance<SUI>      # 예치금 전부 보관
├── participants: Table<address, Participant>
├── participant_list: vector<address>   # ★ Table은 키 순회 불가 → 순회용 vector 병행 유지 (join 시 push)
└── status: ACTIVE | ENDED

Participant
├── stake: u64               # 예치액 (MIST)
├── start_day: u64           # ver4용, 기본 1
├── failed_day: u64          # 0 = 생존 중
└── claimable: u64           # 정산 누적액 (pull 패턴용)
```

### 1-2. 함수 인터페이스 (전 버전 동일 시그니처 유지 목표)
- `create_challenge(total_days, alpha_bp, ...) → Challenge 생성`
- `join(challenge, coin)` — Coin<SUI>를 vault에 합치고 Participant 등록 + participant_list에 push
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
- **전원 탈락**: 성공자수 = 0 → `몰수총액/성공자수`는 0으로 나누기. **각자 원금 반환** (챌린지 무효). ⚠️ 회의 안건이나 MVP 방향은 이걸로 확정하고 구현
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
1. **볼록결합 환급 커브**: day d 탈락자의 환급률
   ```
   r(d) = α·(d/D) + (1−α)·(d/D)²          # α = alpha_bp/10000
   환급 = stake × r(d),  몰수 = stake − 환급
   ```
   α<1이면 "늦게 탈락할수록 더 챙김(공정성)"을 유지하면서 "하루 더 버티는 가치가 뒤로 갈수록 커짐(인센티브)"이 성립. 유도·증명은 CURVE_DESIGN §6
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
fun calc_refund(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    // stake × [alpha_bp·d·D + (10000−alpha_bp)·d²] / (10000·D²)
    // 분자를 u128로 누적 → 나눗셈은 마지막 1회. u128 필수 (분자가 u64 상한 근접)
    // ⚠️ PLACEHOLDER: alpha_bp 값은 회의 후 확정 (권장 탐색 [2000, 4000], 임시 10000)
}
fun calc_forfeit(stake, d, total_days, alpha_bp): u64 = stake − calc_refund(...)
```

### ★ Move 구현 주의 (Solidity와 다른 함정)
- **`Table`은 키 순회 불가** → 일일 지분 분배는 `participant_list: vector<address>`를 돌며 Table에서 꺼내 갱신. 프로토 인원(3~5명)에선 충분. acc_per_share 최적화는 ver4로 미룸 (스코프 방어)
- drip 분배 시 "생존자 stake 총합"도 vector 순회로 그날그날 계산 (탈락자 제외 반영)

### 테스트 3종 (기대값은 아래 숫자 그대로 하드코딩)

**T1. 로직 검증 — dust 0 케이스** (α=1.0, alpha_bp=10000)
| 설정 | D=5, A/B/C 각 10 SUI. B day2 탈락, C day4 탈락 |
|---|---|
| day2 | B 몰수 6 SUI → drip += 6/4 = 1.5 SUI. 생존자 A,C 각 +0.75 |
| day3 | drip 1.5 → A +0.75, C +0.75 |
| day4 | C 몰수 2 SUI → drip += 2/2 = 1.0, drip=2.5. 생존자 A만 +2.5 |
| day5 | drip 2.5 → A +2.5 |
| 기대 | **A = 16.5 SUI / C = 9.5 SUI / B = 4.0 SUI** |
| 보존 | 16.5 + 9.5 + 4.0 = 30, **dust = 0** (모든 나눗셈이 MIST 정수로 나누어떨어짐 — 검산 완료) |

> 이 표가 발표의 킬러 슬라이드: "C는 탈락했지만 생존 기간의 배당 1.5는 가져간다 + 완주자 A는 C가 못 받은 스트림 잔여분까지 흡수한다"

**T2. 커브 단위 테스트** (calc_refund 단독 검산, α=0.3, alpha_bp=3000, D=5, stake=10 SUI)
| d | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| 환급 (SUI) | 0.88 | 2.32 | 4.32 | 6.88 | 10.00 |

(전부 MIST 정수로 정확 — 손검산: r(d) = 0.3(d/5) + 0.7(d/5)²)

**T3. dust 검증** (α=1.0, D=5, A/B/C 각 10 SUI, **B day3만 탈락**)
| day3 | B 몰수 4 SUI = 4e9 MIST → drip = 4e9/3 = **1,333,333,333** (절단, 나머지 1) |
|---|---|
| day3~5 | 생존자 A,C 각 floor(1,333,333,333 × 10/20) = **666,666,666**/일 × 3일 |
| 기대 | A = C = **11,999,999,998 MIST**, B = 6,000,000,000 MIST |
| 보존 | 합 29,999,999,996 + **dust 4 MIST** = 30 SUI ✓, dust 4 ≤ 상계 5×4=20 ✓ |

### ⚠️ 전멸 엣지케이스 (회의 확정 대기 — 임시 규칙으로 구현)
- 최후 생존자들이 같은 날 동시 탈락하면 잔여 스트림의 수령자가 없음
- **임시 규칙 (프로토)**: `submit_results`에서 생존자 0 감지 시 조기 ENDED 전환, 미방출 스트림 잔액은 vault 잔류(dust 취급, 보존 테스트에서 별도 항으로 검증)
- 회의 후보안: "수령자 없는 몰수는 불성립" — 잔액을 그날 탈락자들에게 지분 비례 반환 (CURVE_DESIGN §10). 확정 시 교체

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
- 튜닝 미결: 중도참여자의 D(기간) 정의, 참여 마감선 — 파라미터로 열어둘 것

### 테스트
- A, B day1 참여(각 10), C day3 참여(10), B day4 탈락 → C가 day2 이전 배당을 못 받는지 검증이 핵심

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

1. **alpha_bp 캘리브레이션**: `godsaeng_sim.py`의 몬테카를로 hazard를 실측 이탈률(유사 서비스 공개 통계)로 맞추고 payoff 왜곡 점검 → 권장 탐색 구간 [2000, 4000]. 근거·한계는 CURVE_DESIGN §9
2. ver4 중도참여자의 D(기간) 정의와 참여 마감선
3. 전멸 규칙 확정 (회의 안건 ④)
4. 성공의 정의(임계값/grace day) 확정 시 "탈락일 d" 재정의 → 커브 입력 갱신 (**회의 순서: 성공 정의 → 커브 확정**)

---

## 9. Claude Code 세션 지침 (이 문서를 읽는 AI에게)

- 이 스펙은 **발표용 프로토타입**이다. CLAUDE.md의 풀 로드맵(M0~M5)보다 이 문서가 우선한다. Clock/시간검증/인증을 제안하지 마라
- **ver3는 반드시 스트리밍 분배로 구현하라. 즉시 분배(그날 몰수 전액을 그날 분배)로 구현하는 것은 v1 스펙이며 폐기됐다**
- 설계 근거가 궁금하면 CURVE_DESIGN.md를 읽어라 (커브 유도, 명제와 증명, dust 상계 근거)
- 각 버전은 "테스트 먼저(기대값은 위 표의 숫자 그대로) → 구현 → 통과 → 커밋" 순서로 진행하라
- 커브/분배 수식은 순수 함수로 격리하고 PLACEHOLDER 주석을 달아라 (alpha_bp 미확정)
- **Sui Move의 Table은 순회 불가** — participant_list vector를 병행 유지하라. u64 오버플로 가능성이 있는 곱셈은 u128 캐스팅 기본
- 버전 하나 끝날 때마다: ① 방금 쓴 Move 문법 중 Solidity와 다른 것 요약 ② 다음 버전에서 바뀔 부분 브리핑
