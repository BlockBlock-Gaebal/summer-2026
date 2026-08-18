import {
  shortAddress,
  type ChallengeState,
  type ParticipantState,
} from './read_state';

type RefundCurveProps = {
  challenge: ChallengeState;
  participants: ParticipantState[];
};

const WIDTH = 760;
const HEIGHT = 360;

const LEFT = 70;
const RIGHT = 30;
const TOP = 40;
const BOTTOM = 60;

const PLOT_WIDTH = WIDTH - LEFT - RIGHT;
const PLOT_HEIGHT = HEIGHT - TOP - BOTTOM;

const BP_DENOMINATOR = 10000n;

/**
 * 완주일수 k에 대한 환급률을 basis point로 계산.
 *
 * R(k)
 * = alpha * (k / D)
 * + (1 - alpha) * (k / D)^2
 *
 * 부동소수 계산 없이 bigint로 유지한다.
 */
function refundRateBp(
  k: bigint,
  totalDays: bigint,
  alphaBp: bigint,
): bigint {
  if (totalDays === 0n) return 0n;

  const numerator =
    alphaBp * k * totalDays +
    (BP_DENOMINATOR - alphaBp) * k * k;

  return numerator / (totalDays * totalDays);
}

/**
 * 부드러운 SVG 곡선을 만들기 위한 정규화된 샘플.
 * 계산 자체는 bigint로 한다.
 */
function refundRateBpAtStep(
  step: number,
  totalSteps: number,
  alphaBp: bigint,
): bigint {
  const s = BigInt(step);
  const steps = BigInt(totalSteps);

  const numerator =
    alphaBp * s * steps +
    (BP_DENOMINATOR - alphaBp) * s * s;

  return numerator / (steps * steps);
}

function xFromProgress(progress: number) {
  return LEFT + progress * PLOT_WIDTH;
}

function yFromBp(bp: bigint) {
  const rate = Number(bp) / 10000;

  return TOP + (1 - rate) * PLOT_HEIGHT;
}

function xFromK(k: bigint, totalDays: bigint) {
  if (totalDays === 0n) return LEFT;

  return xFromProgress(
    Number(k) / Number(totalDays),
  );
}

function formatRate(bp: bigint) {
  const whole = bp / 100n;
  const fraction = bp % 100n;

  if (fraction === 0n) {
    return `${whole}%`;
  }

  return `${whole}.${fraction
    .toString()
    .padStart(2, '0')
    .replace(/0$/, '')}%`;
}

/**
 * 탈락자는 failedDay - 1.
 *
 * ENDED 상태에서 failedDay === 0이면 완주자이므로 D.
 *
 * 진행 중인 방의 생존자는 현재 진행된 day 위치에 표시한다.
 * (이 부분은 라이브 방에서의 시각화 편의를 위한 UI 처리)
 */
function completedDays(
  participant: ParticipantState,
  challenge: ChallengeState,
) {
  if (participant.failedDay !== 0n) {
    return participant.failedDay - 1n;
  }

  if (challenge.statusLabel === 'ENDED') {
    return challenge.totalDays;
  }

  return challenge.currentDay > challenge.totalDays
    ? challenge.totalDays
    : challenge.currentDay;
}

export default function RefundCurve({
  challenge,
  participants,
}: RefundCurveProps) {
  const totalDays = challenge.totalDays;
  const alphaBp = challenge.alphaBp;

  const totalSteps = 50;

  const curvePoints = Array.from(
    { length: totalSteps + 1 },
    (_, step) => {
      const progress = step / totalSteps;

      const bp = refundRateBpAtStep(
        step,
        totalSteps,
        alphaBp,
      );

      const x = xFromProgress(progress);
      const y = yFromBp(bp);

      return `${x},${y}`;
    },
  ).join(' ');

  /**
   * 같은 k를 가진 참가자는 좌표가 완전히 일치한다
   * (환급률이 k만의 함수이므로 x도 y도 같다).
   *
   * 그대로 그리면 점·라벨·퍼센트가 겹쳐서
   * "A"와 "C"가 "Å"처럼, "20.8%" 두 개가 "28.8%"처럼 읽힌다.
   *
   * 그래서 k로 묶어 점 하나만 찍고,
   * 라벨은 "A · C"로 합치고 퍼센트는 한 번만 쓴다.
   * 참가자가 몇 명으로 늘어도 점 개수는 서로 다른 k의 개수만큼만 늘어난다.
   */
  const groupedPoints = (() => {
    const byK = new Map<
      string,
      {
        k: bigint;
        bp: bigint;
        x: number;
        y: number;
        labels: string[];
        members: ParticipantState[];
      }
    >();

    participants.forEach((participant, index) => {
      const k = completedDays(
        participant,
        challenge,
      );

      const key = String(k);
      const label = String.fromCharCode(65 + index);

      const existing = byK.get(key);

      if (existing) {
        existing.labels.push(label);
        existing.members.push(participant);
        return;
      }

      const bp = refundRateBp(
        k,
        totalDays,
        alphaBp,
      );

      byK.set(key, {
        k,
        bp,
        x: xFromK(k, totalDays),
        y: yFromBp(bp),
        labels: [label],
        members: [participant],
      });
    });

    return Array.from(byK.values()).sort(
      (a, b) => (a.k < b.k ? -1 : a.k > b.k ? 1 : 0),
    );
  })();

  const dayTicks = Array.from(
    { length: Number(totalDays) + 1 },
    (_, day) => day,
  );

  const yTicks = [
    { bp: 0n, label: '0%' },
    { bp: 2500n, label: '25%' },
    { bp: 5000n, label: '50%' },
    { bp: 7500n, label: '75%' },
    { bp: 10000n, label: '100%' },
  ];

  return (
    <section
      style={{
        marginTop: 32,
        marginBottom: 32,
      }}
    >
      <h2>시간가중 환급 커브</h2>

      <p style={{ fontSize: 14 }}>
        오래 완주할수록 더 많은 원금을 돌려받습니다.
      </p>

      <svg
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        style={{
          width: '100%',
          maxWidth: WIDTH,
          display: 'block',
        }}
        role="img"
        aria-label="시간가중 환급률 커브"
      >
        {/* Y축 grid */}
        {yTicks.map(({ bp, label }) => {
          const y = yFromBp(bp);

          return (
            <g key={label}>
              <line
                x1={LEFT}
                y1={y}
                x2={WIDTH - RIGHT}
                y2={y}
                stroke="#e5e7eb"
                strokeWidth="1"
              />

              <text
                x={LEFT - 12}
                y={y + 4}
                textAnchor="end"
                fontSize="12"
                fill="#6b7280"
              >
                {label}
              </text>
            </g>
          );
        })}

        {/* X축 */}
        <line
          x1={LEFT}
          y1={HEIGHT - BOTTOM}
          x2={WIDTH - RIGHT}
          y2={HEIGHT - BOTTOM}
          stroke="#374151"
        />

        {/* Y축 */}
        <line
          x1={LEFT}
          y1={TOP}
          x2={LEFT}
          y2={HEIGHT - BOTTOM}
          stroke="#374151"
        />

        {/* X축 ticks */}
        {dayTicks.map((day) => {
          const x = xFromProgress(
            day / Number(totalDays),
          );

          return (
            <g key={day}>
              <line
                x1={x}
                y1={HEIGHT - BOTTOM}
                x2={x}
                y2={HEIGHT - BOTTOM + 6}
                stroke="#374151"
              />

              <text
                x={x}
                y={HEIGHT - BOTTOM + 22}
                textAnchor="middle"
                fontSize="12"
                fill="#6b7280"
              >
                {day}
              </text>
            </g>
          );
        })}

        {/* 환급 커브 */}
        <polyline
          points={curvePoints}
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeLinejoin="round"
          strokeLinecap="round"
        />

        {/* 참가자 점 — 같은 k는 한 점으로 묶여 있다 */}
        {groupedPoints.map(
          ({ k, bp, x, y, labels, members }) => {
            /* 라벨이 길어져도(A · B · C · D) 플롯 밖으로 나가지 않게
               가장자리에서는 기준점을 안쪽으로 돌린다 */
            const anchor =
              x < LEFT + 40
                ? 'start'
                : x > WIDTH - RIGHT - 40
                  ? 'end'
                  : 'middle';

            /* 점이 낮으면(k가 작으면) 아래쪽 퍼센트가 x축 선·눈금과 겹친다.
               그럴 때만 퍼센트를 라벨 위로 올린다 */
            const nearAxis = y + 24 > HEIGHT - BOTTOM - 6;

            const labelY = y - 14;
            const rateY = nearAxis ? y - 30 : y + 24;

            const tooltip = [
              members
                .map(
                  (member, i) =>
                    `${labels[i]} (${shortAddress(member.address)})`,
                )
                .join(', '),
              `k=${String(k)}`,
              formatRate(bp),
            ].join(' · ');

            return (
              <g key={String(k)}>
                <circle
                  cx={x}
                  cy={y}
                  r="7"
                  fill="white"
                  stroke="currentColor"
                  strokeWidth="3"
                >
                  <title>{tooltip}</title>
                </circle>

                <text
                  x={x}
                  y={labelY}
                  textAnchor={anchor}
                  fontSize="13"
                  fontWeight="700"
                >
                  {labels.join(' · ')}
                </text>

                <text
                  x={x}
                  y={rateY}
                  textAnchor={anchor}
                  fontSize="11"
                  fill="#6b7280"
                >
                  {formatRate(bp)}
                </text>
              </g>
            );
          },
        )}

        {/* X축 제목 */}
        <text
          x={LEFT + PLOT_WIDTH / 2}
          y={HEIGHT - 12}
          textAnchor="middle"
          fontSize="13"
          fill="#374151"
        >
          완주일수 k
        </text>

        {/* Y축 제목 */}
        <text
          x="18"
          y={TOP + PLOT_HEIGHT / 2}
          textAnchor="middle"
          fontSize="13"
          fill="#374151"
          transform={`rotate(-90 18 ${
            TOP + PLOT_HEIGHT / 2
          })`}
        >
          환급률
        </text>
      </svg>
    </section>
  );
}