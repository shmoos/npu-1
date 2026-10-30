# Small formal proofs

Run `make formal` with the [pinned tools](../docs/toolchain.md). Missing tools, failed assertions, unreachable covers, timeouts or inconclusive proofs fail the command. Results are recorded in `reports/formal.json`; logs and witnesses are retained in `artifacts/formal/`.

| Harness | Proved assertions | Reachability checks |
|---|---|---|
| `pe_formal.sv` | Reset/clear zero all state; step=0 holds all state; enabled data/valid forwarding; invalid operand pair holds accumulation | A nonzero accumulated result and a subsequent held result |
| `axil_formal.sv` | B/R valid and response payload remain stable during backpressure; reset clears responses; no unsolicited response; at most one outstanding AW, W and AR | Split AW/W in both orders with an overlapping read, overlapping stalled responses, simultaneous response completion |

Both safety tasks use SMT-based temporal induction (PE depth 12, AXI depth 16); PASS requires both the base case and induction. These are unbounded safety proofs once induction succeeds, not merely 12/16-cycle simulations. Separate cover tasks generate finite witness traces so that interesting activity is demonstrably possible.

## Assumptions and abstraction boundary

The first sampled clock edge is reset. Later resets are arbitrary. PE operands, valid flags, clear and step are arbitrary top-level inputs. The AXI master holds valid and payload while waiting for a request handshake, as required by AXI. Response readiness is unconstrained and may remain low indefinitely; no fairness assumption hides backpressure bugs. Properties are synchronous to the modeled clock and do not cover metastability or analog reset behavior.

The AXI task reads the **actual** `rtl/npu_axil.sv`. Slang blackboxes only `npu_core`, then Yosys removes that cell and converts its undriven outputs to unconstrained symbolic values. All 259 bits of backend status/data may change independently each cycle. The bus adapter must hold a captured response even in that environment. The register/bus logic is not replaced by a behavioral duplicate. The source of `npu_core` and dependencies is parsed to resolve its typed interface, but the compute backend is not proved here.

The AXI scoreboard tracks accepted requests and completed responses independently. Additional **assertions**, not assumptions, relate the scoreboard to internal latches to make induction converge from reachable states. The harness does not assume its desired result. A no-spurious-response property is not a full AXI compliance or liveness proof.

PE multiplication correctness is exhaustively simulated for all 65,536 INT8 pairs in `make test-pe`; the present formal scope is control/forwarding/hold. Full-array arithmetic, SRAM correctness, full-system deadlock freedom and AWS shell behavior remain outside these proofs. Formal does not replace the randomized C/RTL/NumPy comparison.
