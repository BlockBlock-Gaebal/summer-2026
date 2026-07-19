// 갓생 내기 — 정산 로직 프로토타입 테스트 (PROTO_SPEC.md 기대값 하드코딩)
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

// === 헬퍼: who가 amount만큼 예치하고 참여 ===
fun join_as(scenario: &mut ts::Scenario, who: address, amount: u64) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    // 테스트 전용 민팅 — 실제 체인에선 유저 지갑의 Coin<SUI>이 들어온다
    let stake = coin::mint_for_testing<SUI>(amount, scenario.ctx());
    challenge::join(&mut ch, stake, scenario.ctx());
    ts::return_shared(ch);
}

// ============================================================
// ver1 — Step 1: create_challenge + join
// 스펙 §2: "3명 참여 시 vault = 예치금×3"
// ============================================================

#[test]
fun test_join_three_vault_is_30_sui() {
    let mut scenario = ts::begin(ORACLE);
    // 균등 베팅 10 SUI, 5일짜리 챌린지 방 생성
    challenge::create_challenge(10 * ONE_SUI, 5, scenario.ctx());

    join_as(&mut scenario, A, 10 * ONE_SUI);
    join_as(&mut scenario, B, 10 * ONE_SUI);
    join_as(&mut scenario, C, 10 * ONE_SUI);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 30 * ONE_SUI); // 예치금×3
    assert!(challenge::participant_count(&ch) == 3);
    ts::return_shared(ch);
    scenario.end();
}

// ver1은 균등 베팅 — 방에 정해진 금액과 다르면 거부
#[test, expected_failure(abort_code = challenge::EWrongStakeAmount)]
fun test_join_wrong_amount_fails() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(10 * ONE_SUI, 5, scenario.ctx());
    join_as(&mut scenario, A, 7 * ONE_SUI); // 10 SUI 방에 7 SUI → abort
    scenario.end();
}

// 같은 주소 이중 참여 방지
#[test, expected_failure(abort_code = challenge::EAlreadyJoined)]
fun test_join_twice_fails() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(10 * ONE_SUI, 5, scenario.ctx());
    join_as(&mut scenario, A, 10 * ONE_SUI);
    join_as(&mut scenario, A, 10 * ONE_SUI); // → abort
    scenario.end();
}

// ============================================================
// ver1 — Step 2: submit_results (수동 day 카운터 + 탈락 기록)
// 스펙 §2: 권한 / 중복 제출 방지
// ============================================================

// === 헬퍼: who가 그날 탈락자 명단 제출 (빈 명단 = 전원 생존한 날) ===
fun submit_as(scenario: &mut ts::Scenario, who: address, failed: vector<address>) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    challenge::submit_results(&mut ch, failed, scenario.ctx());
    ts::return_shared(ch);
}

// === 헬퍼: 방 생성 + A, B, C 각 10 SUI 참여 (스펙 기본 시나리오 셋업) ===
fun setup_abc(scenario: &mut ts::Scenario, total_days: u64) {
    challenge::create_challenge(10 * ONE_SUI, total_days, scenario.ctx());
    join_as(scenario, A, 10 * ONE_SUI);
    join_as(scenario, B, 10 * ONE_SUI);
    join_as(scenario, C, 10 * ONE_SUI);
}

#[test]
fun test_submit_advances_day_and_records_failure() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);

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
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, A, vector[B]); // 참가자 A가 제출 시도 → abort
    scenario.end();
}

// 이미 탈락한 사람 재제출 방지 (failed_day 덮어쓰기 = 정산 오염)
#[test, expected_failure(abort_code = challenge::EAlreadyFailed)]
fun test_submit_already_failed_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, ORACLE, vector[B]); // day1: B 탈락
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 재제출 → abort
    scenario.end();
}

// 참가자 아닌 주소 제출 방지
#[test, expected_failure(abort_code = challenge::ENotParticipant)]
fun test_submit_non_participant_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, ORACLE, vector[@0xDEAD]); // → abort
    scenario.end();
}

// 총 D회를 넘는 호출 방지 (D회 호출 = 종료의 전제)
#[test, expected_failure(abort_code = challenge::EAllDaysSubmitted)]
fun test_submit_beyond_total_days_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2); // 2일짜리
    submit_as(&mut scenario, ORACLE, vector[]); // day1
    submit_as(&mut scenario, ORACLE, vector[]); // day2
    submit_as(&mut scenario, ORACLE, vector[]); // day3?! → abort
    scenario.end();
}

// ============================================================
// ver1 — Step 3: finalize + claim
// 스펙 §2 기대값: A = 10 + 20 = 30 SUI, B = 0, C = 0
// ============================================================

fun finalize_as(scenario: &mut ts::Scenario, who: address) {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    challenge::finalize(&mut ch);
    ts::return_shared(ch);
}

// === 헬퍼: who가 claim해서 받은 금액(MIST)을 돌려줌 ===
fun claim_as(scenario: &mut ts::Scenario, who: address): u64 {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    let payout = challenge::claim(&mut ch, scenario.ctx());
    let amount = payout.value();
    payout.burn_for_testing();
    ts::return_shared(ch);
    amount
}

// 스펙 §2 메인 시나리오: B day2 탈락, C day4 탈락, A 완주
#[test]
fun test_ver1_full_scenario() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락
    submit_as(&mut scenario, ORACLE, vector[]);  // day3
    submit_as(&mut scenario, ORACLE, vector[C]); // day4: C 탈락
    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    // 기대값 (스펙 표 그대로): A = 10 + 20 = 30, B = C = 0
    assert!(claim_as(&mut scenario, A) == 30 * ONE_SUI);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::claimable_of(&ch, B) == 0);
    assert!(challenge::claimable_of(&ch, C) == 0);
    // 보존 법칙: 30(A 수령) + 0 + 0 + dust 0 = 30(총 예치) → vault 잔액 0
    assert!(challenge::vault_value(&ch) == 0);
    ts::return_shared(ch);
    scenario.end();
}

// 이중 claim 방지: 첫 claim에서 claimable이 0으로 리셋됨
#[test, expected_failure(abort_code = challenge::ENothingToClaim)]
fun test_double_claim_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[B]);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[C]);
    submit_as(&mut scenario, ORACLE, vector[]);
    finalize_as(&mut scenario, ORACLE);

    claim_as(&mut scenario, A); // 1차: 30 SUI 수령
    claim_as(&mut scenario, A); // 2차 → abort
    scenario.end();
}

// finalize 가드: D회 제출 전엔 종료 불가
#[test, expected_failure(abort_code = challenge::EChallengeNotOver)]
fun test_finalize_before_end_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, ORACLE, vector[]); // day1뿐
    finalize_as(&mut scenario, ORACLE); // → abort
    scenario.end();
}

// claim은 ENDED에서만 (진행 중 현금화 차단)
#[test, expected_failure(abort_code = challenge::ENotEnded)]
fun test_claim_before_finalize_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5);
    submit_as(&mut scenario, ORACLE, vector[]);
    claim_as(&mut scenario, A); // → abort
    scenario.end();
}

// finalize 이중 호출 방지 (claimable 중복 적립 차단)
#[test, expected_failure(abort_code = challenge::EAlreadyEnded)]
fun test_double_finalize_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    finalize_as(&mut scenario, ORACLE);
    finalize_as(&mut scenario, ORACLE); // → abort
    scenario.end();
}

// 엣지 1: 전원 탈락 → 성공자 0명, 0으로 나누기 금지. 각자 원금 반환 (챌린지 무효)
#[test]
fun test_all_fail_refunds_everyone() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2);
    submit_as(&mut scenario, ORACLE, vector[A, B]); // day1: A, B 탈락
    submit_as(&mut scenario, ORACLE, vector[C]);    // day2: C 탈락 → 전원 탈락
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 10 * ONE_SUI);
    assert!(claim_as(&mut scenario, B) == 10 * ONE_SUI);
    assert!(claim_as(&mut scenario, C) == 10 * ONE_SUI);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 0); // 보존: 전액 원위치
    ts::return_shared(ch);
    scenario.end();
}

// 엣지 2: 전원 성공 → 몰수 0. 분배 로직이 abort 없이 통과하고 원금만 반환
#[test]
fun test_all_succeed_returns_principal() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2);
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
