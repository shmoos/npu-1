"""
Unit tests for host operand packing, unpacking, and matrix tile scheduling.
"""

import pytest
import numpy as np
from model.gemm_ref import gemm_reference


def pack_a_tensor(a_tile: np.ndarray) -> bytes:
    """
    Packs a tile of A (shape: (m_valid, K) with m_valid <= 4, K <= 1024)
    into the 4-bank buffer layout (4096 bytes total).
    Bank stride: 1024 bytes.
    Byte offset: row * 1024 + k.
    Unused lanes/rows are padded with 0.
    """
    m_valid, k_len = a_tile.shape
    assert 1 <= m_valid <= 4
    assert 1 <= k_len <= 1024
    buffer = bytearray(4096)
    for row in range(m_valid):
        for k in range(k_len):
            val = int(a_tile[row, k])
            assert -128 <= val <= 127
            buffer[row * 1024 + k] = val & 0xFF
    return bytes(buffer)


def pack_b_tensor(b_tile: np.ndarray) -> bytes:
    """
    Packs a tile of B (shape: (K, n_valid) with n_valid <= 4, K <= 1024)
    into the 4-bank buffer layout (4096 bytes total).
    Bank stride: 1024 bytes.
    Byte offset: col * 1024 + k (B is stored transposed per column bank).
    Unused lanes/cols are padded with 0.
    """
    k_len, n_valid = b_tile.shape
    assert 1 <= n_valid <= 4
    assert 1 <= k_len <= 1024
    buffer = bytearray(4096)
    for col in range(n_valid):
        for k in range(k_len):
            val = int(b_tile[k, col])
            assert -128 <= val <= 127
            buffer[col * 1024 + k] = val & 0xFF
    return bytes(buffer)


def unpack_a_tensor(packed_bytes: bytes, m_valid: int, k_len: int) -> np.ndarray:
    """Reconstructs A tile from packed bytes."""
    a_tile = np.zeros((m_valid, k_len), dtype=np.int8)
    for row in range(m_valid):
        for k in range(k_len):
            byte_val = packed_bytes[row * 1024 + k]
            val = byte_val if byte_val < 128 else byte_val - 256
            a_tile[row, k] = val
    return a_tile


def unpack_b_tensor(packed_bytes: bytes, n_valid: int, k_len: int) -> np.ndarray:
    """Reconstructs B tile from packed bytes."""
    b_tile = np.zeros((k_len, n_valid), dtype=np.int8)
    for col in range(n_valid):
        for k in range(k_len):
            byte_val = packed_bytes[col * 1024 + k]
            val = byte_val if byte_val < 128 else byte_val - 256
            b_tile[k, col] = val
    return b_tile


def unpack_c_buffer(c_words: list[int], m_valid: int, n_valid: int) -> np.ndarray:
    """Unpacks 16 INT32 words from C buffer into (m_valid, n_valid) array."""
    assert len(c_words) == 16
    c_mat = np.zeros((m_valid, n_valid), dtype=np.int32)
    for row in range(m_valid):
        for col in range(n_valid):
            word_val = c_words[row * 4 + col]
            # Convert unsigned 32-bit word to signed int32
            signed_val = word_val if word_val < (1 << 31) else word_val - (1 << 32)
            c_mat[row, col] = signed_val
    return c_mat


def unpack_y_buffer(y_words: list[int], m_valid: int, n_valid: int) -> np.ndarray:
    """Unpacks 4 words (16 INT8 values) from Y buffer into (m_valid, n_valid) array."""
    assert len(y_words) == 4
    y_mat = np.zeros((m_valid, n_valid), dtype=np.int8)
    # Extract 16 bytes little-endian
    all_bytes = []
    for word in y_words:
        all_bytes.append(word & 0xFF)
        all_bytes.append((word >> 8) & 0xFF)
        all_bytes.append((word >> 16) & 0xFF)
        all_bytes.append((word >> 24) & 0xFF)

    for row in range(m_valid):
        for col in range(n_valid):
            b = all_bytes[row * 4 + col]
            val = b if b < 128 else b - 256
            y_mat[row, col] = val
    return y_mat


from model.packing import HostTileScheduler

def test_packing_round_trips():
    rng = np.random.default_rng(42)
    for m in [1, 2, 3, 4]:
        for k in [1, 4, 16, 64, 1024]:
            a_orig = rng.integers(-128, 128, size=(m, k), dtype=np.int8)
            packed = pack_a_tensor(a_orig)
            assert len(packed) == 4096
            a_recovered = unpack_a_tensor(packed, m, k)
            np.testing.assert_array_equal(a_orig, a_recovered)

    for n in [1, 2, 3, 4]:
        for k in [1, 4, 16, 64, 1024]:
            b_orig = rng.integers(-128, 128, size=(k, n), dtype=np.int8)
            packed = pack_b_tensor(b_orig)
            assert len(packed) == 4096
            b_recovered = unpack_b_tensor(packed, n, k)
            np.testing.assert_array_equal(b_orig, b_recovered)


def test_tile_scheduler_reconstruction():
    rng = np.random.default_rng(99)
    # Test arbitrary non-multiple-of-4 shapes: (5, 7, 13), (1, 10, 32), (8, 8, 64)
    for m, n, k in [(5, 7, 13), (1, 10, 32), (8, 8, 64)]:
        a_mat = rng.integers(-128, 128, size=(m, k), dtype=np.int8)
        b_mat = rng.integers(-128, 128, size=(k, n), dtype=np.int8)

        c_expected = gemm_reference(a_mat, b_mat)
        c_reconstructed = np.zeros((m, n), dtype=np.int32)

        scheduler = HostTileScheduler(m, n, k)
        for r_base, c_base, m_val, n_val, a_tile, b_tile in scheduler.get_tiles(a_mat, b_mat):
            # Compute tile GEMM
            c_tile = gemm_reference(a_tile, b_tile)
            c_reconstructed[r_base:r_base + m_val, c_base:c_base + n_val] = c_tile

        np.testing.assert_array_equal(c_expected, c_reconstructed)
