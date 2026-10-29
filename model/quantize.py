"""
NPU-1 Quantization and Fixed-Point Helper Utilities.
Implements symmetric INT8 quantization with zero-point 0 and ties rounded away from zero.
"""

from typing import Tuple
import numpy as np
from model.gemm_ref import round_away_from_zero, signed_round_shift


def quantize_tensor_symmetric(
    tensor: np.ndarray,
    scale: float | None = None
) -> Tuple[np.ndarray, float]:
    """
    Quantizes a floating-point tensor to signed INT8 [-127, 127] using symmetric scale.
    If scale is None, computes scale as max(abs(tensor)) / 127.0.
    """
    if scale is None:
        max_val = float(np.max(np.abs(tensor)))
        scale = max_val / 127.0 if max_val > 0.0 else 1.0

    scaled = tensor / scale
    # Apply round away from zero elementwise
    flat = scaled.flatten()
    q_flat = np.array([round_away_from_zero(x) for x in flat], dtype=np.int32)
    q_clipped = np.clip(q_flat, -127, 127).astype(np.int8)
    return q_clipped.reshape(tensor.shape), scale


def quantize_bias(bias: np.ndarray, s_x: float, s_w: float) -> np.ndarray:
    """
    Quantizes floating-point bias into INT32 with scale s_x * s_w.
    """
    s_bias = s_x * s_w
    assert s_bias > 0.0, "Scale product must be positive"
    scaled = bias / s_bias
    flat = scaled.flatten()
    q_flat = np.array([round_away_from_zero(x) for x in flat], dtype=np.int64)
    assert np.all(q_flat >= -(1 << 31)) and np.all(q_flat <= (1 << 31) - 1)
    return q_flat.astype(np.int32).reshape(bias.shape)


def compute_fixed_point_multiplier(
    target_ratio: float,
    max_shift: int = 31
) -> Tuple[int, int]:
    """
    Finds integer (MULT, SHIFT) such that MULT / (2^SHIFT) closely approximates target_ratio.
    Constraints: 1 <= MULT <= 2^31 - 1, 0 <= SHIFT <= 62.
    """
    assert target_ratio > 0.0, "target_ratio must be positive"

    best_mult = 1
    best_shift = 0
    best_err = float('inf')

    for shift in range(0, max_shift + 1):
        mult = round_away_from_zero(target_ratio * (1 << shift))
        if 1 <= mult <= (1 << 31) - 1:
            approx = mult / (1 << shift)
            err = abs(approx - target_ratio) / target_ratio
            if err < best_err:
                best_err = err
                best_mult = mult
                best_shift = shift

    return best_mult, best_shift
