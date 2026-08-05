"""challenge.move 로직의 파이썬 미러. Move 코드와 연산 순서·절단 시점까지 1:1 대응.
sui move test를 못 돌리는 환경에서 기대값을 검증하기 위한 참조 구현."""
SCALE = 10**12
S = 10**9

def calc_refund(stake, d, D, abp):
    k = 0 if d == 0 else d - 1                      # [D-05]
    numer = stake * (abp*k*D + (10000-abp)*k*k)
    return numer // (10000*D*D)

def personal_refund(stake, start_day, failed_day, D, abp):
    return calc_refund(stake, failed_day - start_day + 1, D - start_day + 1, abp)

def pending_div(stake, acc_entry, acc_now):
    return stake * (acc_now - acc_entry) // SCALE

class Ch:
    def __init__(self, D, abp):
        self.D, self.abp = D, abp
        self.day = 0; self.drip = 0; self.acc = 0
        self.vault = 0; self.P = {}; self.list = []
        self.status = 'PENDING'
    def join(self, who, stake):
        assert self.status != 'ENDED' and self.day < self.D
        assert who not in self.P and stake > 0
        self.vault += stake
        self.P[who] = dict(stake=stake, start_day=self.day+1, acc_entry=self.acc,
                           failed_day=0, claimable=0)
        self.list.append(who)
    def withdraw(self, who):
        assert self.status == 'PENDING'
        p = self.P.pop(who); self.list.remove(who)
        self.vault -= p['stake']; return p['stake']
    def submit(self, failed):
        assert self.status != 'ENDED' and self.day < self.D
        if self.status == 'PENDING': self.status = 'ACTIVE'
        self.day += 1; d = self.day
        acc_before = self.acc
        for a in failed:
            p = self.P[a]; assert p['failed_day'] == 0
            p['failed_day'] = d
            p['claimable'] += pending_div(p['stake'], p['acc_entry'], acc_before)
            r = personal_refund(p['stake'], p['start_day'], d, self.D, self.abp)
            self.drip += (p['stake'] - r) // (self.D - d + 1)
        surv = sum(p['stake'] for p in self.P.values() if p['failed_day'] == 0)
        if surv == 0:
            self.status = 'ENDED'
            for a in self.list:
                p = self.P[a]
                p['claimable'] += personal_refund(p['stake'], p['start_day'], p['failed_day'], self.D, self.abp)
        else:
            self.acc += self.drip * SCALE // surv
    def finalize(self):
        assert self.status != 'ENDED' and self.day == self.D
        self.status = 'ENDED'
        for a in self.list:
            p = self.P[a]
            if p['failed_day'] == 0:
                p['claimable'] += pending_div(p['stake'], p['acc_entry'], self.acc) + p['stake']
            else:
                p['claimable'] += personal_refund(p['stake'], p['start_day'], p['failed_day'], self.D, self.abp)
    def claim(self, who):
        assert self.status == 'ENDED'
        p = self.P[who]; amt = p['claimable']; p['claimable'] = 0
        self.vault -= amt; return amt
