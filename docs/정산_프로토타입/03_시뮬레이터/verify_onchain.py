"""온체인 실측값 ↔ mirror.py 계산값 대조 검증기.

mirror.py는 challenge.move의 파이썬 미러(연산 순서·절단 시점 1:1 대응)이므로,
미러를 정답지로 놓고 실제 배포된 방의 claim 결과를 대조한다.
방이 바뀌면 아래 "시나리오 / 온체인 실측값" 블록만 고치면 된다.

ACTUAL = None 으로 두면 대조 없이 미러 기대값만 출력한다 (리허설 전 "이 값이
나와야 한다"를 미리 확인하는 용도). 이 모드는 항상 exit 0.

사용: python3 verify_onchain.py   (전부 일치 0, 하나라도 불일치 1)
"""
import sys
from mirror import Ch

# ─── 시나리오 (방 파라미터) ────────────────────────────────────
D = 5
ALPHA_BP = 2000
STAKE = 20_000_000                      # MIST, 참가자 전원 동일
PARTICIPANTS = ["A", "B", "C"]
START_DAY = {"A": 1, "B": 1, "C": 1}    # 참가자별 시작일
FAIL_SCHEDULE = {1: ["B"], 3: ["C"]}    # day -> 그날 탈락자 (A는 완주)

# ─── 온체인 실측값 (방 ③) ──────────────────────────────────────
# 참가자별 claimable (ENDED 상태에서 읽은 값)
# 아직 안 돌린 방이면 통째로 None → 미러 기대값만 출력하고 종료(ACTUAL_VAULT는 무시).
ACTUAL = {
    "A": 51_840_000,
    "B": 0,
    "C": 8_160_000,
}
# 온체인 vault 잔액. dust를 독립 계산하려면 필수.
# 아직 모르면 None → 역산 폴백 + 보존 법칙 검증 생략.
# (참가자 dict와 섞으면 sum(ACTUAL.values())가 깨지므로 별도 상수로 둔다)
ACTUAL_VAULT = 60_000_000               # 아무도 claim 안 한 ENDED 상태

# ────────────────────────────────────────────────────────────

ok = True


def chk(label, got, want):
    """run.py의 chk() 스타일. got=온체인 실측, want=미러 계산."""
    global ok
    good = got == want
    ok &= good
    line = f"  {'OK ' if good else 'FAIL'} {label:<22} {got:>15,}"
    if not good:
        line += f"  (미러 {want:,}, diff {got - want:+,})"
    print(line)


def run_mirror():
    """시나리오를 미러로 재생해서 (참가자별 claimable, dust)를 반환."""
    ch = Ch(D, ALPHA_BP)
    # start_day 순서대로 참여. join()은 start_day를 day+1로 잡으므로
    # 해당 시점까지 submit을 진행시킨 뒤 join한다 (run.py scenario()와 동일).
    for who in sorted(PARTICIPANTS, key=lambda w: START_DAY[w]):
        while ch.day < START_DAY[who] - 1:
            ch.submit(FAIL_SCHEDULE.get(ch.day + 1, []))
        ch.join(who, STAKE)
    while ch.day < D and ch.status != "ENDED":
        ch.submit(FAIL_SCHEDULE.get(ch.day + 1, []))
    if ch.status != "ENDED":
        ch.finalize()

    claims = {who: ch.claim(who) for who in PARTICIPANTS}
    return claims, ch.vault          # claim 후 남은 vault가 곧 dust


mirror, mirror_dust = run_mirror()
deposit = STAKE * len(PARTICIPANTS)

print(f"=== 방 파라미터: D={D}, alpha_bp={ALPHA_BP}, "
      f"stake={STAKE:,} x {len(PARTICIPANTS)}인, 탈락={FAIL_SCHEDULE} ===")

if ACTUAL is None:
    # 대조할 실측값이 없다 → 미러가 뭘 예측하는지만 보여주고 끝낸다.
    # 대조가 아니므로 OK/FAIL 판정도, 종료코드 1도 없다.
    print("\n--- 미러 기대값 (대조 없음) ---")
    for who in PARTICIPANTS:
        print(f"       {who:<22} {mirror[who]:>15,}")
    print(f"       {'dust':<22} {mirror_dust:>15,}")
    print(f"       {'-'*38}")
    total = sum(mirror.values()) + mirror_dust
    print(f"       {'합계(claim+dust)':<22} {total:>15,}")
    # 미러 내부 보존 법칙: ∑claimable + dust == ∑예치액. 깨지면 미러 자체가 버그다.
    # 대조가 아니라 참고 표시라 종료코드는 건드리지 않는다 (run.py가 본 검증).
    print(f"       {'예치총합':<22} {deposit:>15,}"
          f"  {'← 보존 법칙 OK' if total == deposit else '← 보존 법칙 깨짐(미러 버그)'}")
    print("\n실측값 미입력 — 미러 기대값만 표시함")
    sys.exit(0)

claim_sum = sum(ACTUAL.values())

if ACTUAL_VAULT is None:
    # 폴백: vault를 모르면 dust를 예치총합에서 역산할 수밖에 없다.
    # 이 경우 dust는 ACTUAL의 종속값이라 보존 법칙이 항등식이 되므로 검사하지 않는다.
    actual_dust = deposit - claim_sum
else:
    actual_dust = ACTUAL_VAULT - claim_sum      # 독립 측정값으로 계산

print("\n--- [1] 온체인 보존 법칙: claimable 합계 + dust == vault ---")
if ACTUAL_VAULT is None:
    print("  WARN 보존 법칙 검증 생략됨 (vault 미제공) — dust는 예치총합에서 역산")
else:
    chk("claim합계 + dust", claim_sum + actual_dust, ACTUAL_VAULT)
    # 위 줄은 dust 정의상 항등식이다. vault가 예치총합과 맞는지가 실질 검증.
    # 단 이 등식은 아무도 claim 안 한 상태에서만 성립한다 (claim 후엔 vault가 줄어든다).
    chk("vault == 예치총합(무claim)", ACTUAL_VAULT, deposit)

print("\n--- [2] 미러 vs 온체인 ---")
for who in PARTICIPANTS:
    chk(who, ACTUAL[who], mirror[who])
chk("dust", actual_dust, mirror_dust)

print("\n" + ("전부 일치" if ok else "불일치 있음"))
sys.exit(0 if ok else 1)
