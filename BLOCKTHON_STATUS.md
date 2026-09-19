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
| node | v22.22.2 (WSL 기준. Windows는 v24.16.0) |
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
| 1차 방 (백업 방) | `0x5ea794e536eccc38f00e8b4d10759236ce8b08afc657dc0d35283a24e2034953` |
| 2차 방 (발표용 방, Walrus 연동) | `0x68295a39ed52b65876aaa0fcc7c84543aaefdfd9c533768f2bd008735b987218` |
| 3차 방 (Q&A 라이브 dry-run용, ACTIVE day 2/5) | `0x5e6cd1579442041ed2a0c2da9d274df80e074961d6bb78edcc199020f997838f` |

3차 방은 발표용 방과 같은 evidence로 **day 2까지 제출**해 두었다 (day1 `2kZyRtJN…`, day2 `Bqp286Gv…`, 둘 다 전원 PASS).
`scripts/.env`의 `CHALLENGE_ID`가 이 방을 가리키고, `.walrus-memory`는 day2 blob `yOEO1ytS0SeE6jtueRtKD922FZNDLLfMV7rBGI7mzG0`(기억 6건)을 가리킨다.
Q&A에서 "지금 돌려볼 수 있냐"가 나오면 `cd scripts && npx tsx agent.ts 3 --dry-run`을 친다 — 기억 6건을 로드해 C가 중복 FAIL로 나온다. **제출은 하지 않는다.**

`docs/DEPLOYMENT.md`에는 오라클 `0x982fcf2d…`가 진모의 오라클 주소로 기록되어 있으나,
WSL 키스토어에서 해당 키를 찾지 못했다. 다른 환경에 있을 가능성이 있다.
`create_challenge`를 호출한 주소가 그 방의 오라클이 되므로, 방을 새로 만들어 진행했다.

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
- **`.walrus-memory`에는 방 구분이 없다.** 새 방을 만들 때는 이 파일을 삭제하고 시작해야 한다. 그대로 두면 이전 방의 기억이 새 방의 판정에 섞인다.

---

## 5. 시나리오 결과

두 방 모두 같은 파라미터(5일, `alpha_bp = 2000`, 3인 × 0.02 SUI)와 같은 탈락 일정으로 돌렸다.

| 구분 | 방 | 판정 | 기억 저장소 | 용도 |
| --- | --- | --- | --- | --- |
| 1차 | 백업 방 `0x5ea794e5…` | day1 더미, day2~5 LLM | 로컬 `memory.json` | 백업. 건드리지 않는다 |
| 2차 | 발표용 방 `0x68295a39…` | day1~5 전부 LLM | Walrus | 발표 |

### 5-1. 2차 — 발표용 방 (Walrus 연동)

| 단계 | 판정 | 다이제스트 | Walrus blobId (저장 후) |
| --- | --- | --- | --- |
| create | | `7VagpPr5byR2LQryUuAt6XDcdQzrQeUCsU8gvqvhZdwm` | |
| join A | | `8Q5EjQyZU6hdrfDkZpV3PnVnnZbC6mnSA3sn7KBsKr8W` | |
| join B | | `7kBR6epXTRzmTr5Ausm5akibigMcD51Cn4oEr6W6ewZ8` | |
| join C | | `CiMh7hsjybePHTWUf7rLt1YXHqQd4R6MU3nTBJmS17BP` | |
| 1 | 전원 PASS | `2HAPByjpzADiahpFYDk279hj4V2r798tJArQPVsdptNh` | `k_aI1-yeDSTgPb8P6wIYvUEFR1xhF2ptn7zDPQyw8eg` |
| 2 | 전원 PASS | `E8MpKSw1rS4brLHR4jQYpmqn6QBbsY7rSsJdEJ7E2f8j` | `GvMPYg4VNeN61We_o-HQtM7Kg41GJzekvW3tCWuRo5Y` |
| 3 | C 중복 FAIL | `6s9Gz49dQaCkTt2qxRQ4DoNBnnddfDHSnRJF4izaDs8a` | `Hiq56TNpx_GIqNYCJoM8-fgrmF2lHZoq4iOGTkAguUg` |
| 4 | B 중복 FAIL | `8ALZt3EeWi2zELecDs4b53c9DzCaekmUrsbTD94r5FKh` | `_2D5pYcZA9qwX7xxtBQjx1KUvqpPE8cnWU7sRsGIXws` |
| 5 | A PASS | `9cH2WLQQjbEz7uoHz8KFgHez4myVeTwFBBwRpwmPkRaA` | `xoDph4cl6J9mZjQ9HiL7kMAdJYsGCy7a7CSuT5RBt6Y` |
| finalize | | `CbzaD8QTpPBptwVKgfqK3UYkw3NUNYVPGS22RscR5HKq` | |

판정 전에 Walrus에서 불러온 기억 건수는 day1~5에 걸쳐 **0 → 3 → 6 → 9 → 11건**으로 늘었다.
저장 직후마다 다시 읽어 원본과 대조했고 5회 모두 일치했다.

FAIL 근거는 두 건 모두 중복 하나뿐이다.

- day3 C: "오늘 제출은 Day 1의 내용(조건부확률, 베이즈 정리 유도, 질병 검사 양성 사후확률 계산 5문제)과 사실상 동일한 내용을 재서술한 것으로 판단된다."
- day4 B: "오늘 제출 내용은 day 2에서 이미 학습한 교착상태 4가지 필요조건 정리 및 은행원 알고리즘 예제 2개 풀이와 사실상 동일하다. 새로운 학습 내용이 없으므로 인정하지 않는다."

판정 로그는 `scripts/replay.ts`로 Walrus에서 다시 볼 수 있다 (`cd scripts && npx tsx replay.ts <blobId> [day]`).
aggregator가 응답하지 않을 때를 위해 day3·day4 출력을 `scripts/demo-logs/`에 저장해 두었다.

최종 정산은 1차와 동일하다 (A 45,040,000 / B 10,800,000 / C 4,160,000 MIST, 합계 60,000,000 = vault, **dust 0**, ENDED).
같은 파라미터와 같은 탈락 일정에서 정산 결과가 결정적으로 재현된 것이다.

### 5-2. 1차 — 백업 방

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
| 오라클 권한의 제한과 회수를 온체인으로 강제하지 못한다 | `submit_results`가 `ctx.sender()`를 검사한다. 권한이 capability 객체가 아니라 sender에 묶여 있어 래퍼 모듈로 제한하거나 위임할 수 없다. 강제하려면 재배포가 필요하다 |
| 텍스트 증빙은 위조가 쉽다 | 컨트랙트는 "누가 탈락했는가"만 받으므로 증빙 타입은 교체 가능한 부품이다 |
| 참가자 상태를 shared object 하나에 넣었다 | 프로토 목표가 정산 수식 검증이었다. 참가자별 객체 분리는 병렬성 확보를 위한 다음 단계이다 |

---

## 8. 커밋 현황

| PR | 내용 |
| --- | --- |
| #34 | `BLOCKTHON.md` 추가, `CLAUDE.md`에 포인터 한 줄 |
| #35 | `feat/ai-agent-judge` — `scripts/agent.ts`(Walrus 연동 포함), `scripts/evidence/`, `BLOCKTHON_STATUS.md`(이 문서), `deck.html` |

`scripts/memory.json`, `scripts/.walrus-memory`, `scripts/.env`는 `.gitignore` 대상이다.
`contracts/`와 `docs/DEPLOYMENT.md`는 이번 작업에서 수정하지 않았다.
