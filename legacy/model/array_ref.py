"""History-based oracle: each PE consumes the input from i+j enabled edges ago.

This uses the mathematical arrival schedule instead of reproducing PE registers.
"""

from dataclasses import dataclass, field
from model.pe_ref import INT32_MIN, INT32_MAX, checked_int8


def pack_bytes(values):
    if len(values) != 4:
        raise ValueError("exactly four lanes are required")
    return sum((checked_int8(value) & 0xFF) << (8 * lane) for lane, value in enumerate(values))


@dataclass
class ArrayState:
    history: list = field(default_factory=list)
    sums: list = field(default_factory=lambda: [0] * 16)
    a_out: int = 0
    b_out: int = 0
    av_out: int = 0
    bv_out: int = 0

    def tick(self, reset, clear, step, av, bv, a, b):
        pack_bytes(a)
        pack_bytes(b)
        if not 0 <= av < 16 or not 0 <= bv < 16:
            raise ValueError("valid masks must fit four bits")
        if clear and not reset and (av or bv):
            raise ValueError("clear requires invalid external inputs")
        if reset or clear:
            self.history.clear()
            self.sums = [0] * 16
            self.a_out = self.b_out = self.av_out = self.bv_out = 0
        elif step:
            self.history.append((list(a), list(b), av, bv))
            t = len(self.history) - 1
            for i in range(4):
                for j in range(4):
                    k = t - i - j
                    if k >= 0:
                        old_a, old_b, old_av, old_bv = self.history[k]
                        if old_av & (1 << i) and old_bv & (1 << j):
                            total = self.sums[i * 4 + j] + old_a[i] * old_b[j]
                            if not INT32_MIN <= total <= INT32_MAX:
                                raise OverflowError("array accumulator overflow")
                            self.sums[i * 4 + j] = total
            edge_a, edge_b = [0] * 4, [0] * 4
            self.av_out = self.bv_out = 0
            for lane in range(4):
                k = t - lane - 3
                if k >= 0:
                    old_a, old_b, old_av, old_bv = self.history[k]
                    edge_a[lane] = old_a[lane]
                    edge_b[lane] = old_b[lane]
                    self.av_out |= ((old_av >> lane) & 1) << lane
                    self.bv_out |= ((old_bv >> lane) & 1) << lane
            self.a_out, self.b_out = pack_bytes(edge_a), pack_bytes(edge_b)
        return (*self.sums, self.a_out, self.b_out, self.av_out, self.bv_out)
