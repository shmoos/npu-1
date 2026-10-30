# Reproducible tools

CI uses **OSS CAD Suite 2026-10-29**, including Verilator, Yosys with the Slang SystemVerilog frontend, SymbiYosys and Yices. Both `ubuntu-24.04` and `macos-14` use the same dated release. The setup action is pinned to commit `c7845bc0d335c8076aa22047e85972caa8a916df`. Python is 3.12 in CI; dependencies are pinned in `requirements.lock.txt`.

Sources: [official suite release](https://github.com/YosysHQ/oss-cad-suite-build/releases/tag/2026-10-29), [official setup action at the pinned revision](https://github.com/YosysHQ/setup-oss-cad-suite/tree/c7845bc0d335c8076aa22047e85972caa8a916df). The release contains Verilator **5.053 devel, v5.052-640-g8c14ab842**, Yosys **0.70+277 / 77dddbd66** and SBY **v0.70-9-g79fc9ed** on the locally exercised Apple Silicon package. Reports record the actual versions on every platform.

## Apple Silicon installation

From the repository root, with Xcode Command Line Tools installed:

```sh
mkdir -p artifacts/tools
curl -fL --retry 3 -o artifacts/tools/oss-cad-suite.tgz \
  https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-10-29/oss-cad-suite-darwin-arm64-20261029.tgz
printf '%s\n' '5a431a6578c93bcf7cd05451cd556f549232f335051adc7cc85b802a5c51fb94  artifacts/tools/oss-cad-suite.tgz' | shasum -a 256 -c -
tar -xzf artifacts/tools/oss-cad-suite.tgz -C artifacts/tools
export PATH="$PWD/artifacts/tools/oss-cad-suite/bin:$PATH"
verilator --version
sby --version
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.lock.txt
make regression formal
```

The archive is about 525 MB. Follow the suite's official macOS quarantine instructions if macOS blocks an executable. Keep the suite directory intact: tool launchers depend on its bundled libraries. Do not copy only the binaries elsewhere.

For Linux x86-64, use asset `oss-cad-suite-linux-x64-20261029.tgz` from the same release (SHA-256 `ae6f7f11eeaf7c504762f1b812d28654a61cbb965f76ecda7aeb8306b1d015eb`) and a C/C++ compiler plus make. Other operating systems/architectures are outside the current CI matrix.

## Why pin the simulator?

Ubuntu's Verilator 5.020 first rejected a blocking-assignment warning in testbench clock generation. After narrowing that warning waiver to the five clock generators, the old simulator still failed array simulation, reporting zero for PE[0,0]. The same tests passed on macOS with 5.052. This is evidence of a tool-version-dependent failure, not proof of its internal cause. Version 5.020 is unsupported for this project until that incompatibility is separately investigated.

The portable RTL uses unpacked arrays, packages, assertions and timed testbenches. “Any Verilator 5.x” was too broad a support claim. The dated suite now supplies the tested simulator and formal tools together. Homebrew Verilator 5.052 was used for the earlier baseline; use the pinned suite to reproduce the current full simulation/formal workflow.

Temporary build directories have no spaces even when the repository path does. Production lint remains strict. The inherited testbenches have narrow clock/initial-assignment/unused-signal waivers; the runner never disables fatal warnings globally.
