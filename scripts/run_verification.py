#!/usr/bin/env python3
"""Build in a space-free temporary folder; keep evidence in the project."""

import argparse
from datetime import datetime, timezone
import hashlib
from importlib.metadata import version
import json
import os
from pathlib import Path
import platform
import random
import resource
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import array_vectors
from model.pe_ref import PEState, dot_reference

ARTIFACTS = ROOT / "artifacts" / "verification"
REPORTS = ROOT / "reports"
SEED_BASE = 20261025


def run(command, cwd, log_name, *, expected_error=None, timeout=180):
    log_path = ARTIFACTS / log_name
    environment = os.environ.copy()
    environment["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
    try:
        result = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout, env=environment)
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        log_path.write_text(output + f"\nTIMEOUT after {timeout} seconds\n")
        raise RuntimeError(f"Command timed out after {timeout}s; see {log_path}") from exc
    log_path.write_text(result.stdout)
    if expected_error is None:
        ok = result.returncode == 0
    else:
        ok = result.returncode != 0 and expected_error in result.stdout
    if not ok:
        raise RuntimeError(f"Command failed: {command}\nLog: {log_path}\n{result.stdout[-6000:]}")
    return result.stdout.strip()


class Vectors:
    def __init__(self, path):
        self.file = path.open("w")
        self.state = PEState()
        self.cycles = 0
        self.file.write("# reset clear step a_valid b_valid a b acc a_out_bits b_out_bits av_out bv_out\n")

    def label(self, label):
        self.file.write(f"# {label}\n")

    def tick(self, reset=0, clear=0, step=1, av=0, bv=0, a=0, b=0):
        expected = self.state.tick(reset, clear, step, av, bv, a, b)
        fields = (reset, clear, step, av, bv, a, b, *expected)
        self.file.write(" ".join(map(str, fields)) + "\n")
        self.cycles += 1

    def close(self):
        self.file.close()
        return self.cycles


def directed_vectors(path):
    v = Vectors(path)
    v.label("reset, clear and dot [1,-2,3] x [4,5,-6]")
    v.tick(reset=1, step=0, av=1, bv=1, a=99, b=99)
    v.tick(clear=1, step=0)
    v.tick(av=1, bv=1, a=1, b=4)    # acc = 4
    v.tick(step=0, av=1, bv=1, a=127, b=127)  # holds everything
    v.tick(av=1, bv=0, a=90, b=-90)  # forwards, no MAC
    v.tick(av=0, bv=1, a=-7, b=12)   # forwards, no MAC
    v.tick(av=1, bv=1, a=-2, b=5)    # acc = -6
    v.tick(av=1, bv=1, a=3, b=-6)    # acc = -24
    v.tick()                        # trailing invalid bubble
    v.tick(clear=1)
    v.tick(av=1, bv=1, a=-128, b=-128)
    v.tick(reset=1, clear=1, step=0, av=1, bv=1, a=127, b=127)
    v.tick(av=1, bv=1, a=-128, b=127)
    v.tick(reset=1)
    v.tick()
    return v.close()


def exhaustive_vectors(path):
    v = Vectors(path)
    v.tick(reset=1)
    for a in range(-128, 128):
        for b in range(-128, 128):
            v.tick(clear=1)
            v.tick(av=1, bv=1, a=a, b=b)
            assert v.state.acc == a * b
    v.tick()
    return v.close()


def dot_vectors(path, count=1000):
    import numpy as np
    v = Vectors(path)
    v.tick(reset=1)
    boundaries = [1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 64, 255, 1024]
    for case in range(count):
        rng = random.Random(SEED_BASE + case)
        length = boundaries[case] if case < len(boundaries) else rng.randint(1, 128)
        a = [rng.randint(-128, 127) for _ in range(length)]
        b = [rng.randint(-128, 127) for _ in range(length)]
        v.label(f"dot case={case} seed={SEED_BASE + case} K={length}")
        v.tick(clear=1, step=case % 2)
        for x, y in zip(a, b):
            if rng.random() < 0.2:
                v.tick(step=0, av=1, bv=1, a=127, b=-128)
            if rng.random() < 0.2:
                v.tick(av=case % 2, bv=1 - case % 2, a=-128, b=127)
            v.tick(av=1, bv=1, a=x, b=y)
        wanted = dot_reference(a, b)
        assert wanted == int(np.array(a, dtype=np.int64) @ np.array(b, dtype=np.int64))
        assert v.state.acc == wanted
        v.tick()
    for x, y in [(-128, -128), (-128, 127), (127, 127)]:
        v.label(f"maximum-length extreme dot a={x} b={y}")
        v.tick(clear=1)
        for _ in range(1024):
            v.tick(av=1, bv=1, a=x, b=y)
        assert v.state.acc == 1024 * x * y
        v.tick()
    return v.close()


def control_vectors(path, count=10000):
    v = Vectors(path)
    rng = random.Random(SEED_BASE)
    v.tick(reset=1)
    for _ in range(count):
        reset = int(rng.random() < 0.05)
        clear = int(rng.random() < 0.05)
        av, bv = rng.randrange(2), rng.randrange(2)
        if clear and not reset:
            av = bv = 0
        v.tick(reset=reset, clear=clear, step=rng.randrange(2), av=av, bv=bv,
               a=rng.randint(-128, 127), b=rng.randint(-128, 127))
    v.tick()
    return v.close()


def build_smoke(verilator, temp):
    work = temp / "smoke"
    work.mkdir()
    shutil.copy2(ROOT / "sim/tb_toolchain_smoke.sv", work)
    run([verilator, "--binary", "--timing", "--assert", "-Wall", "--trace-vcd",
         "--top-module", "tb_toolchain_smoke", "--Mdir", "obj", "tb_toolchain_smoke.sv"],
        work, "smoke_build.log")
    binary = str(work / "obj/Vtb_toolchain_smoke")
    run([binary, "+inject_failure"], work, "smoke_expected_failure.log",
        expected_error="SMOKE_COUNTER_MISMATCH", timeout=30)
    run([binary], work, "smoke_pass.log", timeout=30)
    shutil.copy2(work / "smoke.vcd", ARTIFACTS / "smoke.vcd")
    print("PASS: simulator smoke; an intentional mismatch fails, the valid case passes", flush=True)
    return {"positive": "pass", "intentional_mismatch": "detected", "waveform": "smoke.vcd"}


def check_pe(verilator, temp):
    work = temp / "pe"
    work.mkdir()
    for source in ("rtl/mac_pe.sv", "sim/pe_main.cpp"):
        shutil.copy2(ROOT / source, work)
    run([verilator, "--cc", "--exe", "--build", "--assert", "-Wall", "--trace-vcd",
         "--top-module", "mac_pe", "--Mdir", "obj", "mac_pe.sv", "pe_main.cpp"],
        work, "pe_build.log")
    binary = str(work / "obj/Vmac_pe")
    results = {}
    for name, generator in [("directed", directed_vectors), ("exhaustive", exhaustive_vectors),
                            ("dot_products", dot_vectors), ("control", control_vectors)]:
        path = ARTIFACTS / f"{name}.txt"
        cycles = generator(path)
        command = [binary, str(path)]
        if name == "directed":
            command.append(str(ARTIFACTS / "pe_directed.vcd"))
        run(command, work, f"pe_{name}.log", timeout=60)
        results[name] = {"status": "pass", "cycles": cycles}
        print(f"PASS: PE {name}, {cycles:,} cycles checked", flush=True)

    # The scoreboard must reject a deliberately incorrect expected accumulator.
    wrong = ARTIFACTS / "wrong_expected.txt"
    wrong.write_text("1 0 1 0 0 0 0 1 0 0 0 0\n")
    run([binary, str(wrong)], work, "pe_scoreboard_expected_failure.log",
        expected_error="PE_MISMATCH", timeout=30)

    # This malformed command must fail the RTL protocol assertion, not a scoreboard check.
    protocol = ARTIFACTS / "illegal_clear.txt"
    protocol.write_text("1 0 1 0 0 0 0 0 0 0 0 0\n0 1 1 1 0 1 2 0 0 0 0 0\n")
    run([binary, str(protocol)], work, "pe_protocol_expected_failure.log",
        expected_error="PE_CLEAR_WITH_VALID", timeout=30)
    results["negative_checks"] = {"scoreboard_mismatch": "detected", "illegal_clear": "detected"}
    results["single_product_pairs"] = 65536
    results["seeded_dot_products"] = 1000
    results["maximum_k"] = 1024
    print("PASS: scoreboard mismatch and illegal-clear assertion are both detected", flush=True)
    return results


def check_array(verilator, temp):
    work = temp / "array"
    work.mkdir()
    sources = ["rtl/mac_pe.sv", "rtl/skew_feeder.sv", "rtl/systolic_array_4x4.sv", "sim/array_main.cpp"]
    for source in sources:
        shutil.copy2(ROOT / source, work)
    run([verilator, "--cc", "--exe", "--build", "--assert", "-Wall", "--trace-vcd",
         "-DNPU_SIM_TAGS", "--top-module", "systolic_array_4x4", "--Mdir", "obj",
         *[Path(p).name for p in sources]], work, "array_build.log")
    binary = str(work / "obj/Vsystolic_array_4x4")
    results = {}
    for name, generator in [("directed", array_vectors.directed), ("random_tiles", array_vectors.random_tiles),
                            ("control", array_vectors.random_control)]:
        path = ARTIFACTS / f"array_{name}.txt"
        counts = generator(path)
        command = [binary, str(path)]
        if name == "directed":
            command.append(str(ARTIFACTS / "array_directed.vcd"))
        run(command, work, f"array_{name}.log", timeout=60)
        results[name] = {"status": "pass", **counts}
        print(f"PASS: array {name}, {counts['cycles']:,} cycles, {counts['tiles']:,} tiles", flush=True)
    results["operand_tag_assertions"] = "enabled and passed"
    results["compute_schedule"] = "K+6 enabled edges; stalls excluded"
    return results


def record_versions(verilator):
    def version_command(command):
        return subprocess.run(command, text=True, capture_output=True, timeout=15).stdout.strip()
    record = {"python": sys.version, "architecture": platform.machine(),
              "macos": platform.mac_ver()[0], "platform": platform.platform(),
              "verilator": version_command([verilator, "--version"]),
              "compiler": version_command(["c++", "--version"]),
              "packages": {name: version(name) for name in ("numpy", "pytest", "scikit-learn")}}
    (REPORTS / "tool_versions.txt").write_text(json.dumps(record, indent=2) + "\n")
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--suite", choices=("all", "smoke", "lint", "pe", "array"), default="all")
    args = parser.parse_args()
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(exist_ok=True)
    # Failed assertions are expected in negative tests; don't create large core files.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    verilator = shutil.which(os.environ.get("VERILATOR", "verilator"))
    if not verilator:
        raise SystemExit("Verilator is unavailable. No installation was attempted.")
    summary = {"suite": args.suite, "status": "running", "seed_base": SEED_BASE,
               "started_utc": datetime.now(timezone.utc).isoformat(),
               "tools": record_versions(verilator), "results": {}}
    paths = [*ROOT.glob("rtl/*.sv"), *ROOT.glob("sim/*"), *ROOT.glob("model/*.py"),
             *ROOT.glob("tests/*.py"), *ROOT.glob("scripts/*.py")]
    summary["source_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in paths if p.is_file()}
    try:
        # Staging avoids GNU Make's rejection of spaces in the original project path.
        with tempfile.TemporaryDirectory(prefix="npu1-build-", dir="/private/tmp" if sys.platform == "darwin" else None) as folder:
            temp = Path(folder)
            if " " in str(temp):
                raise RuntimeError("Temporary build directory must not contain spaces")
            if args.suite == "lint":
                sources = ["mac_pe.sv", "skew_feeder.sv", "systolic_array_4x4.sv"]
                for name in sources:
                    shutil.copy2(ROOT / "rtl" / name, temp)
                run([verilator, "--lint-only", "--assert", "-Wall", "-DNPU_SIM_TAGS",
                     "--top-module", "systolic_array_4x4", *sources],
                    temp, "lint.log")
                summary["results"]["lint"] = "pass"
                print("PASS: lint with warnings treated as errors", flush=True)
            if args.suite in ("all", "smoke"):
                summary["results"]["smoke"] = build_smoke(verilator, temp)
            if args.suite in ("all", "pe"):
                summary["results"]["pe"] = check_pe(verilator, temp)
            if args.suite in ("all", "array"):
                summary["results"]["array"] = check_array(verilator, temp)
            if args.suite == "all":
                summary["results"]["python"] = run([sys.executable, "-m", "pytest", "-q", "tests"],
                                                     ROOT, "python_tests.log", timeout=180)
                print(summary["results"]["python"], flush=True)
        summary["status"] = "pass"
    except Exception as exc:
        summary["status"] = "failed"
        summary["error"] = str(exc)
        raise
    finally:
        summary["finished_utc"] = datetime.now(timezone.utc).isoformat()
        destination = REPORTS / f"{args.suite}_verification.json"
        destination.write_text(json.dumps(summary, indent=2) + "\n")
        print(f"Report: {destination}", flush=True)


if __name__ == "__main__":
    main()
