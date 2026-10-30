#!/usr/bin/env python3
"""Single-image inference through the C driver and actual simulated RTL."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import platform
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.inference_ref import IntegerInferenceEngine
from scripts.verify import RTL


def prepare_image(path, foreground="auto"):
    """Keep aspect ratio, pad to square, then reduce to 8x8; no learned preprocessing."""
    with Image.open(path) as source:
        source = ImageOps.exif_transpose(source)
        if source.width * source.height > 20_000_000:
            raise ValueError("Use an image of at most 20 million pixels")
        rgba = source.convert("RGBA")
        bg = "black" if foreground == "light" else "white"
        canvas = Image.new("RGBA", rgba.size, bg)
        gray = Image.alpha_composite(canvas, rgba).convert("L")
    values = np.asarray(gray)
    border = np.concatenate((values[0], values[-1], values[:, 0], values[:, -1]))
    invert = bool(foreground == "dark" or (foreground == "auto" and border.mean() > 127))
    if invert:
        gray = ImageOps.invert(gray)
    side = max(gray.size)
    square = Image.new("L", (side, side), 0)
    square.paste(gray, ((side-gray.width)//2, (side-gray.height)//2))
    small = square.resize((8, 8), Image.Resampling.LANCZOS)
    return np.asarray(small, dtype=np.float64).reshape(64) / 255, invert


def write_request(path, engine, q_input):
    with Path(path).open("wb") as f:
        f.write(struct.pack("<I", 0x4e505532))
        for a, dtype in [(q_input,"i1"),(engine.w1,"i1"),(engine.b1,"<i4")]:
            f.write(np.asarray(a, dtype=dtype).tobytes())
        f.write(struct.pack("<II", engine.requant_mult_1, engine.requant_shift_1))
        for a, dtype in [(engine.w2,"i1"),(engine.b2,"<i4")]:
            f.write(np.asarray(a, dtype=dtype).tobytes())


def build_simulator():
    """Cache only an executable built from these exact sources and tool versions."""
    tool = subprocess.check_output(["verilator", "--version"], text=True).strip()
    compiler = subprocess.check_output(["c++", "--version"], text=True).splitlines()[0]
    sources = [ROOT/"scripts/predict.py"]
    for directory in ("rtl", "sim", "host"):
        sources += sorted(p for p in (ROOT/directory).rglob("*")
                          if p.suffix in (".sv", ".cpp", ".hpp", ".h", ".c"))
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    identity = {"source_sha256": hashes, "verilator": tool, "compiler": compiler,
                "platform": platform.platform()}
    digest = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    cache = ROOT/"artifacts/predict-cache"/digest
    binary = cache/"Vnpu_axil"
    if not binary.exists():
        cache.mkdir(parents=True, exist_ok=True)
        print("Building the RTL simulator (cached for later images)...", flush=True)
        with tempfile.TemporaryDirectory(prefix="npu-predict-", dir="/tmp") as tmp:
            t = Path(tmp)
            for folder in ("rtl", "sim", "host"):
                shutil.copytree(ROOT/folder, t/folder, ignore=shutil.ignore_patterns("*.o", "npu_validate"))
            commands = [
                ["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-Ihost", "-c",
                 "host/npu_runtime.c", "-o", str(t/"runtime.o")],
                ["verilator", "--cc", "--exe", "--build", "--assert", "-Wall", "--top-module",
                 "npu_axil", "-GAXI_ADDR_WIDTH=32", "--Mdir", str(t/"obj"), "-j", "4",
                 "-CFLAGS", "-I"+str(t/"host"), "-LDFLAGS", str(t/"runtime.o")]
                + ["rtl/"+x+".sv" for x in RTL] + [str(t/"sim/predict_sim.cpp")],
            ]
            with (cache/"build.log").open("w") as log:
                for command in commands:
                    subprocess.run(command, cwd=t, stdout=log, stderr=subprocess.STDOUT,
                                   check=True, timeout=240)
            shutil.copy2(t/"obj/Vnpu_axil", binary)
        (cache/"build.json").write_text(json.dumps(identity, indent=2)+"\n")
    return binary, identity, digest


def render_report(report, path):
    """A static data visualization; values always come from the RTL result."""
    image = Image.new("RGB", (1120, 790), "#0b1220")
    d = ImageDraw.Draw(image)
    font = lambda size: ImageFont.load_default(size=size)
    def label(x,y,text,size=18,color="#dce5f5"):
        d.text((x,y), str(text), fill=color, font=font(size))
    label(36,28,"NPU-1 / digit inference",32)
    label(36,76,"Actual SystemVerilog + C driver in Verilator",18,"#93a9c6")
    label(36,132,"INPUT / 8 x 8",19)
    pixels = np.asarray(report["input_normalized"]).reshape(8,8)
    for r in range(8):
        for c in range(8):
            v = int(round(255*float(pixels[r,c])))
            d.rectangle((36+c*29,168+r*29,63+c*29,195+r*29), fill=(v,v,v))
    label(320,132,"RTL PREDICTION",19)
    label(320,168,report["prediction"],96,"#69e3b4")
    expected = report.get("expected_label")
    label(320,280,"Dataset label: "+str(expected) if expected is not None else "Custom image / label unknown")
    label(320,322,"Golden model: bit-exact match",20,"#69e3b4")
    label(320,358,f"Core cycles: {report['core_cycles']:,}   |   Bus cycles: {report['bus_cycles']:,}")
    label(320,390,"Simulation counts, not measured FPGA speed",16,"#93a9c6")
    label(36,454,"HIDDEN ACTIVATIONS / 32 INT8 values after ReLU",19)
    for i,value in enumerate(report["hidden_i8"]):
        x,y=36+(i%16)*65,492+(i//16)*63
        strength=max(0,min(127,value))/127
        color=(int(23+30*strength),int(41+150*strength),int(61+102*strength))
        d.rounded_rectangle((x,y,x+57,y+51),radius=5,fill=color)
        label(x+5,y+4,f"{i:02d}",11,"#b9c6d9")
        label(x+12,y+22,value,19,"#ffffff")
    label(36,638,"OUTPUT LOGITS / signed INT32 scores, not probabilities",19)
    for i,value in enumerate(report["logits_i32"]):
        x=36+i*106
        label(x,677,str(i),20,"#69e3b4" if i==report["prediction"] else "#93a9c6")
        label(x,705,value,15)
    label(36,754,"64 inputs -> 32 hidden neurons -> 10 digits  |  Both layers execute in RTL",15,"#93a9c6")
    image.save(path)


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument("--sample",type=int,help="frozen test index (default: 0)")
    group.add_argument("--image",type=Path,help="centered digit image, PNG/JPEG/etc.")
    parser.add_argument("--foreground",choices=["auto","light","dark"],default="auto")
    parser.add_argument("--out",type=Path,default=ROOT/"artifacts/prediction")
    args=parser.parse_args(argv)
    args.out.mkdir(parents=True,exist_ok=True)
    # A failed invocation must not leave an older success report at this path.
    for name in ("report.json", "report.png", "rtl.json"):
        (args.out/name).unlink(missing_ok=True)
    engine=IntegerInferenceEngine(str(ROOT/"models/digits/quantized_model.json"))
    expected=None;inverted=False
    if args.image:
        x,inverted=prepare_image(args.image,args.foreground)
        source=args.image.name
    else:
        vectors=json.loads((ROOT/"models/digits/test_vectors.json").read_text())
        sample=0 if args.sample is None else args.sample
        if not 0<=sample<len(vectors["test_labels"]):
            parser.error("sample index must be in 0..359")
        x=np.asarray(vectors["test_inputs_norm"][sample],dtype=np.float64)
        expected=int(vectors["test_labels"][sample]);source=f"frozen sample {sample}"
    q=engine.quantize_input(x)
    prediction,reference=engine.run_direct(q)
    binary,identity,digest=build_simulator()
    request=args.out/"request.bin";write_request(request,engine,q)
    result=args.out/"rtl.json"
    result.unlink(missing_ok=True)
    subprocess.run([str(binary),str(request.resolve()),str(result.resolve())],check=True,timeout=60)
    report=json.loads(result.read_text())
    for key in ("hidden_i8","biased_1_i32","logits_i32"):
        if report[key]!=reference[key].reshape(-1).tolist():
            raise RuntimeError(f"RTL/reference mismatch: {key}")
    if report["prediction"]!=prediction:
        raise RuntimeError("RTL/reference prediction mismatch")
    if report["core_cycles"]!=sum(report["layer_core_cycles"]) or report["core_cycles"]<=0:
        raise RuntimeError("invalid cycle counters")
    report.update(source=source,expected_label=expected,input_normalized=x.reshape(-1).tolist(),
                  input_i8=q.reshape(-1).tolist(),polarity_inverted=inverted,bit_exact=True,
                  scope="RTL simulation; no physical FPGA measurement",
                  timestamp_utc=datetime.now(timezone.utc).isoformat(),build_key=digest,
                  model_sha256=hashlib.sha256((ROOT/"models/digits/quantized_model.json").read_bytes()).hexdigest(),
                  **identity)
    (args.out/"report.json").write_text(json.dumps(report,indent=2)+"\n")
    render_report(report,args.out/"report.png")
    print(f"Prediction: {prediction}; reference match: exact; hidden: {report['hidden_i8']}")
    print(f"Core cycles: {report['core_cycles']}; bus cycles: {report['bus_cycles']}")
    print(f"Report: {(args.out/'report.png').resolve()}")
    return 0

if __name__=="__main__":
    try:
        raise SystemExit(main())
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as e:
        print(f"Prediction failed: {e}",file=sys.stderr)
        raise SystemExit(1)
