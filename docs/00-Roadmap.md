---
title: NPU-1 learning roadmap
tags: [npu-1, systemverilog, fpga, learning]
updated: 2026-10-29
status: local-inference-verified-cloud-pending
---
# NPU-1 — from an ALU to verified inference

Open this repository as an Obsidian vault, or copy the `docs` directory into your vault. Start with [[architecture]], [[arithmetic]], and [[register_map]]. Each exercise below has a concrete experiment. You can study and change one component at a time while the complete demo protects the final workload.

> [!success] Achieved locally
> C host → AXI transactions → RAM → systolic array → bias/requantization/ReLU → hidden activations → second RTL layer → logits. Frozen digits model: 344/360 correct, bit-exact hidden/logit comparisons, batch sizes 1 and 4.

> [!important] Physical FPGA work remains
> AWS account, quota, region, spending limit, developer-kit environment, Vivado reports and AFI deployment are still required. A local simulator is running software on your CPU. No ASIC was fabricated and no AWS resource was started.

## 0. Establish a reproducible baseline

- [x] Preserve the original source in Git and `legacy/`.
- [x] Provide portable commands and CI configuration.
- [ ] On your own terminal, install tools and run `make regression` using the README.
- [ ] Open `reports/regression.json` and match its source hashes to your revision.

Read [[verification_plan]]. Learn what each check proves before changing RTL. A regression that fails is useful evidence, not a reason to edit expected values until it passes.

## 1. Understand the processing element

- [x] Signed INT8 product and INT32 accumulator, forwarding, reset, clear, valid and hold.
- [x] Self-checking SV arithmetic tests and assertions.
- [ ] Predict `−128×−128`, `127×127`, and `−128×127` by hand.
- [ ] Trace a three-term dot product and explain why invalid input leaves the sum unchanged.
- [ ] Temporarily remove sign extension on a branch; observe the failing test; restore it.

Run `make test-pe`. Read `rtl/mac_pe.sv` alongside [[arithmetic]]. Distinguish input value from input validity.

## 2. Understand the systolic wavefront

- [x] Parameterized feeder and array; default 4×4.
- [x] Per-cycle oracle on 1×1, 3×5 and 4×4, including stalls and valid holes.
- [ ] Draw the k=0 path to PE[3,3] and account for all six enabled edges.
- [ ] Change a feeder delay and observe the earliest failing cycle in `make test-array`.
- [ ] Explain why pausing only the mesh, while continuing to shift the feeder, breaks pairing.

Use the timing table in [[architecture]]. Observe the difference between physical clock edges and enabled steps.

## 3. Add memory and sequencing

- [x] Four A banks and four B banks with byte writes and synchronous reads.
- [x] Load/run/drain/postprocess/store ownership, command validation, reset recovery.
- [ ] Trace the PREFETCH edge and first RUN edge. Explain which RAM value the PE sees.
- [ ] Read `tile_controller.sv`; predict the state after an illegal K=0 command.
- [ ] Explain why reset does not clear all operand RAM bytes.

Run `make test-core`. Actual block-RAM mapping is an FPGA synthesis question, still pending.

## 4. Make the host protocol dependable

- [x] Independent AXI write-address/data capture and response backpressure.
- [x] Byte-strobe handling, bounded address decode, busy ownership, W1C status and sequence checking.
- [x] Same C driver used with simulated AXI and the prepared AWS SDK transport.
- [ ] Read [[register_map]], then manually calculate addresses for A[2,17] and B[17,3].
- [ ] Explain why sending START is insufficient evidence that a job completed.

Run `make test-axil` and `make demo`. The randomized C++ bus driver holds BREADY/RREADY low and changes addresses after acceptance to expose timing bugs.

## 5. Run a quantized network

- [x] Frozen 64→32→10 digits MLP and NumPy integer reference.
- [x] Hidden activations from RTL become inputs to the second RTL layer.
- [x] Every hidden activation and logit compared, plus classification accuracy.
- [x] Single-image RTL inference with visual activations/cycle report; see [[image_demo]].
- [ ] Read the scale values in `models/digits/quantized_model.json`.
- [ ] Work one positive and one negative rounding example from [[arithmetic]].
- [ ] Optionally train a new model in a separate output folder after installing `requirements-training.txt`; keep the original fixtures for regression.

Run `make demo`; do not substitute a pure Python tiled calculation for RTL inference. The test fixture is frozen; training has not been rerun in this implementation session.

## 6. Close local verification

- [x] Lint and deterministic self-checking tests with failure exit codes.
- [x] K boundary/random cases and all three post-processing modes.
- [x] Source hashes and retained logs; Git milestones.
- [x] Concurrent AXI stress, reset phases, forced watchdog timeout and recovery.
- [x] PE control and AXI adapter induction proofs, with reachability witnesses.
- [ ] Push to your chosen remote and inspect the first CI run.
- [ ] Optional: enable trace capture or inspect a waveform manually; waveform review is not currently claimed.
- [ ] Optional: measure functional/line coverage and extend formal proofs to more blocks. Read `formal/README.md` for the current limited proof scope.

## 7. Prepare AWS F2

Follow [[aws_runbook]] in order. Do not skip the official example.

- [x] Pin the upstream F2 developer-kit revision and inspect OCL templates.
- [x] Prepare NPU staging, shell smoke test, host SDK transport, and constraints guidance.
- [ ] Confirm account access, region, F2 quota and an explicit spending cap.
- [ ] Select a currently compatible x86-64 developer AMI and build instance.
- [ ] Run the unmodified official AXI-Lite example in its HDK simulator.
- [ ] Stage NPU-1 and run the real shell smoke test.
- [ ] Build with Vivado; inspect synthesis, DRC, timing and resource reports.
- [ ] Upload the DCP, create an AFI, wait for `available`, and load its AGFI on F2.
- [ ] Compile the AWS host validator and run the same full fixture workload.
- [ ] Preserve image IDs, source hashes, tool versions and test output.

These steps are pending, not completed by local staging or Verilator tests.

## 8. Measure and clean up

- [x] Define [[benchmark_method]] with separate core and host timings.
- [ ] Measure actual FPGA clock, latency, transfer time and throughput after correctness passes.
- [ ] Compare to a CPU baseline on the same data and clearly label batch size.
- [ ] Stop/terminate approved instances and review EBS, snapshots, S3 and other retained charges.
- [ ] Publish an honest report with failed experiments and limitations.

## 9. Optional Raspberry Pi 5 (4 GB)

Read [[raspberry_pi]]. Use it to collect inputs, run the reference, or submit work over SSH to F2. The Pi is not an FPGA and cannot load an AWS AFI. Local FPGA execution needs a separate board and a new board-specific port.
