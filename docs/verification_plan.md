# M0/M1/M2 verification

## Required checks

| Test | Coverage | Oracle |
|---|---|---|
| Toolchain smoke | Clock, synchronous reset, count, waveform writing | Counter must reach four |
| Smoke negative control | Incorrect expectation must fail | Exact failure marker and nonzero exit |
| Directed PE | Signs, zero, clear, pause, separate validity, reset and restart | Per-edge Python state |
| Exhaustive PE | All 256×256 operand pairs, each with a new sum | Exact Python integer product |
| Seeded dots | 1,000 dot products, boundaries up to K=1024, pauses and bubbles | Python integer sum plus NumPy INT64 |
| Long extremes | Three 1024-term sign/extreme combinations | Analytic product times length |
| Random control | 10,000 randomized reset/clear/step/valid cycles | Per-edge state model |
| Negative scoreboard | A deliberately wrong expected accumulator | Must report `PE_MISMATCH` |
| Negative protocol | Clear with a valid operand | Must report the RTL `PE_CLEAR_WITH_VALID` assertion |
| Python tests | Known answers, input bounds, control behavior, overflow | Explicit examples and NumPy |
| Directed array | Identity, zeros, ones, signs, partial tiles, mid-wave reset/clear | Per-cycle history plus NumPy GEMM |
| Random array tiles | 1,000 seeded tiles; K boundaries through 1024; M/N in 1..4; pauses | All 16 sums and edge forwarding per cycle |
| Random array control | 5,000 cycles of independent lane validity, resets, clears, and pauses | Input-history oracle |
| Operand identity | Tags follow feeder delays and PE hops | Assert equal tags whenever both actual operands are valid |

Every normal PE cycle compares the accumulator, both forwarded data bytes, and both forwarded validity bits after the updating edge. Vectors retain seed/case labels so a failure can be reproduced.

## Commands

Run `make regression` from the project directory for the complete implemented suite. `make lint`, `make smoke`, `make test-pe`, `make test-array`, and `make test-model` select individual checks. Future core/AXI/coverage targets are intentionally absent until their implementations exist.

The Verilator build uses `-Wall` and `--assert`; warnings are not globally suppressed. Each build has a timeout, as does every simulator invocation. Negative tests require a specific diagnostic, not merely any process failure.

## Evidence

- `reports/all_verification.json`: complete-regression status, counts, seeds, versions, timestamps, and source hashes.
- `reports/tool_versions.txt`: actual local tools and Python dependency versions.
- `artifacts/verification/*_build.log`: compiler output.
- `artifacts/verification/pe_*.log`: simulation results, including deliberately failing controls.
- `artifacts/verification/*.txt`: reproducible cycle stimuli and expected outputs.
- `artifacts/verification/smoke.vcd` and `pe_directed.vcd`: waveforms.
- `artifacts/verification/array_directed.vcd`: array waveforms including all 16 sums.

Generated artifacts are ignored by Git. Small reports are retained for milestone review. Temporary space-free build folders are deleted after the run, even on failure.

## Limits

This is local functional verification. Physical timing closure, FPGA validation, four-state unknown propagation, device memory behavior, and PCIe ordering have later gates. A native waveform viewer and a human review/release tag remain separate checklist items.

Python test subprocesses disable unrelated pytest plugin auto-loading and allow a bounded 180-second startup/run window. A timeout writes partial output to the test log and fails the regression; it cannot silently become a passing result.
