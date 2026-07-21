---
marp: true
paginate: true
theme: default
title: 갓생 내기 DeFi 프로토콜
style: |
  section {
    font-family: Pretendard, "Noto Sans KR", sans-serif;
    font-size: 30px;
    padding: 55px 70px;
    background: #f8fafc;
    color: #172033;
  }
  h1 {
    font-size: 52px;
    color: #111827;
    margin-bottom: 24px;
  }
  h2 {
    font-size: 34px;
    color: #2563eb;
  }
  strong {
    color: #2563eb;
  }
  blockquote {
    border-left: 6px solid #2563eb;
    background: #eff6ff;
    padding: 14px 22px;
    font-size: 31px;
  }
  table {
    font-size: 24px;
  }
  code {
    font-size: 25px;
  }
  .center {
    text-align: center;
  }
  .big {
    font-size: 42px;
    font-weight: 700;
  }
  .flow {
    text-align: center;
    font-size: 34px;
    line-height: 1.8;
  }
  .small {
    font-size: 22px;
    color: #64748b;
  }
---

<!-- _class: center -->

# 갓생 내기 DeFi 프로토콜

<div class="big">의지력에 돈을 거는 Sui 기반 습관 챌린지</div>

<br>

**블록블록 여름 개발 프로젝트 중간발표**

<!--
발표 멘트:
사용자가 습관 목표에 돈을 예치하고, 실패하면 일부를 잃으며,
성공자는 그 몰수금을 보상받는 서비스입니다.
오늘은 아이디어 소개보다 현재 구현한 정산 메커니즘을 중심으로 공유하겠습니다.
-->

---

# 기존 습관 내기 서비스의 문제

<div class="flow">

사용자가 돈을 예치한다  
↓  
운영사가 돈을 보관한다  
↓  
운영사가 성공 여부와 보상을 결정한다

</div>

> **돈과 판정 규칙을 모두 운영사를 믿어야 한다.**

<!--
발표 멘트:
챌린지 앱의 아이디어 자체는 이미 시장에서 검증됐습니다.
문제는 운영사가 예치금과 정산 결과를 모두 통제한다는 점입니다.
-->

---

# 우리의 해결 방식

<div class="flow">

**인증 결과는 Off-chain에서 제출**  
↓  
**예치금과 정산 규칙은 Smart Contract가 집행**  
↓  
**사용자가 직접 보상을 Claim**

</div>

> 운영팀도 예치금을 가져가거나 정산 결과를 임의로 바꿀 수 없다.

<!--
발표 멘트:
현실 행동은 블록체인이 직접 볼 수 없으므로 인증은 오프체인에서 처리합니다.
하지만 돈을 보관하고 얼마를 몰수할지는 온체인에서 결정합니다.
-->

---

# 현재까지 구현한 범위

| 구현 항목 | 현재 상태 |
|---|---:|
| Sui Move 정산 Contract | ✅ |
| 예치금 Vault | ✅ |
| 일별 결과 제출 | ✅ |
| 환급·몰수·배당 계산 | ✅ |
| 종료 후 개별 Claim | ✅ |
| Move Test | **21 / 21 통과** |
| Frontend · Backend | 다음 단계 |

<div class="small">현재는 전체 앱 중 가장 중요한 ‘돈 정산 엔진’을 먼저 구현한 단계입니다.</div>

<!--
발표 멘트:
화면은 아직 없지만, 돈이 들어오고 결과에 따라 나뉘고 다시 나가는
핵심 정산 흐름은 이미 Move Contract에서 작동합니다.
-->

---

# 정산 로직의 발전 과정

| 버전 | 핵심 변화 |
|---|---|
| **ver1** | 동일 예치금 · 탈락자 전액 몰수 |
| **ver2** | 가변 예치금 · 지분 비례 분배 |
| **ver3** | 시간가중 환급 · Streaming 분배 |
| **ver4** | 중도 참여 · `acc_per_share` 회계 |

> **핵심 차별점은 ver3의 시간가중 정산입니다.**

<!--
발표 멘트:
처음부터 복잡한 구조를 만들지 않고 기본형부터 한 단계씩 일반화했습니다.
ver3가 우리 아이디어의 핵심이고, ver4에서는 중도 참여까지 확장했습니다.
-->

---

# 차별점 ① 시간가중 환급

<div class="center">

## 같은 탈락이라도 똑같이 처리하지 않는다

</div>

```text
초반 탈락 → 적은 환급 → 큰 몰수
후반 탈락 → 많은 환급 → 작은 몰수
완주       → 원금 전액 환급
```

\[
r(d)=\alpha\frac{d}{D}+(1-\alpha)\left(\frac{d}{D}\right)^2
\]

<div class="small">d: 수행 기간 · D: 전체 기간 · α: 커브의 강도</div>

<!--
발표 멘트:
기존 구조에서는 day 2 탈락과 day 29 탈락을 동일하게 처리합니다.
저희는 수행 기간에 따라 환급률을 높여 노력한 기간을 정산에 반영합니다.
-->

---

# 차별점 ② Streaming 분배

## 몰수금을 그날 바로 전부 나누지 않습니다

```text
즉시 분배
day 2 몰수금 8 SUI → day 2에 전액 지급

Streaming
day 2 몰수금 8 SUI → 종료일까지 나누어 지급
```

> 과거에 발생한 몰수금도 계속 방출되므로  
> **오래 생존할수록 받을 수 있는 보상이 누적됩니다.**

<!--
발표 멘트:
초반에는 탈락자가 많고 몰수액도 큽니다.
이를 즉시 나누면 보상이 초반에 몰리고 후반에는 계속할 유인이 약해집니다.
Streaming은 그 보상을 남은 기간에 걸쳐 나눕니다.
-->

---

# 하나의 예시로 보는 정산 결과

**A, B, C가 각각 10 SUI 예치 · 5일 챌린지**

| 참가자 | 결과 | 환급 | 배당 | 최종 수령 |
|---|---:|---:|---:|---:|
| A | 완주 | 10.0 | +6.5 | **16.5** |
| C | Day 4 탈락 | 8.0 | +1.5 | **9.5** |
| B | Day 2 탈락 | 4.0 | 0 | **4.0** |
| **합계** |  |  |  | **30.0 SUI** |

> **B ≠ C:** 같은 탈락자라도 수행 기간에 따라 결과가 다릅니다.

<!--
발표 멘트:
C는 완주하지 못했지만 day 4까지 버틴 만큼 더 많은 원금과
그동안 쌓인 배당을 가져갑니다.
그리고 총 예치금 30 SUI가 정확히 보존됩니다.
-->

---

# 왜 Sui인가?

| Sui의 특징 | 서비스에서 얻는 이점 |
|---|---|
| **Object Model** | 챌린지 방을 독립된 On-chain Object로 관리 |
| **Move Resource Safety** | Coin의 임의 복제·소실 방지 |
| **Coin / Balance 구조** | 예치금을 Vault에 명확하게 보관 |
| **PTB** | 예치·참여 등록을 한 Transaction으로 처리 |
| **Object 병렬처리** | 서로 다른 챌린지를 독립적으로 처리 |
| **zkLogin** | 향후 일반 로그인과 유사한 UX 제공 |

> 단순히 빠른 체인이 아니라, **자산과 챌린지를 Object로 다루는 구조가 서비스와 잘 맞습니다.**

<!--
발표 멘트:
현재 구현에는 Shared Object와 Coin/Balance 구조가 적용돼 있습니다.
PTB, zkLogin, Sponsored Transaction은 사용자 앱을 붙이는 단계에서 적용할 예정입니다.
-->

---

# 현재 구현된 Contract 흐름

<div class="flow">

`create_challenge()`  
↓  
`join()` — SUI 예치  
↓  
`submit_results()` — 일별 결과 제출  
↓  
`finalize()` — 최종 정산  
↓  
`claim()` — 각자 보상 수령

</div>

<div class="small">모든 시나리오에서 참가자 수령액 + Vault 잔액 = 최초 예치금인지 검증합니다.</div>

<!--
발표 멘트:
정산 과정은 다섯 개의 핵심 함수로 구성됩니다.
일괄 송금이 아니라 각자가 claim하는 pull pattern을 적용했습니다.
-->

---

# 최종 발표까지의 개발 계획

## 1. 정산 규칙 확정

- 성공 기준과 Grace Day
- 환급 커브의 α
- 전원 탈락 처리
- 중도 참여 마감선

## 2. 사용자 앱 연결

- Testnet 배포
- Frontend + Wallet
- 사진 Check-in
- Backend Oracle
- 정산 결과와 Claim 화면

<!--
발표 멘트:
가장 먼저 미결 규칙을 확정하고 테스트 값을 고정해야 합니다.
그다음 Contract를 Testnet에 배포하고 Frontend와 Backend를 연결합니다.
-->

---

# 최종 데모 목표

<div class="flow">

세 명이 SUI를 예치  
↓  
매일 Check-in 결과 제출  
↓  
한 명은 초반 탈락, 한 명은 후반 탈락, 한 명은 완주  
↓  
시간가중 환급 + Streaming 정산  
↓  
각 사용자가 직접 Claim

</div>

> **Testnet에서 예치부터 정산까지 End-to-End로 시연**

<!--
발표 멘트:
최종 발표에서는 단순 테스트 통과 화면이 아니라,
실제 세 Wallet이 참여하고 각자의 정산금을 받는 전 과정을 보여주는 것이 목표입니다.
-->

---

<!-- _class: center -->

# 현재까지의 결론

<div class="big">

돈 정산 로직은 이미 작동합니다.

</div>

<br>

## 남은 과제는 이 Contract를  
## 사람이 실제로 사용할 수 있는 서비스로 연결하는 것입니다.

<!--
마무리 멘트:
현재까지는 서비스의 가장 어려운 돈 로직을 먼저 구현했습니다.
앞으로는 인증, Wallet, 화면을 붙여 실제 사용 가능한 서비스로 완성하겠습니다.
-->
