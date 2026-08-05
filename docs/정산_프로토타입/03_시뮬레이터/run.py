from mirror import *
ok = True
def chk(label, got, want):
    global ok
    good = got == want
    ok &= good
    print(f"  {'OK ' if good else 'FAIL'} {label}: {got:,}" + ("" if good else f"  (기대 {want:,})"))

print("=== T2. 커브 단위 (alpha_bp=2000, D=5, stake=10 SUI) ===")
for d, want in [(1,0),(2,720_000_000),(3,2_080_000_000),(4,4_080_000_000),(5,6_720_000_000)]:
    chk(f"day{d} 탈락", calc_refund(10*S, d, 5, 2000), want)
print("  선형 교차검증(abp=10000):")
chk("  day3 탈락", calc_refund(10*S,3,5,10000), 4*S)
chk("  day5 탈락", calc_refund(10*S,5,5,10000), 8*S)

def scenario(label, D, abp, joins, fails, expect, dust_want, withdraws=None):
    print(f"\n=== {label} ===")
    ch = Ch(D, abp)
    for who, st, day in joins:
        while ch.day < day-1: ch.submit(fails.get(ch.day+1, []))
        ch.join(who, st*S)
    for w in (withdraws or []): ch.withdraw(w)
    while ch.day < D and ch.status != 'ENDED': ch.submit(fails.get(ch.day+1, []))
    if ch.status != 'ENDED': ch.finalize()
    tot = 0
    for who, want in expect.items():
        got = ch.claim(who); tot += got; chk(who, got, want)
    chk("dust", ch.vault, dust_want)

scenario("T1. 로직검증 dust0 (α=1.0)", 5, 10000,
    [("A",10,1),("B",10,1),("C",10,1)], {2:["B"],4:["C"]},
    {"A":20*S, "C":8*S, "B":2*S}, 0)

scenario("T3. dust 검증 (4인으로 교체, α=1.0)", 5, 10000,
    [("A",10,1),("B",10,1),("C",10,1),("D",10,1)], {3:["B"]},
    {"A":11_999_999_999,"C":11_999_999_999,"D":11_999_999_999,"B":4*S}, 3)

scenario("V4-1. 중도참여 배당 배제 (α=1.0)", 5, 10000,
    [("A",10,1),("B",10,1),("C",10,3)], {2:["B"]},
    {"A":15*S,"C":13*S,"B":2*S}, 0)

scenario("V4-2. 개인 타임라인 커브 (α=1.0)", 5, 10000,
    [("A",10,1),("B",10,1),("C",10,3)], {2:["B"],4:["C"]},
    {"A":23_666_666_666,"C":4_333_333_333,"B":2*S}, 1)

scenario("전멸 (α=1.0)", 5, 10000,
    [("A",10,1),("B",10,1),("C",10,1)], {3:["A","B","C"]},
    {"A":4*S,"B":4*S,"C":4*S}, 18*S)

print("\n=== D-08. withdraw (PENDING 철회 후 남은 2인 진행) ===")
ch = Ch(5, 10000)
for w in ["A","B","C"]: ch.join(w, 10*S)
back = ch.withdraw("C")
chk("C 철회 전액", back, 10*S)
chk("vault", ch.vault, 20*S)
chk("참가자 수", len(ch.list), 2)
ch.submit(["B"]); [ch.submit([]) for _ in range(4)]; ch.finalize()
chk("A (완주)", ch.claim("A"), 20*S)
chk("B (day1 탈락, k=0)", ch.claim("B"), 0)
chk("dust", ch.vault, 0)

print("\n" + ("전부 통과" if ok else "실패 있음"))
