# -*- coding: utf-8 -*-
"""
α(선형항 비중) 선택의 정량적 근거
==================================
r(x) = α·x + (1−α)·x²,  x = k/D,  k = 완주일수 = 탈락일 − 1

생존 임금 w(d) = stake·[R(d/D) − R((d−1)/D)] 를 전개하면
    w(d) = stake·[ α/D + (1−α)(2d−1)/D² ]
이고, 여기서 세 가지 구조적 사실이 따라온다.

  (1) 배율의 닫힌 형태
        w(D)/w(1) = (2D−1−(D−1)α) / (1+(D−1)α)
      α에 대한 쌍곡선 감소 — 극값이 없다. 즉 "수학적 최적 α"는 존재하지 않는다.
      따라서 α는 최적화로 구하는 값이 아니라, 목표 배율을 정하고 역산하는 값이다.
        α = (2D−1−T) / [(D−1)(T+1)],   T ∈ [1, 2D−1]

  (2) 모든 α 곡선의 교차점
        ∂w/∂α = 1/D − (2d−1)/D² = 0  →  d = (D+1)/2,  그 값은 stake/D (α 무관)
      또 Σ_{d=1..D} w(d) = stake (망원합) 이므로 총 환급액은 α와 무관하다.
      α는 파이의 크기가 아니라 기울기만 바꾼다 — 교차점을 축으로 한 회전이다.

  (3) 기간 의존성
      배율은 D가 클수록 커진다. 같은 α라도 D=5(데모)와 D=30(실서비스)의
      체감 압박이 다르다.

커브 로직은 godsaeng_sim 에서 import 해 재사용한다 (재구현 금지 —
절단 위치가 달라지면 mirror.py / challenge.move 와 어긋난다).
아래 닫힌 형태는 전부 staying_wage_curve() 결과와 대조 검산한다.

사용: python3 alpha_sweep.py
"""
import os

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# 커브 + 폰트/스타일/색상 재사용
from godsaeng_sim import (
    staying_wage_curve,
    C_BLUE, C_ORANGE, C_GREEN, C_RED, C_PURPLE, C_GRAY,
)

# ---------------------------------------------------------------- 설정
D = 30
ALPHA_GRID = np.round(np.arange(0.0, 1.0 + 1e-9, 0.05), 2)   # 21개 점
ALPHA_PICK = 0.2                     # 현재 채택값 (검증 대상)
ALPHAS_OVERLAY = (0.0, 0.2, 0.5, 1.0)
TARGET_RATIOS = (5.0, 8.0, 10.0)     # 목표 배율 → α 역산
D_GRID = (5, 10, 30, 50)             # D=5 데모 방, D=30 실서비스 상정
STAKE_WON = 100_000                  # 02_staying_wage.png 와 톤 통일

OUTDIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "04_그래프"))
os.makedirs(OUTDIR, exist_ok=True)

RATIO_COL = "마지막/첫날 배율"
CV_COL = "변동계수"
FLAT_COL = "첫날/평탄임금(%)"


# ---------------------------------------------------------------- 닫힌 형태
def ratio_closed(alpha: float, D: int = D) -> float:
    """w(D)/w(1) = (2D−1−(D−1)α) / (1+(D−1)α)."""
    return (2 * D - 1 - (D - 1) * alpha) / (1 + (D - 1) * alpha)


def alpha_for_ratio(target_ratio: float, D: int = D) -> float:
    """목표 배율 T를 주면 그걸 만드는 α를 역산. α = (2D−1−T)/[(D−1)(T+1)].

    T의 유효구간은 [1, 2D−1] — α=1(완전 평탄)일 때 1배, α=0(순수 이차)일 때
    2D−1배가 양 끝이다. 벗어나면 실현 불가능한 목표라 ValueError.
    """
    lo, hi = 1.0, 2.0 * D - 1.0
    if not (lo - 1e-12 <= target_ratio <= hi + 1e-12):
        raise ValueError(f"D={D}에서 배율 {target_ratio}는 실현 불가 "
                         f"(가능 범위 {lo:.1f}~{hi:.1f}배)")
    return (2 * D - 1 - target_ratio) / ((D - 1) * (target_ratio + 1))


def flat_wage_ratio(alpha: float, D: int = D) -> float:
    """첫날 임금 / 평탄 임금(=stake/D) = [1+α(D−1)]/D.
    α에 정확히 선형이라 '초반이 얼마나 덜 가혹한가'를 변별력 있게 보여준다.
    (구 지표였던 day3 환급률은 x=2/D가 원래 작아 α=1.0에서도 6.7%라 변별력이 없었다.)
    """
    return (1.0 + alpha * (D - 1)) / D


# ---------------------------------------------------------------- 지표 표
def metrics(alpha: float) -> dict:
    """지표는 전부 staying_wage_curve() 실측 수열에서 뽑는다 (닫힌 형태는 검산용)."""
    w = staying_wage_curve(D, alpha, stake=1.0)
    mono = bool(np.all(np.diff(w) >= -1e-15))   # α=1.0은 완전 평탄(diff=0) → 비감소로 Y
    return {
        "α": alpha,
        "단조증가": "Y" if mono else "N",
        RATIO_COL: w[-1] / w[0],
        CV_COL: w.std() / w.mean(),
        FLAT_COL: w[0] / (1.0 / D) * 100,       # stake=1.0 이므로 평탄임금 = 1/D
    }


df = pd.DataFrame([metrics(a) for a in ALPHA_GRID])


def at(alpha: float, col: str) -> float:
    return float(df.loc[np.isclose(df["α"], alpha), col].iloc[0])


pd.set_option("display.float_format", lambda v: f"{v:,.3f}")
print("=" * 72)
print(f"[1] α 스윕 — D={D}, {len(ALPHA_GRID)}개 점 (0.00 ~ 1.00, 0.05 간격)")
print("=" * 72)
print(df.to_string(index=False))


# ---------------------------------------------------------------- 검산
print("\n" + "=" * 72)
print("[2] 검산 — 닫힌 형태 vs staying_wage_curve() 실측")
print("=" * 72)

err_ratio = max(abs(ratio_closed(a) - at(a, RATIO_COL)) for a in ALPHA_GRID)
err_flat = max(abs(flat_wage_ratio(a) * 100 - at(a, FLAT_COL)) for a in ALPHA_GRID)
# 역산 왕복: α → 배율 → α 가 제자리로 돌아오는지
err_round = max(abs(alpha_for_ratio(at(a, RATIO_COL)) - a) for a in ALPHA_GRID)

print(f"  배율 닫힌형태 최대 오차      : {err_ratio:.3e}")
print(f"  첫날/평탄임금 닫힌형태 오차  : {err_flat:.3e}")
print(f"  역산 왕복(α→T→α) 최대 오차   : {err_round:.3e}")

# 총합 검산: Σw(d) = stake 이므로 총 환급액은 α와 무관 (교차점 기준 회전만 일어남)
sums = {a: staying_wage_curve(D, a, stake=1.0).sum() for a in ALPHA_GRID}
max_sum_err = max(abs(s - 1.0) for s in sums.values())
print(f"  총합 검산: 모든 α에서 Σw = stake "
      f"(최대 오차 {max_sum_err:.3e}) → 총 환급액은 α와 무관, α는 기울기만 바꾼다")

assert err_ratio < 1e-12 and err_flat < 1e-12 and err_round < 1e-9 and max_sum_err < 1e-12


# ---------------------------------------------------------------- 목표 배율 역산
print("\n" + "=" * 72)
print(f"[3] 목표 배율 → α 역산 (D={D}, 가능 범위 1.0 ~ {2 * D - 1:.1f}배)")
print("=" * 72)
rows = []
for T in TARGET_RATIOS:
    a = alpha_for_ratio(T, D)
    w = staying_wage_curve(D, a, stake=1.0)      # 역산한 α를 실제 커브에 넣어 재확인
    rows.append({"목표 배율": T, "역산 α": a, "실측 배율": w[-1] / w[0],
                 FLAT_COL: w[0] / (1.0 / D) * 100})
inv = pd.DataFrame(rows)
print(inv.to_string(index=False))
a8 = alpha_for_ratio(8.0, D)
print(f"\n  → 채택 α={ALPHA_PICK}는 목표 배율 8배(역산 α={a8:.3f})를 "
      f"소수 첫째자리로 반올림한 값에 해당한다.")


# ---------------------------------------------------------------- D 의존성
print("\n" + "=" * 72)
print(f"[4] 기간 의존성 — α={ALPHA_PICK} 고정, D 변화")
print("=" * 72)
drows = []
for d_ in D_GRID:
    w = staying_wage_curve(d_, ALPHA_PICK, stake=1.0)
    drows.append({"D": d_, "마지막/첫날 배율": w[-1] / w[0],
                  "닫힌형태": ratio_closed(ALPHA_PICK, d_),
                  "교차일 (D+1)/2": (d_ + 1) / 2,
                  "비고": "데모 방" if d_ == 5 else "실서비스 상정" if d_ == 30 else ""})
dd = pd.DataFrame(drows)
print(dd.to_string(index=False))
r_d5, r_d30 = ratio_closed(ALPHA_PICK, 5), ratio_closed(ALPHA_PICK, 30)
print(f"\n  → 같은 α라도 기간이 길수록 배율이 커진다 "
      f"(D=5 {r_d5:.1f}배 → D=30 {r_d30:.1f}배). "
      f"데모 방(D=5)의 체감 압박은 실서비스보다 약하다.")


# ---------------------------------------------------------------- 그래프 1
def fig_tradeoff():
    """x=α, 좌축=후반 압박(배율), 우축=초반 완화(첫날/평탄임금)."""
    fig, ax1 = plt.subplots(figsize=(9, 5.5))

    l1, = ax1.plot(df["α"], df[RATIO_COL], "-o", color=C_BLUE, lw=2.2, ms=4,
                   label="마지막날/첫날 임금 배율  (후반 압박 ↑)")
    ax1.set_yscale("log")           # 1배 ~ 59배라 로그가 아니면 오른쪽 끝이 뭉갠다
    ax1.set_xlabel("α  (선형항 비중)")
    ax1.set_ylabel("마지막날 / 첫날 임금 배율  (로그 스케일)", color=C_BLUE)
    ax1.tick_params(axis="y", labelcolor=C_BLUE)
    ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, p: f"{v:g}×"))

    ax2 = ax1.twinx()
    l2, = ax2.plot(df["α"], df[FLAT_COL], "-s", color=C_ORANGE, lw=2.2, ms=4,
                   label="첫날 임금 / 평탄 임금  (초반 가혹성 ↓)")
    ax2.set_ylabel("첫날 임금 ÷ 평탄 임금(stake/D)  (%)", color=C_ORANGE)
    ax2.tick_params(axis="y", labelcolor=C_ORANGE)
    ax2.set_ylim(0, 105)
    ax2.grid(False)

    ax1.axvline(ALPHA_PICK, color=C_RED, ls="--", lw=1.6)
    ax1.annotate(
        f"채택 α={ALPHA_PICK}\n배율 {at(ALPHA_PICK, RATIO_COL):.1f}× / "
        f"첫날임금 {at(ALPHA_PICK, FLAT_COL):.0f}%",
        xy=(ALPHA_PICK, at(ALPHA_PICK, RATIO_COL)),
        xytext=(ALPHA_PICK + 0.13, at(ALPHA_PICK, RATIO_COL) * 2.3),
        color=C_RED, fontsize=10, fontweight="bold",
        arrowprops=dict(arrowstyle="->", color=C_RED, lw=1.4))

    ax1.set_title("α 트레이드오프: 후반 압박 vs 초반 가혹성 (극값 없는 쌍곡선 — 목표 배율로 역산)")
    ax1.legend(handles=[l1, l2], loc="center right", framealpha=0.92)
    ax1.set_xlim(-0.02, 1.02)

    path = os.path.join(OUTDIR, "03_alpha_sweep_tradeoff.png")
    plt.tight_layout(); plt.savefig(path, bbox_inches="tight"); plt.close()
    return path


# ---------------------------------------------------------------- 그래프 2
def fig_wage_overlay():
    """α별 생존 임금 곡선 + 교차점. 총합이 같으므로 교차점 기준 회전만 일어난다."""
    fig, ax = plt.subplots(figsize=(9, 5.5))
    d = np.arange(1, D + 1)
    colors = [C_PURPLE, C_BLUE, C_GREEN, C_GRAY]

    for a, c in zip(ALPHAS_OVERLAY, colors):
        w = staying_wage_curve(D, a, STAKE_WON)
        pick = np.isclose(a, ALPHA_PICK)
        note = ("  ← 채택" if pick else
                "  (순수 이차)" if a == 0.0 else
                "  (순수 선형·평탄)" if a == 1.0 else "")
        ax.plot(d, w, color=c, lw=3.2 if pick else 2.0,
                zorder=3 if pick else 2, label=f"α={a:.1f}{note}")

    # 교차점: d=(D+1)/2 에서 w = stake/D (α 무관). D가 짝수면 정수 day가 아니다.
    d_cross, w_cross = (D + 1) / 2, STAKE_WON / D
    ax.plot([d_cross], [w_cross], "o", color=C_RED, ms=10, zorder=5,
            markeredgecolor="white", markeredgewidth=1.5)
    ax.annotate(
        f"교차점 d=(D+1)/2={d_cross:g}\nw=stake/D={w_cross:,.0f}원 (α 무관)\n"
        f"Σw=stake로 총합 동일 → α는 이 점을 축으로 회전만 시킨다",
        xy=(d_cross, w_cross), xytext=(d_cross + 1.5, w_cross - 2700),
        color=C_RED, fontsize=9.5, fontweight="bold",
        arrowprops=dict(arrowstyle="->", color=C_RED, lw=1.4))

    ax.set_title("α별 생존 임금 w(d): 총합은 같고 교차점 기준으로 기울기만 바뀐다")
    ax.set_xlabel("day d")
    ax.set_ylabel(f"하루 더 버티는 가치 (원, 예치 {STAKE_WON:,})")
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, p: f"{v:,.0f}"))
    ax.set_xlim(1, D)
    ax.legend(loc="upper left")

    path = os.path.join(OUTDIR, "04_staying_wage_by_alpha.png")
    plt.tight_layout(); plt.savefig(path, bbox_inches="tight"); plt.close()
    return path


print("\n그래프 생성 중...")
p1, p2 = fig_tradeoff(), fig_wage_overlay()
print(f"완료: {p1}")
print(f"      {p2}")


# ---------------------------------------------------------------- 근거 요약문
r02, f02 = at(ALPHA_PICK, RATIO_COL), at(ALPHA_PICK, FLAT_COL)
f0, f1 = at(0.0, FLAT_COL), at(1.0, FLAT_COL)
a5, a10 = alpha_for_ratio(5.0, D), alpha_for_ratio(10.0, D)

print("\n" + "=" * 72)
print("α=0.2를 고른 근거 (발표 대본용)")
print("=" * 72)
print(
    f"""α는 최적화로 구하는 값이 아닙니다. 생존 임금을 전개하면 마지막날 대 첫날 임금 배율이
(2D−1−(D−1)α)/(1+(D−1)α)라는 닫힌 형태로 떨어지는데, 이건 α에 대한 쌍곡선 감소라
극값이 없습니다. 즉 '수학적으로 최적인 α'는 존재하지 않고, 설계자가 목표 배율을 먼저 정한 뒤
역산해야 하는 값입니다. 저희는 그 역산식 α=(2D−1−T)/[(D−1)(T+1)]을 세우고 D={D} 기준으로
목표 배율을 넣어봤습니다. 5배를 목표로 하면 α={a5:.3f}, 8배면 α={a8:.3f}, 10배면 α={a10:.3f}가
나옵니다. 저희가 채택한 α={ALPHA_PICK}는 이 중 8배 목표를 소수 첫째자리로 반올림한 값이고,
실제 배율은 {r02:.1f}배입니다. 8배를 고른 이유는 양 끝이 모두 실패 모드이기 때문입니다.
α=1.0이면 배율이 1.00배로 완전히 평탄해져 29일차나 1일차나 하루 더 버티는 값어치가 같아지고,
시간가중 차등이라는 핵심 차별점이 사라집니다. 반대로 α=0.0이면 첫날 임금이 평탄 임금의
{f0:.1f}%까지 떨어져 초반이 사실상 전액 몰수가 되고, 초반 이탈자에게 '어차피 다 잃었다'는
심리를 줘서 커밋먼트 장치로 역효과가 납니다. α={ALPHA_PICK}에서는 첫날 임금이 평탄 임금의
{f02:.0f}% 수준으로 회복되면서도 배율 {r02:.1f}배의 후반 압박이 유지됩니다. 한 가지 덧붙이면
α는 나눠주는 총액을 바꾸지 않습니다. Σw(d)=stake로 총 환급액은 α와 무관하고, 모든 α 곡선은
d=(D+1)/2={((D + 1) / 2):g}일에서 교차합니다. α는 파이의 크기가 아니라 기울기만,
그 교차점을 축으로 회전시키는 파라미터입니다. 마지막으로 이 배율은 기간에 비례해 커지므로
데모 방(D=5)에서는 같은 α={ALPHA_PICK}라도 배율이 {r_d5:.1f}배에 그칩니다. 실서비스
D={D}의 {r_d30:.1f}배와는 체감이 다르다는 점을 감안해야 합니다."""
)
