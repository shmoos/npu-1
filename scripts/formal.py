#!/usr/bin/env python3
"""Run small induction proofs and cover witnesses; fail if tools are missing."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]

def main():
    logs=ROOT/"artifacts/formal"
    logs.mkdir(parents=True,exist_ok=True)
    report={"timestamp_utc":datetime.now(timezone.utc).isoformat(),
            "scope":"PE control and AXI adapter only; compute backend abstracted for AXI proof",
            "platform":platform.platform(),"steps":{},"passed":False,
            "source_sha256":{str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest()
                             for folder in ("rtl","formal") for f in sorted((ROOT/folder).glob("*"))
                             if f.is_file()},
            "runner_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
    try:
        for executable,flag in [("sby","--version"),("yosys","-V"),("yices-smt2","--version")]:
            if not shutil.which(executable):
                raise RuntimeError(f"Missing {executable}; install pinned OSS CAD Suite (docs/toolchain.md)")
            report[executable]=subprocess.check_output([executable,flag],text=True).strip()
        with tempfile.TemporaryDirectory(prefix="npu-formal-",dir="/tmp") as tmp:
            for module in ("pe","axil"):
                for task in ("prove","cover"):
                    name=module+"-"+task;work=Path(tmp)/name
                    command=["sby","-f","-d",str(work),module+".sby",task]
                    start=time.monotonic()
                    with (logs/(name+".log")).open("w") as output:
                        p=subprocess.run(command,cwd=ROOT/"formal",stdout=output,
                                         stderr=subprocess.STDOUT,timeout=120)
                    status=(work/"status").read_text().split()[0] if (work/"status").exists() else "MISSING"
                    report["steps"][name]={"exit_code":p.returncode,"status":status,
                                           "seconds":round(time.monotonic()-start,3),"command":command}
                    # Keep cover witnesses and counterexamples for inspection.
                    if (work/"engine_0").exists():
                        shutil.copytree(work/"engine_0",logs/name,dirs_exist_ok=True)
                    print(name,status,flush=True)
                    if p.returncode or status!="PASS":
                        raise RuntimeError(f"{name} failed; see {logs/(name+'.log')}")
        report["passed"]=True
    except (OSError,RuntimeError,subprocess.SubprocessError) as e:
        report["failure"]=str(e);print(e,flush=True)
    finally:
        (ROOT/"reports").mkdir(exist_ok=True)
        (ROOT/"reports/formal.json").write_text(json.dumps(report,indent=2)+"\n")
    return 0 if report["passed"] else 1

if __name__=="__main__":
    raise SystemExit(main())
