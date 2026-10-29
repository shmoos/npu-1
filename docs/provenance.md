# Provenance and design corrections

The workspace contained `npu-1` (PE/array learning baseline) and `Gemini Progress on NPU` (a larger draft). The first local commit preserves the original baseline. Active RTL, model fixtures and C APIs were adapted from the larger draft; the sibling directory was left unchanged. `legacy/` is historical reference only.

The draft's mock transport and standalone OCL wrapper did not prove physical FPGA execution or official AWS shell compatibility. Its timing-derived GOPS and mock-host throughput are not used as FPGA measurements here.

Corrections include synchronous RAM data reads and delayed AXI responses; rejection of partial register writes; real RAM byte enables; full address range checks; busy-access errors; reset flushing of post-processing; watchdog priority; explicit bias saturation and multiplier limits; reusable parameterized feeders; C MMIO error propagation; production reference code independent of tests; and actual host-to-RTL two-layer inference.

The digits model and normalized test inputs were already present. This session revalidated integer inference and RTL tensor equivalence but did not retrain the float network. The historical float accuracy/training claims in model metadata are not new measurements. See scikit-learn's [digits dataset documentation](https://scikit-learn.org/stable/modules/generated/sklearn.datasets.load_digits.html) and the dataset attribution there before redistributing data. The training script uses a seeded stratified split and validation calibration; frozen fixtures make inference reproducible without downloading or training anything.

No license is imposed on the user's project. AWS developer-kit files remain governed by their upstream license; the staging tool copies/transforms the user's pinned checkout and preserves its notices. Select an appropriate license and review dataset redistribution terms before public release.
