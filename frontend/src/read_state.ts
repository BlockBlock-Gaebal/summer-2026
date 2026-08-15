/**
 * read_state.ts — Challenge 상태 조회 (공용 모듈, D-21)
 *
 * 담당: 진모 / 사용처: 승준(대시보드), 유안(오라클 스크립트)
 *
 * ─────────────────────────────────────────────────────────────────────
 * 왜 이 파일이 따로 있나
 * ─────────────────────────────────────────────────────────────────────
 * 참가자는 `Table<address, Participant>`에 들어 있는데, Sui의 Table은
 * 오브젝트 안에 값을 품고 있지 않다. 각 엔트리가 **별도의 오브젝트**(dynamic field)로
 * 흩어져 있고, Table 오브젝트 자신은 "껍데기 + 개수"만 갖는다.
 * 그래서 Challenge 하나만 읽어서는 참가자 목록을 볼 수 없고 2단계가 필요하다:
 *
 *   1단계  listDynamicFields(Table ID)      → 엔트리 오브젝트 ID 목록
 *   2단계  batchGetObjects(그 ID들)          → 실제 Participant 값
 *
 * 이건 프론트엔드 난이도 문제가 아니라 컨트랙트 저장 구조에서 나온 문제라
 * 컨트랙트 담당이 공용으로 해소한다 (DECISIONS.md §8.7).
 *
 * ─────────────────────────────────────────────────────────────────────
 * ⚠️ 함정 2개 — 모르면 몇 시간 날린다
 * ─────────────────────────────────────────────────────────────────────
 * (1) **JSON-RPC는 죽었다.** 공개 풀노드의 JSON-RPC가 폐지되어
 *     `@mysten/sui`의 `SuiClient`는 모든 메서드가 `MethodNotFound`로 실패한다.
 *     `SuiGrpcClient`(gRPC-web)를 써야 한다.
 *     그리고 생성자 옵션 이름은 `url`이 아니라 **`baseUrl`**이다.
 *     틀리면 `TypeError: Cannot read properties of undefined (reading 'endsWith')`
 *     라는, 원인을 전혀 알 수 없는 에러가 난다.
 *
 * (2) **`client.core.getObject()`를 쓰면 안 된다.** 이 래퍼는 readMask에 `bcs`만
 *     요청해서 "타입 태그가 앞에 붙은" 원시 BCS를 준다. 그대로 파싱하면 필드가
 *     통째로 밀려서 `alpha_bp = 6513693456844128674` 같은 쓰레기값이 나온다
 *     (에러가 안 나고 조용히 틀리기 때문에 특히 위험하다).
 *     대신 `ledgerService`를 직접 호출하고 readMask에 **`json`**을 넣으면
 *     노드가 파싱해준 깨끗한 JSON이 온다.
 */

import { SuiGrpcClient } from '@mysten/sui/grpc';

// === 타입 ===

export type Network = 'mainnet' | 'testnet' | 'devnet' | 'localnet';

/** 컨트랙트의 status 상수 (challenge.move와 반드시 일치) */
export const STATUS = { PENDING: 0, ACTIVE: 1, ENDED: 2 } as const;

export const STATUS_LABEL: Record<number, string> = {
  0: 'PENDING',
  1: 'ACTIVE',
  2: 'ENDED',
};

export interface ChallengeState {
  id: string;
  oracle: string;
  alphaBp: bigint;
  totalDays: bigint;
  currentDay: bigint;
  dailyDrip: bigint;
  accPerShare: bigint;
  /** vault에 남아 있는 총액 (MIST) */
  vault: bigint;
  status: number;
  statusLabel: string;
  /** 참가자 Table의 오브젝트 ID — 2단계 조회의 입력 */
  participantsTableId: string;
  /** Table 엔트리 개수 (컨트랙트가 관리하는 값) */
  participantsSize: bigint;
  /** 순회용 vector. join 순서가 보존된다 */
  participantList: string[];
}

export interface ParticipantState {
  address: string;
  /** 예치액 (MIST) */
  stake: bigint;
  startDay: bigint;
  accEntry: bigint;
  /** 0 = 생존 중, n = day n에 탈락 */
  failedDay: bigint;
  /** 정산 누적액 (MIST). pull 패턴이라 claim해야 실제로 받는다 */
  claimable: bigint;
}

export interface ChallengeSnapshot {
  challenge: ChallengeState;
  participants: ParticipantState[];
  /** 정합성 이상 등 호출자가 알아야 할 경고 */
  warnings: string[];
}

// === 클라이언트 ===

export function defaultGrpcUrl(network: Network): string {
  if (network === 'localnet') return 'http://127.0.0.1:9000';
  return `https://fullnode.${network}.sui.io:443`;
}

export function createSuiClient(options: { network?: Network; url?: string } = {}): SuiGrpcClient {
  const network = options.network ?? 'testnet';
  // ⚠️ 옵션 이름은 baseUrl이다. url로 쓰면 endsWith 에러가 난다 (파일 상단 함정 (1))
  return new SuiGrpcClient({ network, baseUrl: options.url || defaultGrpcUrl(network) });
}

// === 내부 헬퍼 ===

/**
 * gRPC가 주는 `json` 필드는 protobuf의 Value 타입이라
 * `{ kind: { oneofKind: 'stringValue', stringValue: '2000' } }` 처럼 한 겹 싸여 있다.
 * 이걸 평범한 JS 값으로 벗긴다.
 *
 * 주의: Move의 u64/u128은 JS number로 표현할 수 없는 크기라 노드가 **문자열**로 준다.
 * 그래서 여기서는 문자열 그대로 두고, 숫자 변환은 호출부에서 BigInt로 한다.
 */
function unwrapProtoValue(v: unknown): unknown {
  if (v == null) return v;
  const kind = (v as { kind?: { oneofKind?: string; [k: string]: unknown } }).kind;
  if (!kind || !kind.oneofKind) return v;

  switch (kind.oneofKind) {
    case 'stringValue':
      return kind.stringValue;
    case 'numberValue':
      return kind.numberValue;
    case 'boolValue':
      return kind.boolValue;
    case 'nullValue':
      return null;
    case 'listValue':
      return ((kind.listValue as { values: unknown[] }).values ?? []).map(unwrapProtoValue);
    case 'structValue': {
      const fields = (kind.structValue as { fields: Record<string, unknown> }).fields ?? {};
      const out: Record<string, unknown> = {};
      for (const [k, val] of Object.entries(fields)) out[k] = unwrapProtoValue(val);
      return out;
    }
    default:
      return undefined;
  }
}

/**
 * gRPC 에러 메시지는 퍼센트 인코딩되어 온다
 * (예: `Object%200x00…%20not%20found`). 사람이 읽을 수 있게 되돌린다.
 */
export function humanizeError(e: unknown): string {
  const raw = e instanceof Error ? e.message : String(e);
  try {
    return decodeURIComponent(raw);
  } catch {
    return raw;
  }
}

/** u64/u128이 문자열로 오므로 BigInt로 변환. 없으면 0n */
function big(v: unknown): bigint {
  if (v == null) return 0n;
  if (typeof v === 'bigint') return v;
  return BigInt(typeof v === 'number' ? Math.trunc(v) : String(v));
}

/**
 * 오브젝트 하나를 읽어 파싱된 JSON 본문을 돌려준다.
 * readMask에 `json`을 넣는 것이 핵심 (파일 상단 함정 (2)).
 */
async function fetchObjectJson(
  client: SuiGrpcClient,
  objectId: string,
): Promise<Record<string, unknown>> {
  const res = await client.ledgerService.getObject({
    objectId,
    readMask: { paths: ['object_id', 'object_type', 'json'] },
  } as never).response;

  const obj = (res as { object?: { json?: unknown } }).object;
  if (!obj) throw new Error(`오브젝트를 찾을 수 없다: ${objectId}`);

  const parsed = unwrapProtoValue(obj.json);
  if (!parsed || typeof parsed !== 'object') {
    throw new Error(`오브젝트 본문을 파싱하지 못했다: ${objectId}`);
  }
  return parsed as Record<string, unknown>;
}

// === 조회 ===

/** Challenge(shared object) 하나를 읽는다. 참가자 목록은 포함되지 않는다. */
export async function readChallenge(
  client: SuiGrpcClient,
  challengeId: string,
): Promise<ChallengeState> {
  const f = await fetchObjectJson(client, challengeId);

  // participants는 Table이라 { id, size } 형태로 온다 (내용물은 여기 없다)
  const table = (f.participants ?? {}) as { id?: string; size?: string };
  const status = Number(f.status ?? 0);

  return {
    id: String(f.id ?? challengeId),
    oracle: String(f.oracle ?? ''),
    alphaBp: big(f.alpha_bp),
    totalDays: big(f.total_days),
    currentDay: big(f.current_day),
    dailyDrip: big(f.daily_drip),
    accPerShare: big(f.acc_per_share),
    vault: big(f.vault),
    status,
    statusLabel: STATUS_LABEL[status] ?? `UNKNOWN(${status})`,
    participantsTableId: String(table.id ?? ''),
    participantsSize: big(table.size),
    participantList: Array.isArray(f.participant_list) ? (f.participant_list as string[]) : [],
  };
}

/**
 * 1단계 — Table의 dynamic field 엔트리 ID를 전부 모은다.
 * 페이지네이션이 있으므로 pageToken이 빌 때까지 돈다.
 */
export async function listParticipantFieldIds(
  client: SuiGrpcClient,
  tableId: string,
): Promise<string[]> {
  const ids: string[] = [];
  let pageToken: Uint8Array | undefined;

  do {
    const res = await client.stateService.listDynamicFields({
      parent: tableId,
      pageSize: 1000,
      pageToken,
      readMask: { paths: ['field_id'] },
    } as never).response;

    const page = res as { dynamicFields?: { fieldId?: string }[]; nextPageToken?: Uint8Array };
    for (const f of page.dynamicFields ?? []) {
      if (f.fieldId) ids.push(f.fieldId);
    }
    pageToken = page.nextPageToken?.length ? page.nextPageToken : undefined;
  } while (pageToken);

  return ids;
}

/**
 * 2단계 — 엔트리 오브젝트들을 실제로 읽어 Participant 값을 꺼낸다.
 *
 * 각 엔트리는 `Field<address, Participant>` 타입이고 JSON은
 *   { id, name: "<참가자 주소>", value: { stake, start_day, acc_entry, failed_day, claimable } }
 * 형태다. name이 Table의 키(주소), value가 값(Participant).
 */
export async function readParticipants(
  client: SuiGrpcClient,
  tableId: string,
): Promise<ParticipantState[]> {
  const fieldIds = await listParticipantFieldIds(client, tableId);
  if (fieldIds.length === 0) return [];

  const out: ParticipantState[] = [];

  // batchGetObjects는 한 번에 50개까지라 나눠 보낸다
  const CHUNK = 50;
  for (let i = 0; i < fieldIds.length; i += CHUNK) {
    const batch = fieldIds.slice(i, i + CHUNK);
    const res = await client.ledgerService.batchGetObjects({
      requests: batch.map((id) => ({ objectId: id })),
      readMask: { paths: ['object_id', 'object_type', 'json'] },
    } as never).response;

    const objects = (res as { objects?: unknown[] }).objects ?? [];
    for (const entry of objects) {
      const result = (entry as { result?: { oneofKind?: string; object?: { json?: unknown } } }).result;
      if (result?.oneofKind !== 'object' || !result.object) continue;

      const parsed = unwrapProtoValue(result.object.json) as
        | { name?: string; value?: Record<string, unknown> }
        | undefined;
      if (!parsed?.value) continue;

      const v = parsed.value;
      out.push({
        address: String(parsed.name ?? ''),
        stake: big(v.stake),
        startDay: big(v.start_day),
        accEntry: big(v.acc_entry),
        failedDay: big(v.failed_day),
        claimable: big(v.claimable),
      });
    }
  }

  return out;
}

/**
 * Challenge + 참가자 전체를 한 번에. 대부분의 호출부는 이것만 쓰면 된다.
 *
 * 참가자 순서는 `participant_list`(join 순서)를 따른다. Table은 키 순회가 불가능해서
 * dynamic field 조회 순서가 보장되지 않기 때문이다.
 * 둘의 정합성이 깨지면 warnings에 담아 올린다 — 이건 컨트랙트 불변식이라
 * 어긋나면 조회 버그가 아니라 진짜 문제다 (CLAUDE.md §5-4).
 */
export async function readState(
  client: SuiGrpcClient,
  challengeId: string,
): Promise<ChallengeSnapshot> {
  const challenge = await readChallenge(client, challengeId);
  const warnings: string[] = [];

  if (!challenge.participantsTableId) {
    return { challenge, participants: [], warnings: ['참가자 Table ID를 찾지 못했다'] };
  }

  const fetched = await readParticipants(client, challenge.participantsTableId);
  const byAddress = new Map(fetched.map((p) => [p.address, p]));

  // participant_list 순서대로 재배열
  const participants: ParticipantState[] = [];
  for (const addr of challenge.participantList) {
    const p = byAddress.get(addr);
    if (p) {
      participants.push(p);
      byAddress.delete(addr);
    } else {
      warnings.push(`participant_list에 있으나 Table에 없다: ${addr}`);
    }
  }
  // list에는 없는데 Table에만 있는 경우 (있으면 안 된다)
  for (const leftover of byAddress.values()) {
    warnings.push(`Table에 있으나 participant_list에 없다: ${leftover.address}`);
    participants.push(leftover);
  }

  if (BigInt(participants.length) !== challenge.participantsSize) {
    warnings.push(
      `참가자 수 불일치: Table.size=${challenge.participantsSize}, 조회된 엔트리=${participants.length}`,
    );
  }

  return { challenge, participants, warnings };
}

// === 표시용 ===

/** MIST를 SUI 문자열로. 표시 전용이며 계산에 쓰지 말 것 (정밀도 손실) */
export function mistToSui(mist: bigint, fractionDigits = 4): string {
  const ONE = 1_000_000_000n;
  const whole = mist / ONE;
  const frac = mist % ONE;
  const fracStr = frac.toString().padStart(9, '0').slice(0, fractionDigits);
  return fractionDigits > 0 ? `${whole}.${fracStr}` : `${whole}`;
}

export function shortAddress(addr: string, head = 6, tail = 4): string {
  if (addr.length <= head + tail + 2) return addr;
  return `${addr.slice(0, head + 2)}…${addr.slice(-tail)}`;
}

// ═══════════════════════════════════════════════════════════════════════