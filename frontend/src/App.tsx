import { useEffect, useState } from 'react';
import {
  createSuiClient,
  readState,
  mistToSui,
  shortAddress,
  type ChallengeSnapshot,
} from './read_state';
import { calcRefund, refundRate } from './curve';
import {
  NETWORK,
  GRPC_URL,
  CHALLENGE_ID,
  POLL_INTERVAL,
} from './config';


const client = createSuiClient({
  network: NETWORK,
  url: GRPC_URL,
});

export default function App() {
  const [snap, setSnap] = useState<ChallengeSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const loadState = async () => {
      try {
        const nextSnap = await readState(client, CHALLENGE_ID);
        setSnap(nextSnap);
        setError(null);

        console.log('상태 갱신:', nextSnap);
      } catch (e) {
        console.error(e);
        setError(String(e));
      }
    };

    // 처음 페이지를 열었을 때 즉시 한 번 조회
    loadState();

    // 이후 5초마다 다시 조회
    const interval = setInterval(loadState, POLL_INTERVAL);

    // 컴포넌트가 사라질 때 polling 종료
    return () => clearInterval(interval);
  }, []);

  if (error && !snap) {
    return <pre>에러: {error}</pre>;
  }

  if (!snap) {
    return <p>불러오는 중...</p>;
  }

  const { challenge: c, participants } = snap;

  return (
    <div style={{ padding: 24, fontFamily: 'sans-serif' }}>
      <h1>갓생 내기</h1>

      <p>
        {c.statusLabel}
        {' · '}
        day {String(c.currentDay)} / {String(c.totalDays)}
        {' · '}
        vault {mistToSui(c.vault)} SUI
      </p>

      <table cellPadding={8}>
        <thead>
          <tr>
             <th align="left">주소</th>
             <th align="right">예치금</th>
             <th align="right">탈락일</th>
             <th align="right">환급률</th>
             <th align="right">환급 원금</th>
             <th align="right">claimable</th>
             <th align="left">상태</th>
          </tr>
        </thead>

        <tbody>
  {participants.map((p) => {
    const failed = p.failedDay !== 0n;

    const refund = failed
      ? calcRefund(
          p.stake,
          p.failedDay,
          c.totalDays,
          c.alphaBp,
        )
      : null;

    const rate = failed
      ? refundRate(
          p.failedDay,
          c.totalDays,
          c.alphaBp,
        )
      : null;

    return (
      <tr key={p.address}>
        <td>
          <code>{shortAddress(p.address)}</code>
        </td>

        <td align="right">
          {mistToSui(p.stake)} SUI
        </td>

        <td align="right">
          {failed
            ? `Day ${String(p.failedDay)}`
            : '—'}
        </td>

        <td align="right">
          {rate === null
            ? '—'
            : `${(rate * 100).toFixed(1)}%`}
        </td>

        <td align="right">
          {refund === null
            ? '—'
            : `${mistToSui(refund)} SUI`}
        </td>

        <td align="right">
          {mistToSui(p.claimable)} SUI
        </td>

        <td>
          {!failed
            ? '생존'
            : p.failedDay === 1n
              ? '전액 몰수'
              : `Day ${String(p.failedDay)} 탈락`}
        </td>
      </tr>
    );
  })}
</tbody>
      </table>

      <p style={{ marginTop: 20, fontSize: 12 }}>
        5초마다 Sui Testnet 상태를 자동으로 갱신합니다.
      </p>
    </div>
  );
}