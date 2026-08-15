// src/curve.ts

/**
 * day d에 탈락한 참가자의 환급 원금 (MIST)
 *
 * failedDay === 0:
 * 아직 생존 중이거나 완주한 상태
 */
export function calcRefund(
  stake: bigint,
  failedDay: bigint,
  totalDays: bigint,
  alphaBp: bigint,
): bigint {
  if (failedDay === 0n) return stake;

  // day d 탈락 → 실제 완주일수 k = d - 1
  const k = failedDay - 1n;
  const D = totalDays;

  const numerator =
    alphaBp * k * D +
    (10000n - alphaBp) * k * k;

  return (stake * numerator) / (10000n * D * D);
}

/**
 * 표시용 환급률
 * 0 ~ 1
 */
export function refundRate(
  failedDay: bigint,
  totalDays: bigint,
  alphaBp: bigint,
): number {
  if (failedDay === 0n) return 1;

  const k = Number(failedDay - 1n);
  const D = Number(totalDays);
  const alpha = Number(alphaBp) / 10000;

  const x = k / D;

  return alpha * x + (1 - alpha) * x * x;
}