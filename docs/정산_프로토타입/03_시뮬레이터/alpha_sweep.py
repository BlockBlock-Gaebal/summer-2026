# -*- coding: utf-8 -*-
"""
α(선형항 비중) 선택의 정량적 근거
==================================
r(x) = α·x + (1−α)·x²,  x = k/D,  k = 완주일수 = 탈락일 − 1

α는 두 요구가 충돌하는 지점에 있다.
  - α↑ : 커브가 선형에 가까워짐 → 생존 임금이 평탄해져 차등/압박 효과 소멸
  - α↓ : 커브가 볼록해짐 → 초반이 가혹해져 day2~3 탈락도 사실상 전액 몰수
          → "어차피 다 잃었다" 심리로 커밋먼트 장치가 역효과

이 스크립트는 그 트레이드오프를 4개 지표로 계량하고, α=0.2가
합리적 구간에 있음을 보인다.

커브 로직은 godsaeng_sim 에서 import 해 재사용한다 (재구현 금지 —
절단 위치가 달라지면 mirror.py / challenge.move 와 어긋난다).
폰트·스타일·색상 블록도 import 시점에 함께 적용된다.

사용: python3 alpha_sweep.py
"""
import os

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

# 커브 3종 + 폰트/스타일/색상 재사용
from godsaeng_sim import (
    curve, retention, staying_wage_curve,
    C_BLUE, C_ORANGE, C_GREEN, C_RED, C_PURPLE, C_GRAY,
)

# ---------------------------------------------------------------- 설정
D = 30
ALPHA_GRID = np.round(np.arange(0.0, 1.0 + 1e-9, 0.05), 2)   # 21개 점
ALPHA_PICK = 0.2                    # 현재 채택값 (검증 대상)
ALPHAS_OVERLAY = (0.0, 0.2, 0.5, 1.0)
STAKE_WON = 100_000                 # 생존 임금 그래프용 (02_staying_wage.png와 톤 통일)
EARLY_DAY = 3                       # 초반 가혹성 판정 기준일 (k = EARLY_DAY - 1)

# 04_그래프/ 는 03_시뮬레이터/ 의 형제 디렉터리. cwd와 무관하게 잡는다.
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "04_그래프")
OUTDIR = os.path.normpath(OUTDIR)
os.makedirs(OUTDIR, exist_ok=True)


# ---------------------------------------------------------------- 지표
def metrics(alpha: float) -> dict:
    """α 하나에 대한 4개 지표. 생존 임금 수열은 staying_wage_curve()로만 얻는다."""
    w = staying_wage_curve(D, alpha, stake=1.0)      # w[i] = day (i+1)의 하루 가치

    # 단조증가: 절벽(감소 구간)이 없는지. α=1.0은 완전 평탄이라 diff==0 → 비감소로 판정.
    mono = bool(np.all(np.diff(w) >= -1e-15))

    return {
        "α": alpha,
        "단조증가": "Y" if mono else "N",
        "마지막/첫날 배율": w[-1] / w[0],
        "변동계수": w.std() / w.mean(),
        f"day{EARLY_DAY} 환급률(%)": retention(EARLY_DAY, D, alpha) * 100,
    }


df = pd.DataFrame([metrics(a) for a in ALPHA_GRID])

RATIO_COL = "마지막/첫날 배율"
CV_COL = "변동계수"
EARLY_COL = f"day{EARLY_DAY} 환급률(%)"


def at(alpha: float, col: str) -> float:
    """표에서 특정 α의 지표값을 꺼낸다."""
    return float(df.loc[np.isclose(df["α"], alpha), col].iloc[0])


# ---------------------------------------------------------------- 표 출력
pd.set_option("display.float_format", lambda v: f"{v:,.3f}")
print("=" * 72)
print(f"α 스윕 — D={D}, {len(ALPHA_GRID)}개 점 (0.00 ~ 1.00, 0.05 간격)")
print("=" * 72)
print(df.to_string(index=False))


# ---------------------------------------------------------------- 그래프 1
def fig_tradeoff():
    """x=α, 좌축=후반 압박 강도(배율), 우축=초반 가혹성(day3 환급률).
    두 곡선이 반대로 움직이는 게 이 그림의 전부다."""
    fig, ax1 = plt.subplots(figsize=(9, 5.5))

    l1, = ax1.plot(df["α"], df[RATIO_COL], "-o", color=C_BLUE, lw=2.2, ms=4,
                   label="마지막날/첫날 임금 배율  (후반 압박 ↑)")
    ax1.set_yscale("log")            # 1배 ~ 59배라 로그가 아니면 오른쪽 끝이 뭉갠다
    ax1.set_xlabel("α  (선형항 비중)")
    ax1.set_ylabel("마지막날 / 첫날 임금 배율  (로그 스케일)", color=C_BLUE)
    ax1.tick_params(axis="y", labelcolor=C_BLUE)
    ax1.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, p: f"{v:g}×"))

    ax2 = ax1.twinx()
    l2, = ax2.plot(df["α"], df[EARLY_COL], "-s", color=C_ORANGE, lw=2.2, ms=4,
                   label=f"day{EARLY_DAY} 탈락자 환급률  (초반 가혹성 ↓)")
    ax2.set_ylabel(f"day{EARLY_DAY} 탈락자 환급률 (%)", color=C_ORANGE)
    ax2.tick_params(axis="y", labelcolor=C_ORANGE)
    ax2.grid(False)                  # twin축 그리드 겹침 방지

    ax1.axvline(ALPHA_PICK, color=C_RED, ls="--", lw=1.6)
    ax1.annotate(
        f"채택 α={ALPHA_PICK}\n배율 {at(ALPHA_PICK, RATIO_COL):.1f}× / "
        f"환급률 {at(ALPHA_PICK, EARLY_COL):.2f}%",
        xy=(ALPHA_PICK, at(ALPHA_PICK, RATIO_COL)),
        xytext=(ALPHA_PICK + 0.12, at(ALPHA_PICK, RATIO_COL) * 2.1),
        color=C_RED, fontsize=10, fontweight="bold",
        arrowprops=dict(arrowstyle="->", color=C_RED, lw=1.4))

    ax1.set_title("α 트레이드오프: 후반 압박 vs 초반 가혹성")
    ax1.legend(handles=[l1, l2], loc="center right", framealpha=0.92)
    ax1.set_xlim(-0.02, 1.02)

    path = os.path.join(OUTDIR, "03_alpha_sweep_tradeoff.png")
    plt.tight_layout(); plt.savefig(path, bbox_inches="tight"); plt.close()
    return path


# ---------------------------------------------------------------- 그래프 2
def fig_wage_overlay():
    """α별 생존 임금 곡선 겹쳐보기. 채택값 α=0.2만 굵게."""
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

    ax.set_title("α별 생존 임금 w(d): α가 커질수록 평탄 → 후반 압박 소멸")
    ax.set_xlabel("day d")
    ax.set_ylabel(f"하루 더 버티는 가치 (원, 예치 {STAKE_WON:,})")
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, p: f"{v:,.0f}"))
    ax.set_xlim(1, D)
    ax.legend()

    path = os.path.join(OUTDIR, "04_staying_wage_by_alpha.png")
    plt.tight_layout(); plt.savefig(path, bbox_inches="tight"); plt.close()
    return path


print("\n그래프 생성 중...")
p1, p2 = fig_tradeoff(), fig_wage_overlay()
print(f"완료: {p1}")
print(f"      {p2}")


# ---------------------------------------------------------------- 근거 요약문
r0, r02, r05, r1 = (at(a, RATIO_COL) for a in (0.0, 0.2, 0.5, 1.0))
e0, e02, e1 = (at(a, EARLY_COL) for a in (0.0, 0.2, 1.0))
cv0, cv02, cv1 = (at(a, CV_COL) for a in (0.0, 0.2, 1.0))
mono_all = (df["단조증가"] == "Y").all()

print("\n" + "=" * 72)
print("α=0.2를 고른 근거 (발표 대본용)")
print("=" * 72)
print(
    f"""α는 후반 압박과 초반 가혹성 사이의 트레이드오프 파라미터입니다. D={D} 기준으로 α를
0부터 1까지 0.05 간격으로 훑어보면 두 지표가 정확히 반대로 움직입니다. 커브를 순수 선형으로
두는 α=1.0에서는 마지막 날 생존 임금이 첫날과 똑같아 배율이 {r1:.2f}배, 변동계수도 {cv1:.3f}로
완전히 평탄해집니다. 즉 29일차나 1일차나 하루 더 버티는 값어치가 같아서, 시간가중 차등이라는
이 프로토콜의 핵심 차별점이 사라집니다. 반대로 순수 이차인 α=0.0에서는 배율이 {r0:.1f}배까지
치솟아 압박은 최대가 되지만, day{EARLY_DAY} 탈락자의 환급률이 {e0:.2f}%로 사실상 전액 몰수가
됩니다. 초반 이탈자에게 '어차피 다 잃었다'는 심리를 주면 커밋먼트 장치로서 역효과입니다.
저희가 채택한 α={ALPHA_PICK}는 이 두 실패 모드를 모두 피합니다. 마지막날 대 첫날 임금 배율이
{r02:.1f}배로 후반 압박을 뚜렷하게 유지하면서도, day{EARLY_DAY} 탈락자 환급률은 {e02:.2f}%로
α=0.0 대비 약 {e02 / e0:.1f}배 완화됩니다. 중간값인 α=0.5로 가면 배율이 {r05:.1f}배까지
떨어져 압박이 절반 이하로 약해지므로, 차등 강도를 살리려면 α는 0.5보다 확실히 작아야 합니다.
정리하면 α={ALPHA_PICK}는 '초반을 전액 몰수로 만들지 않는 최소 선형항'과 '후반 압박을 살리는
최대 볼록성'이 만나는 구간의 값이며, 전 구간에서 생존 임금 단조증가가 유지되어
{'중도 이탈을 유인하는 임금 절벽도 발생하지 않습니다' if mono_all else '일부 구간에서 임금 절벽이 발생합니다'}."""
)
