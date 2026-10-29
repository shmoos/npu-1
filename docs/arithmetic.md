# Exact integer arithmetic

[[architecture]] · [[register_map]]

- Operands: signed two's-complement INT8, −128…127; product: signed INT16. `−128 × −128 = 16384`, not an overflow.
- PE accumulation: 32-bit two's-complement addition. The standalone PE wraps on overflow; the core's legal K≤1024 ensures `|sum| ≤ 16,777,216`, so no raw dot-product overflow occurs.
- Bias: signed INT32 per output column. Add using widened arithmetic, then **saturate to [−2³¹, 2³¹−1]** before scaling and before writing C.
- Mode 0: C=raw accumulator, Y=0. Mode 1: C=saturated(acc+bias), Y=0.
- Mode 2: C=saturated(acc+bias); z=C×MULT using signed INT64; rounded q is defined below; Y=min(127,max(0,q)).
- MULT must be 1…2³¹−1 and SHIFT 0…62 in mode 2. The high multiplier bit is rejected, not silently discarded.

For SHIFT=0, q=z. Otherwise:

```text
q = sign(z) × ((abs(z) + 2^(SHIFT−1)) >> SHIFT)
```

Ties round away from zero: 3/2→2 and −3/2→−2. ReLU then maps negatives to zero. The bounded C and MULT keep multiplication and the largest rounding offset inside signed INT64. Zero-point is always zero. Quantization of source floats uses symmetric range −127…127; the raw hardware also accepts −128.

The NumPy reference first widens operands to INT64. Multiplying NumPy INT8 arrays directly would overflow before comparison. `postprocess_ref` uses Python integers for fixed-point math, providing an independent oracle. The frozen MLP uses one positive scale per tensor, one requantization multiplier/shift for its hidden layer, and biased INT32 output logits. Argmax selects the class; softmax is unnecessary.

There is no runtime float arithmetic in the accelerator. Training/calibration are optional offline work; local inference reuses the checked-in frozen model. Accuracy and tensor equivalence are separate tests: correct classifications alone cannot prove correct RTL.
