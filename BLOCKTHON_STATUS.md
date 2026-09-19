# BLOCKTHON_STATUS.md — 2026-09-19 당일 진행 상황

> 이 문서는 Blockthon 2026 당일 작업의 현재 상태를 기록한다.
> 대회 대응 판단 기준은 `BLOCKTHON.md`, 프로토콜 설계 정본은 `docs/DECISIONS.md`이다.
> 이 문서는 대회가 끝나면 아카이브 대상이다.

---

## 1. 한 줄 요약

여름에 완성한 정산 엔진 위에, 비어 있던 판정 레이어를 **기억 기반 AI 에이전트**로 채웠다.
사용자가 텍스트로 증빙을 제출하면, 에이전트가 Walrus에서 과거 기록을 불러와 오늘 제출과 대조하고,
판정 결과를 `submit_results`로 온체인에 제출한다. 컨트랙트는 재배포하지 않았다.

---

## 2. 작업 환경

| 항목 | 값 |
| --- | --- |
| 작업 위치 | WSL `~/blockthon/summer-2026` |
| 주의 | Windows에는 sui CLI가 없다. 모든 온체인 작업은 WSL에서 한다 |
| sui | 1.75.2 |
| node | v24.16.0 |
| 네트워크 | testnet |
| 개발 방식 | Claude Code 바이브코딩 |

---

## 3. 주소와 객체

| 역할 | 값 |
| --- | --- |
| PACKAGE_ID | `0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60` |
| 오라클 = 참가자 A | `0x1d0bb9ab7409b943d740f21b4cd359387ccb1477fc9d92369e7ae84d54d09249` |
| 참가자 B | `0xdf8989618416814503a001b5799f8f11059088ac0ba7d9b1b20cf50e6bbee71b` |
| 참가자 C | `0xca849b28f4729eb7dfe03cd6facb35f269e24497816f801ba71de81e424d1bdb` |
| 1차 방 (백업) | `0x5ea794e536eccc38f00e8b4d10759236ce8b08afc657dc0d35283a24e2034953` |
| 2차 방 (Walrus 연동) | `0x68295a39ed52b65876aaa0fcc7c84543aaefdfd9c533768f2bd008735b987218` |

`docs/DEPLOYMENT.md`에 적힌 오라클 `0x982fcf2d…`의 개인키는 김유안이 보유하고 있어 이번에는 사용하지 못했다.
`create_challenge`를 호출한 주소가 그 방의 오라클이 되므로, 방을 새로 만들어 해결했다.

---

## 4. 만든 것

### `scripts/agent.ts`

```
evidence/day{N}.json 읽기
  → Walrus에서 과거 기억 로드
  → LLM 판정 (규칙 + 과거 기록 + 오늘 제출)
  → FAIL 명단 산출
  → sui client ptb 로 submit_results 호출
  → 성공하면 갱신된 기억을 Walrus에 저장
```

- LLM은 Anthropic Messages API를 `fetch`로 직접 호출한다. 모델은 `claude-sonnet-4-6`이다.
- API 키는 `process.env.ANTHROPIC_API_KEY`에서만 읽는다. 로그에 출력하지 않는다.
- 개인키를 파일에 두지 않는다. 서명은 `sui client ptb`의 CLI 서명을 사용한다.
- 과거 제출 텍스트는 `<past_submissions>` 태그로 감싸고 데이터로만 다루도록 지시한다. 프롬프트 인젝션을 막기 위한 조치이다.

### 안전장치

다음 경우에는 `submit_results`를 호출하지 않고 중단한다.

| 조건 | 이유 |
| --- | --- |
| 요청한 day와 체인의 다음 day가 다를 때 | 중복 제출 방지 |
| 증빙에 방 밖 주소나 중복 주소가 있을 때 | 오판정 방지 |
| 생존 참가자의 증빙이 빠졌을 때 | 파일 실수로 인한 탈락 방지 |
| 생존자 전원이 FAIL일 때 | 전멸 오판정 방지 (`--allow-wipeout`으로 허용 가능) |
| active address가 오라클이 아닐 때 | 권한 오류 방지 |
| dry-run 결과와 실제 판정이 다를 때 | `--expect-fail`로 지정한 명단과 대조 |

`--dry-run`을 붙이면 판정과 CLI dry-run까지만 하고 제출하지 않는다.

### Walrus 연동

- 저장: `PUT https://publisher.walrus-testnet.walrus.space/v1/blobs?epochs=5`
- 로드: `GET https://aggregator.walrus-testnet.walrus.space/v1/blobs/{blobId}`
- blobId는 `scripts/.walrus-memory`에 기록한다.
- 업로드 직후 읽으면 CDN이 404를 캐싱할 수 있으므로 1초, 2초, 4초 간격으로 3회 재시도한다.
- 저장은 온체인 제출이 성공한 뒤에만 한다. dry-run 단계에서 저장하면, 재실행할 때 오늘 제출이 과거 기록으로 잡혀 자기 자신과 중복 판정이 난다.

---

## 5. 1차 시나리오 결과 (백업 방)

| day | 판정 | 다이제스트 |
| --- | --- | --- |
| create | | `GGuvR2XgKrzEkP4v6K8KKSR3zqJqAfTPsDrsyFYAqtCR` |
| 1 | 더미 판정, 전원 PASS | `E6riqvFFkCFp4qYGnK3kAjTeJdp1dENm3Ur38ccVTAGR` |
| 2 | 전원 PASS | `GMD6BT68fVp4sMSe19cSCHQLWitnpse7Ph23M6KFjrav` |
| 3 | C 중복 FAIL | `GWTKtxQZMAGJK33hfTGWrC8p21RasaWw4S9je2ds35hr` |
| 4 | B 중복 FAIL | `BgACPdpVHGgVUFGU7yrJF7eabuxSvn7kHHGTfKWwXh3U` |
| 5 | A PASS | `BiDEwgHyVKt9YNxb7FMuhSTYUvKCCdTHAP7hywdzHx7A` |
| finalize | | `F5xqrTWBf2ZD8P6VoZEuXHLcmcoh588yRQyNyVRXRvxt` |

최종 정산은 다음과 같다.

| 참가자 | 탈락일 | claimable (MIST) | SUI |
| --- | --- | --- | --- |
| A | 완주 | 45,040,000 | 0.04504 |
| B | day 4 | 10,800,000 | 0.01080 |
| C | day 3 | 4,160,000 | 0.00416 |
| 합계 | | 60,000,000 | 0.06 |

status는 ENDED이고 dust는 0이다. 아무도 claim하지 않아 vault가 예치 총액 그대로이므로,
보존 법칙을 화면에서 그대로 검산할 수 있다. **이 방에서는 claim을 하지 않는다.**

---

## 6. 발표 구성

화면 세 개를 전환한다.

| 화면 | 내용 |
| --- | --- |
| HTML 덱 | 문제 정의, 환급 커브, 아키텍처, 최종 정산표, 한계와 확장 |
| 터미널 | 에이전트 판정 로그. 과거 기억 로드와 중복 판정 근거가 보인다 |
| 대시보드 | `npm run dev -- --host` 후 `?challenge=<방ID>`로 접속 |

대시보드는 URL 쿼리로 방을 바꿀 수 있으므로 `src/config.ts`를 수정할 필요가 없다.

---

## 7. 알려진 한계 (Q&A 대비)

| 한계 | 답변 방향 |
| --- | --- |
| 지갑 UI가 없다 | 참가와 예치는 실제 온체인 트랜잭션이다. 지갑 UI는 스코프에서 제외했다 |
| Walrus blob이 공개라 제출 원문이 노출된다 | Seal이 이 문제를 위한 레이어이다. 판정 근거는 공개하고 제출 원문은 가리는 분리가 다음 단계이다 |
| 오라클 권한의 제한과 회수를 온체인으로 강제하지 못한다 | `submit_results`가 `ctx.sender()`를 검사하므로 래퍼 모듈로는 우회가 가능하다. 강제하려면 재배포가 필요하다 |
| 텍스트 증빙은 위조가 쉽다 | 컨트랙트는 "누가 탈락했는가"만 받으므로 증빙 타입은 교체 가능한 부품이다 |
| 참가자 상태를 shared object 하나에 넣었다 | 프로토 목표가 정산 수식 검증이었다. 참가자별 객체 분리는 병렬성 확보를 위한 다음 단계이다 |

---

## 8. 커밋 현황

| PR | 내용 |
| --- | --- |
| #34 | `BLOCKTHON.md` 추가, `CLAUDE.md`에 포인터 한 줄 |
| #35 | `feat/ai-agent-judge` — `scripts/agent.ts`, `scripts/evidence/` |

`scripts/memory.json`과 `scripts/.env`는 `.gitignore` 대상이다.
`contracts/`와 `docs/DEPLOYMENT.md`는 이번 작업에서 수정하지 않았다.
