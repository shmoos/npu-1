"""
NPU-1 Golden Arithmetic Reference Models.
Operates using widened INT64 arithmetic to verify absence of overflow.
"""

import numpy as np


def pe_product(a_val: int, b_val: int) -> int:
    """Exact signed INT8 product."""
    assert -128 <= a_val <= 127, f"a_val {a_val} out of INT8 range"
    assert -128 <= b_val <= 127, f"b_val {b_val} out of INT8 range"
    prod = int(np.int64(a_val) * np.int64(b_val))
    assert -32768 <= prod <= 32767, f"product {prod} out of INT16 range"
    return prod


def dot_product_ref(a_vals: list[int], b_vals: list[int]) -> int:
    """Computes exact dot product accumulating into 32-bit integer."""
    assert len(a_vals) == len(b_vals)
    acc = np.int64(0)
    for a, b in zip(a_vals, b_vals):
        acc += np.int64(pe_product(a, b))
    assert -(1 << 31) <= acc <= (1 << 31) - 1, f"acc {acc} out of INT32 range"
    return int(acc)


def gemm_reference(a_i8: np.ndarray, b_i8: np.ndarray) -> np.ndarray:
    """
    Golden matrix multiplication C = A @ B.
    A: shape (M, K), dtype int8
    B: shape (K, N), dtype int8
    Returns C: shape (M, N), dtype int32
    """
    assert a_i8.dtype == np.int8 or np.issubdtype(a_i8.dtype, np.integer)
    assert b_i8.dtype == np.int8 or np.issubdtype(b_i8.dtype, np.integer)
    a_64 = a_i8.astype(np.int64)
    b_64 = b_i8.astype(np.int64)
    result_64 = a_64 @ b_64
    assert np.all(result_64 >= -(1 << 31)), "Underflow below signed INT32 min"
    assert np.all(result_64 <= (1 << 31) - 1), "Overflow above signed INT32 max"
    return result_64.astype(np.int32)


def round_away_from_zero(x: float) -> int:
    """
    Rounds to nearest integer with half-way ties rounded away from zero:
    sign(x) * floor(abs(x) + 0.5)
    """
    if x >= 0:
        return int(np.floor(x + 0.5))
    else:
        return -int(np.floor(abs(x) + 0.5))


def signed_round_shift(z: int, shift: int) -> int:
    """
    Rounds signed 64-bit integer z after right-shifting by shift bits.
    Ties are rounded away from zero:
    For shift == 0: z
    For shift > 0: sign(z) * ((abs(z) + 2^(shift - 1)) >> shift)
    """
    assert 0 <= shift <= 62, f"shift {shift} out of [0, 62] range"
    if shift == 0:
        return z
    sign = 1 if z >= 0 else -1
    abs_z = abs(z)
    rounded = (abs_z + (1 << (shift - 1))) >> shift
    return sign * rounded


def postprocess_ref(
    acc_int32: int,
    bias: int,
    mode: int,
    requant_mult: int = 1,
    requant_shift: int = 0
) -> tuple[int, int]:
    """
    Executes post-processing logic according to MODE:
      mode 0: raw INT32 GEMM output
      mode 1: biased INT32
      mode 2: biased + ReLU + requantized INT8
    Returns: (c_out_int32, y_out_int8)
    """
    if mode == 0:
        return (acc_int32, 0)

    # Mode 1 & 2: Add bias
    biased = int(np.int64(acc_int32) + np.int64(bias))
    biased = max(-(1 << 31), min((1 << 31) - 1, biased))

    if mode == 1:
        return (biased, 0)

    # Mode 2: Requantize and ReLU
    assert mode == 2 and 1 <= requant_mult <= 0x7fffffff
    z = biased * int(requant_mult)
    q = signed_round_shift(z, requant_shift)
    relu = max(0, q)
    y_i8 = int(np.clip(relu, -127, 127))
    return (biased, y_i8)
