/**
 * sui_tx.ts — 오라클 서명 트랜잭션 실행 (seed.ts / submit.ts 공용)
 *
 * ─────────────────────────────────────────────────────────────────────
 * ⚠️ 함정 1 — `tx.build({ client })`가 gRPC 클라이언트에서는 항상 던진다
 * ─────────────────────────────────────────────────────────────────────
 * "Transaction resolution is not supported with the GRPC client"
 * (`node_modules/@mysten/sui/src/grpc/core.ts`의 `resolveTransactionPlugin()`이
 * 통째로 `throw`만 하는 미구현 스텁이다 — 주석 처리된 구현 흔적만 남아 있다).
 * JSON-RPC 클라이언트 기준으로 설계된 "가스 코인 자동 선택 / 오브젝트 버전 자동
 * 조회" 기능이 gRPC 쪽엔 아직 없다는 뜻이다. 그래서 이 파일이 그 역할을 대신한다:
 * 가스 코인·가스 가격·shared object의 initial_shared_version을 **직접 읽어서
 * 트랜잭션에 미리 박아 넣는다.** 전부 채워져 있으면(`needsTransactionResolution`이
 * false) `tx.build()`가 이 미구현 경로를 아예 타지 않는다 — `resolveTransactionPlugin`
 * 자체가 그렇게 짜여 있다 (`node_modules/@mysten/sui/src/transactions/resolve.ts`).
 *
 * ─────────────────────────────────────────────────────────────────────
 * ⚠️ 함정 2 — `client.core.executeTransaction()`을 쓰면 안 된다
 * ─────────────────────────────────────────────────────────────────────
 * 이 래퍼(같은 `core.ts`)는 실패한 트랜잭션의 에러를
 * `JSON.stringify(effects.status.error)`로 문자열화하는데, MoveAbort의 abort_code
 * 필드가 **bigint**라서 `TypeError: Do not know how to serialize a BigInt`로 죽는다.
 * 즉 우리가 가장 자주 보게 될 에러(EAlreadyJoined 등 MoveAbort)에서 **항상** 죽는다
 * (SDK 버그, 원인 불명 크래시로 보인다 — read_state.ts 상단 함정 (2)와 같은 종류).
 *
 * 그래서 `client.core`를 거치지 않고 `transactionExecutionService`를 직접 호출해
 * status/abort code를 우리가 직접 읽는다. 새로 만들어진 오브젝트 ID를 뽑을 때도
 * 같은 이유로 `core`의 내부 헬퍼 대신 raw effects의 enum 숫자값을 직접 비교한다
 * (CREATED=2, SHARED=3 — proto 정의값. `@mysten/sui`가 이 enum을 공개 export하지
 * 않아 이름으로 못 가져온다. `node_modules/@mysten/sui/src/grpc/proto/sui/rpc/v2/
 * effects.ts`, `owner.ts` 참고).
 */

import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

export const SUI_COIN_TYPE = '0x2::sui::SUI';

/** 컨트랙트 에러 코드표 (challenge.move 상단 상수와 반드시 일치, QUICKSTART 부록 C와 동일) */
export const ABORT_CODES: Record<number, string> = {
  0: 'EZeroStake — 예치액 0',
  1: 'EAlreadyJoined — 이미 참여한 주소',
  2: 'EJoinClosed — 참여 마감(종료됐거나 마지막 날 초과)',
  3: 'ENotOracle — 오라클이 아님',
  4: 'ENotParticipant — 참가자가 아닌 주소',
  5: 'EAlreadyFailed — 이미 탈락 처리됨',
  6: 'EAllDaysSubmitted — 이미 총 일수만큼 제출함',
  7: 'EChallengeNotOver — 아직 D일이 안 끝났는데 finalize',
  8: 'EAlreadyEnded — 이미 종료된 방',
  9: 'ENotEnded — 종료 전에 claim',
  10: 'ENothingToClaim — 받을 게 0',
  11: 'EInvalidAlpha — alpha_bp > 10000',
  12: 'EWithdrawClosed — PENDING이 아닌데 withdraw',
};

export class MoveAbortError extends Error {
  constructor(
    public readonly code: number,
    description: string,
  ) {
    super(`MoveAbort ${code} — ${ABORT_CODES[code] ?? '알 수 없는 코드'} (${description})`);
    this.name = 'MoveAbortError';
  }
}

/** 트랜잭션마다 넉넉히 잡는 가스 예산. 실제로 쓰는 만큼만 차감되고 남는 건 환불된다 */
export const GAS_BUDGET = 30_000_000;

export function loadOracleKeypair(): Ed25519Keypair {
  const key = process.env.ORACLE_PRIVATE_KEY;
  if (!key) {
    throw new Error(
      'ORACLE_PRIVATE_KEY가 .env에 없다. `sui keytool export --key-identity yuan-oracle`로 얻어 ' +
        '.env의 ORACLE_PRIVATE_KEY에 넣을 것 (커밋 금지).',
    );
  }
  return Ed25519Keypair.fromSecretKey(key);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * shared object(Challenge)를 트랜잭션에 넣을 때는 `tx.object(id)`가 아니라 이 함수로
 * 얻은 참조를 `tx.sharedObjectRef(...)`에 넘겨야 한다. `tx.object(id)`는 버전 정보 없는
 * "UnresolvedObject"를 만드는데, 그걸 채우는 게 바로 gRPC에서 안 되는 그 자동 조회다.
 *
 * ⚠️ 방금 만든 오브젝트를 곧바로 조회하면 "Object not found"가 뜰 수 있다 — 실측으로
 * 확인함(create_challenge 성공 직후 join용 조회가 한 번 실패했다 재시도하니 됐다).
 * 풀노드의 읽기 경로가 쓰기를 즉시 못 따라가는 반영 지연으로 보인다. 그래서 짧게
 * 재시도한다 (총 ~6초, 데모 중 사람이 다음 명령을 치는 시간보다 짧다).
 */
export async function sharedObjectRef(
  client: SuiGrpcClient,
  objectId: string,
): Promise<{ objectId: string; initialSharedVersion: string; mutable: boolean }> {
  const ATTEMPTS = 6;
  let lastError: unknown;
  for (let attempt = 0; attempt < ATTEMPTS; attempt++) {
    if (attempt > 0) await sleep(1000);
    try {
      const { objects } = await client.core.getObjects({ objectIds: [objectId] });
      const obj = objects[0];
      if (obj instanceof Error) throw obj;
      if (!obj || obj.owner.$kind !== 'Shared') {
        throw new Error(`${objectId}는 shared object가 아니다 (owner: ${obj?.owner.$kind ?? 'unknown'})`);
      }
      return {
        objectId,
        initialSharedVersion: obj.owner.Shared.initialSharedVersion,
        mutable: true,
      };
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError instanceof Error ? lastError : new Error(String(lastError));
}

/** sender 소유의 SUI 코인 중 minValue 이상인 것을 하나 골라 가스 지불 + 필요시 split 재료로 쓴다 */
async function selectGasCoin(
  client: SuiGrpcClient,
  owner: string,
  minValue: number,
): Promise<{ objectId: string; version: string; digest: string }> {
  const { objects } = await client.core.getCoins({ address: owner, coinType: SUI_COIN_TYPE });
  const coin = objects.find((o) => BigInt(o.balance) >= BigInt(minValue));
  if (!coin) {
    throw new Error(
      `${owner} 소유의 SUI 코인 중 ${minValue} MIST 이상인 게 없다 — 잔고 부족 (진모에게 pay-sui 요청 필요할 수 있음)`,
    );
  }
  return { objectId: coin.id, version: coin.version, digest: coin.digest };
}

export interface TxOutcome {
  digest: string;
  /** 이 트랜잭션에서 새로 생성된 shared object들의 ID (예: create_challenge의 Challenge) */
  createdSharedObjectIds: string[];
}

/**
 * Transaction을 서명하고 실행해, 성공하면 결과를 돌려주고 실패하면 던진다.
 *
 * `minGasCoinValue`: 가스 코인에서 예산(GAS_BUDGET) 외에 더 빠져나갈 금액이 있으면
 * (예: join에서 `tx.splitCoins(tx.gas, [stake])`로 예치금도 같은 코인에서 쪼갤 때)
 * 그 금액까지 더해서 넘긴다. 기본값은 가스 예산만.
 */
export async function signAndExecute(
  client: SuiGrpcClient,
  tx: Transaction,
  signer: Ed25519Keypair,
  options: { minGasCoinValue?: number } = {},
): Promise<TxOutcome> {
  const sender = signer.toSuiAddress();
  tx.setSenderIfNotSet(sender);
  tx.setGasBudgetIfNotSet(GAS_BUDGET);

  const [gasPriceRes, gasCoin] = await Promise.all([
    client.core.getReferenceGasPrice(),
    selectGasCoin(client, sender, options.minGasCoinValue ?? GAS_BUDGET),
  ]);
  tx.setGasPrice(BigInt(gasPriceRes.referenceGasPrice));
  tx.setGasPayment([gasCoin]);

  const bytes = await tx.build({ client });
  const { signature } = await signer.signTransaction(bytes);

  const response = await client.transactionExecutionService.executeTransaction({
    transaction: { bcs: { value: bytes } },
    signatures: [
      {
        bcs: { value: Uint8Array.from(Buffer.from(signature, 'base64')) },
        signature: { oneofKind: undefined },
      },
    ],
    // ⚠️ 함정 3 — core.ts는 여기서도 'transaction.digest' 식으로 접두어를 붙이는데
    // executeTransaction 응답의 readMask는 ExecutedTransaction 필드에 직접 걸린다
    // (getTransaction과 달리 response.transaction 자체가 이미 ExecutedTransaction이라
    // 한 겹 덜 감싼다). 접두어를 붙이면 "invalid read_mask path"로 거부당한다.
    readMask: { paths: ['digest', 'effects'] },
  } as never).response;

  const executed = response.transaction as
    | { digest?: string; effects?: Record<string, unknown> }
    | undefined;
  if (!executed?.effects) {
    throw new Error('executeTransaction 응답에 effects가 없다 — 노드/네트워크 문제일 수 있다');
  }

  const status = executed.effects.status as
    | { success?: boolean; error?: { description?: string; errorDetails?: { oneofKind?: string; abort?: { abortCode?: bigint } } } }
    | undefined;

  if (!status?.success) {
    const err = status?.error;
    if (err?.errorDetails?.oneofKind === 'abort') {
      const code = Number(err.errorDetails.abort?.abortCode ?? -1n);
      throw new MoveAbortError(code, err.description ?? '');
    }
    throw new Error(`트랜잭션 실패: ${err?.description ?? '원인 불명'}`);
  }

  const changedObjects = (executed.effects.changedObjects ?? []) as Array<{
    objectId?: string;
    idOperation?: number;
    outputOwner?: { kind?: number };
  }>;
  const createdSharedObjectIds = changedObjects
    .filter((c) => c.idOperation === 2 /* CREATED */ && c.outputOwner?.kind === 3 /* SHARED */)
    .map((c) => c.objectId!)
    .filter(Boolean);

  return { digest: executed.digest ?? '', createdSharedObjectIds };
}
