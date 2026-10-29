# Performance measurement

First prove bit-exact correctness. The current logs measure simulated cycles; wall-clock runtime of Verilator describes simulator speed, not FPGA speed. No measured FPGA throughput, power or Fmax is available.

For one tile, useful MACs = M_VALID×N_VALID×K; count a multiply and add as two operations. The array peak is 16 MAC/clock = 32 operations/clock, assuming every PE is active. At a **hypothetical** frequency f Hz, peak=32f operations/s. This formula is not a timing-closure claim.

Use `npu_perf_t` to capture core_cycles, load_time_us, exec_time_us (includes polling), read_time_us and total_time_us. For hardware measurements:

1. Record Git revision, model hash, AFI/AGFI, instance/region, shell clock recipe, actual clock report, compiler and SDK.
2. Measure K ∈ {1,4,16,64,256,1024}, full 4×4 and partial 1×4 tiles. Keep load, polling and read times separate.
3. Measure full two-layer inference at batch 1 and 4, with the same input/model quantization and output checks.
4. Warm up, then collect at least 30 independent repetitions. Report median and p95, sample count, useful MACs, and whether weights were retransferred.
5. Compute core throughput as `2*M*N*K*clock_hz/core_cycles`; host throughput uses total elapsed monotonic time and includes transfers. Do not use core-only throughput to advertise application latency.
6. Compare a NumPy CPU run on the same host and inputs. State thread settings and batch size. Report speedups only from these measured results.

This first version writes operands through AXI-Lite for every tile, so host transfers may dominate. DSP/BRAM/LUT counts and critical paths require Vivado reports. Optimization candidates are operand reuse, double buffering, a pipelined postprocessor, and DMA; they should follow measured bottlenecks.
