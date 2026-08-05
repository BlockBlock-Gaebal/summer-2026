# frontend — 읽기 전용 대시보드

**담당: 승준 (B)** / 마감: 8/17

## 만드는 것
Sui Testnet의 Challenge 객체를 **읽어서 화면에 뿌리기만** 한다.

- 참가자 목록 + 상태 (대기 / 생존 / 탈락)
- 탈락자의 확정 환급액, 각자 누적 claimable
- 현재 day / 전체 day, 챌린지 상태 (PENDING / ACTIVE / ENDED)
- (여유되면) 커브 그래프 위에 각 참가자 점 찍기 — 우리 차별점이 눈에 보이는 유일한 지점

## 만들지 않는 것
지갑 연결, 트랜잭션 서명, 참여·claim 버튼, 로그인, 반응형, 다크모드, 백엔드 연동.
**쓰기는 전부 `scripts/`가 CLI로 한다.**

## 스택
Vite + React + TypeScript, `@mysten/sui` (RPC 읽기 전용), 폴링 5초.

## 컨트랙트 조회 함수 (8/9 확정)
`status` / `total_days` / `alpha_bp` / `daily_drip` / `participant_addresses`
/ `stake_of` / `start_day_of` / `failed_day_of` / `claimable_of`
/ `vault_value` / `participant_count` / `current_day`

`participant_addresses`로 주소 목록을 받아 주소별로 나머지를 조회하는 구조다.

## 주의
- **day1 탈락자는 claimable이 0이라 claim이 abort된다.** claim 버튼/표시를 띄우면 안 된다
- 패키지 주소·Challenge 객체 ID는 진모가 8/9 이후 공유. 그전엔 mock 데이터로 화면부터 만들 것
