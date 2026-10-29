#!/usr/bin/env python3
"""
NPU-1 End-to-End Digits Inference Driver.
Evaluates the quantized 64->32->10 MLP on test vectors using the pure integer
hardware tile scheduler or direct execution model.
"""

import argparse
import json
import os
import sys
import time
import numpy as np

# Ensure root directory is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from model.inference_ref import IntegerInferenceEngine


def parse_args():
    parser = argparse.ArgumentParser(description="NPU-1 Digits Inference Runner")
    parser.add_argument("--model", type=str, default="models/digits/quantized_model.json",
                        help="Path to quantized model JSON")
    parser.add_argument("--vectors", type=str, default="models/digits/test_vectors.json",
                        help="Path to test vectors JSON")
    parser.add_argument("--batch-size", type=int, default=1, choices=[1, 4],
                        help="Inference batch size (1 or 4)")
    parser.add_argument("--mode", type=str, default="tiled", choices=["tiled", "direct"],
                        help="Execution mode (tiled NPU hardware emulation or direct)")
    parser.add_argument("--limit", type=int, default=None,
                        help="Limit number of test samples (default: all)")
    parser.add_argument("--output", type=str, default=None,
                        help="Path to save evaluation JSON results")
    return parser.parse_args()


def main():
    args = parse_args()

    if not os.path.exists(args.model):
        print(f"ERROR: Model file '{args.model}' not found.")
        sys.exit(1)
    if not os.path.exists(args.vectors):
        print(f"ERROR: Test vectors file '{args.vectors}' not found.")
        sys.exit(1)

    print(f"Loading model from: {args.model}")
    engine = IntegerInferenceEngine(args.model)

    print(f"Loading test vectors from: {args.vectors}")
    with open(args.vectors, "r") as f:
        vec_data = json.load(f)

    test_inputs = np.array(vec_data["test_inputs_norm"], dtype=np.float32)
    test_labels = np.array(vec_data["test_labels"], dtype=np.int32)
    total_samples = len(test_labels) if args.limit is None else min(args.limit, len(test_labels))

    print(f"Running inference on {total_samples} samples (Batch Size = {args.batch_size}, Mode = {args.mode})...")

    correct = 0
    predictions = []
    latencies_us = []
    start_time = time.perf_counter()

    batch_size = args.batch_size
    num_batches = (total_samples + batch_size - 1) // batch_size

    for b in range(num_batches):
        idx_start = b * batch_size
        idx_end = min(idx_start + batch_size, total_samples)
        current_b_size = idx_end - idx_start

        batch_inputs = test_inputs[idx_start:idx_end]
        batch_q = np.array([engine.quantize_input(x) for x in batch_inputs], dtype=np.int8)

        t0 = time.perf_counter()
        if args.mode == "tiled":
            # For tiled hardware emulation
            pred_class, tensors = engine.run_tiled(batch_q)
            # If batch_size > 1, extract argmax across batch
            batch_logits = tensors["logits_i32"]
            batch_preds = [int(p) for p in np.argmax(batch_logits, axis=-1)]
        else:
            batch_preds = []
            for i in range(current_b_size):
                pred, _ = engine.run_direct(batch_q[i:i+1])
                batch_preds.append(pred)
        t1 = time.perf_counter()

        latencies_us.append(((t1 - t0) * 1e6) / current_b_size)
        for i, pred in enumerate(batch_preds):
            predictions.append(pred)
            if pred == test_labels[idx_start + i]:
                correct += 1

    total_wall_time = time.perf_counter() - start_time
    accuracy = correct / total_samples * 100.0

    print("============================================================")
    print("             NPU-1 INFERENCE EVALUATION REPORT              ")
    print("============================================================")
    print(f"  Total Samples Evaluated: {total_samples}")
    print(f"  Batch Size             : {args.batch_size}")
    print(f"  Execution Mode         : {args.mode.upper()}")
    print(f"  Correct Classifications: {correct}")
    print(f"  Integer Test Accuracy  : {accuracy:.2f}% ({correct}/{total_samples})")
    print(f"  Float Baseline Accuracy: {engine.model['metrics']['float_test_acc']*100:.2f}%")
    print(f"  Accuracy Loss          : {engine.model['metrics']['float_test_acc']*100 - accuracy:+.2f} pp")
    print(f"  Total Wall-Clock Time  : {total_wall_time:.3f} s")
    print(f"  Mean Latency / Sample  : {np.mean(latencies_us):.1f} us")
    print(f"  Median Latency / Sample: {np.median(latencies_us):.1f} us")
    print(f"  Throughput             : {total_samples / total_wall_time:.1f} inferences/sec")
    print("============================================================")

    if args.output:
        res_data = {
            "total_samples": total_samples,
            "correct": correct,
            "accuracy_pct": accuracy,
            "mean_latency_us": float(np.mean(latencies_us)),
            "median_latency_us": float(np.median(latencies_us)),
            "throughput_inf_per_s": float(total_samples / total_wall_time),
            "predictions": predictions
        }
        with open(args.output, "w") as f:
            json.dump(res_data, f, indent=2)
        print(f"Saved evaluation results to: {args.output}")

    if accuracy < 95.0:
        print(f"ERROR: Accuracy {accuracy:.2f}% failed to achieve >= 95.0% threshold!")
        sys.exit(1)
    else:
        print("Gate G4/G9 Verification PASSED: Integer accuracy meets target.")
        sys.exit(0)


if __name__ == "__main__":
    main()
