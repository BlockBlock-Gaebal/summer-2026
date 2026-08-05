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
const E: address = @0xE; // T3(4인 dust 케이스)용 4번째 참가자

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

// [D-08] who가 PENDING 구간에서 참여 철회, 돌려받은 금액(MIST)을 반환
fun withdraw_as(scenario: &mut ts::Scenario, who: address): u64 {
    scenario.next_tx(who);
    let mut ch = scenario.take_shared<Challenge>();
    let back = challenge::withdraw(&mut ch, scenario.ctx());
    let amount = back.value();
    back.burn_for_testing();
    ts::return_shared(ch);
    amount
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
// [D-06] α=0.2 (alpha_bp=2000), D=5, stake=10 SUI
// [D-05] 커브 입력은 완주일수 k = d−1. day d 탈락자는 day1~d−1의 (d−1)일만 성공한 것
// r(k) = 0.2(k/5) + 0.8(k/5)² — 전부 MIST 정수로 정확 (분자 10000k+8000k², 분모 250000)
// ============================================================

#[test]
fun test_t2_curve_unit() {
    let stake = 10 * ONE_SUI;
    // | d      | 1    | 2    | 3    | 4    | 5    |
    // | 환급   | 0.00 | 0.72 | 2.08 | 4.08 | 6.72 |
    // day1 탈락 = k0 = 하루도 성공 못 함 → 환급 0
    assert!(challenge::calc_refund(stake, 1, 5, 2000) ==             0);
    assert!(challenge::calc_refund(stake, 2, 5, 2000) ==   720_000_000);
    assert!(challenge::calc_refund(stake, 3, 5, 2000) == 2_080_000_000);
    assert!(challenge::calc_refund(stake, 4, 5, 2000) == 4_080_000_000);
    // day5(마지막 날) 탈락 = k4. 완주자(전액)와 3.28 SUI 차이 — 마지막 날 무임승차 제거
    assert!(challenge::calc_refund(stake, 5, 5, 2000) == 6_720_000_000);

    // 몰수 = stake − 환급 (보존: 환급+몰수 = stake)
    assert!(challenge::calc_forfeit(stake, 1, 5, 2000) == 10 * ONE_SUI);
    assert!(challenge::calc_forfeit(stake, 5, 5, 2000) ==  3_280_000_000);

    // α=1.0 (alpha_bp=10000) = 순수 선형: r(d) = d/D → T1/T3의 전제 검산
    assert!(challenge::calc_refund(stake, 2, 5, 10000) == 2 * ONE_SUI); // k=1 → 1/5
    assert!(challenge::calc_refund(stake, 4, 5, 10000) == 6 * ONE_SUI); // k=3 → 3/5
}

// ============================================================
// ver3 — T1: 스트리밍 로직 검증, dust 0 케이스 (α=1.0)
// 스펙 §4: D=5, A/B/C 각 10 SUI. B day2 탈락, C day4 탈락
//   day2: B 몰수 8 → drip += 8/4 = 2.0, A/C 각 +1.0
//   day3: drip 2.0 → A/C 각 +1.0
//   day4: C 몰수 4 → drip += 4/2 = 2.0 (drip=4.0), A만 +4.0
//   day5: drip 4.0 → A +4.0
// [D-05 적용] 기대: A = 20 / C = 8 / B = 2 SUI, dust = 0
// ============================================================

#[test]
fun test_t1_streaming_settlement() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락 (k=1, 환급 2, 몰수 8)
    submit_as(&mut scenario, ORACLE, vector[]);  // day3
    submit_as(&mut scenario, ORACLE, vector[C]); // day4: C 탈락 (k=3, 환급 6, 몰수 4)

    // ★ 킬러 슬라이드 포인트: C는 탈락했지만 생존 기간(day2~3)의 배당 2 SUI는 이미 적립
    //   (그날 탈락자는 그날 배당 제외 → day4 몫은 없음. 적립분은 회수하지 않음)
    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::claimable_of(&ch, C) == 2_000_000_000);
    ts::return_shared(ch);

    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    // 기대값 (스펙 표 그대로): A는 C가 못 받은 스트림 잔여분까지 흡수
    assert!(claim_as(&mut scenario, A) == 20_000_000_000); // 원금 10 + 배당 10
    assert!(claim_as(&mut scenario, C) ==  8_000_000_000); // 환급 6 + 배당 2
    assert!(claim_as(&mut scenario, B) ==  2_000_000_000); // 환급 2 (k=1 → r=1/5)

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    // 보존 법칙: 20 + 8 + 2 = 30 SUI, dust = 0 (α=1에서 drip 증가분이 항상 s/D로 일정)
    assert!(challenge::vault_value(&ch) == 0);
    ts::return_shared(ch);
    scenario.end();
}

// ============================================================
// ver3 — T3: dust 검증 (α=1.0, B day3만 탈락)
// 스펙 §4: B 몰수 6e9 → drip = 6e9/3 = 2e9 (여기선 정확히 떨어짐. 절단은 지분 분배에서 발생)
//   [D-05 부수성질] α=1에서 drip 증가분이 항상 s/D로 일정 → 3인 균등 시 전부 정확히
//   나누어떨어져 dust가 0이 된다. dust 검증 기능을 되살리려면 생존자 수가 3 이상이어야 함
//   → 4인(A/B/C/E)으로 교체. B day3 탈락(k=2, 환급 4, 몰수 6) → drip 2, 생존 3인 지분합 30
// 기대: A = C = E = 11,999,999,999 / B = 4e9, dust 3 ≤ 상계 5×(4+1)=25
// ============================================================

#[test]
fun test_t3_dust_bound() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    join_as(&mut scenario, E, 10 * ONE_SUI); // 4번째 참가자 — 생존자 3인을 만들어 절단 유발

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[]);  // day2
    submit_as(&mut scenario, ORACLE, vector[B]); // day3: B 탈락 (몰수 4)
    submit_as(&mut scenario, ORACLE, vector[]);  // day4
    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    // acc_per_share는 절단이 "정산 시점 1회"라 매일 절단보다 유저에게 유리한 방향:
    //   acc 누적 = floor(2e9×1e12/30e9) × 3일 = 66,666,666,666 × 3
    //   개인 배당 = floor(10e9 × 199,999,999,998 / 1e12) = 1,999,999,999
    assert!(claim_as(&mut scenario, A) == 11_999_999_999);
    assert!(claim_as(&mut scenario, C) == 11_999_999_999);
    assert!(claim_as(&mut scenario, E) == 11_999_999_999);
    assert!(claim_as(&mut scenario, B) ==  4_000_000_000); // k=2 → r=2/5

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    let dust = challenge::vault_value(&ch);
    // 이중 검증 (스펙 §1-4): 정확값 + 상계 — 상계 assert가 "dust인 줄 알았던 로직 버그"를 잡는다
    assert!(dust == 3);                       // 합 39,999,999,997 + 3 = 40 SUI
    assert!(dust <= 5 * (4 + 1));             // dust ≤ total_days × (인원+1) MIST
    ts::return_shared(ch);
    scenario.end();
}

// ============================================================
// ver4 — 중도 참여 (acc_per_share 패턴)
// 스펙 §5 검증 핵심: 중도 참여자가 "참여 이전 배당"을 못 받는지.
// 스펙 스케치(B day4 탈락)로는 C 참여 전 배당이 없어 검증이 공허 →
// B 탈락을 day2로 당겨 참여 전 배당(1.5 SUI)이 실재하도록 조정
// ============================================================

// V4-1: A, B 시작 참여(각 10) / B day2 탈락 / C day3부터 참여(10)
//   day2: B 몰수 8 → drip 2.0, 생존자 A 혼자 → A +2.0
//   day3~5: A, C 반반 → 각 +1.0/일
// 기대: A = 15.0 / C = 13.0 (day2 몫 제외!) / B = 2.0, dust 0
#[test]
fun test_v4_midjoin_excluded_from_prior_dividends() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(5, ALPHA_LINEAR, scenario.ctx());
    join_as(&mut scenario, A, 10 * ONE_SUI);
    join_as(&mut scenario, B, 10 * ONE_SUI);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락 → 배당 발생 시작
    join_as(&mut scenario, C, 10 * ONE_SUI);     // C 중도 참여 (start_day=3)
    submit_as(&mut scenario, ORACLE, vector[]);  // day3
    submit_as(&mut scenario, ORACLE, vector[]);  // day4
    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 15_000_000_000); // 10 + 2.0 + 1.0×3
    assert!(claim_as(&mut scenario, C) == 13_000_000_000); // 10 + 1.0×3 (day2 몫 없음)
    assert!(claim_as(&mut scenario, B) ==  2_000_000_000);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 0); // 보존: 15+13+2 = 30, dust 0
    ts::return_shared(ch);
    scenario.end();
}

// V4-2: V4-1에서 C가 day4 탈락 — 중도 참여자의 커브는 "개인 타임라인" 기준
//   ⚠️ 임시 규칙 T-02 / T-03 후속 과제 (DECISIONS.md §2): d_개인 = 탈락일−start_day+1, D_개인 = D−start_day+1
//   C: start_day=3, day4 탈락 → d=2, D=3 → [D-05] k=1 → 환급 = 10×1/3 = 3,333,333,333
//   C 몰수 6,666,666,667 → drip += /2 = 3,333,333,333 → day4~5 A 독식
// 기대: A = 23,666,666,666 / C = 4,333,333,333 / B = 2.0 (합 29,999,999,999 + dust 1 = 30)
#[test]
fun test_v4_midjoin_personal_timeline_curve() {
    let mut scenario = ts::begin(ORACLE);
    challenge::create_challenge(5, ALPHA_LINEAR, scenario.ctx());
    join_as(&mut scenario, A, 10 * ONE_SUI);
    join_as(&mut scenario, B, 10 * ONE_SUI);

    submit_as(&mut scenario, ORACLE, vector[]);  // day1
    submit_as(&mut scenario, ORACLE, vector[B]); // day2: B 탈락
    join_as(&mut scenario, C, 10 * ONE_SUI);     // C 중도 참여 (start_day=3)
    submit_as(&mut scenario, ORACLE, vector[]);  // day3: A, C 각 +1.0
    submit_as(&mut scenario, ORACLE, vector[C]); // day4: C 개인 타임라인 2/3 지점 탈락
    submit_as(&mut scenario, ORACLE, vector[]);  // day5
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 23_666_666_666);
    assert!(claim_as(&mut scenario, C) ==  4_333_333_333); // 환급 3,333,333,333 + 배당 1.0
    assert!(claim_as(&mut scenario, B) ==  2_000_000_000);

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 1);
    ts::return_shared(ch);
    scenario.end();
}

// 종료된(마지막 day 제출 완료) 챌린지엔 참여 불가
#[test, expected_failure(abort_code = challenge::EJoinClosed)]
fun test_join_after_last_day_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]); // day1
    submit_as(&mut scenario, ORACLE, vector[]); // day2 = 마지막 날
    join_as(&mut scenario, @0xD, 10 * ONE_SUI); // → abort
    scenario.end();
}

// ============================================================
// 엣지케이스 + 가드
// ============================================================

// ⚠️ 전멸 (최후 생존자 동시 탈락) — 임시 규칙 (스펙 §4, T-02 / T-03 후속 과제 — DECISIONS.md §2):
// 생존자 0 감지 시 조기 ENDED, 탈락자 환급은 확정, 미방출 스트림은 vault 잔류(dust 취급)
#[test]
fun test_annihilation_early_end() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 2, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]);        // day1: 전원 생존
    submit_as(&mut scenario, ORACLE, vector[A, B, C]); // day2: 전원 동시 탈락

    // finalize 없이 조기 ENDED → 커브 환급 r(k=1) = 1/2 → 각자 5 SUI
    // ⚠️ day1 전멸이면 k=0이라 전원 환급 0 = 전액 vault 잔류 + claim이 ENothingToClaim으로
    //    abort한다. T-02(전멸 임시규칙)의 실질 심각도가 D-05로 커진 지점 — 후속 확정 필요
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

// ============================================================
// [D-08] PENDING 구간 — 첫 결과 제출 전 자유 참여/철회
// 이 구간이 있어야 grace 0(무관용)이 정당해진다:
// "빠질 기회를 명시적으로 줬는데 안 빠졌다" → day1 탈락자 환급 0이 본인 선택이 됨
// ============================================================

#[test]
fun test_withdraw_in_pending_returns_full_stake() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);

    assert!(withdraw_as(&mut scenario, C) == 10 * ONE_SUI); // 전액 반환

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::vault_value(&ch) == 20 * ONE_SUI);   // 30 − 10
    assert!(challenge::participant_count(&ch) == 2);        // Table/vector 정합성
    assert!(challenge::status(&ch) == 0);                   // 여전히 PENDING
    ts::return_shared(ch);

    // 남은 2인으로 정상 진행되는지 (철회가 이후 정산을 오염시키지 않는가)
    submit_as(&mut scenario, ORACLE, vector[B]); // day1: B 탈락 (k=0, 환급 0, 몰수 10)
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    submit_as(&mut scenario, ORACLE, vector[]);
    finalize_as(&mut scenario, ORACLE);

    assert!(claim_as(&mut scenario, A) == 20 * ONE_SUI); // 원금 10 + B 몰수 10 전액 흡수

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::claimable_of(&ch, B) == 0); // day1 탈락 = k0 = 환급 0
    assert!(challenge::vault_value(&ch) == 0);     // 보존, dust 0
    ts::return_shared(ch);
    scenario.end();
}

#[test, expected_failure(abort_code = challenge::EWithdrawClosed)]
fun test_withdraw_after_first_submit_fails() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    submit_as(&mut scenario, ORACLE, vector[]); // 첫 제출 = 돈이 잠기는 순간 (PENDING→ACTIVE)
    withdraw_as(&mut scenario, C);              // abort
    scenario.end();
}

#[test]
fun test_rejoin_after_withdraw() {
    let mut scenario = ts::begin(ORACLE);
    setup_abc(&mut scenario, 5, ALPHA_LINEAR);
    withdraw_as(&mut scenario, C);
    join_as(&mut scenario, C, 10 * ONE_SUI); // 철회 후 재참여 — 중복참여 가드와 충돌하지 않아야

    scenario.next_tx(ORACLE);
    let ch = scenario.take_shared<Challenge>();
    assert!(challenge::participant_count(&ch) == 3);
    assert!(challenge::vault_value(&ch) == 30 * ONE_SUI);
    assert!(challenge::start_day_of(&ch, C) == 1); // PENDING 재참여는 정식 참여(start_day=1)
    ts::return_shared(ch);
    scenario.end();
}
