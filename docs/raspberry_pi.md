# Optional Raspberry Pi 5 host

A Pi 5 with 4 GB RAM can run Python/NumPy preprocessing and this small reference model. Copy the repository, create a native Arm Python environment, and run `make test-model`. Verilator on a Pi is possible but will be slower; it is still CPU simulation.

For a remote demonstration, collect or normalize an 8×8 digit, send the input to a controlled F2 host over SSH, and return logits/classification. First implement and validate a single-input extension to the host CLI; the current validator consumes the frozen batch fixture format. Keep authentication and timeouts in SSH; do not expose raw MMIO or an unauthenticated network service.

The AWS SDK transport runs on the F2 Linux machine, where PCIe exposes the FPGA. The Pi's PCIe connector does not provide FPGA logic; AWS AFIs cannot run on the Pi. A Pi-connected FPGA would require another board, physical interface, constraints, boot/reset and host-transport implementation. None is claimed here.
