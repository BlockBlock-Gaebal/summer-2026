// 갓생 내기 — 정산 로직 프로토타입 테스트 (PROTO_SPEC.md 기대값 하드코딩)
// ver3 기준: 볼록결합 환급 커브 + 스트리밍(베스팅) 분배.
// flat 정산 시절(ver1/ver2)의 시나리오는 git 히스토리의 해당 커밋에 보존됨.
#[test_only]
module godsaeng::challenge_tests;

use godsaeng::challenge::{Self, Challenge};
use sui::coin;
use sui::sui::SUI;
use sui::test_scenario as ts;

// === 테스트용 주소 ===
const ORACLE: address = @0xFACE; // 방 생성자 = 오라클 (프로토에선 수동 호출자)
const A: address = @0xA;
const B: address = @0xB;
const C: address = @0xC;

const ONE_SUI: u64 = 1_000_000_000; // 1 SUI = 10^9 MIST
const ALPHA_LINEAR: u64 = 10000;    // α=1.0 = 순수 선형 커브 (T1/T3 전제)

// ============================================================
// 헬퍼
// ============================================================

// who가 amount만큼 예치하고 참여
fun join_as(scenario: &mut ts::Scenario, who: address, amount: u64) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    // 테스트 전용 민팅 — 실제 체인에선 유저 지갑의 Coin<SUI>이 들어온다
    let stake = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    challenge::join(&mut ch, stake, scenario.ctx());
    ts::return_shared(ch);
}

// who가 그날 탈락자 명단 제출 (빈 명단 = 전원 생존한 날. 그래도 반드시 호출 — day 진행)
fun submit_as(scenario: &mut ts::Scenario, who: address, failed: vector<address>) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    challenge::submit_results(&mut ch, failed, scenario.ctx());
    ts::return_shared(ch);
}

// 방 생성 + A, B, C 각 10 SUI 참여 (스펙 기본 시나리오 셋업)
fun setup_abc(scenario: &mut ts::Scenario, total_days: u64, alpha_bp: u64) {
    challenge::create_challenge(total_days, alpha_bp, scenario.ctx());
    join_as(scenario, A, 10 * ONE_SUI);
    join_as(scenario, B, 10 * ONE_SUI);
    join_as(scenario, C, 10 * ONE_SUI);
}

fun finalize_as(scenario: &mut ts::Scenario, who: address) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    challenge::finalize(&mut ch);
    ts::return_shared(ch);
}

// who가 claim해서 받은 금액(MIST)을 돌려줌
fun claim_as(scenario: &mut ts::Scenario, who: address): u64 {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    let payout = challenge::claim(&mut ch, scenario.ctx());
    let amount = payout.value();
    payout.burn_for_testing();
    ts::return_shared(ch);
    amount
}

// ============================================================
// join — 예치 (스펙 §2: "3명 참여 시 vault = 예치금×3")
// ============================================================

#[test]
fun test_join_three_vault_is_30_sui() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 30 * ONE_SUI); // 예치금×3
    assert!(challenge::participant_count(&ch) == 3);
    ts::return_shared(ch);
    scenario.end();
}

// 가변 베팅이라도 0원 참여는 거부 (지분 0 = 무임승차 관전)
#[test, expected_failure(abort_code = challenge::EZeroStake)]
fun test_join_zero_stake_fails() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(5, ALPHA_LINEAR, scenario.ctx());
    join_as(&mut scenario, A, 0); // → abort
    scenario.end();
}

// 같은 주소 이중 참여 방지
#[test, expected_failure(abort_code = challenge::EAlreadyJoined)]
fun test_join_twice_fails() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(5, ALPHA_LINEAR, scenario.ctx());
    join_as(&mut scenario, A, 10 * ONE_SUI);
    join_as(&mut scenario, A, 10 * ONE_SUI); // → abort
    scenario.end();
}

// 커브 파라미터 범위 검증 (alpha_bp는 basis point, 0~10000)
#[test, expected_failure(abort_code = challenge::EInvalidAlpha)]
fun test_create_invalid_alpha_fails() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(5, 10001, scenario.ctx()); // → abort
    scenario.end();
}

// ============================================================
// submit_results — 수동 day 카운터 + 탈락 기록 (스펙 §2: 권한/중복 방지)
// ============================================================

#[test]
fun test_submit_advances_day_and_records_failure() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1: 전원 생존
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::current_day(&ch) == 2);
    assert!(challenge::failed_day_of(&ch, B) == 2); // B는 day2 탈락으로 기록
    assert!(challenge::failed_day_of(&ch, A) == 0); // A는 생존 중
    ts::return_shared(ch);
    scenario.end();
}

// 오라클이 아닌 사람의 결과 제출 거부
#[test, expected_failure(abort_code = challenge::ENotOracle)]
fun test_submit_by_non_oracle_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, A, vector[B]); // 참가자 A가 제출 시도 → abort
    scenario.end();
}

// 이미 탈락한 사람 재제출 방지 (failed_day 덮어쓰기 = 정산 오염)
#[test, expected_failure(abort_code = challenge::EAlreadyFailed)]
fun test_submit_already_failed_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[B]); // day1: B 탈락
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 재제출 → abort
    scenario.end();
}

// 참가자 아닌 주소 제출 방지
#[test, expected_failure(abort_code = challenge::ENotParticipant)]
fun test_submit_non_participant_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[@0xDEAD]); // → abort
    scenario.end();
}

// 총 D회를 넘는 호출 방지 (D회 호출 = 종료의 전제)
#[test, expected_failure(abort_code = challenge::EAllDaysSubmitted)]
fun test_submit_beyond_total_days_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR); // 2일짜리
    submit_as(&mut scenario, ORACLE, vector[]); // day1
    submit_as(&mut scenario, ORACLE, vector[]); // day2
    submit_as(&mut scenario, ORACLE, vector[]); // day3?! → abort
    scenario.end();
}

// ============================================================
// ver3 — T2: 커브 단위 테스트 (calc_refund 단독 검산)
// 스펙 §4: α=0.3 (alpha_bp=3000), D=5, stake=10 SUI
// r(d) = 0.3(d/5) + 0.7(d/5)² — 기대값 표 그대로, 전부 MIST 정수로 정확
// ============================================================

#[test]
fun test_t2_curve_unit() {
    let stake = 10 * ONE_SUI;
    // | d      | 1    | 2    | 3    | 4    | 5     |
    // | 환급   | 0.88 | 2.32 | 4.32 | 6.88 | 10.00 |
    assert!(challenge::calc_refund(stake, 1, 5, 3000) ==   880_000_000);
    assert!(challenge::calc_refund(stake, 2, 5, 3000) == 2_320_000_000);
    assert!(challenge::calc_refund(stake, 3, 5, 3000) == 4_320_000_000);
    assert!(challenge::calc_refund(stake, 4, 5, 3000) == 6_880_000_000);
    assert!(challenge::calc_refund(stake, 5, 5, 3000) == 10 * ONE_SUI); // 완주 직전까지 가면 전액

    // 몰수 = stake − 환급 (보존: 환급+몰수 = stake)
    assert!(challenge::calc_forfeit(stake, 1, 5, 3000) == 9_120_000_000);
    assert!(challenge::calc_forfeit(stake, 5, 5, 3000) == 0);

    // α=1.0 (alpha_bp=10000) = 순수 선형: r(d) = d/D → T1/T3의 전제 검산
    assert!(challenge::calc_refund(stake, 2, 5, 10000) == 4 * ONE_SUI);
    assert!(challenge::calc_refund(stake, 4, 5, 10000) == 8 * ONE_SUI);
}

// ============================================================
// ver3 — T1: 스트리밍 로직 검증, dust 0 케이스 (α=1.0)
// 스펙 §4: D=5, A/B/C 각 10 SUI. B day2 탈락, C day4 탈락
//   day2: B 몰수 6 → drip += 6/4 = 1.5, A/C 각 +0.75
//   day3: drip 1.5 → A/C 각 +0.75
//   day4: C 몰수 2 → drip += 2/2 = 1.0 (drip=2.5), A만 +2.5
//   day5: drip 2.5 → A +2.5
// 기대: A = 16.5 / C = 9.5 / B = 4.0 SUI, dust = 0
// ============================================================

#[test]
fun test_t1_streaming_settlement() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락 (몰수 6)
    submit_as(&mut scenario, ORACLE, vector[]);  // day3
    submit_as(&mut scenario, ORACLE, vector[C]); // day4: C 탈락 (몰수 2)

    // ★ 킬러 슬라이드 포인트: C는 탈락했지만 생존 기간(day2~3)의 배당 1.5 SUI는 이미 적립
    //   (그날 탈락자는 그날 배당 제외 → day4 몫은 없음. 적립분은 회수하지 않음)
    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::claimable_of(&ch, C) == 1_500_000_000);
    ts::return_shared(ch);

    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    // 기대값 (스펙 표 그대로): A는 C가 못 받은 스트림 잔여분까지 흡수
    assert!(claim_as(&mut scenario, A) == 16_500_000_000); // 원금 10 + 배당 6.5
    assert!(claim_as(&mut scenario, C) ==  9_500_000_000); // 환급 8 + 배당 1.5
    assert!(claim_as(&mut scenario, B) ==  4_000_000_000); // 환급 4 (r(2)=2/5)

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    // 보존 법칙: 16.5 + 9.5 + 4.0 = 30 SUI, dust = 0 (전 나눗셈이 정확히 나누어떨어짐)
    assert!(challenge::vault_value(&ch) == 0);
    ts::return_shared(ch);
    scenario.end();
}

// ============================================================
// ver3 — T3: dust 검증 (α=1.0, B day3만 탈락)
// 스펙 §4: B 몰수 4e9 → drip = 4e9/3 = 1,333,333,333 (절단)
//   day3~5: A/C 각 floor(1,333,333,333 × 10/20) = 666,666,666/일 × 3일
// 기대: A = C = 11,999,999,998 / B = 6e9, dust 4 MIST ≤ 상계 5×(3+1)=20
// ============================================================

#[test]
fun test_t3_dust_bound() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[]);  // day2
    submit_as(&mut scenario, ORACLE, vector[B]); // day3: B 탈락 (몰수 4)
    submit_as(&mut scenario, ORACLE, vector[]);  // day4
    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 11_999_999_998);
    assert!(claim_as(&mut scenario, C) == 11_999_999_998);
    assert!(claim_as(&mut scenario, B) ==  6_000_000_000);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    let dust = challenge::vault_value(&ch);
    // 이중 검증 (스펙 §1-4): 정확값 + 상계 — 상계 assert가 "dust인 줄 알았던 로직 버그"를 잡는다
    assert!(dust == 4);                       // 합 29,999,999,996 + 4 = 30 SUI
    assert!(dust <= 5 * (3 + 1));             // dust ≤ total_days × (인원+1) MIST
    ts::return_shared(ch);
    scenario.end();
}

// ============================================================
// 엣지케이스 + 가드
// ============================================================

// ⚠️ 전멸 (최후 생존자 동시 탈락) — 임시 규칙 (스펙 §4, 회의 확정 대기):
// 생존자 0 감지 시 조기 ENDED, 탈락자 환급은 확정, 미방출 스트림은 vault 잔류(dust 취급)
#[test]
fun test_annihilation_early_end() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[A, B, C]); // day1: 전원 동시 탈락

    // finalize 없이 조기 ENDED → 커브 환급 r(1) = 1/2 → 각자 5 SUI
    assert!(claim_as(&mut scenario, A) == 5 * ONE_SUI);
    assert!(claim_as(&mut scenario, B) == 5 * ONE_SUI);
    assert!(claim_as(&mut scenario, C) == 5 * ONE_SUI);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    // 보존 (별도 항 검증): 수령 15 + 미방출 스트림 잔액 15 = 30 SUI
    assert!(challenge::vault_value(&ch) == 15 * ONE_SUI);
    ts::return_shared(ch);
    scenario.end();
}

// 전원 성공: 몰수 0 → drip 0. 분배 로직이 abort 없이 통과하고 원금만 반환
#[test]
fun test_all_succeed_returns_principal() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]); // day1: 전원 생존
    submit_as(&mut scenario, ORACLE, vector[]); // day2: 전원 생존
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 10 * ONE_SUI);
    assert!(claim_as(&mut scenario, B) == 10 * ONE_SUI);
    assert!(claim_as(&mut scenario, C) == 10 * ONE_SUI);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 0);
    ts::return_shared(ch);
    scenario.end();
}

// 이중 claim 방지: 첫 claim에서 claimable이 0으로 리셋됨
#[test, expected_failure(abort_code = challenge::ENothingToClaim)]
fun test_double_claim_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    finalize_as(&mut scenario, ORACLE);

    claim_as(&mut scenario, A); // 1차: 10 SUI 수령
    claim_as(&mut scenario, A); // 2차 → abort
    scenario.end();
}

// finalize 가드: D회 제출 완료 전 종료 금지 (스트림 완납 전 종료 = 보존 법칙 붕괴)
#[test, expected_failure(abort_code = challenge::EChallengeNotOver)]
fun test_finalize_before_end_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]); // day1뿐
    finalize_as(&mut scenario, ORACLE); // → abort
    scenario.end();
}

// claim은 ENDED에서만 (진행 중 현금화 차단 — 적립 배당도 종료 전 인출 불가)
#[test, expected_failure(abort_code = challenge::ENotEnded)]
fun test_claim_before_finalize_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]);
    claim_as(&mut scenario, A); // → abort
    scenario.end();
}

// finalize 이중 호출 방지 (claimable 중복 적립 차단)
#[test, expected_failure(abort_code = challenge::EAlreadyEnded)]
fun test_double_finalize_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    finalize_as(&mut scenario, ORACLE);
    finalize_as(&mut scenario, ORACLE); // → abort
    scenario.end();
}
