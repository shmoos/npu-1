"""
Unit tests for Python golden arithmetic references and cycle model.
"""

import pytest
import numpy as np
from model.gemm_ref import (
    pe_product,
    dot_product_ref,
    gemm_reference,
    round_away_from_zero,
    signed_round_shift,
    postprocess_ref,
)
from model.cycle_model import SystolicArrayCycleModel


def test_directed_products():
    assert pe_product(0, 0) == 0
    assert pe_product(0, 127) == 0
    assert pe_product(1, -1) == -1
    assert pe_product(-128, -128) == 16384
    assert pe_product(-128, 127) == -16256
    assert pe_product(127, 127) == 16129
    assert pe_product(-1, -1) == 1


def test_dot_product_directed():
    a = [1, -2, 3]
    b = [4, 5, -6]
    assert dot_product_ref(a, b) == -24

    # 1024 terms of -128 * -128
    a_long = [-128] * 1024
    b_long = [-128] * 1024
    assert dot_product_ref(a_long, b_long) == 16777216


def test_gemm_reference_shapes():
    rng = np.random.default_rng(42)
    for m, n, k in [(1, 1, 1), (4, 4, 4), (4, 4, 64), (5, 7, 13), (8, 8, 128)]:
        a = rng.integers(-128, 128, size=(m, k), dtype=np.int8)
        b = rng.integers(-128, 128, size=(k, n), dtype=np.int8)
        c = gemm_reference(a, b)
        assert c.shape == (m, n)
        assert c.dtype == np.int32
        # Verify manual loop matches
        c_expected = np.zeros((m, n), dtype=np.int32)
        for i in range(m):
            for j in range(n):
                c_expected[i, j] = sum(int(a[i, kk]) * int(b[kk, j]) for kk in range(k))
        np.testing.assert_array_equal(c, c_expected)


def test_rounding_away_from_zero():
    assert round_away_from_zero(0.0) == 0
    assert round_away_from_zero(0.4) == 0
    assert round_away_from_zero(0.5) == 1
    assert round_away_from_zero(0.6) == 1
    assert round_away_from_zero(-0.4) == 0
    assert round_away_from_zero(-0.5) == -1
    assert round_away_from_zero(-0.6) == -1
    assert round_away_from_zero(2.5) == 3
    assert round_away_from_zero(-2.5) == -3


def test_signed_round_shift():
    # shift = 0
    assert signed_round_shift(42, 0) == 42
    assert signed_round_shift(-42, 0) == -42

    # shift = 1: divide by 2, ties away from zero
    assert signed_round_shift(1, 1) == 1
    assert signed_round_shift(-1, 1) == -1
    assert signed_round_shift(2, 1) == 1
    assert signed_round_shift(-2, 1) == -1
    assert signed_round_shift(3, 1) == 2
    assert signed_round_shift(-3, 1) == -2

    # shift = 2: divide by 4, round offset is 2
    assert signed_round_shift(2, 2) == 1
    assert signed_round_shift(-2, 2) == -1
    assert signed_round_shift(4, 2) == 1
    assert signed_round_shift(-4, 2) == -1


def test_postprocess_modes():
    # Mode 0: Raw
    assert postprocess_ref(100, bias=10, mode=0) == (100, 0)

    # Mode 1: Biased
    assert postprocess_ref(100, bias=10, mode=1) == (110, 0)

    # Mode 2: Biased, ReLU, Requant
    c, y = postprocess_ref(100, bias=10, mode=2, requant_mult=2, requant_shift=1)
    assert c == 110
    assert y == 110

    # Negative result becomes 0 through ReLU
    c, y = postprocess_ref(-200, bias=10, mode=2, requant_mult=1, requant_shift=0)
    assert c == -190
    assert y == 0


def test_systolic_array_cycle_model():
    model = SystolicArrayCycleModel(4, 4)
    rng = np.random.default_rng(123)

    # Test cases: K values from roadmap M2.6
    k_values = [1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 64, 255]
    for k in k_values:
        a = rng.integers(-128, 128, size=(4, k), dtype=np.int8)
        b = rng.integers(-128, 128, size=(k, 4), dtype=np.int8)

        # Expected GEMM
        c_expected = gemm_reference(a, b)

        # Cycle model simulation with operand reduction index tags and timing checks
        c_sim, traces = model.simulate_tile(a, b, enable_tags=True)

        assert len(traces) == k + 6, f"Expected {k+6} cycles, got {len(traces)}"
        np.testing.assert_array_equal(c_sim, c_expected)

    # Extreme values: all -128
    a_ext = np.full((4, 4), -128, dtype=np.int8)
    b_ext = np.full((4, 4), -128, dtype=np.int8)
    c_sim, _ = model.simulate_tile(a_ext, b_ext)
    c_exp = gemm_reference(a_ext, b_ext)
    np.testing.assert_array_equal(c_sim, c_exp)
