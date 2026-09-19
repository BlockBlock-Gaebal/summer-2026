# docs/study — 비개발자용 학습 자료

> 이 폴더는 Locked In 프로젝트를 **처음 보는 사람(또는 AI 에이전트)** 이 전체 구조를 잡기 위한 설명 페이지다.
> 설계 결정의 정본은 `docs/DECISIONS.md`, 배포 정보의 정본은 `docs/DEPLOYMENT.md`, 당일 상황은 `docs/blockthon-2026/BLOCKTHON_STATUS.md`(아카이브)다.
> 이 폴더의 문서와 정본이 다르면 정본이 맞다.

| 파일 | 내용 | 대상 |
| --- | --- | --- |
| `01_프로젝트_해부도.html` | 한 문장 요약 · 등장인물 6명 · 판정 흐름 도식 · 실제 5일 타임라인 · 돈의 이동(60,000,000 MIST 정산) · 저장소 지도 · 용어 사전 · 알려진 한계 | 개발을 모르는 사람이 "이게 뭐고 어떻게 굴러가는지" 잡을 때 |
| `02_코드_해부.html` | 계층 구조와 통신 방식 · 온체인 데이터 구조(Challenge/Participant) · 상태 기계 · `submit_results` 내부 계산(acc_per_share, 정수 환급 공식) · 실행 시퀀스 · `agent.ts` 코드 조각과 안전장치 줄 번호 · 읽기(gRPC·dynamic field) · 설계 선택의 이유 · 기술 목록 | "기술적으로 어떻게 돌아가는지"를 코드 기준으로 볼 때 |

## 여는 법

브라우저(Chrome/Edge)로 파일을 열면 된다. 외부 의존성은 Google Fonts뿐이라 오프라인에서도 글꼴만 바뀌고 내용은 그대로 보인다.
`02_코드_해부.html`의 상태 기계·시퀀스 다이어그램은 mermaid 문법으로 적혀 있어 claude.ai 아티팩트 뷰어에서는 그림으로, 일반 브라우저에서는 텍스트로 보인다.

같은 내용의 claude.ai 링크(비공개, 다이어그램 렌더링됨):

- 프로젝트 해부도: https://claude.ai/artifact/PgF8GXJrLxTdMA3hVKCdB8
- 코드 해부: https://claude.ai/artifact/JPTabq38DoUGzGF8ofoUEr

## 기준 시점

2026-09-19 (Blockthon 2026 당일) 기준. 숫자는 발표용 방 `0x68295a39…` 의 실제 온체인 값이다.
