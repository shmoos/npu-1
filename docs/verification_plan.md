# Verification evidence — 2026-10-29

The current complete local run passed. `reports/regression.json` contains exact source hashes and commands. Logs are in `artifacts/verification/`. The retained report describes the source contents it tested, even if later documentation changes alter the Git commit.

| Scope | Evidence / outcome |
|---|---|
| Production RTL lint | Verilator `-Wall --assert`, no warnings on `npu_axil` |
| Python golden model | 16 tests: arithmetic, quantization, packing and pure-Python tiled/reference inference |
| PE | Self-checking SV directed arithmetic, all 65,536 INT8 operand pairs, seeded dot products, valid/hold/reset |
| Array | SV directed/random tiles, K through 1024, pauses and consecutive jobs |
| Skew timing | Independent every-cycle history oracle: 1×1, 3×5, 4×4; five streams each, valid holes and random global holds |
| Buffered core | SV raw/bias results, configuration errors and abort/recovery; supplemented by the more comprehensive end-to-end oracle |
| AXI | SV basic protocol plus C++ randomized AW/W arrival and B/R backpressure |
| Edge protocol | All 16 RAM byte-strobe masks, zero-strobe START, partial register rejection, RAM latency, full-address bounds, busy access rejection, W1C, invalid jobs |
| Reset | 50 abort delays spanning operation phases, followed by subsequent work |
| C host driver | Compiled with `-Wall -Wextra -Werror`; used for real simulated MMIO; failed write transport injection checked |
| Random GEMM | 160 NumPy-generated problems per bus seed; M=1…9, N=1…13, K={1,2,3,4,7,16,31,64,255,1023,1024}; modes 0/1/2, extreme bias and requantization values |
| Neural network | 360 frozen digits, both layers executed through RTL, batch sizes 1 and 4; every hidden activation/logit bit-exact; 344/360 correct |
| Repeatability | The same arithmetic fixture is exercised under three independent bus-delay seeds: 1, 7, 42 |

The three seeds change bus timing; they do not create three different sets of arithmetic inputs. The random operand fixture uses NumPy seed 20261029. Existing SV random tests use the simulator default deterministic seed. Inference runs total 2,160 sample executions across the three bus schedules and two batch sizes.

The local toolchain is macOS arm64, Verilator 5.052, Python 3.13.7, NumPy 2.2.6 and pytest 9.0.2. The runner starts fresh builds in temporary paths with no spaces. SV tests run with assertions enabled. Failure and timeout return nonzero, with logs preserved. Testbench-only unused-signal and initial-nonblocking-assignment warnings are suppressed for inherited benches; production lint does not suppress these globally.

## Unverified or limited

- Actual AWS shell simulation (including its vendor IP and reset/PCIe behavior), Vivado elaboration/synthesis/place-and-route, inferred BRAM/DSP resources, timing closure, AFI generation and physical F2 deployment.
- AWS SDK hardware-linked binary execution. The locally compiled CLI is an SDK-unavailable build that fails explicitly when asked to attach.
- GitHub Actions execution: workflow is prepared, no remote run claimed.
- Training/float baseline reproduction: frozen quantized assets were reused. Accuracy above was measured on those frozen test vectors.
- Formal proof, functional/line coverage percentages, manually reviewed waveforms, and forced watchdog expiry.
- Simultaneous read/write stress beyond the sequential host workload, arbitrary external reset midway through every AXI channel, and multi-process host access.
- Physical power, throughput, Fmax, cost estimates and CPU speedups. None are claimed.

Staging a source package or checking its hashes cannot close a hardware gate. Preserve each later report separately and add its exact command, source/image IDs and outcome before checking off AWS milestones.
