# NPU-1 progress

Updated: October 25, 2026.

## Implemented

- Local project structure, isolated Python environment, pinned dependencies, Git initialization, and recorded tool versions.
- M0 simulator smoke with an intentionally wrong expectation detected before the passing run.
- M1 signed INT8 MAC PE with reset, clear, global hold, forwarding, validity, and protocol assertions.
- M2 sixteen-PE output-stationary array and zero/one/two/three-step skew feeders.
- Independent Python references, C++ cycle scoreboards, negative checks, repeatable Makefile commands, and VCD waveforms.

## Verification evidence

Read `reports/all_verification.json` for the latest combined result and exact source hashes. Individual array results are in `reports/array_verification.json`.

The PE suite checks all 65,536 single-product pairs, 1,000 seeded dot products, three maximum-length extreme reductions, and 10,000 random control cycles. The array suite checks 1,000 random matrix tiles, eight directed tiles, and 5,000 random control cycles. All 16 accumulators and outgoing operands/validity are compared on every array cycle; token assertions check matched reduction steps.

## Next milestone

M3: implement four A banks, four B banks, synchronous reads, input prefetch, and a bounded tile controller. Freeze how one command loads operands, starts computation, drains six array steps, and stores all 16 results. Then test partial tiles, maximum K, invalid commands, and reset/restart before adding neural-network post-processing.

## Outstanding review items

- Open the generated VCD in a chosen native waveform viewer; no extra viewer has been installed.
- Review the PE and array interfaces and select a source-code license before publication.
- Create reviewed release commits/tags; the new local repository has not been committed or tagged.
- The initial broad roadmap remains a plan for buffers, inference, AWS, benchmarks, and Pi integration. Cloud resources have not been provisioned.

## Development notes

The project stays in its existing folder. Builds stage selected sources into a temporary path without spaces, then preserve logs and waveforms back in the project. VCD is used because the installed Verilator's compressed-waveform build required an unavailable optional dependency. Python test startup now has a longer bounded timeout and unrelated plugin auto-loading is disabled.
