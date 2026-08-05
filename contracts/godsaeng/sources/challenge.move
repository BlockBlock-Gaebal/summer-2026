/// 갓생 내기 — 돈 정산 로직 프로토타입 (PROTO_SPEC.md)
/// ver4: 가변 베팅 + 볼록결합 환급 커브 + 스트리밍 일일정산 + 중도 참여(acc_per_share)
///
/// 프로토 스코프: Clock/시간검증 없음. 오라클(= 방 생성자)이 submit_results를
/// 수동 호출할 때마다 day가 +1 되는 수동 day 카운터 방식.
module godsaeng::challenge;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::table::{Self, Table};

// === 에러 코드 ===
const EZeroStake: u64 = 0;
const EAlreadyJoined: u64 = 1;
const EJoinClosed: u64 = 2;
const ENotOracle: u64 = 3;
const ENotParticipant: u64 = 4;
const EAlreadyFailed: u64 = 5;
const EAllDaysSubmitted: u64 = 6;
const EChallengeNotOver: u64 = 7;
const EAlreadyEnded: u64 = 8;
const ENotEnded: u64 = 9;
const ENothingToClaim: u64 = 10;
const EInvalidAlpha: u64 = 11;
const EWithdrawClosed: u64 = 12;

// === 상태 ===
/// [D-08] 첫 결과 제출 전. 돈이 아직 잠기지 않아 join/withdraw 자유
const STATUS_PENDING: u8 = 0;
const STATUS_ACTIVE: u8 = 1;
const STATUS_ENDED: u8 = 2;

/// [ver4] acc_per_share 배율. "stake 1 MIST가 받았어야 할 배당"은 1 MIST보다
/// 훨씬 작은 소수라, 1e12를 곱해 u128 정수로 들고 다니다 정산 때 1회 나눠 내린다
const SCALE: u128 = 1_000_000_000_000;

/// 챌린지 방 하나 = shared object 하나.
/// 누구나 트랜잭션에서 참조할 수 있어야 하므로 (여러 유저가 join)
/// owned object가 아니라 shared object로 만든다.
public struct Challenge has key {
    id: UID,
    /// 결과 제출 권한자. 프로토에선 방 생성자 = 오라클 (수동 호출)
    oracle: address,
    /// 환급 커브 파라미터 α (basis point, 0~10000).
    /// ⚠️ PLACEHOLDER: 회의 후 확정 (권장 탐색 [2000, 4000], 임시 10000=순수 선형)
    alpha_bp: u64,
    total_days: u64,
    /// 0 = 시작 전. submit_results마다 +1
    current_day: u64,
    /// [ver3] 전역 일일 방출량 (MIST). 몰수 발생 시에만 증가 (단조증가).
    /// 모든 스트림의 종점이 total_days로 같아서 변수 하나로 O(1) 관리 가능
    daily_drip: u64,
    /// [ver4] "챌린지 시작부터 지금까지 stake 1 MIST가 받았어야 할 배당 누적치"
    /// (×SCALE). 매일 acc += drip×SCALE/생존자지분합.
    /// 개인 배당 = stake × (acc_정산시점 − acc_참여시점) / SCALE — 참여 시점의
    /// acc를 스냅샷해 빼므로 진입 이전 배당 제외가 수학적으로 자동 보장
    /// (Aave/MasterChef 정석 패턴)
    acc_per_share: u128,
    /// 예치금 전부 보관. Coin이 아니라 Balance인 이유:
    /// Coin은 UID를 가진 "지갑 속 낱개 객체", Balance는 다른 객체 안에
    /// 품어두는 잔액 타입 — vault처럼 내부 보관엔 Balance가 정석
    vault: Balance<SUI>,
    participants: Table<address, Participant>,
    /// Table은 키 순회 불가 → 정산 때 돌기 위한 순회용 vector 병행 유지
    participant_list: vector<address>,
    status: u8,
}

public struct Participant has store {
    /// 예치액 (MIST)
    stake: u64,
    /// [ver4] 참여 시작 day. 시작 전 참여 = 1, day d 진행 후 참여 = d+1
    start_day: u64,
    /// [ver4] 참여 시점의 acc_per_share 스냅샷 — 이전 배당 제외의 기준점
    acc_entry: u128,
    /// 0 = 생존 중, n = day n에 탈락
    failed_day: u64,
    /// 정산 누적액 — pull 패턴: 컨트랙트가 보내주지 않고 각자 claim으로 찾아감
    claimable: u64,
}

// === 정산 수식 (순수 함수 — 상태 접근 없음, 테스트 = 수식 검산) ===

/// day d 탈락자의 환급액 (MIST). 볼록결합 커브 (설계 근거: CURVE_DESIGN §6):
///   r(k) = α·(k/D) + (1−α)·(k/D)²,  α = alpha_bp/10000
/// α<1이면 "늦게 탈락할수록 더 챙김" + "하루 더 버티는 가치가 뒤로 갈수록 커짐" 동시 성립.
///
/// [D-05] 커브의 입력은 탈락일 d가 아니라 **완주일수 k = d − 1**이다.
/// day d에 탈락한 사람이 실제로 성공한 날은 day 1 ~ d−1의 (d−1)일이다.
/// d를 그대로 쓰면 탈락한 그 날까지 크레딧이 들어가고, 그 오차가 d = D에서
/// "실패했는데 완주자와 동일한 전액 환급"으로 터진다 (= 마지막 날 무임승차).
/// k로 옮기면 생존 임금이 전 구간에서 단조증가하고, day1 탈락자 환급은 0이 된다.
///
/// 부수 성질: α=1일 때 몰수 = s(D−k)/D, 스트림 길이 = D−d+1 = D−k 이므로
/// 일일 drip 증가분이 탈락 시점과 무관하게 정확히 s/D로 일정하다 (새 인덱싱에서만 성립).
///
/// 정수 연산 변형: 통분해서 소수·분수 제거, 나눗셈은 마지막 1회 (절단 오차 최소화)
///   환급 = stake × [alpha_bp·k·D + (10000−alpha_bp)·k²] / (10000·D²)
/// 분자가 u64 상한(~1.8e19) 근접 → u128 누적 필수.
///
/// alpha_bp 확정값: 2000 (D-06). 완주자는 이 함수를 타지 않고 finalize에서 원금 전액을 받는다.
public fun calc_refund(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    // [D-05] 완주일수로 변환. d=0(미탈락 표식)이 들어오는 경로는 없어야 하나 방어적으로 처리
    let k = if (d == 0) { 0 } else { d - 1 };
    let numer = (stake as u128)
        * ((alpha_bp as u128) * (k as u128) * (total_days as u128)
            + ((10000 - alpha_bp) as u128) * (k as u128) * (k as u128));
    let denom = 10000 * (total_days as u128) * (total_days as u128);
    (numer / denom) as u64
}

/// day d 탈락자의 몰수액 = stake − 환급 (보존: 환급 + 몰수 = stake)
public fun calc_forfeit(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    stake - calc_refund(stake, d, total_days, alpha_bp)
}

/// [ver4] 중도 참여자의 커브는 개인 타임라인 기준.
/// ⚠️ 임시 규칙 T-03 (중도참여자의 D 정의는 후속 과제):
///   d_개인 = failed_day − start_day + 1, D_개인 = total_days − start_day + 1
/// calc_refund가 내부에서 k = d − 1로 변환하므로 개인 완주일수는
/// k_개인 = failed_day − start_day 가 되어 [D-05]가 그대로 적용된다.
/// start_day=1이면 ver3 커브와 정확히 일치 (자연스러운 일반화)
fun personal_refund(stake: u64, start_day: u64, failed_day: u64, total_days: u64, alpha_bp: u64): u64 {
    calc_refund(stake, failed_day - start_day + 1, total_days - start_day + 1, alpha_bp)
}

/// [ver4] 미정산 배당 = stake × (acc_지금 − acc_참여시점) / SCALE.
/// 곱셈 먼저 u128, 나눗셈(SCALE 내리기)은 마지막 1회
fun pending_dividend(stake: u64, acc_entry: u128, acc_now: u128): u64 {
    ((stake as u128) * (acc_now - acc_entry) / SCALE) as u64
}

/// 챌린지 방 생성. 호출자가 오라클이 된다.
public fun create_challenge(total_days: u64, alpha_bp: u64, ctx: &mut TxContext) {
    assert!(alpha_bp <= 10000, EInvalidAlpha);
    let ch = Challenge {
        id: object::new(ctx),
        oracle: ctx.sender(),
        alpha_bp,
        total_days,
        current_day: 0,
        daily_drip: 0,
        acc_per_share: 0,
        vault: balance::zero(),
        participants: table::new(ctx),
        participant_list: vector[],
        // [D-08] 첫 submit_results 전까지는 돈이 잠기지 않는다
        status: STATUS_PENDING,
    };
    transfer::share_object(ch);
}

/// 예치하고 참여. Coin<SUI> 객체 자체를 받아 vault에 합친다 —
/// Move에서 돈은 리소스라 인자로 받은 순간 이 함수가 소유권을 넘겨받고,
/// 어딘가에 반드시 넣어야(join) 컴파일이 된다 (증발 불가).
public fun join(ch: &mut Challenge, stake: Coin<SUI>, ctx: &TxContext) {
    // join은 status에 따라 의미가 둘로 갈린다 (D-08 + ver4):
    //   PENDING 중 join = 정식 참여 (start_day = 1). withdraw로 철회 가능
    //   ACTIVE  중 join = 중도 참여 (start_day = current_day + 1). 철회 불가 —
    //                     이미 스트림이 흐르고 있어 자발적 이탈은 별도 설계 영역(로드맵)
    // ⚠️ 참여 마감선 τ는 후속 과제 — 확정 시 파라미터화
    assert!(ch.status != STATUS_ENDED && ch.current_day < ch.total_days, EJoinClosed);
    let sender = ctx.sender();
    assert!(!ch.participants.contains(sender), EAlreadyJoined);
    // ver2: 가변 베팅 — 금액은 자유, 단 0원(지분 0 무임승차)은 거부
    let amount = stake.value();
    assert!(amount > 0, EZeroStake);

    ch.vault.join(stake.into_balance());
    ch.participants.add(sender, Participant {
        stake: amount,
        // day d까지 진행된 방에 들어오면 day d+1부터가 내 챌린지
        start_day: ch.current_day + 1,
        // 지금까지의 acc를 스냅샷 → 이전 배당은 (acc − acc_entry) 뺄셈에서 자동 제외
        acc_entry: ch.acc_per_share,
        failed_day: 0,
        claimable: 0,
    });
    ch.participant_list.push_back(sender);
}

/// [D-08] 참여 철회 — PENDING(첫 결과 제출 전)에서만 가능. 예치금 전액을 돌려받는다.
///
/// 이 구간이 있어야 grace 0(무관용)이 정당해진다: "빠질 기회를 명시적으로 줬는데
/// 안 빠졌다"가 되므로 day1 탈락자의 환급 0이 가혹함이 아니라 본인 선택이 된다.
/// 펀드의 청약 기간 / 소비자법의 청약 철회기간에 해당하는 구조.
///
/// Participant는 drop 능력이 없는 struct이므로 remove 후 반드시 분해(destructure)해야
/// 컴파일된다 — Move가 "상태를 슬쩍 버리는" 실수를 언어 차원에서 막는 지점.
public fun withdraw(ch: &mut Challenge, ctx: &mut TxContext): Coin<SUI> {
    assert!(ch.status == STATUS_PENDING, EWithdrawClosed);
    let sender = ctx.sender();
    assert!(ch.participants.contains(sender), ENotParticipant);

    let Participant { stake, start_day: _, acc_entry: _, failed_day: _, claimable: _ } =
        ch.participants.remove(sender);

    // Table과 vector의 정합성 유지 — 반드시 둘 다 제거한다.
    // swap_remove는 O(1)이지만 순서가 바뀐다. 순서 의존 로직이 없어 안전
    let (found, idx) = ch.participant_list.index_of(&sender);
    assert!(found, ENotParticipant);
    ch.participant_list.swap_remove(idx);

    coin::from_balance(ch.vault.split(stake), ctx)
}

/// 그날 탈락자 명단 제출 — 오라클 전용, 호출 1회 = day 1일 진행.
/// 운영 규칙: 탈락자가 없는 날도 빈 vector로 반드시 호출해야 한다
/// (총 D회 호출이 종료의 전제 — 수동 day 카운터라 호출 = day 진행).
public fun submit_results(ch: &mut Challenge, failed: vector<address>, ctx: &TxContext) {
    assert!(ctx.sender() == ch.oracle, ENotOracle);
    assert!(ch.status != STATUS_ENDED, EAlreadyEnded); // 전멸 조기종료 후 호출 차단
    assert!(ch.current_day < ch.total_days, EAllDaysSubmitted);
    // [D-08] 첫 제출 = 돈이 잠기는 순간. 이후 withdraw 불가
    if (ch.status == STATUS_PENDING) { ch.status = STATUS_ACTIVE; };
    ch.current_day = ch.current_day + 1;
    let d = ch.current_day;

    // ① 오늘 탈락 기록 + 배당 정산 + 몰수분 스트림 편입.
    //    acc 갱신(③)보다 먼저, "갱신 전 acc"로 정산해야
    //    "그날 탈락자는 그날 배당 제외" 규칙이 성립
    let acc_before = ch.acc_per_share;
    failed.do!(|addr| {
        assert!(ch.participants.contains(addr), ENotParticipant);
        let p = ch.participants.borrow_mut(addr);
        assert!(p.failed_day == 0, EAlreadyFailed); // 재제출 = 정산 오염 차단
        p.failed_day = d;
        // 생존 기간에 쌓인 배당을 지금 확정 (이후 acc가 올라도 못 받음)
        p.claimable = p.claimable + pending_dividend(p.stake, p.acc_entry, acc_before);
        // 몰수액을 day d ~ D의 (D−d+1)일에 걸쳐 균등 방출.
        // 스트림 편입 시점에 1회 절단 (스펙 §1-3 규약 — 테스트 기대값의 전제)
        let refund = personal_refund(p.stake, p.start_day, d, ch.total_days, ch.alpha_bp);
        ch.daily_drip = ch.daily_drip + (p.stake - refund) / (ch.total_days - d + 1);
    });

    // ② 오늘 기준 생존자 지분합 (Table 순회 불가 → vector로 그날그날 계산)
    let list = ch.participant_list;
    let mut survivor_stake_sum = 0;
    list.do_ref!(|addr| {
        let p = ch.participants.borrow(*addr);
        if (p.failed_day == 0) {
            survivor_stake_sum = survivor_stake_sum + p.stake;
        };
    });

    if (survivor_stake_sum == 0) {
        // ⚠️ 전멸 임시 규칙 (스펙 §4, 회의 확정 대기): 최후 생존자들이 동시 탈락하면
        // 잔여 스트림의 수령자가 없음 → 조기 ENDED + 탈락자 커브 환급만 확정.
        // (배당은 ①에서 이미 정산됨) 미방출 스트림 잔액은 vault 잔류 (dust 취급)
        ch.status = STATUS_ENDED;
        list.do_ref!(|addr| {
            let p = ch.participants.borrow_mut(*addr);
            p.claimable = p.claimable
                + personal_refund(p.stake, p.start_day, p.failed_day, ch.total_days, ch.alpha_bp);
        });
    } else {
        // ③ 오늘의 방출량을 "지분당 누적 배당"에 반영 — 개인별 순회 적립 대신 O(1).
        // 개인 몫은 탈락/종료 시점에 (acc − acc_entry)로 일괄 정산 (절단도 그때 1회)
        ch.acc_per_share =
            ch.acc_per_share + (ch.daily_drip as u128) * SCALE / (survivor_stake_sum as u128);
    };
}

/// 종료 처리 + 정산액 계산. 돈은 안 움직이고 각자의 claimable에 숫자만 기록.
/// 가드: D회 제출 완료 전 종료 금지 (ver3에선 스트림 완납 전 종료 = 보존 법칙 붕괴).
/// 결과가 결정적이라 오라클 제한 없이 누구나 호출 가능.
public fun finalize(ch: &mut Challenge) {
    assert!(ch.status != STATUS_ENDED, EAlreadyEnded); // claimable 중복 적립 차단
    // PENDING(한 번도 제출 안 됨)은 current_day=0이라 아래 가드에서 걸린다
    assert!(ch.current_day == ch.total_days, EChallengeNotOver);
    ch.status = STATUS_ENDED;

    // 전원 탈락(전멸)은 submit_results가 조기 ENDED로 처리 — 여기 도달 시 생존자 ≥ 1
    let list = ch.participant_list;
    let acc = ch.acc_per_share;
    list.do_ref!(|addr| {
        let p = ch.participants.borrow_mut(*addr);
        if (p.failed_day == 0) {
            // 성공자: 누적 배당 정산 + 원금 반환
            p.claimable = p.claimable + pending_dividend(p.stake, p.acc_entry, acc) + p.stake;
        } else {
            // 탈락자: 커브 환급 (배당은 탈락 당일 이미 정산. claim 자체가 ENDED에서만 가능)
            p.claimable = p.claimable
                + personal_refund(p.stake, p.start_day, p.failed_day, ch.total_days, ch.alpha_bp);
        };
    });
}

/// pull 패턴 정산: 각자 자기 몫을 Coin으로 찾아간다 (일괄 분배 루프 금지).
/// claimable을 0으로 리셋한 뒤 인출하므로 이중 claim은 ENothingToClaim으로 abort.
public fun claim(ch: &mut Challenge, ctx: &mut TxContext): Coin<SUI> {
    assert!(ch.status == STATUS_ENDED, ENotEnded); // 진행 중 현금화 차단
    let sender = ctx.sender();
    assert!(ch.participants.contains(sender), ENotParticipant);

    let p = ch.participants.borrow_mut(sender);
    assert!(p.claimable > 0, ENothingToClaim);
    let amount = p.claimable;
    p.claimable = 0;
    coin::from_balance(ch.vault.split(amount), ctx)
}

// === 조회 (테스트/FE용) ===
public fun vault_value(ch: &Challenge): u64 { ch.vault.value() }

public fun participant_count(ch: &Challenge): u64 { ch.participant_list.length() }

public fun current_day(ch: &Challenge): u64 { ch.current_day }

public fun failed_day_of(ch: &Challenge, who: address): u64 {
    ch.participants.borrow(who).failed_day
}

public fun claimable_of(ch: &Challenge, who: address): u64 {
    ch.participants.borrow(who).claimable
}

public fun stake_of(ch: &Challenge, who: address): u64 {
    ch.participants.borrow(who).stake
}

public fun start_day_of(ch: &Challenge, who: address): u64 {
    ch.participants.borrow(who).start_day
}

// --- 대시보드(읽기 전용 FE)용 조회 ---
/// 0 = PENDING, 1 = ACTIVE, 2 = ENDED
public fun status(ch: &Challenge): u8 { ch.status }

public fun total_days(ch: &Challenge): u64 { ch.total_days }

public fun alpha_bp(ch: &Challenge): u64 { ch.alpha_bp }

public fun daily_drip(ch: &Challenge): u64 { ch.daily_drip }

/// 참가자 주소 전체. FE는 이걸 받아 주소별로 stake/failed_day/claimable을 조회한다
public fun participant_addresses(ch: &Challenge): vector<address> { ch.participant_list }
