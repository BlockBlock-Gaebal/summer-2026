# scripts — 오라클 / 데모 자동화

**담당: 유안 (C)** / 마감: 8/17

## 만드는 것
컨트랙트에 쓰기 트랜잭션을 날리는 CLI 스크립트. 데모의 조작부다.

- `create` — 챌린지 생성 (total_days, alpha_bp)
- `join` / `withdraw` — 참여 · 철회 (PENDING 구간 시연용)
- `submit` — 오라클 결과 제출 (탈락자 명단, 빈 명단도 가능)
- `finalize` / `claim`
- **`demo`** — 위 전체를 순차 실행. day 간격은 인자로 (기본 6초 — 대시보드 폴링 5초가 따라올 수 있는 속도)

## 스택
TypeScript + `@mysten/sui`. 키는 `.env`로 관리하고 **절대 커밋하지 말 것**.

## 데모 시나리오 기본값
D=5, 3인 각 10 SUI, day2 한 명 탈락, day4 한 명 탈락
→ 완주자 20 SUI / day4 탈락 8 SUI / day2 탈락 2 SUI (α=1.0 기준)

## 주의
- `submit_results`는 **탈락자가 없는 날도 빈 vector로 반드시 호출**해야 한다 (호출 = day 진행)
- 첫 `submit` 호출이 PENDING → ACTIVE 전환점이다. 그 전까지만 `withdraw` 가능
- 패키지 주소는 진모가 8/9 이후 공유
