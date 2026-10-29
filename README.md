# NPU-1

A learning project for a signed INT8 inference accelerator, with a SystemVerilog multiply–accumulate processing element (PE) and a 4×4 output-stationary systolic array.

## Current implementation

- Fixed signed 8-bit operands, signed 16-bit product, and signed 32-bit accumulator.
- One-cycle registered operand/valid forwarding through 16 connected PEs.
- Four-lane input feeders with delays of zero, one, two, and three enabled edges.
- A history-based array oracle, per-cycle checking of every accumulator, and simulation-only operand tags.
- Synchronous reset, a separate clear cycle, global step/hold, and independent input-valid signals.
- Python integer reference, a C++ cycle-by-cycle scoreboard, exhaustive arithmetic tests, and seeded accumulation/control tests.
- Protocol assertions and a local simulator smoke test that checks both passing and intentionally failing behavior.

Buffers and a tile controller are the next milestone, followed by inference and AWS integration. This code currently runs in local simulation; physical FPGA validation comes later.

## Run the implemented checks

From this project directory, with the existing `.venv`:

```bash
make regression
```

Other implemented targets:

```bash
make lint
make smoke
make test-pe
make test-array
make test-model
```

The runner copies the selected source files to a temporary directory without spaces, compiles and executes there, then removes that temporary directory. Your original source folder can retain its current name. Logs, stimuli, and VCD waveforms stay under `artifacts/verification/`; reports stay under `reports/`.

This runner does not install software or contact AWS. VCD tracing avoids the optional compressed-waveform dependency missing from the initial Verilator setup.

For a fresh checkout, install a compatible Verilator and C++ compiler, then create a new Python environment at its final path:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.lock.txt
make regression
```

Do not move an existing virtual environment between paths; recreate it. The tested versions are recorded in `reports/tool_versions.txt`. An alternate Python interpreter can be selected with `make PYTHON=python3 regression` if it already has the required packages.

## Where to read next

- [PE contract and cycle example](docs/architecture.md)
- [Verification plan and commands](docs/verification_plan.md)
- [Milestone progress](docs/progress.md)
- [Full project roadmap](../NPU-1%20-%20Roadmap.md)
- `rtl/mac_pe.sv`: synthesizable PE datapath and simulation assertions.
- `model/pe_ref.py`: independent Python integer reference.
- `rtl/systolic_array_4x4.sv`: 16 PEs, skew feeders, and verification-only tags.
- `model/array_ref.py`: independent operand-arrival history and accumulator model.
- `scripts/run_verification.py`: repeatable test runner and report writer.

## Reading the evidence

`reports/all_verification.json` is the result of the latest complete regression, including source hashes. Check `status`; a failed run is recorded as failed. Individual targets write separate reports and do not overwrite the complete regression report.

The files containing `expected_failure` in their names are deliberate negative tests. Their success criterion is a nonzero exit with the specified diagnostic. A normal test must exit successfully with no mismatches.

No license has been selected yet. Choose one before publishing the project.
