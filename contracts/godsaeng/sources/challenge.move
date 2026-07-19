/// 갓생 내기 — 돈 정산 로직 프로토타입 (PROTO_SPEC.md)
/// ver3: 가변 베팅 + 볼록결합 환급 커브 + 스트리밍(베스팅) 일일정산
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

// === 상태 ===
const STATUS_ACTIVE: u8 = 0;
const STATUS_ENDED: u8 = 1;

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
    /// ver4(중도 참여)용. ver1에선 항상 1
    start_day: u64,
    /// 0 = 생존 중, n = day n에 탈락
    failed_day: u64,
    /// 정산 누적액 — pull 패턴: 컨트랙트가 보내주지 않고 각자 claim으로 찾아감
    claimable: u64,
}

// === 정산 수식 (순수 함수 — 상태 접근 없음, 테스트 = 수식 검산) ===

/// day d 탈락자의 환급액 (MIST). 볼록결합 커브 (설계 근거: CURVE_DESIGN §6):
///   r(d) = α·(d/D) + (1−α)·(d/D)²,  α = alpha_bp/10000
/// α<1이면 "늦게 탈락할수록 더 챙김" + "하루 더 버티는 가치가 뒤로 갈수록 커짐" 동시 성립.
///
/// 정수 연산 변형: 통분해서 소수·분수 제거, 나눗셈은 마지막 1회 (절단 오차 최소화)
///   환급 = stake × [alpha_bp·d·D + (10000−alpha_bp)·d²] / (10000·D²)
/// 분자가 u64 상한(~1.8e19) 근접 → u128 누적 필수.
///
/// ⚠️ PLACEHOLDER: alpha_bp 값은 회의 후 확정 (권장 탐색 [2000, 4000], 임시 10000=순수 선형)
public fun calc_refund(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    let numer = (stake as u128)
        * ((alpha_bp as u128) * (d as u128) * (total_days as u128)
            + ((10000 - alpha_bp) as u128) * (d as u128) * (d as u128));
    let denom = 10000 * (total_days as u128) * (total_days as u128);
    (numer / denom) as u64
}

/// day d 탈락자의 몰수액 = stake − 환급 (보존: 환급 + 몰수 = stake)
public fun calc_forfeit(stake: u64, d: u64, total_days: u64, alpha_bp: u64): u64 {
    stake - calc_refund(stake, d, total_days, alpha_bp)
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
        vault: balance::zero(),
        participants: table::new(ctx),
        participant_list: vector[],
        status: STATUS_ACTIVE,
    };
    transfer::share_object(ch);
}

/// 예치하고 참여. Coin<SUI> 객체 자체를 받아 vault에 합친다 —
/// Move에서 돈은 리소스라 인자로 받은 순간 이 함수가 소유권을 넘겨받고,
/// 어딘가에 반드시 넣어야(join) 컴파일이 된다 (증발 불가).
public fun join(ch: &mut Challenge, stake: Coin<SUI>, ctx: &TxContext) {
    assert!(ch.current_day == 0, EJoinClosed); // 시작 후 참여는 ver4에서
    let sender = ctx.sender();
    assert!(!ch.participants.contains(sender), EAlreadyJoined);
    // ver2: 가변 베팅 — 금액은 자유, 단 0원(지분 0 무임승차)은 거부
    let amount = stake.value();
    assert!(amount > 0, EZeroStake);

    ch.vault.join(stake.into_balance());
    ch.participants.add(sender, Participant {
        stake: amount,
        start_day: 1,
        failed_day: 0,
        claimable: 0,
    });
    ch.participant_list.push_back(sender);
}

/// 그날 탈락자 명단 제출 — 오라클 전용, 호출 1회 = day 1일 진행.
/// 운영 규칙: 탈락자가 없는 날도 빈 vector로 반드시 호출해야 한다
/// (총 D회 호출이 종료의 전제 — 수동 day 카운터라 호출 = day 진행).
public fun submit_results(ch: &mut Challenge, failed: vector<address>, ctx: &TxContext) {
    assert!(ctx.sender() == ch.oracle, ENotOracle);
    assert!(ch.status == STATUS_ACTIVE, EAlreadyEnded); // 전멸 조기종료 후 호출 차단
    assert!(ch.current_day < ch.total_days, EAllDaysSubmitted);
    ch.current_day = ch.current_day + 1;
    let d = ch.current_day;

    // ① 오늘 탈락 기록 + 몰수분 스트림 편입.
    //    분배(③)보다 먼저 해야 "그날 탈락자는 그날 배당 제외" 규칙이 성립
    failed.do!(|addr| {
        assert!(ch.participants.contains(addr), ENotParticipant);
        let p = ch.participants.borrow_mut(addr);
        assert!(p.failed_day == 0, EAlreadyFailed); // 재제출 = 정산 오염 차단
        p.failed_day = d;
        // 몰수액을 day d ~ D의 (D−d+1)일에 걸쳐 균등 방출.
        // 스트림 편입 시점에 1회 절단 (스펙 §1-3 규약 — 테스트 기대값의 전제)
        let forfeit = calc_forfeit(p.stake, d, ch.total_days, ch.alpha_bp);
        ch.daily_drip = ch.daily_drip + forfeit / (ch.total_days - d + 1);
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
        // 미방출 스트림 잔액은 vault 잔류 (dust 취급, 보존 테스트에서 별도 항)
        ch.status = STATUS_ENDED;
        list.do_ref!(|addr| {
            let p = ch.participants.borrow_mut(*addr);
            p.claimable =
                p.claimable + calc_refund(p.stake, p.failed_day, ch.total_days, ch.alpha_bp);
        });
    } else {
        // ③ 오늘의 방출량을 생존자에게 지분 비례 적립 (곱셈 먼저·u128, floor 잔여는 dust)
        let drip = ch.daily_drip;
        list.do_ref!(|addr| {
            let p = ch.participants.borrow_mut(*addr);
            if (p.failed_day == 0) {
                let share = (
                    (drip as u128) * (p.stake as u128) / (survivor_stake_sum as u128)
                ) as u64;
                p.claimable = p.claimable + share;
            };
        });
    };
}

/// 종료 처리 + 정산액 계산. 돈은 안 움직이고 각자의 claimable에 숫자만 기록.
/// 가드: D회 제출 완료 전 종료 금지 (ver3에선 스트림 완납 전 종료 = 보존 법칙 붕괴).
/// 결과가 결정적이라 오라클 제한 없이 누구나 호출 가능.
public fun finalize(ch: &mut Challenge) {
    assert!(ch.status == STATUS_ACTIVE, EAlreadyEnded); // claimable 중복 적립 차단
    assert!(ch.current_day == ch.total_days, EChallengeNotOver);
    ch.status = STATUS_ENDED;

    // 배당은 submit_results에서 매일 적립돼 있음 (스트리밍).
    // 여기선 성공자 원금 + 탈락자 커브 환급만 claimable에 합산.
    // 전원 탈락(전멸)은 submit_results가 조기 ENDED로 처리 — 여기 도달 시 생존자 ≥ 1
    let list = ch.participant_list;
    list.do_ref!(|addr| {
        let p = ch.participants.borrow_mut(*addr);
        if (p.failed_day == 0) {
            p.claimable = p.claimable + p.stake; // 성공자: 원금 반환
        } else {
            // 탈락자: 커브 환급 (진행 중 현금화 차단 — claim 자체가 ENDED에서만 가능)
            p.claimable =
                p.claimable + calc_refund(p.stake, p.failed_day, ch.total_days, ch.alpha_bp);
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
