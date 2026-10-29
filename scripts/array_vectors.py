"""Deterministic whole-tile cases plus cycle/forwarding expectations."""

import random
from model.array_ref import ArrayState, pack_bytes

SEED_BASE = 20261025


class ArrayVectors:
    def __init__(self, path):
        self.file = path.open("w")
        self.state = ArrayState()
        self.cycles = 0
        self.tiles = 0
        self.file.write("# reset clear step av bv a_packed b_packed sums[16] a_edge b_edge av_edge bv_edge\n")

    def label(self, text):
        self.file.write(f"# {text}\n")

    def tick(self, reset=0, clear=0, step=1, av=0, bv=0, a=None, b=None):
        a = [0] * 4 if a is None else a
        b = [0] * 4 if b is None else b
        expected = self.state.tick(reset, clear, step, av, bv, a, b)
        row = (reset, clear, step, av, bv, pack_bytes(a), pack_bytes(b), *expected)
        self.file.write(" ".join(map(str, row)) + "\n")
        self.cycles += 1

    def tile(self, a, b, m=4, n=4, rng=None, label="tile"):
        import numpy as np
        k_size = len(b)
        assert 1 <= k_size <= 1024 and 1 <= m <= 4 and 1 <= n <= 4
        self.label(label)
        self.tick(clear=1, step=0)
        active_steps = 0
        for k in range(k_size):
            if rng is not None and rng.random() < 0.2:
                self.tick(step=0, av=15, bv=15, a=[127] * 4, b=[-128] * 4)
            self.tick(av=(1 << m) - 1, bv=(1 << n) - 1,
                      a=[a[i][k] if i < m else 0 for i in range(4)],
                      b=[b[k][j] if j < n else 0 for j in range(4)])
            active_steps += 1
        for _ in range(6):
            if rng is not None and rng.random() < 0.2:
                self.tick(step=0)
            self.tick()
            active_steps += 1
        assert active_steps == k_size + 6
        aa = np.asarray(a, dtype=np.int64).copy()
        bb = np.asarray(b, dtype=np.int64).copy()
        aa[m:, :] = 0
        bb[:, n:] = 0
        expected = (aa @ bb).ravel().tolist()
        assert self.state.sums == expected, (label, self.state.sums, expected)
        self.tiles += 1

    def close(self):
        self.file.close()
        return {"cycles": self.cycles, "tiles": self.tiles}


def directed(path):
    v = ArrayVectors(path)
    v.tick(reset=1)
    v.tile([[int(i == k) for k in range(4)] for i in range(4)],
           [[k * 7 - j * 3 for j in range(4)] for k in range(4)], label="identity times asymmetric B")
    v.tile([[0] * 3 for _ in range(4)], [[k - j for j in range(4)] for k in range(3)], label="zero A")
    v.tile([[1] * 4 for _ in range(4)], [[1] * 4 for _ in range(4)], label="K4 all ones: ten compute edges")
    v.tile([[-128] * 7 for _ in range(4)], [[-128] * 4 for _ in range(7)], label="negative times negative")
    v.tile([[-128] * 3 for _ in range(4)], [[127] * 4 for _ in range(3)], label="mixed sign")
    v.tile([[i + k - 4 for k in range(5)] for i in range(4)],
           [[k * 2 + j - 5 for j in range(4)] for k in range(5)], m=1, n=2, label="partial 1x2 tile")
    for control in ("clear", "reset"):
        v.label(f"abort in-flight operands with {control}")
        v.tick(av=15, bv=15, a=[7] * 4, b=[8] * 4)
        v.tick(**{control: 1})
        v.tile([[1, 2] for _ in range(4)], [[3] * 4, [-4] * 4], label=f"fresh tile after {control}")
    return v.close()


def random_tiles(path, count=1000):
    v = ArrayVectors(path)
    v.tick(reset=1)
    boundaries = [1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 64, 255, 1024]
    for case in range(count):
        rng = random.Random(SEED_BASE + case)
        k = boundaries[case] if case < len(boundaries) else rng.randint(1, 32)
        m, n = (4, 4) if case < len(boundaries) else (rng.randint(1, 4), rng.randint(1, 4))
        a = [[rng.randint(-128, 127) for _ in range(k)] for _ in range(4)]
        b = [[rng.randint(-128, 127) for _ in range(4)] for _ in range(k)]
        v.tile(a, b, m, n, rng, label=f"random tile={case} seed={SEED_BASE + case} M={m} N={n} K={k}")
    return v.close()


def random_control(path, count=5000):
    v = ArrayVectors(path)
    v.tick(reset=1)
    rng = random.Random(SEED_BASE)
    v.label(f"independent lane validity/reset/clear/step seed={SEED_BASE}")
    for _ in range(count):
        reset, clear = int(rng.random() < 0.02), int(rng.random() < 0.02)
        av, bv = (0, 0) if clear else (rng.randrange(16), rng.randrange(16))
        v.tick(reset=reset, clear=clear, step=rng.randrange(2), av=av, bv=bv,
               a=[rng.randint(-128, 127) for _ in range(4)],
               b=[rng.randint(-128, 127) for _ in range(4)])
    return v.close()
