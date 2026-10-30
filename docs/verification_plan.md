# Verification evidence — 2026-10-29

`reports/regression.json` is the latest complete local simulation report. `reports/formal.json` records the separate proofs; `reports/demo-smoke.json` records the image CLI checks. Each report identifies the source/tool inputs it tested. Earlier target reports remain dated snapshots, not substitutes for the current complete run. Logs are retained under `artifacts/` and uploaded by CI.

| Scope | Evidence / outcome |
|---|---|
| Production RTL lint | Verilator `-Wall --assert`, no warnings on `npu_axil` |
| Python tests | 19 tests: arithmetic, quantization, packing, Python inference and image preprocessing |
| PE simulation | Self-checking SV arithmetic, all 65,536 INT8 operand pairs, seeded dot products, valid/hold/reset |
| Array | SV directed/random tiles, K through 1024, pauses and consecutive jobs |
| Skew timing | Independent every-cycle history oracle: 1×1, 3×5, 4×4; five streams each, valid holes and random global holds |
| Buffered core | SV raw/bias results, configuration errors and abort/recovery; supplemented by the end-to-end oracle |
| AXI | SV protocol tests plus randomized AW/W arrival and B/R backpressure; 1,000 overlapping reads/writes per bus seed, distinct-address RAM scoreboard and byte strobes |
| Edge protocol | All 16 RAM byte-strobe masks, zero-strobe START, partial register rejection, RAM latency, full-address bounds, busy access rejection, W1C, invalid jobs |
| Reset/abort | 50 soft-abort delays; seven hard-reset bus phases per seed: AW-only, W-only, newly captured write, held B, pending AR, held R, overlapping held B/R; preconditions, no ghost response and subsequent transactions checked |
| Watchdog | Real controller timeout with test limit 64; error code 6, BUSY release, no DONE/completed sequence, bounded cycle counter, W1C and a nonzero-result GEMM without reset |
| C host driver | `-Wall -Wextra -Werror`; real simulated MMIO; failed transport write propagation |
| Random GEMM | 160 problems for each of three arithmetic seeds (480 runs); M=1…9, N=1…13, K={1,2,3,4,7,16,31,64,255,1023,1024}; modes 0/1/2, extreme bias/requantization |
| Neural network | 360 frozen digits, both layers executed in RTL, batch sizes 1 and 4; all hidden activations/logits bit-exact; 344/360 correct under each bus seed |
| Image CLI | Frozen samples 0/42/359; light/dark PNG inputs; hidden sums, activations and logits bit-exact; render/decode report; invalid input and stale report checks |
| Formal | PE control and AXI adapter safety proved by induction; separate cover tasks all reached. [Exact scope and assumptions](../formal/README.md) |

Arithmetic seeds are **20261029, 20261030, 20261031**, paired respectively with bus seeds **1, 7, 42**. Shapes and directed extremes repeat by design; random operands/biases differ. The network remains frozen, yielding 2,160 sample executions across three bus schedules and two batch sizes. Existing SV `$urandom` tests use the simulator's deterministic default seed; they are not advertised as new independent arithmetic seeds.

## A bug the new tests found

The old watchdog override applied even in `ST_ERROR`. After expiry, it repeatedly overwrote the error state's transition to IDLE, retaining BUSY until the 16-bit timer wrapped. The new test first failed with `watchdog error failed to release BUSY`. The override now applies only to active work, allowing error/done states to retire. The default remains 50,000 cycles; a bounded parameter lets the test trigger expiry in a short run. The recovery GEMM uses a nonzero expected result so a cleared or idle datapath cannot pass accidentally.

## Reproduction and CI

Use the [pinned toolchain](toolchain.md), then `make regression formal`. The local host is macOS arm64 with Python 3.13.7; CI selects Python 3.12, Linux x86-64 and macOS arm64. Reports record actual versions. The runner builds in fresh space-free temporary directories, enables assertions, and records failing commands and exit status. Formal missing-tool/inconclusive/timeout outcomes fail rather than being silently skipped.

The first GitHub runs exposed an old-simulator problem. The original lint failure and later Verilator 5.020 array failure remain visible in Actions history; the workflow now pins the dated suite. See the [live CI workflow](https://github.com/shmoos/npu-1/actions/workflows/verify.yml) and `reports/ci.json` once a completed remote run is recorded. A local PASS alone is not remote evidence.

## Remaining limits

- AWS shell simulation, vendor IP/PCIe/reset integration, Vivado elaboration/synthesis/place-and-route, BRAM/DSP inference, timing closure, AFI creation and physical F2 deployment.
- AWS SDK hardware-linked binary execution. The SDK-unavailable CLI intentionally fails when asked to attach.
- Training/float baseline reproduction: frozen quantized assets were reused. The reported accuracy is measured on those frozen vectors; it does not establish custom-image accuracy.
- Full-system formal correctness/liveness, functional or line coverage percentages, and manually reviewed waveforms. Formal cover reachability is not a coverage percentage.
- Simultaneous same-address RAM read/write semantics, exhaustive reset testing at every state/edge, and multi-process host access. Stress reads and writes use distinct addresses.
- Physical power, throughput, Fmax, AWS cost estimates and CPU speedups. No hardware performance is claimed.

Staging a source package or checking its hashes cannot close a hardware gate. Preserve each later hardware report separately with commands, source/image IDs and outcomes.
