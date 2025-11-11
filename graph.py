import random, math, numpy as np
from collections import Counter

# --- 1) 빠른 추정기 (Hoeffding로 m 선택) --------------------------
def sample_size(eps=0.02, delta=0.01):
    return math.ceil((1/(2*eps*eps))*math.log(2/delta))

def estimate_sortedness(arr, m=5000, rng=random):
    n = len(arr)
    if n < 2: return 1.0
    cnt = 0
    for _ in range(m):
        i = rng.randrange(0, n-1)
        if arr[i] <= arr[i+1]: cnt += 1
    return cnt/m

def estimate_duplicates(arr, m=5000, rng=random):
    n = len(arr)
    idx = [rng.randrange(0, n) for _ in range(m)]
    vals = [arr[i] for i in idx]
    uniq = len(set(vals))
    return 1 - uniq/len(vals)

# --- 2) 데이터 생성기 (목표 d,s 근사) ------------------------------
def synth_with_dup(n, d_target, key_range=None, zipf=False, rng=random):
    # choose U unique keys
    U = max(1, min(n, round((1-d_target)*n)))
    if key_range is None:
        key_range = max(U, 10)
    if zipf:
        # zipf weights for duplicates
        weights = np.arange(1, U+1)**(-1.2)
        weights /= weights.sum()
        keys = rng.sample(range(key_range), U)
        return list(np.random.choice(keys, size=n, p=weights))
    else:
        keys = rng.sample(range(key_range), U)
        return [rng.choice(keys) for _ in range(n)]

def degrade_sortedness(arr, s_target, rng=random):
    # start from sorted(arr); perform random adjacent swaps until s≈target
    a = sorted(arr)
    n = len(a)
    def current_s(a):
        return sum(1 for i in range(n-1) if a[i]<=a[i+1])/(n-1) if n>1 else 1.0
    # heuristic: expected drop per swap ≈ 2/(n)
    s = 1.0
    steps = 0
    while s > s_target and steps < 50*n:
        i = rng.randrange(0, n-1)
        a[i], a[i+1] = a[i+1], a[i]
        steps += 1
        if steps % 500 == 0:
            s = current_s(a)
    return a

def synth(n, d, s, key_range=None, zipf=False, rng=random):
    base = synth_with_dup(n, d, key_range=key_range, zipf=zipf, rng=rng)
    a = degrade_sortedness(base, s, rng=rng)
    return a

# --- 3) 임계치 학습(간단 grid) ------------------------------------
def choose_algo_by_rule(s, d, key_range, s_star=0.9, d_star=0.9, K_star=1000):
    if s >= s_star: return "TIMSORT"     # or insertion/merge
    if d >= d_star and key_range <= K_star: return "COUNTING"
    return "QUICK"

# 런타임 측정은 여러분의 정렬 구현으로 바꾸세요.
def time_algo(algo, arr):
    # return wall-clock runtime (ms)
    import time
    b = list(arr)
    t0 = time.perf_counter()
    if algo == "QUICK":
        b.sort()  # placeholder: replace with your quick
    elif algo == "TIMSORT":
        b.sort()  # Python sort ~ Timsort
    elif algo == "COUNTING":
        # toy counting sort for non-negative ints
        K = max(b)+1
        cnt = [0]*K
        for x in b: cnt[x]+=1
        out=[]
        for v,c in enumerate(cnt): out.extend([v]*c)
    else:
        b.sort()
    t1 = time.perf_counter()
    return (t1-t0)*1000

# 파일럿: 경계 찾기
def pilot_boundary(n=20000, grid=(5,5), reps=3, key_range=1000):
    import numpy as np
    S = np.linspace(0.0,1.0,grid[0])
    D = np.linspace(0.0,1.0,grid[1])
    rec=[]
    for s in S:
        for d in D:
            for _ in range(reps):
                arr = synth(n, d, s, key_range=key_range)
                tq = time_algo("QUICK", arr)
                # pick best of alternatives
                ta = min(time_algo("TIMSORT", arr), time_algo("COUNTING", arr))
                rec.append((s,d,tq,ta))
    return rec
