# NPU-1

A real SystemVerilog INT8 inference accelerator learning project. The portable RTL and C host driver run together in Verilator on macOS Apple Silicon or Linux. **Physical FPGA deployment has not been performed.**

The current design has a parameterized output-stationary array (default 4×4), signed 8×8→16 multiplication, 32-bit accumulation, 8 KiB of banked operand RAM, a tile controller, bias/ReLU/requantization, and an AXI4-Lite register interface. The fixed host ABI operates a 4×4 tile with `1 ≤ K ≤ 1024`; the host tiles larger M and N.

The included 64→32→10 digits MLP executes both layers through the RTL. Its **hidden activations and logits match the NumPy reference bit for bit**, with **344/360 correct classifications (95.56%)** at batch sizes 1 and 4. These are local RTL simulation results, not measured FPGA throughput.

## Start here

```sh
# macOS: install Verilator and a C/C++ toolchain first
brew install verilator
xcode-select --install  # only if Command Line Tools are missing
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.lock.txt
make regression
```

Use Python 3.11 or newer and Verilator 5.x (5.052 tested locally). Existing Python environments can use `make PYTHON=python3 regression`. Builds run in a fresh temporary path without spaces, so this repository can remain in `Chip Project/npu-1`.

- `make demo`: compile the C driver and RTL, run 160 randomized GEMMs and all 360 digits at batch sizes 1/4 under three AXI timing seeds.
- `make regression`: lint, Python reference tests, self-checking SV PE/array/core/bus tests, rectangular array timing tests, and the demo.
- `make lint`, `make test-pe`, `make test-array`, `make test-core`, `make test-axil`, `make test-model`: individual checks.
- `make host`: compile the hardware validation CLI without the AWS SDK; it deliberately refuses to emulate AWS. See the runbook for the SDK build.

Read [the Obsidian roadmap](docs/00-Roadmap.md), [architecture and timing](docs/architecture.md), [arithmetic](docs/arithmetic.md), [register protocol](docs/register_map.md), [verification evidence](docs/verification_plan.md), and [AWS F2 runbook](docs/aws_runbook.md).

## Evidence and boundaries

`reports/regression.json` records source hashes, tools, exact commands, exit codes and durations. Logs live in `artifacts/verification/`. A failed run records failure and returns nonzero. Individual targets do not replace the full regression report. CI is configured in `.github/workflows/verify.yml`; its remote execution is pending until this repository is pushed.

AWS staging is pinned to an inspected official developer-kit commit. Staging validation is not AWS shell simulation. Vivado synthesis, BRAM/DSP inference, timing closure, AFI creation, hardware correctness, FPGA performance and power remain unverified. No AWS resources were created or charged by this work. This project does not claim an ASIC.

`legacy/` preserves the original learning baseline and selected draft material for comparison; it is excluded from current testing. Its old reports and claims are historical. The active source was adapted from both existing local versions, then corrected and revalidated; see [provenance](docs/provenance.md). No publishing license has been selected for the active project.
