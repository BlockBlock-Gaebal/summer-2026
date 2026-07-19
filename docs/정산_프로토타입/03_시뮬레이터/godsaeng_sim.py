# -*- coding: utf-8 -*-
"""
갓생 내기 프로토콜 — 정산 로직 payoff 시뮬레이터
=================================================
설계안: 볼록 환급 커브 + 스트리밍(베스팅) 분배

  환급률   r(d) = α·(d/D) + (1-α)·(d/D)²          # α ∈ [0,1] : 선형 비중
  몰수액   f(d) = stake · (1 - r(d))
  분배     day d 몰수액을 잔여 (D-d+1)일에 걸쳐 균등 drip,
           매일의 drip을 그날 생존자에게 예치금 지분 비례 분배
           (그날 탈락자는 그날 배당에서 제외)

사용법:
  python3 godsaeng_sim.py            # 전체 표 + 그래프 생성
  코드 하단 SCENARIOS / ALPHAS 를 수정해서 케이스 추가

주의: 이 시뮬은 float 기준. 온체인 구현은 u64/u128 정수 스케일링이라
      dust(정수 나눗셈 나머지)가 추가로 발생함 → 보존 법칙 테스트는
      `분배총합 + dust == 예치총합` 형태로 검증할 것.

실행 환경: python3 + numpy, pandas, matplotlib 필요
  pip install numpy pandas matplotlib
  (한글 폰트: Windows는 맑은 고딕이 기본 내장되어 있어 별도 설정 불필요.
   폰트가 깨지면 아래 폰트 설정 블록을 자신의 OS에 맞게 수정할 것.)
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib import font_manager
import os
import platform

# ---------------------------------------------------------------- 폰트/스타일
# 리눅스(원 개발 환경) 기준 경로. Windows/Mac에서 폰트가 깨지면 아래 분기를 참고해 수정.
if platform.system() == "Windows":
    plt.rcParams["font.family"] = "Malgun Gothic"
elif platform.system() == "Darwin":
    plt.rcParams["font.family"] = "AppleGothic"
else:
    _KR = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    if os.path.exists(_KR):
        font_manager.fontManager.addfont(_KR)
        plt.rcParams["font.family"] = font_manager.FontProperties(fname=_KR).get_name()
plt.style.use("seaborn-v0_8-whitegrid")
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams.update({"figure.dpi": 150, "font.size": 11,
                     "axes.titlesize": 13, "axes.titleweight": "bold"})

C_BLUE, C_ORANGE, C_GREEN, C_RED, C_PURPLE, C_GRAY = \
    "#4C72B0", "#DD8452", "#55A868", "#C44E52", "#8172B3", "#999999"

FIGDIR = "figures"
os.makedirs(FIGDIR, exist_ok=True)


# ================================================================ 핵심 수식
def retention(d: float, D: int, alpha: float) -> float:
    """day d 탈락 시 환급률 r(d) ∈ [0,1]. d=D(완주)면 1."""
    x = d / D
    return alpha * x + (1.0 - alpha) * x * x


def forfeit(stake: float, d: int, D: int, alpha: float) -> float:
    """day d 탈락 시 몰수액."""
    return stake * (1.0 - retention(d, D, alpha))


# ================================================================ 정산 엔진
def settle(stakes: dict, fail_days: dict, D: int, alpha: float,
           streaming: bool = True) -> pd.DataFrame:
    """
    stakes    : {"A": 10.0, ...}
    fail_days : {"B": 2, ...}   (없으면 완주)
    streaming : True = 스트리밍 분배 / False = 즉시 분배(비교용)

    반환: 참가자별 환급 / 누적배당 / 총수령 + 보존 검증
    규칙: day d 탈락자는 day d 배당부터 제외 (탈락과 동시에 자격 상실)
          day d 몰수액의 스트림은 day d 부터 잔여 (D-d+1)일간 흐름
    """
    names = list(stakes)
    fail = {n: fail_days.get(n, 0) for n in names}          # 0 = 완주
    div = {n: 0.0 for n in names}                            # 누적 배당
    drip = 0.0                                               # 전역 daily drip

    for d in range(1, D + 1):
        todays_failed = [n for n in names if fail[n] == d]
        survivors = [n for n in names if fail[n] == 0 or fail[n] > d]
        s_sum = sum(stakes[n] for n in survivors)

        # 오늘 발생한 몰수 → 스트림 편입 (or 즉시 분배)
        day_forfeit = sum(forfeit(stakes[n], d, D, alpha) for n in todays_failed)

        if streaming:
            for n in todays_failed:
                drip += forfeit(stakes[n], d, D, alpha) / (D - d + 1)
            payout_today = drip
        else:
            payout_today = day_forfeit

        if survivors and s_sum > 0 and payout_today > 0:
            for n in survivors:
                div[n] += payout_today * stakes[n] / s_sum
        # 생존자 0명이면 그날 배당은 소멸 대신 스트림에 남음
        # (전멸 엣지케이스 — 실제 컨트랙트에선 처리 규칙 필요, 설계문서 참고)

    rows = []
    for n in names:
        d = fail[n]
        refund = stakes[n] if d == 0 else stakes[n] - forfeit(stakes[n], d, D, alpha)
        rows.append({"참가자": n, "예치": stakes[n],
                     "결과": "완주" if d == 0 else f"day{d} 탈락",
                     "환급": refund, "누적배당": div[n],
                     "총수령": refund + div[n],
                     "손익": refund + div[n] - stakes[n]})
    df = pd.DataFrame(rows)
    total_in, total_out = df["예치"].sum(), df["총수령"].sum()
    df.attrs["conservation"] = (total_in, total_out, total_in - total_out)
    return df


# ================================================================ 분석 도구
def staying_wage_curve(D: int, alpha: float, stake: float = 1.0) -> np.ndarray:
    """환급 성분만의 생존 임금 w_r(d) = stake·[r(d+1) - r(d)], d = 1..D-1"""
    d = np.arange(1, D)
    return stake * (np.vectorize(retention)(d + 1, D, alpha)
                    - np.vectorize(retention)(d, D, alpha))


def payoff_table_by_dropday(D: int, alpha: float, n_players: int = 5,
                            stake: float = 10.0) -> pd.DataFrame:
    """
    '내가 day k에 탈락하면 총 얼마 받나'를 k = 1..D(완주) 전부에 대해 계산.
    나머지 (n-1)명은 전원 완주 가정 → 나 혼자의 탈락 시점 효과를 고립시킨 표.
    """
    rows = []
    for k in list(range(1, D + 1)) + [0]:  # 0 = 완주
        stakes = {f"P{i}": stake for i in range(n_players)}
        fails = {} if k == 0 else {"P0": k}
        df = settle(stakes, fails, D, alpha)
        me = df[df["참가자"] == "P0"].iloc[0]
        rows.append({"탈락일": "완주" if k == 0 else k,
                     "환급": me["환급"], "배당": me["누적배당"],
                     "총수령": me["총수령"], "손실": stake - me["총수령"]})
    return pd.DataFrame(rows)


def monte_carlo(D: int, alpha: float, n_players: int = 10, stake: float = 10.0,
                n_sims: int = 3000, base_hazard: float = 0.06,
                decay: float = 0.92, seed: int = 42) -> pd.DataFrame:
    """
    확률적 탈락 모형: day d 생존자의 탈락 확률 h(d) = base_hazard · decay^(d-1)
    (초반 탈락 속출 → 후반 감소, 실제 챌린지 앱들의 좌편향 이탈 분포 근사)
    각 시뮬에서 참가자별 최종 payoff 를 기록 → 생존일수별 기대 payoff 요약.
    """
    rng = np.random.default_rng(seed)
    records = []
    for _ in range(n_sims):
        stakes = {f"P{i}": stake for i in range(n_players)}
        fails = {}
        alive = set(stakes)
        for d in range(1, D + 1):
            h = base_hazard * decay ** (d - 1)
            for n in list(alive):
                if rng.random() < h:
                    fails[n] = d
                    alive.discard(n)
        df = settle(stakes, fails, D, alpha)
        for _, r in df.iterrows():
            surv = D if r["결과"] == "완주" else int(r["결과"][3:-3])
            records.append({"생존일": surv, "완주": r["결과"] == "완주",
                            "총수령": r["총수령"], "손익": r["손익"]})
    return pd.DataFrame(records)


# ================================================================ 그래프
def fig_retention_curves(D=30, alphas=(0.0, 0.3, 0.6, 1.0)):
    fig, ax = plt.subplots(figsize=(9, 5.5))
    d = np.linspace(0, D, 200)
    colors = [C_PURPLE, C_BLUE, C_GREEN, C_GRAY]
    for a, c in zip(alphas, colors):
        r = a * (d / D) + (1 - a) * (d / D) ** 2
        ls = "--" if a == 1.0 else "-"
        ax.plot(d, r * 100, ls, color=c, lw=2.2,
                label=f"α={a:.1f}" + ("  (순수 선형)" if a == 1 else "  (순수 이차)" if a == 0 else ""))
    ax.set_title("환급 커브 r(d): α가 낮을수록 볼록 (후반 급회복)")
    ax.set_xlabel("탈락일 d"); ax.set_ylabel("환급률 (%)")
    ax.legend(); ax.set_xlim(0, D); ax.set_ylim(0, 100)
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/01_retention_curves.png", bbox_inches="tight"); plt.close()


def fig_staying_wage(D=30, alphas=(0.0, 0.3, 0.6, 1.0), stake=100000):
    fig, ax = plt.subplots(figsize=(9, 5.5))
    colors = [C_PURPLE, C_BLUE, C_GREEN, C_GRAY]
    d = np.arange(1, D)
    for a, c in zip(alphas, colors):
        w = staying_wage_curve(D, a, stake)
        ax.plot(d, w, color=c, lw=2.2, label=f"α={a:.1f}")
    cost = 1500 + 4200 * (d / D) ** 1.4
    ax.plot(d, cost, ":", color=C_RED, lw=2, label="노력 비용 c(d) 개형 (가정)")
    ax.set_title("생존 임금 w(d): α<1 이면 우상향 → 비용 곡선을 끝까지 이김")
    ax.set_xlabel("day d"); ax.set_ylabel("하루 더 버티는 가치 (원)")
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, p: f"{x:,.0f}"))
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/02_staying_wage.png", bbox_inches="tight"); plt.close()


def fig_flow_compare(D=5):
    """초반 탈락 속출 케이스: 즉시 vs 스트리밍의 일자별 배당량"""
    stakes = {n: 10.0 for n in "ABCDE"}
    fails = {"D": 1, "E": 1, "C": 2}
    alpha = 1.0  # 흐름 비교가 목적이라 선형으로 고정

    def daily_flow(streaming):
        drip, flows = 0.0, []
        for d in range(1, D + 1):
            tf = [n for n in stakes if fails.get(n) == d]
            day_f = sum(forfeit(stakes[n], d, D, alpha) for n in tf)
            if streaming:
                for n in tf:
                    drip += forfeit(stakes[n], d, D, alpha) / (D - d + 1)
                flows.append(drip)
            else:
                flows.append(day_f)
        return flows

    inst, strm = daily_flow(False), daily_flow(True)
    x = np.arange(1, D + 1); w = 0.38
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.bar(x - w / 2, inst, w, color=C_ORANGE, label="즉시 분배")
    ax.bar(x + w / 2, strm, w, color=C_BLUE, label="스트리밍")
    for xi, v in zip(x - w / 2, inst):
        if v > 0: ax.text(xi, v + 0.15, f"{v:.1f}", ha="center", fontsize=10)
    for xi, v in zip(x + w / 2, strm):
        if v > 0: ax.text(xi, v + 0.15, f"{v:.1f}", ha="center", fontsize=10)
    ax.set_title("초반 탈락 속출 시 일자별 배당량 — 즉시 분배는 초반에 몰리고, 스트리밍은 우상향")
    ax.set_xlabel("day"); ax.set_ylabel("그날 풀리는 배당 (SUI)")
    ax.set_xticks(x); ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/03_flow_compare.png", bbox_inches="tight"); plt.close()


def fig_payoff_by_dropday(D=30, alphas=(0.0, 0.3, 0.6, 1.0), stake=10.0):
    fig, ax = plt.subplots(figsize=(9, 5.5))
    colors = [C_PURPLE, C_BLUE, C_GREEN, C_GRAY]
    for a, c in zip(alphas, colors):
        t = payoff_table_by_dropday(D, a, n_players=5, stake=stake)
        t2 = t[t["탈락일"] != "완주"]
        ax.plot(t2["탈락일"], t2["총수령"], color=c, lw=2.2, label=f"α={a:.1f}")
    ax.axhline(stake, color=C_RED, ls=":", lw=1.5, label="예치금 (본전선)")
    ax.set_title("탈락일별 총수령액 (다른 4명 전원 완주 가정, 예치 10)")
    ax.set_xlabel("탈락일"); ax.set_ylabel("총수령 (환급+배당)")
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/04_payoff_by_dropday.png", bbox_inches="tight"); plt.close()


def fig_monte_carlo(D=30, alphas=(0.3, 1.0)):
    fig, axes = plt.subplots(1, 2, figsize=(12, 5), sharey=True)
    for ax, a in zip(axes, alphas):
        mc = monte_carlo(D, a)
        g = mc.groupby("생존일")["총수령"].mean()
        ax.plot(g.index, g.values, color=C_BLUE, lw=2.2)
        ax.axhline(10, color=C_RED, ls=":", lw=1.5)
        ax.set_title(f"α={a:.1f}  생존일수별 평균 총수령")
        ax.set_xlabel("생존일수 (30 = 완주)")
    axes[0].set_ylabel("평균 총수령 (예치 10)")
    fig.suptitle("몬테카를로 (10인, 초반 몰림 이탈 모형, 3000회)", fontweight="bold")
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/05_monte_carlo.png", bbox_inches="tight"); plt.close()


# ================================================================ 메인
if __name__ == "__main__":
    pd.set_option("display.float_format", lambda v: f"{v:,.3f}")

    D = 30
    ALPHAS = [0.0, 0.3, 0.6, 1.0]

    SCENARIOS = {
        "S1_킬러예시(D=5)": dict(D=5, stakes={"A": 10, "B": 10, "C": 10},
                                 fails={"B": 2, "C": 4}),
        "S2_초반속출(D=30,5인)": dict(D=30, stakes={n: 10 for n in "ABCDE"},
                                      fails={"D": 1, "E": 2, "C": 5}),
        "S3_후반탈락(D=30,5인)": dict(D=30, stakes={n: 10 for n in "ABCDE"},
                                      fails={"C": 25}),
        "S4_가변베팅(D=30)": dict(D=30, stakes={"A": 20, "B": 10, "C": 30, "D": 10},
                                  fails={"B": 6, "C": 20}),
    }

    print("=" * 78)
    print("시나리오별 payoff 표 (스트리밍 분배 + 볼록결합 커브)")
    print("=" * 78)
    for name, sc in SCENARIOS.items():
        for a in ALPHAS:
            df = settle(sc["stakes"], sc["fails"], sc["D"], a)
            tin, tout, gap = df.attrs["conservation"]
            print(f"\n--- {name} | α={a:.1f} | 보존: in {tin:.3f} = out {tout:.3f} "
                  f"(오차 {gap:.1e}) ---")
            print(df.to_string(index=False))

    print("\n" + "=" * 78)
    print("탈락일별 payoff 표 (D=30, 5인, 나머지 전원 완주 가정) — α 비교")
    print("=" * 78)
    for a in ALPHAS:
        t = payoff_table_by_dropday(D, a)
        pick = t[t["탈락일"].isin([1, 5, 10, 15, 20, 25, 29, "완주"])]
        print(f"\n--- α={a:.1f} ---")
        print(pick.to_string(index=False))

    print("\n그래프 생성 중...")
    fig_retention_curves()
    fig_staying_wage()
    fig_flow_compare()
    fig_payoff_by_dropday()
    fig_monte_carlo()
    print(f"완료: {FIGDIR}/ 에 그래프 5장 저장됨")
