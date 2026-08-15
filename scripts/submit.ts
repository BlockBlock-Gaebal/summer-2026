/**
 * submit.ts — day별 탈락자 제출 자동화 (오라클 전용)
 *
 * 실행할 때마다 딱 하루치만 진행한다 (`submit_results` 호출 1번 = day +1,
 * challenge.move의 수동 day 카운터 규약 — CLAUDE.md §5-6). 몇 번째 day인지는
 * `.demo-state.json`이 아니라 **체인에서 직접** `current_day`를 읽어 정한다 —
 * 그래야 중간에 실패해도 재실행이 상태를 그대로 이어받는다.
 *
 * 시나리오(고정): day1 = B 탈락, day3 = C 탈락, 나머지 날 = 아무도 탈락 안 함
 * (= A 완주). B/C의 주소는 seed.ts와 같은 방식으로 `.env`의
 * PARTICIPANT_B_ADDRESS / PARTICIPANT_C_ADDRESS에서 읽는다.
 *
 * ⚠️ 안전장치: 그날의 예정 탈락자가 아직 join 안 했거나 주소가 안 적혀 있으면
 * **submit_results를 아예 호출하지 않고 throw한다.** (진모 리뷰 지적, 08-15)
 * 처음엔 "조용히 빈 명단으로 진행"했는데, 이게 거꾸로 더 위험하다 — abort는
 * 아무 일도 안 일어나서 재시도가 공짜지만, submit_results가 성공하면
 * current_day가 +1 되고 되돌릴 방법이 없다. SCHEDULE은 절대 day 번호
 * 기준이라, B가 join 안 된 채로 실수로 한 번 돌리면 day1이 그냥 소모되고
 * B는 시나리오상 영영 탈락시킬 수 없다 (5일짜리 방을 새로 파야 함).
 * 그래서 명단이 스케줄과 안 맞으면 무조건 멈추고, 사람이 확인 후 재실행하게 한다.
 *
 * total_days만큼 다 제출되면(day == total_days) 이어서 자동으로 finalize()도
 * 호출해 ENDED로 마무리한다. finalize는 오라클 제한이 없는 함수라 아무 서명으로나
 * 되지만, 지금 가진 키가 오라클 키뿐이라 그대로 쓴다.
 */

import { readState, createSuiClient, humanizeError, mistToSui, shortAddress, STATUS } from './read_state';
import { signAndExecute, loadOracleKeypair, sharedObjectRef } from './sui_tx';
import { Transaction } from '@mysten/sui/transactions';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STATE_FILE = join(__dirname, '.demo-state.json');

/** day → 그날 탈락시킬 참가자 역할(PARTICIPANT_<role>_ADDRESS). 없는 날 = 완주 진행 */
const SCHEDULE: Record<number, 'B' | 'C'> = { 1: 'B', 3: 'C' };

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * ⚠️ 실측: submit_results 트랜잭션이 성공한 직후 바로 read_state를 하면 day가
 * 아직 안 올라간 채로 보일 때가 있다 (풀노드 읽기 경로의 반영 지연 — sui_tx.ts의
 * sharedObjectRef 주석 참고). 그래서 기대한 day에 도달할 때까지 짧게 재조회한다.
 */
async function pollSnapshot(
  client: Parameters<typeof readState>[0],
  challengeId: string,
  isReady: (snap: Awaited<ReturnType<typeof readState>>) => boolean,
): Promise<Awaited<ReturnType<typeof readState>>> {
  let snap = await readState(client, challengeId);
  for (let attempt = 0; attempt < 5 && !isReady(snap); attempt++) {
    await sleep(1200);
    snap = await readState(client, challengeId);
  }
  return snap;
}

/**
 * finalize()를 부르고 ENDED가 반영될 때까지 기다린다. day 진행 직후와, "이미 마지막
 * 날까지 제출됐지만 finalize는 아직 안 된" 상태(바로 아래 버그 설명) 양쪽에서 쓴다.
 */
async function finalizeAndWait(
  client: Parameters<typeof readState>[0],
  packageId: string,
  challengeId: string,
  oracle: ReturnType<typeof loadOracleKeypair>,
): Promise<Awaited<ReturnType<typeof readState>>> {
  console.log('\nfinalize() 호출...');
  const finalizeTx = new Transaction();
  const finalizeRef = await sharedObjectRef(client, challengeId);
  finalizeTx.moveCall({
    target: `${packageId}::challenge::finalize`,
    arguments: [finalizeTx.sharedObjectRef(finalizeRef)],
  });
  const finalizeResult = await signAndExecute(client, finalizeTx, oracle);
  console.log(`finalize 완료 (digest: ${finalizeResult.digest})`);
  return pollSnapshot(client, challengeId, (s) => s.challenge.status === STATUS.ENDED);
}

function loadChallengeId(): string {
  if (!existsSync(STATE_FILE)) {
    throw new Error('scripts/.demo-state.json이 없다 — 먼저 `npm run seed`로 데모 방을 만들 것');
  }
  const state = JSON.parse(readFileSync(STATE_FILE, 'utf-8')) as { challengeId: string };
  if (!state.challengeId) throw new Error('.demo-state.json에 challengeId가 없다 — seed.ts를 다시 실행할 것');
  return state.challengeId;
}

async function main(): Promise<void> {
  await import('dotenv/config');

  const packageId = process.env.PACKAGE_ID;
  if (!packageId) throw new Error('PACKAGE_ID가 .env에 없다. docs/DEPLOYMENT.md 참고.');

  const network = (process.env.SUI_NETWORK ?? 'testnet') as 'testnet' | 'mainnet' | 'devnet' | 'localnet';
  const client = createSuiClient({ network, url: process.env.SUI_GRPC_URL });
  const oracle = loadOracleKeypair();
  const challengeId = loadChallengeId();

  const before = await readState(client, challengeId);
  const c = before.challenge;
  console.log(`\n방: ${challengeId}`);
  console.log(`현재 상태: ${c.statusLabel}, day ${c.currentDay}/${c.totalDays}, 참가자 ${c.participantsSize}명\n`);

  if (c.status === STATUS.ENDED) {
    console.log('이미 ENDED다. 더 진행할 것 없음.');
    printSummary(before);
    return;
  }

  if (c.participantsSize === 0n) {
    // D-22: 빈 방에 submit_results 호출 = 전멸 오판정으로 영구 잠김. 운용 규칙으로 차단한다.
    throw new Error('참가자 0명인 방이다 — submit_results를 호출하면 즉시 전멸 처리되어 영구 잠긴다. 중단.');
  }

  if (Number(c.currentDay) === Number(c.totalDays)) {
    // 이미 total_days만큼 다 제출된 상태 (예: 직전 실행이 마지막 날 제출엔 성공했지만
    // 그 직후 read_state의 반영 지연 때문에 finalize 자동 호출까지는 못 갔던 경우 —
    // 실측으로 확인된 경로다). submit_results를 다시 부르면 EAllDaysSubmitted로
    // abort하므로, submit 없이 finalize만 마저 부른다.
    console.log('이미 마지막 날까지 제출된 상태다 — submit 없이 finalize()만 호출한다.');
    const final = await finalizeAndWait(client, packageId, challengeId, oracle);
    printSummary(final);
    console.log(`\n상태 확인: npm run read-state -- ${challengeId}\n`);
    return;
  }

  const nextDay = Number(c.currentDay) + 1;
  const role = SCHEDULE[nextDay];
  let failed: string[] = [];

  if (role) {
    const addr = process.env[`PARTICIPANT_${role}_ADDRESS`];
    if (!addr) {
      throw new Error(
        `day ${nextDay}: ${role} 탈락이 예정돼 있으나 PARTICIPANT_${role}_ADDRESS가 .env에 없다 — ` +
          `채우고 다시 실행할 것. (여기서 빈 명단으로 넘어가면 day를 되돌릴 수 없이 날린다)`,
      );
    }
    const participant = before.participants.find((p) => p.address === addr);
    if (!participant) {
      throw new Error(
        `day ${nextDay}: ${role}(${shortAddress(addr)})가 아직 이 방에 join하지 않았다 — ` +
          `먼저 join시키고 다시 실행할 것.`,
      );
    }
    if (participant.failedDay !== 0n) {
      throw new Error(
        `day ${nextDay}: ${role}(${shortAddress(addr)})는 이미 day${participant.failedDay}에 탈락 처리돼 있다 — ` +
          `SCHEDULE 설정을 확인할 것.`,
      );
    }
    failed = [addr];
    console.log(`day ${nextDay}: 예정대로 ${role}(${shortAddress(addr)}) 탈락 제출`);
  } else {
    console.log(`day ${nextDay}: 예정된 탈락자 없음 — 빈 명단으로 진행`);
  }

  const tx = new Transaction();
  const ref = await sharedObjectRef(client, challengeId);
  tx.moveCall({
    target: `${packageId}::challenge::submit_results`,
    arguments: [tx.sharedObjectRef(ref), tx.pure.vector('address', failed)],
  });

  const result = await signAndExecute(client, tx, oracle);
  console.log(`submit_results 완료 (digest: ${result.digest})`);

  const after = await pollSnapshot(client, challengeId, (s) => Number(s.challenge.currentDay) >= nextDay);
  console.log(`\nday ${after.challenge.currentDay}/${after.challenge.totalDays} 진행됨. 상태: ${after.challenge.statusLabel}`);

  let final = after;
  if (after.challenge.currentDay === after.challenge.totalDays && after.challenge.status !== STATUS.ENDED) {
    console.log('\n마지막 날 제출 완료');
    final = await finalizeAndWait(client, packageId, challengeId, oracle);
  }

  printSummary(final);
  console.log(`\n상태 확인: npm run read-state -- ${challengeId}\n`);
}

function printSummary(snap: Awaited<ReturnType<typeof readState>>): void {
  console.log('');
  for (const p of snap.participants) {
    const state = p.failedDay === 0n ? (snap.challenge.status === STATUS.ENDED ? '완주' : '생존') : `day${p.failedDay} 탈락`;
    console.log(`  ${shortAddress(p.address)}  stake=${mistToSui(p.stake)}  claimable=${mistToSui(p.claimable)}  ${state}`);
  }
}

main().catch((e) => {
  console.error(`\nsubmit 실패: ${humanizeError(e)}\n`);
  process.exit(1);
});
