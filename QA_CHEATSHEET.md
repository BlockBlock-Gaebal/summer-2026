# QA_CHEATSHEET.md — 발표자용 한 장 (2026-09-19)

## 파일 5개

| 파일 | 한 줄 |
| --- | --- |
| `scripts/agent.ts` | 심판. 증빙 읽기 → Walrus 기억 로드 → LLM 판정 → `submit_results` 제출 → 기억 저장 |
| `scripts/replay.ts` | Walrus blob을 읽어 판정 로그를 그대로 다시 보여 줌 (LLM·키 불필요) |
| `scripts/web/server.ts` | 브라우저 입력 폼. 증빙 파일 만들고 agent.ts를 띄워 로그를 실시간 전달 |
| `contracts/godsaeng/sources/challenge.move` | 금고·환급 공식·정산. 8월 배포본 그대로, 재배포 없음 |
| `scripts/evidence/` | 참가자가 낸 글 (day1~5.json). 지금은 파일, 나중엔 앱 입력창 |

## ID와 링크

| 항목 | 값 |
| --- | --- |
| 발표용 방 (ENDED, dust 0) | `0x68295a39ed52b65876aaa0fcc7c84543aaefdfd9c533768f2bd008735b987218` |
| 3차 방 (라이브 dry-run용, ACTIVE day 2/5) | `0x5e6cd1579442041ed2a0c2da9d274df80e074961d6bb78edcc199020f997838f` |
| day3 tx (C 중복 FAIL) | `6s9Gz49dQaCkTt2qxRQ4DoNBnnddfDHSnRJF4izaDs8a` |
| day4 tx (B 중복 FAIL) | `8ALZt3EeWi2zELecDs4b53c9DzCaekmUrsbTD94r5FKh` |
| day3 blobId (판정 후 저장, 9건) | `Hiq56TNpx_GIqNYCJoM8-fgrmF2lHZoq4iOGTkAguUg` |
| day4 blobId (판정 후 저장, 11건) | `_2D5pYcZA9qwX7xxtBQjx1KUvqpPE8cnWU7sRsGIXws` |

- 방 보기: https://suiscan.xyz/testnet/object/0x68295a39ed52b65876aaa0fcc7c84543aaefdfd9c533768f2bd008735b987218
- day3 tx: https://suiscan.xyz/testnet/tx/6s9Gz49dQaCkTt2qxRQ4DoNBnnddfDHSnRJF4izaDs8a
- day4 tx: https://suiscan.xyz/testnet/tx/8ALZt3EeWi2zELecDs4b53c9DzCaekmUrsbTD94r5FKh
- day3 blob 원문: https://aggregator.walrus-testnet.walrus.space/v1/blobs/Hiq56TNpx_GIqNYCJoM8-fgrmF2lHZoq4iOGTkAguUg
- 대시보드: `cd frontend && npm run dev -- --host` → 기본이 발표용 방

## 실행 명령 3개 (전부 `cd ~/blockthon/summer-2026/scripts` 에서)

```bash
npx tsx replay.ts Hiq56TNpx_GIqNYCJoM8-fgrmF2lHZoq4iOGTkAguUg 3    # day3 판정 로그 재생 (C FAIL)
npx tsx replay.ts _2D5pYcZA9qwX7xxtBQjx1KUvqpPE8cnWU7sRsGIXws 4    # day4 판정 로그 재생 (B FAIL)
npx tsx agent.ts 3 --dry-run                                     # 3차 방 라이브: 기억 6건 로드 → C FAIL. 제출 안 됨
```

인터넷이 죽으면: `cat demo-logs/day3.log`, `cat demo-logs/day4.log`

## 예상 질문 7개

| # | 질문 | 답 |
| --- | --- | --- |
| Q1 | 오라클 = A = 승자 아니냐 | 데모라 키를 합쳤다. 컨트랙트는 오라클을 별도 주소로 받는다. 실서비스는 분리 |
| Q2 | blobId가 온체인에 없다 | 맞다. 지금은 로컬 포인터 + tx 시각으로 정황 증명. blobId 온체인 anchoring이 다음 단계 |
| Q3 | 왜 컨트랙트를 업그레이드 안 했나 | 정산 검증본을 그대로 쓰는 게 우선. UpgradeCap이 있어서 blobId 필드 추가는 재배포 없이 가능 |
| Q4 | 코사인 유사도면 되지 않나 | 규칙이 자연어라 확장 가능하고, 근거 문장이 감사 로그가 된다 |
| Q5 | 30일 100명이면 | 주소별 blob 분리 + 요약이 다음 단계. 요약하면 원문 재생성이 깨지는 트레이드오프 있음 |
| Q6 | 사용자 입력이 아니라 운영자 입력 아니냐 | 맞다. 참가자별 서명 제출은 스코프 밖 |
| Q7 | 규칙을 day3에 바꾸면 | 규칙 해시를 온체인에 박는 게 다음 단계. 지금은 사후 감사만 |

## 절대 하지 말 것

- "그건 개발자한테…" — 모든 답은 위 표 안에 있다
- "프로토 목표가 정산 수식 검증" 을 두 번 이상 말하기
