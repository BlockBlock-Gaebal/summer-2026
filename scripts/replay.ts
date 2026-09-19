/**
 * replay.ts — Walrus에 저장된 판정 기억을 읽어 agent.ts의 콘솔 출력 형식으로 다시 보여준다.
 *
 * agent.ts가 매 day 저장하는 blob은 그날까지의 기억 스냅샷이다. 그 blobId를 주면
 * 그 안에 든 판정(제출 텍스트 · PASS/FAIL · 근거)을 day 순서로 출력한다.
 * 발표에서 판정 로그를 다시 보여주는 용도라 체인도, LLM도, .env도 건드리지 않는다.
 * 읽기 전용이다 — 아무것도 쓰지 않는다.
 *
 * 사용법 (scripts/ 에서):
 *   npx tsx replay.ts <blobId>        # 전체 day를 순서대로
 *   npx tsx replay.ts <blobId> 3      # day 3 판정만
 *
 * "과거 기록 N건 로드"는 그 day 판정 당시 에이전트가 봤을 기록(day < N)만 센다.
 * 헤더의 건수는 blob 전체 레코드 수라 그보다 크다 (예: day3 blob = 9건, 판정 때 로드는 6건).
 */

import { shortAddress } from './read_state';

const WALRUS_AGGREGATOR = 'https://aggregator.walrus-testnet.walrus.space';
const RETRIES = 3;

interface MemoryRecord {
  day: number;
  text: string;
  verdict: 'PASS' | 'FAIL';
  reason: string;
}

type Memory = Record<string, MemoryRecord[]>;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** agent.ts의 withRetry와 같은 1s, 2s, 4s 백오프. 업로드 직후 aggregator의 404를 넘기기 위한 것. */
async function fetchMemoryBlob(blobId: string): Promise<Memory> {
  const url = `${WALRUS_AGGREGATOR}/v1/blobs/${encodeURIComponent(blobId)}`;
  let lastError = '';
  for (let attempt = 1; attempt <= RETRIES + 1; attempt++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const parsed: unknown = JSON.parse(await res.text());
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('blob 내용이 { "0x주소": [...] } 형태가 아니다');
      }
      return parsed as Memory;
    } catch (e) {
      lastError = (e as Error).message;
      if (attempt > RETRIES) break;
      const wait = 1000 * 2 ** (attempt - 1);
      console.log(`  (Walrus GET 실패, ${wait / 1000}s 후 재시도 ${attempt}/${RETRIES}: ${lastError})`);
      await sleep(wait);
    }
  }
  throw new Error(
    `Walrus에서 blob을 읽지 못했다 (${RETRIES + 1}회 시도, 마지막 오류: ${lastError})\n` +
      `  blobId: ${blobId}\n  URL: ${url}\n` +
      `  aggregator가 죽었으면 scripts/demo-logs/ 의 저장본을 cat으로 보여줄 것.`,
  );
}

function countRecords(memory: Memory): number {
  return Object.values(memory).reduce((n, rs) => n + rs.length, 0);
}

function printDay(memory: Memory, day: number): void {
  console.log(`\n═══ day ${day} 판정 (Walrus replay) ═══`);
  const failed: string[] = [];
  for (const [address, records] of Object.entries(memory)) {
    const today = records.find((r) => r.day === day);
    if (!today) {
      // 이 day 레코드가 없다 = 이미 탈락해서 판정 대상이 아니었던 참가자
      const lastFail = records.find((r) => r.verdict === 'FAIL' && r.day < day);
      if (lastFail) console.log(`\n▶ ${address}\n  (day${lastFail.day}에 이미 탈락 — 판정 제외)`);
      continue;
    }
    const past = records.filter((r) => r.day < day);
    console.log(`\n▶ ${address}`);
    console.log(`  과거 기록 ${past.length}건 로드${past.length ? ` (day ${past.map((r) => r.day).join(', ')})` : ''}`);
    console.log(`  오늘 제출: ${today.text.trim() === '' ? '(비어 있음)' : today.text.trim()}`);
    console.log(`  판정: ${today.verdict}`);
    console.log(`  근거: ${today.reason}`);
    if (today.verdict === 'FAIL') failed.push(address);
  }
  console.log(`\n═══ 결과 ═══`);
  console.log(`FAIL 명단: ${failed.length === 0 ? '없음' : ''}`);
  for (const a of failed) console.log(`  - ${a}`);
}

async function main(): Promise<void> {
  const [blobId, dayArg] = process.argv.slice(2);
  if (!blobId) throw new Error('사용법: npx tsx replay.ts <blobId> [day]');
  const onlyDay = dayArg === undefined ? undefined : Number(dayArg);
  if (onlyDay !== undefined && (!Number.isInteger(onlyDay) || onlyDay < 1)) {
    throw new Error(`day는 1 이상의 정수여야 한다: ${dayArg}`);
  }

  const memory = await fetchMemoryBlob(blobId);
  console.log(`Walrus에서 기억 로드: blobId=${blobId} (${countRecords(memory)}건)`);

  const days = [...new Set(Object.values(memory).flat().map((r) => r.day))].sort((a, b) => a - b);
  if (days.length === 0) throw new Error('blob에 판정 기록이 하나도 없다.');
  if (onlyDay !== undefined && !days.includes(onlyDay)) {
    throw new Error(`이 blob에는 day ${onlyDay} 기록이 없다 (있는 day: ${days.join(', ')})`);
  }

  for (const day of onlyDay !== undefined ? [onlyDay] : days) printDay(memory, day);
  console.log('');
}

main().catch((e) => {
  console.error(`\nreplay 실패: ${(e as Error).message}\n`);
  process.exit(1);
});
