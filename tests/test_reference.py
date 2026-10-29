import numpy as np
import pytest

from model.pe_ref import INT32_MAX, PEState, dot_reference


@pytest.mark.parametrize("a,b,expected", [
    ([-128], [-128], 16384),
    ([-128], [127], -16256),
    ([127], [127], 16129),
    ([1, -2, 3], [4, 5, -6], -24),
    ([-128] * 1024, [-128] * 1024, 16777216),
])
def test_known_dot_products(a, b, expected):
    assert dot_reference(a, b) == expected


def test_reference_agrees_with_widened_numpy():
    rng = np.random.default_rng(130)
    for length in (1, 3, 4, 16, 64, 255, 1024):
        a = rng.integers(-128, 128, length, dtype=np.int16)
        b = rng.integers(-128, 128, length, dtype=np.int16)
        assert dot_reference(a, b) == int(a.astype(np.int64) @ b.astype(np.int64))


@pytest.mark.parametrize("a,b", [([], []), ([1], [1, 2]), ([128], [1]),
                                    ([-129], [1]), ([1] * 1025, [1] * 1025)])
def test_illegal_dot_inputs(a, b):
    with pytest.raises(ValueError):
        dot_reference(a, b)


def test_control_and_forwarding():
    state = PEState()
    assert state.tick(1, 0, 0, 1, 1, 7, 8) == (0, 0, 0, 0, 0)
    assert state.tick(0, 0, 1, 1, 1, -2, 3) == (-6, 254, 3, 1, 1)
    assert state.tick(0, 0, 0, 0, 0, 99, 99) == (-6, 254, 3, 1, 1)
    assert state.tick(0, 0, 1, 1, 0, 9, -1) == (-6, 9, 255, 1, 0)
    assert state.tick(0, 1, 0, 0, 0, 9, 9) == (0, 0, 0, 0, 0)


def test_clear_protocol_violation():
    with pytest.raises(ValueError):
        PEState().tick(0, 1, 1, 1, 0, 1, 1)


def test_reference_detects_overflow():
    with pytest.raises(OverflowError):
        PEState(acc=INT32_MAX).tick(0, 0, 1, 1, 1, 1, 1)
