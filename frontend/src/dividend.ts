// src/dividend.ts

/**
 * 미실현 배당 (pending dividend) — 표시 전용 파생값 (D-19)
 *
 * ─────────────────────────────────────────────────────────────────────
 * 왜 필요한가
 * ─────────────────────────────────────────────────────────────────────
 * 컨트랙트는 생존자의 배당을 매일 개인별로 적립하지 않는다. 전역 누적치
 * `acc_per_share` 하나만 굴리고(O(1)), 개인 몫은 **탈락 시점 또는 finalize
 * 시점에 한 번** `claimable`로 정산한다 (challenge.move의 pending_dividend).
 *
 * 그래서 챌린지가 진행 중(ACTIVE)인 동안 생존자의 `claimable`은 계속 0이다.
 * 화면만 보면 선두 주자와 day1 전액 몰수자가 똑같이 0.00000 SUI로 보인다.
 * MasterChef 계열이 `pendingReward()` 뷰를 따로 두는 것과 같은 문제이고,
 * 해법도 같다 — 적립은 나중에 하되, 화면에는 미실현분을 계산해서 보여준다.
 *
 * 돈이 움직이는 계산이 아니므로 컨트랙트에 뷰 함수를 추가하지 않고
 * 프론트에서 계산한다 (D-19).
 */

/**
 * acc_per_share 배율.
 *
 * 출처: `contracts/godsaeng/sources/challenge.move`의 상수 `SCALE`
 *   `const SCALE: u128 = 1_000_000_000_000;`
 *
 * "stake 1 MIST가 받았어야 할 배당"은 1 MIST보다 훨씬 작은 소수라,
 * 컨트랙트가 1e12를 곱한 정수로 들고 다니다 정산 때 1회 나눠 내린다.
 * 이 값이 컨트랙트와 어긋나면 배당이 조용히 1e12배 틀어지므로,
 * challenge.move를 고칠 일이 생기면 여기도 함께 본다.
 */
export const ACC_SCALE = 1_000_000_000_000n;

/**
 * 아직 claimable에 적립되지 않은 배당 (MIST)
 *
 * challenge.move의 `pending_dividend()` 미러다. 연산 순서까지 동일하게 맞춘다 —
 * **곱셈 먼저, 나눗셈(SCALE 내리기)은 마지막 1회.** 순서를 바꾸면 절단이 두 번
 * 일어나 온체인 값과 어긋난다 (CLAUDE.md §5-5).
 *
 * `acc_entry`는 참여 시점의 acc 스냅샷이라, 뺄셈만으로 "내가 들어오기 전에
 * 쌓인 배당"이 자동으로 제외된다 (중도 참여자도 별도 처리가 필요 없다).
 */
export function pendingDividend(
  stake: bigint,
  accEntry: bigint,
  accPerShare: bigint,
): bigint {
  // acc_per_share는 단조증가라 정상 상태에서는 accEntry를 밑돌 수 없다.
  // bigint 나눗셈은 음수도 조용히 0쪽으로 절단해버리므로 방어적으로 막는다
  if (accPerShare <= accEntry) return 0n;

  return (stake * (accPerShare - accEntry)) / ACC_SCALE;
}

/**
 * 화면에 무엇을 띄울지까지 정한 결과.
 *
 * 금액을 그대로 내보내지 않고 종류를 나누는 이유는 **이중 계상 오해를 막기
 * 위해서**다. 탈락자와 종료된 방의 참가자는 배당이 이미 `claimable` 안에
 * 들어가 있어서, 여기에 또 숫자를 찍으면 "따로 더 받는 돈"으로 읽힌다.
 */
export type PendingDividendView =
  /** 진행 중인 생존자 — 아직 적립되지 않은 배당. 0일 수 있다 */
  | { kind: 'accruing'; amount: bigint }
  /** 탈락자 — 생존 기간 배당은 탈락 당일 확정되어 이미 claimable 안에 있다 */
  | { kind: 'settledAtFail' }
  /** ENDED — finalize가 전원의 배당을 claimable로 적립한 뒤다 */
  | { kind: 'settledAtEnd' };

/**
 * 참가자 한 명의 미실현 배당 표시값을 정한다.
 *
 * `statusLabel`로 판정하는 이유: 온체인 status는 gRPC JSON에서 실수로
 * 직렬화되어 온다(0.0 / 1.0 / 2.0). read_state가 이미 라벨로 정규화해 두었으니
 * 그 라벨을 쓰고 숫자 비교는 하지 않는다.
 *
 * PENDING은 ACTIVE와 같은 경로를 탄다 — 첫 submit 전이라 acc_per_share가 0이고
 * 결과도 0이 되므로, 따로 분기할 필요가 없다.
 */
export function pendingDividendView(
  stake: bigint,
  accEntry: bigint,
  failedDay: bigint,
  accPerShare: bigint,
  statusLabel: string,
): PendingDividendView {
  if (statusLabel === 'ENDED') return { kind: 'settledAtEnd' };
  if (failedDay !== 0n) return { kind: 'settledAtFail' };

  return {
    kind: 'accruing',
    amount: pendingDividend(stake, accEntry, accPerShare),
  };
}
