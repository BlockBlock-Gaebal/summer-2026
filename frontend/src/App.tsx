import { useEffect, useState } from 'react';
import {
  createSuiClient,
  readState,
  shortAddress,
  type ChallengeSnapshot,
} from './read_state';
import { calcRefund, refundRate } from './curve';
import { pendingDividendView } from './dividend';
import RefundCurve from './RefundCurve';
import {
  NETWORK,
  GRPC_URL,
  CHALLENGE_ID,
  POLL_INTERVAL,
} from './config';

import './App.css';

const client = createSuiClient({
  network: NETWORK,
  url: GRPC_URL,
});

const MIST_PER_SUI = 1_000_000_000n;

function formatSui(value: bigint, decimals = 5) {
  const whole = value / MIST_PER_SUI;
  const fraction = (value % MIST_PER_SUI)
    .toString()
    .padStart(9, '0')
    .slice(0, decimals);

  return `${whole}.${fraction}`;
}

export default function App() {
  const [snap, setSnap] = useState<ChallengeSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [lastOk, setLastOk] = useState<Date | null>(null);
  const [failCount, setFailCount] = useState(0);

  useEffect(() => {
    const loadState = async () => {
      try {
        const nextSnap = await readState(client, CHALLENGE_ID);

        setSnap(nextSnap);
        setError(null);
        setLastOk(new Date());
        setFailCount(0);
      } catch (e) {
        console.error(e);
        setError(String(e));
        setFailCount((count) => count + 1);
      }
    };

    loadState();

    const interval = setInterval(loadState, POLL_INTERVAL);

    return () => clearInterval(interval);
  }, []);

  if (error && !snap) {
    return (
      <main className="app-shell">
        <div className="error-screen">
          <strong>체인 데이터를 불러오지 못했습니다.</strong>
          <span>{error}</span>
        </div>
      </main>
    );
  }

  if (!snap) {
    return (
      <main className="app-shell">
        <div className="loading-screen">
          Sui Testnet에서 Challenge를 불러오는 중...
        </div>
      </main>
    );
  }

  const { challenge: c, participants, warnings } = snap;

  const progress =
    c.totalDays === 0n
      ? 0
      : Math.min(
          100,
          (Number(c.currentDay) / Number(c.totalDays)) * 100,
        );

  return (
    <main className="app-shell">

      {/* 연결 실패 */}
      {failCount >= 2 && (
        <div className="connection-warning">
          <strong>⚠ 체인 연결 끊김</strong>
          <span>아래 값은 마지막 정상 조회 시점의 데이터입니다.</span>
        </div>
      )}

      {/* read_state warnings */}
      {warnings.length > 0 && (
        <div className="data-warning">
          {warnings.map((warning) => (
            <div key={warning}>⚠ {warning}</div>
          ))}
        </div>
      )}

      {/* Header */}
      <header className="dashboard-header">
        <div>
          <div className="eyebrow">
            BLOCKBLOCK · SUI TESTNET
          </div>

          <h1>Locked In (갓생 내기)</h1>

          <p>
            Locked in. Paid out.
          </p>
        </div>

        <div
          className={
            failCount >= 2
              ? 'network-badge network-error'
              : 'network-badge'
          }
        >
          <span className="network-dot" />

          {failCount >= 2
            ? 'CONNECTION LOST'
            : 'LIVE'}
        </div>
      </header>

      {/* Stats */}
      <section className="stats-grid">

        <article className="stat-card">
          <span className="stat-label">
            STATUS
          </span>

          <strong className={`challenge-status status-${c.statusLabel.toLowerCase()}`}>
            {c.statusLabel}
          </strong>
        </article>

        <article className="stat-card">
          <span className="stat-label">
            CURRENT DAY
          </span>

          <strong>
            {String(c.currentDay)}
            <span className="stat-sub">
              {' '} / {String(c.totalDays)}
            </span>
          </strong>
        </article>

        <article className="stat-card">
          <span className="stat-label">
            TOTAL VAULT
          </span>

          <strong>
            {formatSui(c.vault, 4)}
            <span className="stat-sub"> SUI</span>
          </strong>
        </article>

        <article className="stat-card">
          <span className="stat-label">
            PARTICIPANTS
          </span>

          <strong>{participants.length}</strong>
        </article>

      </section>

      {/* Progress */}
      <section className="progress-card">

        <div className="section-header">
          <div>
            <span className="section-eyebrow">
              CHALLENGE PROGRESS
            </span>

            <strong>
              Day {String(c.currentDay)} of {String(c.totalDays)}
            </strong>
          </div>

          <strong>{progress.toFixed(0)}%</strong>
        </div>

        <div className="progress-track">
          <div
            className="progress-fill"
            style={{ width: `${progress}%` }}
          />
        </div>

      </section>

      {/* Curve */}
      <section className="dashboard-card curve-card">
        <RefundCurve
          challenge={c}
          participants={participants}
        />
      </section>

      {/* Participant Table */}
      <section className="dashboard-card">

        <div className="table-title">
          <div>
            <span className="section-eyebrow">
              PARTICIPANTS
            </span>

            <h2>참가자 현황</h2>
          </div>

          <span>
            {participants.length} participants
          </span>
        </div>

        <div className="table-wrapper">
          <table className="participant-table">

            <thead>
              <tr>
                <th>참가자</th>
                <th>주소</th>
                <th>예치금</th>
                <th>탈락일</th>
                <th>환급률</th>
                <th>환급 원금</th>
                <th title="아직 claimable에 적립되지 않은 생존 배당. 탈락·종료 시점에 claimable로 합쳐진다">
                  미실현 배당
                </th>
                <th>Claimable</th>
                <th>상태</th>
              </tr>
            </thead>

            <tbody>
              {participants.map((p, index) => {
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

                // 진행 중 생존자의 claimable은 계속 0이다 (적립이 탈락·finalize
                // 시점에 몰려 있다). 그 구간을 화면에서 메우는 값
                const dividend = pendingDividendView(
                  p.stake,
                  p.accEntry,
                  p.failedDay,
                  c.accPerShare,
                  c.statusLabel,
                );

                let statusLabel = '생존';
                let statusClass = 'alive';

                if (!failed && c.statusLabel === 'ENDED') {
                  statusLabel = '완주';
                  statusClass = 'completed';
                }

                if (failed) {
                  if (refund === 0n) {
                    statusLabel = '전액 몰수';
                    statusClass = 'slashed';
                  } else {
                    statusLabel = `Day ${String(p.failedDay)} 탈락`;
                    statusClass = 'failed';
                  }
                }

                return (
                  <tr key={p.address}>

                    <td>
                      <span className="participant-name">
                        {String.fromCharCode(65 + index)}
                      </span>
                    </td>

                    <td>
                      <code className="address">
                        {shortAddress(p.address)}
                      </code>
                    </td>

                    <td>
                      {formatSui(p.stake, 4)} SUI
                    </td>

                    <td>
                      {failed
                        ? `Day ${String(p.failedDay)}`
                        : '—'}
                    </td>

                    <td>
                      {rate === null
                        ? '—'
                        : `${(rate * 100).toFixed(1)}%`}
                    </td>

                    <td>
                      {refund === null
                        ? '—'
                        : `${formatSui(refund, 5)} SUI`}
                    </td>

                    <td>
                      {dividend.kind === 'accruing' ? (
                        <span className="pending-dividend">
                          {formatSui(dividend.amount, 5)} SUI
                        </span>
                      ) : (
                        <span
                          className="cell-muted"
                          title={
                            dividend.kind === 'settledAtEnd'
                              ? '종료 시 claimable에 합산됨'
                              : '탈락 당일 확정되어 claimable에 포함됨'
                          }
                        >
                          {dividend.kind === 'settledAtEnd'
                            ? '정산 완료'
                            : '—'}
                        </span>
                      )}
                    </td>

                    <td className="claimable">
                      {formatSui(p.claimable, 5)} SUI
                    </td>

                    <td>
                      <span className={`status-badge ${statusClass}`}>
                        {statusLabel}
                      </span>
                    </td>

                  </tr>
                );
              })}
            </tbody>

          </table>
        </div>

      </section>

      {/* Footer */}
      <footer className="dashboard-footer">

        <div className="footer-row">

          <div>
            <span
              className={
                failCount >= 2
                  ? 'connection-dot disconnected'
                  : 'connection-dot'
              }
            />

            {failCount >= 2
              ? 'Disconnected'
              : 'Connected to Sui Testnet'}
          </div>

          <div>
            마지막 갱신{' '}
            {lastOk
              ? lastOk.toLocaleTimeString('ko-KR')
              : '확인 중'}
          </div>

        </div>

        <div className="footer-meme">
          discipline PvP for unemployed gambling addicts
        </div>

      </footer>

    </main>
  );
}