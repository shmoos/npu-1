#!/usr/bin/env python3
"""Exercise the public CLI, including disk images, polarity, cache reuse and errors."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def main():
    out=ROOT/"artifacts/demo-smoke";out.mkdir(parents=True,exist_ok=True)
    evidence={"timestamp_utc":datetime.now(timezone.utc).isoformat(),"passed":False,"cases":[]}
    def run(name,args,expected_exit=0):
        folder=out/name
        cmd=[sys.executable,str(ROOT/"scripts/predict.py"),*args,"--out",str(folder)]
        p=subprocess.run(cmd,cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
        (out/(name+".log")).write_text(p.stdout)
        if p.returncode!=expected_exit:
            raise RuntimeError(f"{name}: exit {p.returncode}: {p.stdout[-2000:]}")
        evidence["cases"].append({"name":name,"command":cmd,"exit_code":p.returncode})
        if expected_exit:
            if (folder/"report.json").exists() or (folder/"report.png").exists():
                raise RuntimeError("failure left a stale success report")
            return None
        report=json.loads((folder/"report.json").read_text())
        if not report["bit_exact"] or len(report["hidden_i8"])!=32 or len(report["logits_i32"])!=10:
            raise RuntimeError("incomplete inference report")
        with Image.open(folder/"report.png") as im:
            im.verify()
        evidence["cases"][-1].update(prediction=report["prediction"],core_cycles=report["core_cycles"],
                                      build_key=report["build_key"],bit_exact=report["bit_exact"])
        print(name,"PASS",flush=True)
        return report
    try:
        for index in (0,42,359):run(f"sample-{index}",["--sample",str(index)])
        vectors=json.loads((ROOT/"models/digits/test_vectors.json").read_text())
        pixels=np.rint(np.asarray(vectors["test_inputs_norm"][0]).reshape(8,8)*255).astype(np.uint8)
        light=out/"light digit.png";dark=out/"dark digit.png"
        Image.fromarray(pixels).save(light);Image.fromarray(255-pixels).save(dark)
        a=run("light-image",["--image",str(light)])
        b=run("dark-image",["--image",str(dark)])
        if a["input_i8"]!=b["input_i8"] or a["logits_i32"]!=b["logits_i32"]:
            raise RuntimeError("light/dark image paths disagree")
        bad=out/"bad.png";bad.write_bytes(b"not an image")
        # Reuse an output directory that previously held a successful report.
        run("dark-image",["--image",str(bad)],expected_exit=1)
        run("invalid-sample",["--sample","360"],expected_exit=2)
        evidence["passed"]=True
        print("PASS 3 sample inferences, 2 image inferences, polarity, stale output and invalid input checks")
    except (OSError,RuntimeError,subprocess.SubprocessError) as e:
        evidence["failure"]=str(e);print(e)
    finally:
        evidence["runner_sha256"]=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        (ROOT/"reports").mkdir(exist_ok=True)
        (ROOT/"reports/demo-smoke.json").write_text(json.dumps(evidence,indent=2)+"\n")
    return 0 if evidence["passed"] else 1

if __name__=="__main__":
    raise SystemExit(main())
