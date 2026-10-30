# One image through the accelerator

Run the frozen example first:

```sh
make predict SAMPLE=0
# macOS: view the generated report
open artifacts/prediction/report.png
```

Then supply your own centered, single-digit image:

```sh
make predict IMAGE="/absolute/path/my digit.png"
# Explicit polarity or a separate output directory:
python scripts/predict.py --image "/absolute/path/my digit.png" \
  --foreground dark --out artifacts/my-digit
```

`--foreground auto` examines the border to choose dark-on-light or light-on-dark. The image is converted to grayscale, padded to a square while preserving aspect ratio, then reduced to 8×8 with Lanczos filtering. Transparent backgrounds become white by default, or black with `--foreground light`. No automatic cropping or character segmentation is performed. Center one thick digit and leave a small margin. The model was trained on small grayscale digits; camera photos and very different handwriting may classify poorly even when the hardware arithmetic is exact.

![Example output from the RTL](images/digit-demo.png)

## What actually executes

1. Python prepares 64 pixels and quantizes them using the frozen model's input scale.
2. A small binary request carries only the input, weights, biases and quantization parameters to the simulator. It does **not** carry expected hidden values or logits.
3. The C host driver tiles both dense layers over the AXI interface. The first layer's RTL outputs become the second layer's inputs.
4. The simulator returns biased hidden sums, 32 INT8 activations, ten INT32 logits and cycle counters.
5. Python independently computes the reference and rejects any mismatch before writing the final report.

The PNG shows the prepared input, predicted digit, hidden activations, raw logits and cycle counts. `report.json` also contains all input/intermediate values, source hashes, model hash, tool versions and a timestamp. Logits are scores, not confidence probabilities. The frozen sample's true label is shown when known; custom images have no supplied truth label.

The first invocation builds the simulator. Later images reuse the executable only when source contents, tool versions and platform match. Build logs and identity records are in `artifacts/predict-cache/`. The cache is local and ignored by Git.

## Reading the cycle counts

For the current 64→32→10 model at batch one, the example uses **916 core cycles**, summed across eight first-layer tiles and three second-layer tiles. Bus cycles include simulated host transfers, polling and deterministic AXI stalls, and exclude initial host attachment/reset. These are clock counts inside simulation. They are not wall-clock benchmark results or measured FPGA speed; no clock-frequency or CPU-speedup claim follows from them.

## Reproduce the demo checks

```sh
python scripts/demo_smoke.py
```

This is also part of `make regression`: three frozen sample indices, light/dark PNG image paths with spaces, exact intermediate comparisons, image report decoding, invalid input rejection and removal of stale success reports after failure. Image preprocessing has separate Python unit tests. There is no browser server or cloud dependency.
