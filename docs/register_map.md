# Planned tile buffers and register interface

Status: specification only. M0–M2 do not yet implement memories, the command controller, AXI-Lite, or post-processing. This contract is copied from the roadmap for M3–M5 implementation.

### 3.4 Buffer packing

Use a fixed bank stride of 1024 bytes. Host layout is deliberately different for A and B:

```text
A byte offset = row * 1024 + k       # four row banks
B byte offset = column * 1024 + k    # four column banks; B is packed transposed
C byte offset = 4 * (row * 4 + column)
Y byte offset = row * 4 + column
```

Each A/B bank supplies one signed byte per compute step after its documented read latency. Eight banks supply four A plus four B values. Raw capacity is 4096 + 4096 + 64 + 16 bytes, plus bias and control state; actual FPGA block usage depends on memory aspect ratios and inference.

Pack four consecutive bytes in a 32-bit word, first byte in bits `[7:0]`. Use explicit little-endian serialization in files and software. Test negative bytes such as `0x80` and `0xff`. Explicitly write all consumed input locations and padded lanes before START; do not rely on FPGA RAM power-up values or reset clearing the RAM contents.

### 3.5 Proposed NPU-1 register map

These offsets are **our custom ABI**, not existing AWS registers. Freeze this table before creating both the RTL decoder and host header. OCL is reached through the application PCIe BAR; use the pinned AWS SDK's identifiers. [AWS PCIe memory map](https://awsdocs-fpga-f2.readthedocs-hosted.com/latest/hdk/docs/AWS-Fpga-Pcie-Memory-Map.html)

| Byte offset | Register / window | Access | Meaning |
|---|---|---|---|
| `0x0000` | ID | RO | Fixed NPU-1 magic, e.g. `0x4e505531` |
| `0x0004` | ABI_VERSION | RO | Register-interface version |
| `0x0008` | CONTROL | WO | Bit 0 START; bit 1 SOFT_RESET; self-clearing commands |
| `0x000c` | STATUS | RO/W1C | Bit 0 BUSY RO; bit 1 DONE W1C; bit 2 ERROR W1C |
| `0x0010` | K | RW idle | 1…1024 |
| `0x0014` | M_VALID | RW idle | 1…4 |
| `0x0018` | N_VALID | RW idle | 1…4 |
| `0x001c` | MODE | RW idle | 0 raw GEMM; 1 biased INT32 logits; 2 biased/ReLU/requantized INT8 |
| `0x0020` | CYCLES_LO | RO | Latched completion-cycle count, low word |
| `0x0024` | CYCLES_HI | RO | High word of the same completed operation |
| `0x0028` | ERROR_CODE | RO | First outstanding error, with documented enumeration |
| `0x002c` | COMMAND_SEQ | RW idle | Host-provided sequence ID latched at START |
| `0x0030` | COMPLETED_SEQ | RO | Last completed sequence ID |
| `0x0034` | REQUANT_MULT | RW idle | Positive integer multiplier, at most `2^31−1` |
| `0x0038` | REQUANT_SHIFT | RW idle | Right shift, 0…62 |
| `0x003c` | BUILD_ID | RO | Build identifier linked to a full manifest hash |
| `0x0040…0x004c` | BIAS[0…3] | RW idle | Four signed INT32 column biases |
| `0x1000…0x1fff` | A | RW idle | Four banks, 1024 bytes per row |
| `0x2000…0x2fff` | B | RW idle | Four banks, 1024 bytes per column |
| `0x3000…0x303f` | C | RO idle | 16 row-major INT32 results; raw for mode 0, biased for modes 1/2 |
| `0x3100…0x310f` | Y | RO idle | 16 row-major INT8 results, valid only for mode 2 |

Protocol rules:

- Accept at most one command. Latch all configuration on START; clear stale DONE and start the cycle counter.
- Reject START/configuration/buffer writes while BUSY, without modifying the active operation. STATUS and immutable ID reads remain available.
- Keep result buffers stable after DONE until the next accepted START; reads while BUSY return an explicit error. New START invalidates prior results.
- DONE means the complete result is stored and readable. Increment/echo the completed sequence only on success.
- W1C means writing a 1 clears that sticky status bit; writing 0 leaves it unchanged. Specify simultaneous event/clear priority; new errors win.
- SOFT_RESET aborts computation and clears control/valid state; preserve the AXI adapter long enough to complete the reset write response. Host must reload all consumed inputs afterward.
- Honor AXI-Lite byte strobes, independently arriving write-address and write-data channels, and response backpressure. Return defined errors for unmapped or misaligned accesses.
- Define whole-command bounds and an internal watchdog; a host timeout must never become an infinite polling loop.

