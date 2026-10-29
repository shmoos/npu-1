"""
Tests for quantization methods, fixed-point conversion, and error envelopes.
"""

import numpy as np
import pytest
from model.quantize import (
    quantize_tensor_symmetric,
    quantize_bias,
    compute_fixed_point_multiplier,
)
from model.gemm_ref import round_away_from_zero, signed_round_shift


def test_round_away_from_zero_ties():
    # Test positive ties
    assert round_away_from_zero(0.5) == 1
    assert round_away_from_zero(1.5) == 2
    assert round_away_from_zero(2.5) == 3

    # Test negative ties
    assert round_away_from_zero(-0.5) == -1
    assert round_away_from_zero(-1.5) == -2
    assert round_away_from_zero(-2.5) == -3


def test_quantize_tensor_symmetric_clipping():
    # Array with extreme values outside [-127, 127] when scaled
    x = np.array([-200.0, -127.0, 0.0, 127.0, 200.0])
    q, s = quantize_tensor_symmetric(x, scale=1.0)
    assert q[0] == -127  # clipped
    assert q[1] == -127
    assert q[2] == 0
    assert q[3] == 127
    assert q[4] == 127   # clipped


def test_compute_fixed_point_multiplier_precision():
    # Test various target scaling ratios
    test_ratios = [0.001197, 0.05, 0.125, 0.5, 1.0, 2.718, 3.14159]
    for target in test_ratios:
        mult, shift = compute_fixed_point_multiplier(target)
        assert 1 <= mult <= (1 << 31) - 1
        assert 0 <= shift <= 62
        approx = mult / (1 << shift)
        relative_error = abs(approx - target) / target
        assert relative_error < 1e-4, f"Target {target} had error {relative_error}"


def test_signed_round_shift_extremes():
    # 64-bit value at boundary
    z_pos = (1 << 31) * 80341
    shifted_pos = signed_round_shift(z_pos, 26)
    assert shifted_pos > 0

    z_neg = -(1 << 31) * 80341
    shifted_neg = signed_round_shift(z_neg, 26)
    assert shifted_neg < 0
    assert shifted_pos == -shifted_neg
