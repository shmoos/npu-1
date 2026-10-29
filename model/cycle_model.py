"""
Cycle-accurate software model of the NPU-1 4x4 Output-Stationary Systolic Array
and Skew Feeder.
"""

from dataclasses import dataclass
import numpy as np


@dataclass
class CycleTrace:
    cycle: int
    pe_accumulators: np.ndarray  # Shape (4, 4), dtype int32
    pe_mac_events: list[tuple[int, int, int, int, int]]  # list of (row, col, k_a, k_b, product)


class SystolicArrayCycleModel:
    def __init__(self, array_m: int = 4, array_n: int = 4):
        self.m = array_m
        self.n = array_n
        self.reset()

    def reset(self):
        # Accumulators
        self.acc = np.zeros((self.m, self.n), dtype=np.int32)

        # Skew feeder pipelines:
        # row i has i delay stages
        self.a_skew_pipe = [[] for _ in range(self.m)]
        # col j has j delay stages
        self.b_skew_pipe = [[] for _ in range(self.n)]

        # PE internal forwarding registers:
        # a_reg[i][j]: forwarded to [i][j+1]
        self.a_pe_reg = [[(0, 0, False) for _ in range(self.n)] for _ in range(self.m)]
        # b_pe_reg[i][j]: forwarded to [i+1][j]
        self.b_pe_reg = [[(0, 0, False) for _ in range(self.n)] for _ in range(self.m)]

        self.cycle_count = 0

    def simulate_tile(
        self,
        a_matrix: np.ndarray,  # shape (4, K), dtype int8
        b_matrix: np.ndarray,  # shape (K, 4), dtype int8
        enable_tags: bool = True
    ) -> tuple[np.ndarray, list[CycleTrace]]:
        """
        Simulates the entire computation of a 4x4 tile with reduction dimension K.
        Returns:
          final_accumulators: (4, 4) np.int32
          traces: list of CycleTrace per cycle
        """
        k_dim = a_matrix.shape[1]
        assert b_matrix.shape[0] == k_dim
        assert a_matrix.shape[0] == self.m
        assert b_matrix.shape[1] == self.n

        self.reset()
        traces = []

        total_steps = k_dim + 6

        for step in range(total_steps):
            mac_events = []

            # 1. Determine unskewed inputs for this cycle
            a_unskewed = []
            for i in range(self.m):
                if step < k_dim:
                    val = int(a_matrix[i, step])
                    tag = step if enable_tags else 0
                    valid = True
                else:
                    val = 0
                    tag = -1
                    valid = False
                a_unskewed.append((val, tag, valid))

            b_unskewed = []
            for j in range(self.n):
                if step < k_dim:
                    val = int(b_matrix[step, j])
                    tag = step if enable_tags else 0
                    valid = True
                else:
                    val = 0
                    tag = -1
                    valid = False
                b_unskewed.append((val, tag, valid))

            # 2. Skew feeder evaluation
            # Row i has i delay stages
            a_skewed = []
            for i in range(self.m):
                if i == 0:
                    a_skewed.append(a_unskewed[0])
                else:
                    # Input to pipeline
                    self.a_skew_pipe[i].append(a_unskewed[i])
                    if len(self.a_skew_pipe[i]) > i:
                        a_skewed.append(self.a_skew_pipe[i].pop(0))
                    else:
                        a_skewed.append((0, -1, False))

            # Col j has j delay stages
            b_skewed = []
            for j in range(self.n):
                if j == 0:
                    b_skewed.append(b_unskewed[0])
                else:
                    self.b_skew_pipe[j].append(b_unskewed[j])
                    if len(self.b_skew_pipe[j]) > j:
                        b_skewed.append(self.b_skew_pipe[j].pop(0))
                    else:
                        b_skewed.append((0, -1, False))

            # 3. Array inputs at boundaries and PE hops
            # Current cycle operand arrivals at each PE
            a_at_pe = [[(0, -1, False) for _ in range(self.n)] for _ in range(self.m)]
            b_at_pe = [[(0, -1, False) for _ in range(self.n)] for _ in range(self.m)]

            for i in range(self.m):
                for j in range(self.n):
                    if j == 0:
                        a_at_pe[i][0] = a_skewed[i]
                    else:
                        a_at_pe[i][j] = self.a_pe_reg[i][j - 1]

                    if i == 0:
                        b_at_pe[0][j] = b_skewed[j]
                    else:
                        b_at_pe[i][j] = self.b_pe_reg[i - 1][j]

            # 4. Perform MAC and prepare next PE register updates
            next_a_pe_reg = [[(0, -1, False) for _ in range(self.n)] for _ in range(self.m)]
            next_b_pe_reg = [[(0, -1, False) for _ in range(self.n)] for _ in range(self.m)]

            for i in range(self.m):
                for j in range(self.n):
                    a_val, a_tag, a_val_valid = a_at_pe[i][j]
                    b_val, b_tag, b_val_valid = b_at_pe[i][j]

                    if a_val_valid and b_val_valid:
                        if enable_tags:
                            assert a_tag == b_tag, f"Cycle {step}: Tag mismatch at PE({i},{j})! a_tag={a_tag}, b_tag={b_tag}"
                            # Verify arrival time formula: step == k + i + j
                            assert step == a_tag + i + j, f"Cycle {step} != expected {a_tag + i + j} at PE({i},{j})"

                        product = a_val * b_val
                        self.acc[i, j] += np.int32(product)
                        mac_events.append((i, j, a_tag, b_tag, product))

                    next_a_pe_reg[i][j] = (a_val, a_tag, a_val_valid)
                    next_b_pe_reg[i][j] = (b_val, b_tag, b_val_valid)

            self.a_pe_reg = next_a_pe_reg
            self.b_pe_reg = next_b_pe_reg

            traces.append(CycleTrace(
                cycle=step,
                pe_accumulators=self.acc.copy(),
                pe_mac_events=mac_events
            ))

        return self.acc.copy(), traces
