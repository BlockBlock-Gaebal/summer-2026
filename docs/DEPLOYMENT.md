# DEPLOYMENT.md — 배포 정보 (정본)

> **이 파일이 배포 정보의 유일한 정본이다.**
> 로컬 메모, 카톡, 개인 코드에 적힌 ID는 전부 사본일 뿐이며 이 파일과 다르면 이 파일이 맞다.
> 재배포 시 규칙: **① 이 파일 갱신 → ② PR → ③ 단톡 통보.** 셋 다 해야 완료.

---

## 현재 배포 (Sui Testnet)

| 항목 | 값 |
|---|---|
| 네트워크 | Sui **Testnet** |
| 배포일 | 2026-08-09 |
| 배포자 | 진모 |

```
Package ID
0x11615c35e5bda13cb1f86c17b076e8ec025fcb0008fdf68ddc9ab0c290612e60

Challenge ID (shared object)
0xfb1eb049655a716a4270e977f948f02da07bfb60736acf7fe1dc08a66c78c6b7

참가자 Table ID
0xca4d8522d37c09d0e8f6ac5a98ee8673c8da2d408a9dacc80d531c3b1fd75f80

오라클 주소 (진모)
0x982fcf2d322d579917cd45a3ec2903460d52fddd5deb74f2c4ecfa86d5dedb65
```

---

## 사용 규칙

- **코드에 ID를 하드코딩하지 않는다.** 각자 파트에서 config 파일 / 환경변수 등 한 군데로 모아두고 거기서만 읽는다.
  - 파일 이름·형식은 각자 재량 (예: `frontend/src/config.ts`, `scripts/.env`)
  - 목적: 재배포 시 각자 한 줄만 고치면 되게
- 배포 ID는 **프리즈 대상이 아니다.** 재배포는 언제든 가능하며, 위 3단계 절차만 지키면 된다. (프리즈 범위는 `DECISIONS.md` 참조)

---

## 참가자 Table 조회 주의

`Table<address, Participant>`는 Sui에서 **dynamic field**로 저장된다.
따라서 `getObject(Table ID)`로는 **참가자 내용이 나오지 않는다** (껍데기만 나옴).

조회는 2단계:

1. `getDynamicFields(Table ID)` → 엔트리 목록
2. 각 엔트리에 `getDynamicFieldObject` → 실제 Participant 값

→ 이 로직은 **`scripts/read_state.ts`로 공용화**한다 (담당: 진모). 프론트·오라클 양쪽에서 재사용할 것.

---

## 배포 이력

| 날짜 | 변경 사유 | Package ID (앞 8자리) |
|---|---|---|
| 2026-08-09 | 최초 Testnet 배포 (ver1~4) | `0x11615c35` |
