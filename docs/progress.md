# Current progress

See [[00-Roadmap]] for the learning sequence and [[verification_plan]] for verified scope. Active results are in `reports/`, historical results in `legacy/reports/`. Local inference is implemented; AWS shell/build/deployment gates remain pending.


## Latest local improvements

- Pinned OSS CAD Suite for matching Linux/macOS CI environments; see [[toolchain]].
- `make predict SAMPLE=0` or `make predict IMAGE="digit.png"` executes both layers through RTL and produces a visual report; see [[image_demo]].
- Independent arithmetic seeds, concurrent AXI traffic, hard-reset bus phases, and real watchdog expiry/recovery. The watchdog regression exposed and fixed a BUSY-retention bug.
- PE control and AXI adapter induction proofs and cover witnesses; exact assumptions are in `formal/README.md`.

Use `make regression formal` to reproduce the current gates. AWS deployment remains pending; none of these local changes starts cloud resources.
