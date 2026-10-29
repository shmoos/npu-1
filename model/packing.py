"""Host tiling reference; no RTL execution."""
import numpy as np

class HostTileScheduler:
    """
    Slices arbitrary (M, K) and (K, N) matrices into 4x4 tiles,
    yielding (row_base, col_base, m_valid, n_valid, a_tile, b_tile).
    """
    def __init__(self, m: int, n: int, k: int):
        self.m = m
        self.n = n
        self.k = k

    def get_tiles(self, a_matrix: np.ndarray, b_matrix: np.ndarray):
        assert a_matrix.shape == (self.m, self.k)
        assert b_matrix.shape == (self.k, self.n)

        for row_base in range(0, self.m, 4):
            m_valid = min(4, self.m - row_base)
            for col_base in range(0, self.n, 4):
                n_valid = min(4, self.n - col_base)

                a_tile = a_matrix[row_base:row_base + m_valid, :]
                b_tile = b_matrix[:, col_base:col_base + n_valid]

                yield row_base, col_base, m_valid, n_valid, a_tile, b_tile

