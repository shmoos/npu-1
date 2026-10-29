# Host ABI v1

32-bit AXI4-Lite, little-endian, byte addresses. Identification magic `0x4e505531`, ABI `0x00010000`. Full 32-bit addresses are decoded in the F2 wrapper; the portable adapter defaults to 16 address bits.

| Offset | Name | Access / meaning |
|---|---|---|
| 0x00 | ID | RO magic |
| 0x04 | ABI | RO version |
| 0x08 | CONTROL | WO bit0 START, bit1 SOFT_RESET; reset wins if both set |
| 0x0c | STATUS | RO bit0 BUSY; bit1 DONE and bit2 ERROR are write-one-to-clear |
| 0x10 | K | RW 1…1024, low 16 bits |
| 0x14 | M_VALID | RW 1…4, low 3 bits |
| 0x18 | N_VALID | RW 1…4, low 3 bits |
| 0x1c | MODE | RW 0 raw, 1 biased INT32, 2 requantized/ReLU INT8; low 2 bits |
| 0x20 / 0x24 | CYCLES low/high | RO last completed/failed command's controller cycles |
| 0x28 | ERROR_CODE | RO sticky diagnostic |
| 0x2c | COMMAND_SEQ | RW host command identifier |
| 0x30 | COMPLETED_SEQ | RO last successful identifier |
| 0x34 | MULT | RW mode-2 positive multiplier |
| 0x38 | SHIFT | RW mode-2 shift, low 6 bits |
| 0x3c | BUILD_ID | RO `0x20261029` source build label, not a Git hash |
| 0x40…0x4c | BIAS[0…3] | RW signed INT32, one per column |
| 0x1000…0x1fff | A RAM | RW, four 1024-byte row banks |
| 0x2000…0x2fff | B RAM | RW, four 1024-byte column banks |
| 0x3000…0x303f | C | RO 16 INT32 outputs, row-major |
| 0x3100…0x310f | Y | RO 16 INT8 outputs, row-major packed four per word |

Addresses must be word aligned. Unknown addresses, read-only writes and misalignment return SLVERR. Zero WSTRB acknowledges without side effects. Registers require WSTRB=1111; partial nonzero register writes return SLVERR. RAM accepts all 16 byte-strobe patterns. Narrow config registers retain only the documented low bits; the C runtime rejects out-of-range user parameters before issuing writes.

AW and W are captured independently. One outstanding write and one outstanding read are supported; no combinational dependency requires them to arrive together. B and R responses remain stable until ready. RAM read responses include the synchronous memory delay. All operand/result reads and operand/config writes are rejected while busy; STATUS/control resets remain available. START while busy returns SLVERR, leaving the current operation running.

Errors: 1 invalid K, 2 M, 3 N, 4 mode, 6 watchdog, 7 requantization. Bus violations are reported by AXI SLVERR, not by the core error register. Reserved codes in the C/package enums are not currently emitted. Clearing ERROR does not erase ERROR_CODE; consult it only while ERROR is set.

## Transaction sequence

1. Attach F2 application PF BAR0 (OCL); verify ID and ABI; soft-reset.
2. Clear stale status. Write configuration and biases.
3. Pack A at `0x1000 + row*1024 + k`; B at `0x2000 + col*1024 + k`. Four adjacent k values occupy one little-endian word. Zero pad the last partial word.
4. Write sequence and START. Poll STATUS with a monotonic deadline. On ERROR read the code; on timeout reset before reuse.
5. Require DONE, not BUSY, and matching COMPLETED_SEQ before consuming results.
6. Read C at `0x3000+4*(row*4+col)` or Y bytes at `0x3100+row*4+col`. Ignore inactive rows/columns.
7. Clear DONE and issue the next tile.

The C driver implements this with error propagation for every MMIO operation. Calls are single-threaded and not safe for competing processes. The host chooses tiling; hardware never discovers tensor dimensions by itself.
