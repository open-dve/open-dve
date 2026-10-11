#!/usr/bin/env python3
"""Reference model of odve_rand_pkg: prints the lines odve_rand_tb.sv writes
to rand_out.txt, computed from IEEE 1800 Annex N in plain Python (standard
library only). A simulator whose output equals this matches every other one.

    odve_rand_ref.py [--seed N]      # N = the +SEED of the run; none: 1
"""
import argparse
import struct
import sys

M32 = 0xFFFFFFFF
M64 = 0xFFFFFFFFFFFFFFFF


def s32(x):
    x &= M32
    return x - (1 << 32) if x & 0x80000000 else x


def mix(h):
    h &= M32
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & M32
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & M32
    h ^= h >> 16
    return h


def fnv(s):
    h = 0x811C9DC5
    for b in s.encode():
        h = ((h ^ b) * 0x01000193) & M32
    return h


def annexn_u16(seed):
    """$dist_uniform(seed, 0, 65535): Annex N rtl_dist_uniform -> uniform().
    Returns (new seed, value). Every step is exact in double precision."""
    if seed == 0:
        seed = 259341593
    seed = s32(69069 * seed + 1)
    u = ((seed & M32) >> 9) | 0x3F800000
    c = struct.unpack("f", struct.pack("I", u))[0]
    c = c + c * 0.00000011920928955078125
    r = (65536.0 - 0.0) * (c - 1.0) + 0.0   # end + 1 = 65536
    i = int(r)                              # r >= 0: truncation is floor
    return seed, min(max(i, 0), 65535)


class Rand:
    run_seed = 1

    def __init__(self, name="odve_rand"):
        self.name = name
        self.state = s32(self.stream_seed(name))

    @classmethod
    def stream_seed(cls, name):
        return mix(cls.run_seed ^ mix(fnv(name)))

    def set_seed(self, seed):
        self.state = s32(seed)

    def get_seed(self):
        return self.state & M32

    def spawn(self, name=""):
        r = Rand(name)
        x = self.u32()
        r.set_seed(mix(x ^ fnv(name)))
        return r

    def u16(self):
        self.state, v = annexn_u16(self.state)
        return v

    def u32(self):
        x = self.u16()
        return (x << 16) | self.u16()

    def u64(self):
        x = self.u32()
        return (x << 32) | self.u32()

    def below(self, n):
        n &= M64
        if n == 0:
            return self.u64()
        if n == 1:
            return 0
        for width, draw in ((1 << 16, self.u16), (1 << 32, self.u32), (1 << 64, self.u64)):
            if n <= width:
                t = (width - n) % n
                x = draw()
                while x < t:
                    x = draw()
                return x % n

    def urand(self, lo, hi):
        lo &= M64
        hi &= M64
        if hi < lo:
            lo, hi = hi, lo
        return (lo + self.below((hi - lo + 1) & M64)) & M64

    def urange(self, mx, mn=0):
        return self.urand(mn & M32, mx & M32) & M32

    def irand(self, lo, hi):
        if hi < lo:
            lo, hi = hi, lo
        return s32(lo + self.below(hi - lo + 1))

    def chance(self, pct):
        pct &= M32
        if pct == 0:
            return 0
        if pct >= 100:
            return 1
        return int(self.below(100) < pct)

    def index(self, n):
        return 0 if n <= 1 else self.below(n)

    def weighted(self, w):
        total = sum(w)
        if total == 0:
            return 0
        x = self.below(total)
        for i, wi in enumerate(w):
            if x < wi:
                return i
            x -= wi
        return 0


def fold(h, v):
    v &= M64
    h = (mix(h ^ (v & M32)) + 0x9E3779B9) & M32
    return (mix(h ^ (v >> 32)) + 0x9E3779B9) & M32


def lines():
    out = []

    def put(key, v):
        out.append(f"{key} {v & M64}")

    # t_seeds
    names = ["", "a", "b", "odve_rand", "uvm_test_top.env.mst_agent.drv",
             "a very long stream name with spaces and digits 0123456789"]
    r = Rand("seeds")
    put("run_seed", Rand.run_seed)
    for j, n in enumerate(names):
        put(f"stream_seed {j}", Rand.stream_seed(n))
    k1 = r.spawn("item")
    k2 = r.spawn("item")
    k3 = r.spawn()
    put("spawn 1", k1.u32())
    put("spawn 2", k2.u32())
    put("spawn 3", k3.u32())
    put("spawn name", int(k1.name == "item"))
    s = r.get_seed()
    h = 0
    for _ in range(100):
        h = fold(h, r.u32())
    r.set_seed(s)
    for _ in range(100):
        h = fold(h, r.u32())
    put("replay", h)
    r.set_seed(0)
    put("seed0", r.u32())

    # t_words
    r = Rand("words")
    for k in range(20):
        put(f"u16 {k}", r.u16())
    for k in range(10):
        put(f"u32 {k}", r.u32())
    for k in range(10):
        put(f"u64 {k}", r.u64())
    h = 0
    for b in range(4):
        for _ in range(250000):
            h = fold(h, r.u16())
        put(f"long {b}", h)

    # t_ranges
    r = Rand("ranges")
    for n in [0, 1, 2, 3, 7, 100, 65535, 65536, 65537, 1000000, 0xFFFFFFFF, 1 << 32, (1 << 32) + 1,
              1 << 63, (1 << 63) + 1, M64]:
        h = 0
        for _ in range(50):
            h = fold(h, r.below(n))
        put(f"below {n}", h)
    h = 0
    for _ in range(50):
        h = fold(h, r.urand(100, 10))
    for _ in range(50):
        h = fold(h, r.urand(5, 5))
    for _ in range(50):
        h = fold(h, r.urand(0, M64))
    for _ in range(50):
        h = fold(h, r.urand(0xFFFFFFFFFFFFFFF0, M64))
    put("urand", h)
    h = 0
    for _ in range(50):
        h = fold(h, r.urange(15))
    for _ in range(50):
        h = fold(h, r.urange(0))
    for _ in range(50):
        h = fold(h, r.urange(M32))
    for _ in range(50):
        h = fold(h, r.urange(3, 9))
    put("urange", h)
    h = 0
    for lo, hi in ((-5, 5), (-2**31, 2**31 - 1), (2**31 - 1, -2**31), (-2**31, -2**31 + 8)):
        for _ in range(50):
            h = fold(h, r.irand(lo, hi))
    put("irand", h)
    h = 0
    for p in range(102):
        for _ in range(20):
            h = fold(h, r.chance(p))
    for _ in range(20):
        h = fold(h, r.chance(M32))
    put("chance", h)
    h = 0
    for n in (0, 1, 13):
        for _ in range(50):
            h = fold(h, r.index(n))
    put("index", h)
    h = 0
    for w in ([70, 20, 10], [0, 0, 5], [0, 0], [1, 0, M32, 3]):
        for _ in range(50):
            h = fold(h, r.weighted(w))
    put("weighted", h)

    # t_sweep
    c, r = Rand("sweep.ctl"), Rand("sweep")
    h = bad = 0
    for _ in range(100000):
        kind = c.urange(3)
        if kind == 0:
            lo = c.urange(1000)
            hi = lo + c.urange(1000)
        elif kind == 1:
            lo = c.u32()
            hi = c.u32()
        elif kind == 2:
            lo = c.u64()
            hi = (lo + c.urange(255)) & M64
        else:
            lo = 0
            hi = ((1 << c.urange(63)) - 1) & M64
        v = r.urand(lo, hi)
        if not (min(lo, hi) <= v <= max(lo, hi)):
            bad += 1
        h = fold(h, v)
    put("sweep", h)
    put("sweep_out_of_range", bad)

    # t_exprs
    r = Rand("exprs")
    h = 0
    for _ in range(2000):
        v = 10 + r.urange(3)
        h = fold(h, v)
        v = r.urange(9) if r.chance(50) else r.urange(99, 50)
        h = fold(h, v)
        h = fold(h, 1 if r.urange(9) in (2, 3, 4, 7) else 2)
        h = fold(h, r.urange(1000))
        h = fold(h, r.urange(9) % 4)
    put("exprs", h)

    # workers: the delays come from the same stream, so the values do not
    # depend on the timing
    for i in range(50):
        r = Rand(f"worker{i}")
        h = 0
        for _ in range(400):
            v = r.urange(99)
            c = r.urange(4)
            h = fold(h, v)
            if c == 0:
                r.urange(5, 1)
        put(f"worker {i}", h)

    # sub-module always block
    r = Rand("sub")
    h = 0
    for _ in range(100):
        h = fold(h, r.u16())
    put("sub", h)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int, default=1, help="the run's +SEED (default 1)")
    a = ap.parse_args()
    Rand.run_seed = a.seed & M32
    sys.stdout.write("\n".join(lines()) + "\n")


if __name__ == "__main__":
    main()
