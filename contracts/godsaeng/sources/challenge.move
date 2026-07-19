/// 갓생 내기 — 돈 정산 로직 프로토타입 (PROTO_SPEC.md)
/// ver1: 균등 베팅 + flat 몰수 + 성공자 균등 분배
///
/// 프로토 스코프: Clock/시간검증 없음. 오라클(= 방 생성자)이 submit_results를
/// 수동 호출할 때마다 day가 +1 되는 수동 day 카운터 방식.
module godsaeng::challenge;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::table::{Self, Table};

// === 에러 코드 ===
const EWrongStakeAmount: u64 = 0;
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
    /// ver1: 균등 베팅 — 방 생성 시 고정된 1인당 예치액 (MIST)
    stake_amount: u64,
    total_days: u64,
    /// 0 = 시작 전. submit_results마다 +1
    current_day: u64,
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

/// 챌린지 방 생성. 호출자가 오라클이 된다.
public fun create_challenge(stake_amount: u64, total_days: u64, ctx: &mut TxContext) {
    let ch = Challenge {
        id: object::new(ctx),
        oracle: ctx.sender(),
        stake_amount,
        total_days,
        current_day: 0,
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
    assert!(stake.value() == ch.stake_amount, EWrongStakeAmount);

    ch.vault.join(stake.into_balance());
    ch.participants.add(sender, Participant {
        stake: ch.stake_amount,
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
    assert!(ch.current_day < ch.total_days, EAllDaysSubmitted);
    ch.current_day = ch.current_day + 1;

    // 명단의 각 주소를 "오늘(current_day) 탈락"으로 기록
    failed.do!(|addr| {
        assert!(ch.participants.contains(addr), ENotParticipant);
        let p = ch.participants.borrow_mut(addr);
        assert!(p.failed_day == 0, EAlreadyFailed); // 재제출 = 정산 오염 차단
        p.failed_day = ch.current_day;
    });
}

/// 종료 처리 + 정산액 계산. 돈은 안 움직이고 각자의 claimable에 숫자만 기록.
/// 가드: D회 제출 완료 전 종료 금지 (ver3에선 스트림 완납 전 종료 = 보존 법칙 붕괴).
/// 결과가 결정적이라 오라클 제한 없이 누구나 호출 가능.
public fun finalize(ch: &mut Challenge) {
    assert!(ch.status == STATUS_ACTIVE, EAlreadyEnded); // claimable 중복 적립 차단
    assert!(ch.current_day == ch.total_days, EChallengeNotOver);
    ch.status = STATUS_ENDED;

    // 1차 순회: 몰수 총액 + 성공자 수 집계 (Table 순회 불가 → vector로)
    let list = ch.participant_list;
    let mut forfeit_total = 0;
    let mut survivor_count = 0;
    list.do_ref!(|addr| {
        let p = ch.participants.borrow(*addr);
        if (p.failed_day == 0) {
            survivor_count = survivor_count + 1;
        } else {
            forfeit_total = forfeit_total + p.stake;
        };
    });

    // 2차 순회: claimable 기록
    if (survivor_count == 0) {
        // 엣지: 전원 탈락 → 성공자 0으로 나누기 불가. 챌린지 불성립, 각자 원금 원위치
        list.do_ref!(|addr| {
            let p = ch.participants.borrow_mut(*addr);
            p.claimable = p.stake;
        });
    } else {
        // ver1 수식: 성공자 수령액 = stake + 몰수총액/성공자수 (floor, 나머지는 dust로 vault 잔류)
        // 전원 성공이면 forfeit_total = 0 → share = 0, 원금만 반환 (abort 없음)
        let share = forfeit_total / survivor_count;
        list.do_ref!(|addr| {
            let p = ch.participants.borrow_mut(*addr);
            if (p.failed_day == 0) {
                p.claimable = p.stake + share;
            };
        });
    };
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
