"""Unbounded Python integers expose overflow instead of silently wrapping."""

from dataclasses import dataclass

INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
K_MAX = 1024


def checked_int8(value: int) -> int:
    value = int(value)
    if not -128 <= value <= 127:
        raise ValueError("operand must be signed INT8")
    return value


def dot_reference(a, b) -> int:
    if len(a) != len(b) or not 1 <= len(a) <= K_MAX:
        raise ValueError("dot product requires equal lengths in 1..1024")
    result = sum(checked_int8(x) * checked_int8(y) for x, y in zip(a, b))
    if not INT32_MIN <= result <= INT32_MAX:
        raise OverflowError("signed INT32 result overflow")
    return result


@dataclass
class PEState:
    acc: int = 0
    a_out: int = 0
    b_out: int = 0
    a_valid_out: bool = False
    b_valid_out: bool = False

    def tick(self, reset, clear, step, a_valid, b_valid, a, b):
        a, b = checked_int8(a), checked_int8(b)
        if clear and not reset and (a_valid or b_valid):
            raise ValueError("clear must occupy its own invalid-input cycle")
        if reset or clear:
            self.acc = self.a_out = self.b_out = 0
            self.a_valid_out = self.b_valid_out = False
        elif step:
            self.a_out, self.b_out = a, b
            self.a_valid_out, self.b_valid_out = bool(a_valid), bool(b_valid)
            if a_valid and b_valid:
                total = self.acc + a * b
                if not INT32_MIN <= total <= INT32_MAX:
                    raise OverflowError("signed INT32 accumulator overflow")
                self.acc = total
        return (self.acc, self.a_out & 0xFF, self.b_out & 0xFF,
                int(self.a_valid_out), int(self.b_valid_out))
