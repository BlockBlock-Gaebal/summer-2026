/**
 * web/server.ts — 브라우저 입력 폼 → evidence/day{N}.json 생성 → agent.ts 실행 → 로그 스트리밍
 *
 * agent.ts를 고치지 않는다. 브라우저가 받은 텍스트로 증빙 파일을 만들고, agent.ts를
 * 자식 프로세스로 띄워 stdout/stderr를 그대로 SSE로 흘려보낼 뿐이다. 판정·안전장치·서명은
 * 전부 agent.ts 안에서 그대로 일어난다.
 *
 *   GET  /        입력 폼 (index.html)
 *   GET  /state   .env의 CHALLENGE_ID 방 상태 — 다음 day, 생존자 명단
 *   POST /judge   { texts: { "0x…": "…" }, mode: "dry-run" | "submit" }
 *                 → evidence/day{N}.json 덮어쓰기 → agent.ts 실행 → text/event-stream 으로 로그
 *
 * 실행 (scripts/ 에서):  npm run web   →  http://localhost:3000
 * ⚠️ 방은 .env의 CHALLENGE_ID 하나뿐이다. 발표용·백업 방은 .env에 없으므로 건드릴 수 없다.
 * ⚠️ 한 번에 하나의 판정만 돌린다 (동시 실행 시 409).
 */

import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { config as loadEnv } from 'dotenv';
import { readState, createSuiClient, STATUS, humanizeError } from '../read_state';

const WEB_DIR = dirname(fileURLToPath(import.meta.url));
const SCRIPTS_DIR = join(WEB_DIR, '..');
const EVIDENCE_DIR = join(SCRIPTS_DIR, 'evidence');
const PORT = Number(process.env.PORT ?? 3000);

loadEnv({ path: join(SCRIPTS_DIR, '.env') });
const CHALLENGE_ID = process.env.CHALLENGE_ID;
if (!CHALLENGE_ID) throw new Error('scripts/.env에 CHALLENGE_ID가 없다.');
const client = createSuiClient({
  network: (process.env.SUI_NETWORK ?? 'testnet') as 'testnet' | 'mainnet' | 'devnet' | 'localnet',
  url: process.env.SUI_GRPC_URL,
});

let running = false;

async function stateJson() {
  const s = await readState(client, CHALLENGE_ID!);
  const c = s.challenge;
  return {
    challengeId: CHALLENGE_ID,
    status: c.statusLabel,
    currentDay: Number(c.currentDay),
    totalDays: Number(c.totalDays),
    nextDay: Number(c.currentDay) + 1,
    canJudge: c.status !== STATUS.ENDED && c.currentDay < c.totalDays,
    oracle: c.oracle,
    participants: s.participants.map((p) => ({
      address: p.address,
      stake: String(p.stake),
      failedDay: Number(p.failedDay),
      alive: p.failedDay === 0n,
    })),
    evidenceExists: existsSync(join(EVIDENCE_DIR, `day${Number(c.currentDay) + 1}.json`)),
  };
}

function readBody(req: import('node:http').IncomingMessage): Promise<string> {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => { data += chunk; if (data.length > 1_000_000) reject(new Error('body too large')); });
    req.on('end', () => resolve(data));
    req.on('error', reject);
  });
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
  try {
    if (req.method === 'GET' && url.pathname === '/') {
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
      res.end(readFileSync(join(WEB_DIR, 'index.html')));
      return;
    }
    if (req.method === 'GET' && url.pathname === '/state') {
      res.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(await stateJson()));
      return;
    }
    if (req.method === 'POST' && url.pathname === '/judge') {
      if (running) { res.writeHead(409, { 'content-type': 'text/plain; charset=utf-8' }); res.end('이미 판정이 실행 중이다.'); return; }
      const body = JSON.parse(await readBody(req)) as { texts?: Record<string, string>; mode?: string };
      const mode = body.mode === 'submit' ? 'submit' : 'dry-run';
      const texts = body.texts ?? {};

      // 체인에서 다음 day와 생존자를 읽고, 폼이 준 텍스트로 증빙 파일을 만든다 (생존자 전원 필수 — 없으면 agent가 멈춘다)
      const st = await stateJson();
      if (!st.canJudge) { res.writeHead(400, { 'content-type': 'text/plain; charset=utf-8' }); res.end(`이 방은 ${st.status} 상태라 판정할 수 없다.`); return; }
      const evidence = st.participants.filter((p) => p.alive).map((p) => ({ address: p.address, text: String(texts[p.address] ?? '').trim() }));
      const file = join(EVIDENCE_DIR, `day${st.nextDay}.json`);
      writeFileSync(file, JSON.stringify(evidence, null, 2) + '\n');

      running = true;
      res.writeHead(200, { 'content-type': 'text/event-stream; charset=utf-8', 'cache-control': 'no-cache', connection: 'keep-alive' });
      const send = (event: string, data: string) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      send('log', `evidence/day${st.nextDay}.json 생성 (${evidence.length}명, ${mode})`);
      send('log', `$ npx tsx agent.ts ${st.nextDay}${mode === 'dry-run' ? ' --dry-run' : ''}`);

      const args = ['tsx', 'agent.ts', String(st.nextDay)];
      if (mode === 'dry-run') args.push('--dry-run');
      const child = spawn('npx', args, { cwd: SCRIPTS_DIR, env: process.env, stdio: ['ignore', 'pipe', 'pipe'] });
      const pipe = (stream: NodeJS.ReadableStream, event: string) => {
        let buf = '';
        stream.on('data', (chunk: Buffer) => {
          buf += chunk.toString('utf-8');
          const lines = buf.split('\n'); buf = lines.pop() ?? '';
          for (const line of lines) send(event, line);
        });
        stream.on('end', () => { if (buf) send(event, buf); });
      };
      pipe(child.stdout!, 'log');
      pipe(child.stderr!, 'err');
      child.on('close', (code) => { running = false; send('done', String(code ?? -1)); res.end(); });
      req.on('close', () => { /* 브라우저가 닫혀도 agent는 끝까지 돌게 둔다 — 중간에 죽이면 제출만 되고 기억 저장이 빠질 수 있다 */ });
      return;
    }
    res.writeHead(404); res.end();
  } catch (e) {
    if (!res.headersSent) res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(`오류: ${humanizeError(e)}`);
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`web 입력 폼: http://localhost:${PORT}  (방 ${CHALLENGE_ID})`);
});
