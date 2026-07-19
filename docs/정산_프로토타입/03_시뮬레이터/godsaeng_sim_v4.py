# -*- coding: utf-8 -*-
"""
갓생 내기 프로토콜 — ver4 중도 참여 설계 시뮬레이터
======================================================
세 가지 설계안을 구현·비교한다:

  설계 I   "open"    — 개방형: 합류자는 합류일 이후의 모든 방출(기존 스트림 포함)을 받음
  설계 II  "vintage" — 빈티지 분리: 합류자는 자기 합류 이후에 태어난 스트림만 받음
  설계 III "nav"     — NAV 진입가: 합류자가 기존 스트림의 미방출 잔량에 대한 공정가를
                        프리미엄으로 지불(기존 생존자에게 즉시 지급)하고, 이후 open과 동일

공통 규칙 (ver3 계승):
  - 환급 커브: r(x) = α x + (1−α) x²,  x = 개인 경과일 / 개인 잔여기간 (명제 5: 개인 정규화 강제)
  - 스트리밍: day b 몰수액은 day b~D에 균등 방출
  - 그날 탈락자는 그날 배당 제외 / 합류자는 합류 당일부터 배당 자격
  - day 처리 순서: ① 합류 → ② 탈락 판정(스트림 탄생) → ③ 방출·분배
    (따라서 day g 합류자에게 day g에 태어난 스트림은 "신규"다)

사용법: python3 godsaeng_sim_v4.py
  pip install numpy pandas matplotlib
"""

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
from matplotlib import font_manager
import os
import platform

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


# ================================================================ 커브
def retention(d, Dj, alpha):
    x = d / Dj
    return alpha * x + (1 - alpha) * x * x


# ================================================================ 범용 정산 엔진 (결정론, 소인원용)
def settle_v4(players, D, alpha, design):
    """
    players: {name: {"stake": float, "start": int, "fail": int(0=완주)}}
    design : "open" | "vintage" | "nav"
    반환   : DataFrame (환급/배당/프리미엄/총수령/순지출), 보존 검증 attrs
    """
    names = list(players)
    st = {n: players[n]["stake"] for n in names}
    start = {n: players[n]["start"] for n in names}
    fail = {n: players[n]["fail"] for n in names}

    div = {n: 0.0 for n in names}
    prem_paid = {n: 0.0 for n in names}      # nav: 합류자가 낸 프리미엄
    prem_recv = {n: 0.0 for n in names}      # nav: 기존 생존자가 받은 프리미엄
    streams = []                              # (born_day, rate)

    def joined(n, t):  return start[n] <= t
    def alive(n, t):   return joined(n, t) and (fail[n] == 0 or fail[n] > t)

    for t in range(1, D + 1):
        # ① 합류 (nav: 프리미엄 산정·지급)
        for n in names:
            if start[n] == t and t > 1 and design == "nav":
                old_rate = sum(r for b, r in streams if b < t)
                R = old_rate * (D - t + 1)                     # 기존 스트림의 미방출 잔량
                incum = [m for m in names if alive(m, t) and start[m] < t]
                S_incl = sum(st[m] for m in incum) + st[n]
                p = R * st[n] / S_incl if S_incl > 0 else 0.0  # p(g) = Δ·잔여일·s/(S+s)
                prem_paid[n] += p
                S_inc = sum(st[m] for m in incum)
                for m in incum:
                    prem_recv[m] += p * st[m] / S_inc if S_inc > 0 else 0.0

        # ② 탈락 → 스트림 탄생 (개인 타임라인 커브)
        for n in names:
            if fail[n] == t:
                Dj = D - start[n] + 1
                d = t - start[n] + 1
                forfeit = st[n] * (1 - retention(d, Dj, alpha))
                streams.append((t, forfeit / (D - t + 1)))

        # ③ 방출·분배
        surv = [n for n in names if alive(n, t)]
        if not surv:
            continue
        for b, rate in streams:
            if b > t:
                continue
            if design == "vintage":
                elig = [n for n in surv if start[n] <= b]      # 스트림 탄생 이전 합류자만
            else:
                elig = surv
            S = sum(st[n] for n in elig)
            if S > 0:
                for n in elig:
                    div[n] += rate * st[n] / S

    rows = []
    for n in names:
        Dj = D - start[n] + 1
        if fail[n]:
            d = fail[n] - start[n] + 1
            refund = st[n] * retention(d, Dj, alpha)
            res = f"day{fail[n]} 탈락"
        else:
            refund, res = st[n], ("완주" if start[n] == 1 else f"day{start[n]} 합류·완주")
        total = refund + div[n] + prem_recv[n]
        rows.append({"참가자": n, "예치": st[n], "결과": res,
                     "환급": refund, "배당": div[n],
                     "프리미엄±": prem_recv[n] - prem_paid[n],
                     "총수령": total, "순손익": total - st[n] - prem_paid[n]})
    df = pd.DataFrame(rows)
    t_in = df["예치"].sum() + sum(prem_paid.values())
    t_out = df["총수령"].sum()
    df.attrs["conservation"] = (t_in, t_out, t_in - t_out)
    return df


# ================================================================ 고속 MC (스나이퍼 1명, 2버킷 빈티지)
def mc_entry_timing(D=30, n_inc=8, stake=10.0, alpha=0.3,
                    base_h=0.06, decay=0.92, n_sims=600, seed=7):
    """
    기존 8인(확률적 탈락) + 절대 실패하지 않는 합류자(스나이퍼) 1명.
    합류일 g를 훑으며 세 설계에서 (a) 스나이퍼 순차익 (b) 기존 완주자 평균 수령을 계산.
    분산 축소: 공통 난수 — 같은 탈락 시나리오를 모든 g/설계에 재사용.
    """
    rng = np.random.default_rng(seed)
    gs = np.arange(1, D + 1, 2)
    sniper = {d: {des: [] for des in ("open", "vintage", "nav")} for d in gs}
    incumb = {d: {des: [] for des in ("open", "vintage", "nav")} for d in gs}
    incumb_base = []

    for _ in range(n_sims):
        # 탈락 시나리오 1회 추첨 (전 g/설계 공유)
        fails = np.zeros(n_inc, dtype=int)
        for i in range(n_inc):
            for d in range(1, D + 1):
                if rng.random() < base_h * decay ** (d - 1):
                    fails[i] = d
                    break
        alive_mask = np.array([[f == 0 or f > t for f in fails] for t in range(1, D + 1)])  # [t-1, i]
        SA = alive_mask @ (np.ones(n_inc) * stake)                     # 기존 생존 stake 합 (day t)
        F = np.zeros(D + 1)                                             # day b 몰수액
        for i, f in enumerate(fails):
            if f:
                F[f] = F[f] + stake * (1 - retention(f, D, alpha))
        rate_cum = np.zeros(D + 1)                                      # Δ(t): born ≤ t
        for b in range(1, D + 1):
            rate_cum[b] = rate_cum[b - 1] + (F[b] / (D - b + 1) if F[b] else 0)

        completers = [i for i, f in enumerate(fails) if f == 0]
        # 베이스라인: 합류자 없음 → 완주자 수령
        if completers:
            tot = stake + sum(rate_cum[t] * stake / SA[t - 1] for t in range(1, D + 1) if SA[t - 1] > 0)
            incumb_base.append(tot)

        for g in gs:
            # born < g = 구스트림, born ≥ g = 신스트림
            rate_old_at = lambda t: rate_cum[min(t, g - 1)] if g > 1 else 0.0
            for des in ("open", "vintage", "nav"):
                sdiv = 0.0
                for t in range(g, D + 1):
                    denom = SA[t - 1] + stake
                    r_all = rate_cum[t]
                    r_new = r_all - rate_old_at(t)
                    if des == "open" or des == "nav":
                        sdiv += r_all * stake / denom
                    else:
                        sdiv += r_new * stake / denom
                prem = 0.0
                if des == "nav" and g > 1:
                    prem = rate_cum[g - 1] * (D - g + 1) * stake / (SA[g - 1] + stake)
                sniper[g][des].append(sdiv - prem)

                if completers:
                    c_div = 0.0
                    for t in range(1, D + 1):
                        if SA[t - 1] <= 0:
                            continue
                        r_all = rate_cum[t]
                        if t < g:
                            c_div += r_all * stake / SA[t - 1]
                        else:
                            r_old = rate_old_at(t)
                            r_new = r_all - r_old
                            if des == "vintage":
                                c_div += r_old * stake / SA[t - 1] + r_new * stake / (SA[t - 1] + stake)
                            else:
                                c_div += r_all * stake / (SA[t - 1] + stake)
                    if des == "nav":
                        c_div += prem * stake / SA[g - 1] if SA[g - 1] > 0 else 0
                    incumb[g][des].append(stake + c_div)

    res = {"g": gs,
           "sniper": {des: np.array([np.mean(sniper[g][des]) for g in gs]) for des in ("open", "vintage", "nav")},
           "incumb": {des: np.array([np.mean(incumb[g][des]) for g in gs]) for des in ("open", "vintage", "nav")},
           "incumb_base": np.mean(incumb_base)}
    return res


# ================================================================ 그래프
def fig_donation_trap(D=30, alpha=0.3, stake=10.0):
    gs = np.arange(1, D + 1)
    orig = [stake * retention(D - g + 1, D, alpha) for g in gs]   # 원기간 D 기준: 완주해도 r<1
    norm = [stake for _ in gs]                                     # 개인 정규화: 완주 = 전액
    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(gs, norm, color=C_BLUE, lw=2.5, label="개인 잔여기간 정규화 (제안)")
    ax.plot(gs, orig, color=C_RED, lw=2.5, ls="--", label="원래 기간 D 기준 (기각)")
    ax.axhline(stake, color=C_GRAY, lw=1, ls=":")
    ax.set_title("완주자의 환급액 vs 합류일 — 원기간 커브는 '기부 함정'을 만든다")
    ax.set_xlabel("합류일 g"); ax.set_ylabel("완주 시 환급 (예치 10)")
    ax.legend(); ax.set_ylim(0, 11)
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/v4_1_donation_trap.png", bbox_inches="tight"); plt.close()


def fig_mc(res):
    gs = res["g"]
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for des, c, lab in (("open", C_ORANGE, "설계 I 개방형"),
                        ("vintage", C_BLUE, "설계 II 빈티지 분리"),
                        ("nav", C_GREEN, "설계 III NAV 진입가")):
        ax.plot(gs, res["sniper"][des], color=c, lw=2.4, marker="o", ms=4, label=lab)
    ax.axhline(0, color=C_GRAY, lw=1)
    ax.set_title("스나이퍼(절대 실패 안 하는 합류자)의 기대 순차익 vs 합류일")
    ax.set_xlabel("합류일 g"); ax.set_ylabel("기대 순차익 (예치 10 대비)")
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/v4_2_sniping_arbitrage.png", bbox_inches="tight"); plt.close()

    # 노력 보정 수익률: 하루 고생당 기대 차익
    D = gs[-1] + 1
    fig, ax = plt.subplots(figsize=(9, 5.5))
    for des, c, lab in (("open", C_ORANGE, "설계 I 개방형"),
                        ("vintage", C_BLUE, "설계 II 빈티지 분리"),
                        ("nav", C_GREEN, "설계 III NAV 진입가")):
        rho = res["sniper"][des] / (D - gs + 1)
        ax.plot(gs, rho, color=c, lw=2.4, marker="o", ms=4, label=lab)
    ax.axhline(0, color=C_GRAY, lw=1)
    ax.set_title("노력 1일당 기대 차익 ρ(g) — 개방형만 우상향 = 찍먹 차익")
    ax.set_xlabel("합류일 g"); ax.set_ylabel("기대 차익 / 남은 체크인 일수")
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/v4_5_effort_adjusted.png", bbox_inches="tight"); plt.close()

    fig, ax = plt.subplots(figsize=(9, 5.5))
    for des, c, lab in (("open", C_ORANGE, "설계 I"), ("vintage", C_BLUE, "설계 II"), ("nav", C_GREEN, "설계 III")):
        ax.plot(gs, res["incumb"][des], color=c, lw=2.4, marker="o", ms=4, label=lab)
    ax.axhline(res["incumb_base"], color=C_GRAY, lw=1.5, ls="--",
               label=f"합류자 없음 기준선 ({res['incumb_base']:.2f})")
    ax.set_title("기존 완주자의 기대 수령 vs 합류일 — 희석의 크기")
    ax.set_xlabel("합류일 g"); ax.set_ylabel("완주자 기대 총수령")
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/v4_3_incumbent_dilution.png", bbox_inches="tight"); plt.close()


def fig_scenario_bars(results):
    names = list(results["open"]["참가자"])
    x = np.arange(len(names)); w = 0.26
    fig, ax = plt.subplots(figsize=(9, 5))
    for k, (des, c, lab) in enumerate((("open", C_ORANGE, "설계 I 개방형"),
                                       ("vintage", C_BLUE, "설계 II 빈티지"),
                                       ("nav", C_GREEN, "설계 III NAV"))):
        net = results[des]["총수령"].values.copy()
        prem_out = np.where(results[des]["프리미엄±"].values < 0, -results[des]["프리미엄±"].values, 0)
        net = net - prem_out
        bars = ax.bar(x + (k - 1) * w, net, w, color=c, label=lab)
        for b, v in zip(bars, net):
            ax.text(b.get_x() + b.get_width() / 2, v + 0.15, f"{v:.2f}", ha="center", fontsize=9)
    ax.set_xticks(x); ax.set_xticklabels(names)
    ax.axhline(10, color=C_GRAY, lw=1, ls=":")
    ax.set_title("검증 시나리오 S-V4: 참가자별 순수령 (설계 3종 비교)")
    ax.set_ylabel("순수령 (프리미엄 지불 반영)")
    ax.legend()
    plt.tight_layout(); plt.savefig(f"{FIGDIR}/v4_4_scenario_bars.png", bbox_inches="tight"); plt.close()


# ================================================================ 메인
if __name__ == "__main__":
    pd.set_option("display.float_format", lambda v: f"{v:,.3f}")
    print("=" * 80)
    print("S-V4 검증 시나리오: D=5, α=1.0")
    print("A,B,X day1 각 10 예치 / X day2 탈락 / C day3 합류(10) / A,B,C 완주")
    print("=" * 80)
    players = {"A": {"stake": 10, "start": 1, "fail": 0},
               "B": {"stake": 10, "start": 1, "fail": 0},
               "X": {"stake": 10, "start": 1, "fail": 2},
               "C": {"stake": 10, "start": 3, "fail": 0}}
    results = {}
    for des in ("open", "vintage", "nav"):
        df = settle_v4(players, D=5, alpha=1.0, design=des)
        results[des] = df
        tin, tout, gap = df.attrs["conservation"]
        print(f"\n--- 설계 {des} | 보존: in {tin:.3f} = out {tout:.3f} (오차 {gap:.1e}) ---")
        print(df.to_string(index=False))

    print("\n" + "=" * 80)
    print("배제 검증: A,B day1 / C day3 합류 / B day4 탈락 (합류 이전 스트림 없음 → 3설계 동일해야 함)")
    print("=" * 80)
    p2 = {"A": {"stake": 10, "start": 1, "fail": 0},
          "B": {"stake": 10, "start": 1, "fail": 4},
          "C": {"stake": 10, "start": 3, "fail": 0}}
    for des in ("open", "vintage", "nav"):
        df = settle_v4(p2, D=5, alpha=1.0, design=des)
        print(f"\n--- {des} ---")
        print(df.to_string(index=False))

    print("\n몬테카를로 (입장 타이밍 스윕) 실행 중... 수십 초 소요")
    res = mc_entry_timing()
    print("완료. 그래프 생성 중...")
    fig_donation_trap()
    fig_mc(res)
    fig_scenario_bars(results)
    print(f"figures/v4_1~4 저장 완료")

    # 요약 수치 출력 (문서용)
    gs = res["g"]
    D = 30
    for des in ("open", "vintage", "nav"):
        arr = res["sniper"][des]
        rho = arr / (D - gs + 1)
        print(f"[절대 차익] {des}: g=1 → {arr[0]:.3f}, g=15 → {arr[len(gs)//2]:.3f}, g={gs[-1]} → {arr[-1]:.3f}")
        print(f"[일당 차익] {des}: g=1 → {rho[0]:.4f}, g=15 → {rho[len(gs)//2]:.4f}, g={gs[-1]} → {rho[-1]:.4f}"
              f"  (최대 {rho.max():.4f} @ g={gs[rho.argmax()]})")
    print(f"[기존 완주자] 기준선(합류자 無) = {res['incumb_base']:.3f}")
    for des in ("open", "vintage", "nav"):
        arr = res["incumb"][des]
        print(f"[기존 완주자] {des}: g=1 합류 시 {arr[0]:.3f}, g=15 → {arr[len(gs)//2]:.3f}, g={gs[-1]} → {arr[-1]:.3f}")
