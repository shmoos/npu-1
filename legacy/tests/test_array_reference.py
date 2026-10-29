import pytest
from model.array_ref import ArrayState, pack_bytes


def test_byte_order():
    assert pack_bytes([-128, -1, 0, 127]) == 0x7F00FF80


def test_first_and_last_arrival():
    state = ArrayState()
    state.tick(1, 0, 1, 0, 0, [0]*4, [0]*4)
    state.tick(0, 0, 1, 15, 15, [1, 2, 3, 4], [5, 6, 7, 8])
    assert state.sums[0] == 5
    assert state.sums[15] == 0
    for _ in range(5):
        state.tick(0, 0, 1, 0, 0, [0]*4, [0]*4)
    assert state.sums[15] == 0
    state.tick(0, 0, 1, 0, 0, [0]*4, [0]*4)
    assert state.sums[15] == 32  # K=1 requires seven enabled edges.


def test_pause_and_clear_in_flight():
    state = ArrayState()
    before = state.tick(0, 0, 1, 15, 15, [2]*4, [3]*4)
    assert state.tick(0, 0, 0, 15, 15, [127]*4, [127]*4) == before
    state.tick(0, 1, 0, 0, 0, [0]*4, [0]*4)
    for _ in range(10):
        state.tick(0, 0, 1, 0, 0, [0]*4, [0]*4)
    assert state.sums == [0]*16


def test_clear_requires_invalid_external_operands():
    with pytest.raises(ValueError):
        ArrayState().tick(0, 1, 1, 1, 0, [1]*4, [1]*4)
