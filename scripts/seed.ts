/**
 * seed.ts — 유안 소유 데모 방 생성 + 참가자 join 자동화
 *
 * ─────────────────────────────────────────────────────────────────────
 * 왜 `.env`의 CHALLENGE_ID(검증용 방)를 재사용하지 않나
 * ─────────────────────────────────────────────────────────────────────
 * 검증용 방(`0xcc48adc4…`)의 오라클은 진모다. `submit_results`는 오라클만 부를 수
 * 있어서(ENotOracle), 유안이 submit.ts를 검증하려면 **본인이 오라클인 별도 방**이
 * 필요하다. 그래서 이 스크립트는 새 방을 만들고, ID를 `.env`가 아니라 로컬 상태
 * 파일(`.demo-state.json`, gitignore 대상)에 저장한다. 재실행하면 그 파일을 보고
 * 기존 방을 재사용한다 — "재실행해도 같은 상태가 재현되어야 한다"는 요구사항의 구현.
 *
 * ─────────────────────────────────────────────────────────────────────
 * 참가자 A / B / C를 어떻게 마련하나 (회의 결정: 3인 실제 서명 주소가 필요한데
 * 유안은 지금 자기 키(yuan-oracle=A)만 가지고 있다)
 * ─────────────────────────────────────────────────────────────────────
 * - **A = yuan-oracle 자신.** 오라클이자 참가자. 이 스크립트가 SDK로 자동 join한다.
 * - **B, C = 유안이 직접 준비한 별도 주소.** 새 개인키를 이 스크립트가 만들거나
 *   저장하지 않는다 (개인키 파일 저장은 예전 지갑 노출 사고와 같은 리스크 범주라
 *   피하기로 했다). 대신:
 *     1. `sui client new-address ed25519 <별명>`으로 로컬 키스토어에 B/C 주소를 만든다
 *     2. `.env`에 PARTICIPANT_B_ADDRESS / PARTICIPANT_C_ADDRESS로 **주소만**(공개 정보) 적는다
 *     3. 이 스크립트가 그 주소들의 참여 여부·잔고를 읽기 전용으로 확인하고,
 *        아직이면 "얼마를 채워야 하는지" 또는 "무슨 명령을 실행해야 하는지"를 화면에 찍어준다
 *     4. 실제 join 서명은 유안이 B/C의 active-address로 전환해 손으로 `sui client ptb`를 실행한다
 *        (스크립트가 남의 키로 대신 서명할 수 없다 — Move의 ctx.sender()는 서명자 본인이다)
 */

import { readState, createSuiClient, humanizeError, mistToSui, shortAddress, STATUS } from './read_state';
import { signAndExecute, loadOracleKeypair, MoveAbortError, GAS_BUDGET, sharedObjectRef, SUI_COIN_TYPE } from './sui_tx';
import { Transaction } from '@mysten/sui/transactions';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const STATE_FILE = join(__dirname, '.demo-state.json');

// [D-06][D-14] 확정 데모 파라미터. 회의에서 바뀌면 여기 두 값만 고치면 된다.
const TOTAL_DAYS = 5;
const ALPHA_BP = 2000;

// 소액 테스트넷 자금이라 참가자당 소액으로 잡는다 (오라클 잔고 총 ~0.2 SUI 전제)
const STAKE_A = 20_000_000; // 0.02 SUI
const STAKE_BC = 20_000_000; // 0.02 SUI — B/C가 손으로 join할 때 쓸 금액(안내문에도 이 값을 찍는다)
// B/C 잔고가 이 이상이어야 "충전됐다"고 판단한다 (stake + 가스 예산 여유분)
const MIN_BC_BALANCE = STAKE_BC + GAS_BUDGET * 2;

interface DemoState {
  challengeId: string;
}

function loadState(): DemoState | null {
  if (!existsSync(STATE_FILE)) return null;
  try {
    return JSON.parse(readFileSync(STATE_FILE, 'utf-8')) as DemoState;
  } catch {
    return null;
  }
}

function saveState(state: DemoState): void {
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2) + '\n', 'utf-8');
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * readState는 일시적 gRPC 오류(네트워크 blip, 풀노드 반영 지연)로도 던질 수 있다.
 * 그걸 "저장된 방을 못 쓴다"로 오인해 곧장 새 방을 만들면 saveState가
 * `.demo-state.json`을 덮어써 기존 방(과 거기 이미 join된 B/C의 stake)을
 * 로컬에서 추적 불가능하게 잃어버린다 — 그래서 몇 번 재시도하고, 그래도 안
 * 되면 "새로 만들지 않고" 그대로 던져서 사용자가 원인을 보게 한다.
 */
async function readStateWithRetry(
  client: Parameters<typeof readState>[0],
  challengeId: string,
  attempts = 3,
): Promise<Awaited<ReturnType<typeof readState>>> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await sleep(1000);
    try {
      return await readState(client, challengeId);
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}

async function main(): Promise<void> {
  await import('dotenv/config');

  const packageId = process.env.PACKAGE_ID;
  if (!packageId) throw new Error('PACKAGE_ID가 .env에 없다. docs/DEPLOYMENT.md 참고.');

  const network = (process.env.SUI_NETWORK ?? 'testnet') as 'testnet' | 'mainnet' | 'devnet' | 'localnet';
  const client = createSuiClient({ network, url: process.env.SUI_GRPC_URL });
  const oracle = loadOracleKeypair();
  const oracleAddress = oracle.toSuiAddress();

  console.log(`\n오라클(=A) 주소: ${oracleAddress}\n`);

  // ── 1. 방 확보: 기존 로컬 상태 재사용 or 새로 생성 ──────────────────────
  let challengeId: string | null = null;
  const existing = loadState();
  if (existing) {
    // 여기서 실패하면(재시도 후에도) 절대 "새로 만든다"로 넘어가지 않는다 — 그러면
    // 아래 saveState가 기존 방 ID를 덮어써 되돌릴 수 없다. 일시적 오류인지 진짜
    // 못 쓰는 방인지 구분이 안 되므로, 안전한 쪽(중단)으로 던진다.
    const c = await readStateWithRetry(client, existing.challengeId);
    if (c.challenge.oracle === oracleAddress && c.challenge.status !== STATUS.ENDED) {
      challengeId = existing.challengeId;
      console.log(`기존 데모 방 재사용: ${challengeId} (상태: ${c.challenge.statusLabel})`);
    } else {
      console.log(`저장된 방(${existing.challengeId})은 재사용할 수 없다 (오라클 불일치 또는 ENDED) — 새로 만든다.`);
    }
  }

  if (!challengeId) {
    console.log(`새 방 생성 중... (total_days=${TOTAL_DAYS}, alpha_bp=${ALPHA_BP})`);
    const tx = new Transaction();
    tx.moveCall({
      target: `${packageId}::challenge::create_challenge`,
      arguments: [tx.pure.u64(TOTAL_DAYS), tx.pure.u64(ALPHA_BP)],
    });
    const result = await signAndExecute(client, tx, oracle);
    const created = result.createdSharedObjectIds[0];
    if (!created) throw new Error('create_challenge는 성공했는데 새 shared object를 못 찾았다 — effects 파싱 확인 필요');
    challengeId = created;
    saveState({ challengeId });
    console.log(`생성 완료: ${challengeId} (digest: ${result.digest})`);
  }

  // ── 2. A(오라클 자신) join ───────────────────────────────────────────
  console.log(`\nA(${shortAddress(oracleAddress)}) join 시도 (${mistToSui(BigInt(STAKE_A))} SUI)...`);
  try {
    const tx = new Transaction();
    const ref = await sharedObjectRef(client, challengeId);
    const [stake] = tx.splitCoins(tx.gas, [STAKE_A]);
    tx.moveCall({
      target: `${packageId}::challenge::join`,
      arguments: [tx.sharedObjectRef(ref), stake],
    });
    const result = await signAndExecute(client, tx, oracle, { minGasCoinValue: GAS_BUDGET + STAKE_A });
    console.log(`A join 완료 (digest: ${result.digest})`);
  } catch (e) {
    if (e instanceof MoveAbortError && e.code === 1) {
      console.log('A는 이미 참여해 있다 (EAlreadyJoined) — 정상, 건너뜀.');
    } else {
      throw e;
    }
  }

  // ── 3. B, C 상태 확인 + 안내 (서명은 유안이 직접) ───────────────────────
  const snap = await readState(client, challengeId);
  const joined = new Set(snap.participants.map((p) => p.address));

  for (const role of ['B', 'C'] as const) {
    const addr = process.env[`PARTICIPANT_${role}_ADDRESS`];
    console.log(`\n── 참가자 ${role} ──`);

    if (!addr) {
      console.log(
        [
          `PARTICIPANT_${role}_ADDRESS가 .env에 없다. 준비 순서:`,
          `  1) sui client new-address ed25519 demo-${role.toLowerCase()}`,
          `  2) 나온 주소를 .env에 PARTICIPANT_${role}_ADDRESS=0x... 로 추가`,
          `  3) 이 스크립트 재실행`,
        ].join('\n'),
      );
      continue;
    }

    if (joined.has(addr)) {
      console.log(`${role}(${shortAddress(addr)})는 이미 참여해 있다. 할 일 없음.`);
      continue;
    }

    const balanceRes = await client.core.getBalance({ address: addr, coinType: SUI_COIN_TYPE });
    const balance = BigInt(balanceRes.balance.balance);

    if (balance < BigInt(MIN_BC_BALANCE)) {
      console.log(
        [
          `${role}(${addr}) 잔고 부족: ${mistToSui(balance)} SUI (join+가스에 최소 ${mistToSui(BigInt(MIN_BC_BALANCE))} SUI 필요)`,
          `진모에게 이 주소로 pay-sui 요청:`,
          `  ${addr}`,
        ].join('\n'),
      );
      continue;
    }

    console.log(
      [
        `${role}(${shortAddress(addr)}) 충전 확인됨 (${mistToSui(balance)} SUI). 아래 명령을 ${role}의 active-address로 실행:`,
        '',
        `  sui client switch --address ${addr}`,
        `  sui client ptb \\`,
        `    --split-coins gas "[${STAKE_BC}]" \\`,
        `    --assign stake \\`,
        `    --move-call ${packageId}::challenge::join @${challengeId} stake.0 \\`,
        `    --gas-budget ${GAS_BUDGET}`,
      ].join('\n'),
    );
  }

  console.log(`\n상태 확인: npm run read-state -- ${challengeId}\n`);
}

main().catch((e) => {
  console.error(`\nseed 실패: ${humanizeError(e)}\n`);
  process.exit(1);
});
