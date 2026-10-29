# Arithmetic contract

Implemented datapath: signed INT8 inputs, signed 16-bit product, signed INT32 output-stationary sums. Reset and clear set the sum to zero. Both operand-valid bits and step must be asserted to add a product.

`−128 × −128 = 16384`, `−128 × 127 = −16256`, and `127 × 127 = 16129`. Sign extension occurs before addition. A 33-bit intermediate supports the simulation overflow assertion; the stored result is 32 bits. Overflow is unsupported and must not be interpreted as saturation.

For the planned maximum reduction length K=1024, the conservative magnitude bound is `1024 × 16384 = 16,777,216`. The future controller will enforce K; the PE and array do not currently count or enforce it.

The software references use Python integers and NumPy INT64. They validate the signed operand ranges and result bounds before converting output values.

## Planned inference arithmetic

Model tensors use symmetric zero point zero and values −127…127. A real tensor value is represented approximately as `scale × integer`. Use one weight scale per layer initially. Quantize bias at the input-scale times weight-scale, add it once after the full reduction, and require the widened sum to fit INT32.

For hidden activations, multiply the biased sum by an offline-selected positive 31-bit integer multiplier, round a right shift using nearest/ties-away-from-zero, apply ReLU, and saturate to the INT8 model range. Use signed 64-bit intermediates. Shift zero is a separate no-shift case. Final biased INT32 logits share one positive scale, allowing integer argmax.

Bias, requantization, ReLU, and model export remain unimplemented until M4. Exact formulas and register settings are in the parent roadmap.
