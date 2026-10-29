"""
Trains 64 -> 32 -> 10 MLP on scikit-learn digits dataset,
calibrates symmetric quantization scales, computes optimal MULT/SHIFT,
evaluates float and integer accuracy on frozen test set,
and exports quantized model JSON and intermediate test fixtures.
"""

import json
import os
import numpy as np
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier

from model.quantize import (
    quantize_tensor_symmetric,
    quantize_bias,
    compute_fixed_point_multiplier,
)
from model.gemm_ref import gemm_reference, signed_round_shift


def train_and_export(output_dir: str = "models/digits"):
    os.makedirs(output_dir, exist_ok=True)
    random_seed = 42

    print("=== Step 1: Loading Dataset & Splitting ===")
    digits = load_digits()
    x_raw = digits.data  # shape (1797, 64), values in [0, 16]
    y_raw = digits.target  # shape (1797,)

    # Normalization rule: pixel / 16.0
    x_norm = x_raw / 16.0

    # Stratified 60% train, 20% val, 20% test
    x_train_val, x_test, y_train_val, y_test = train_test_split(
        x_norm, y_raw, test_size=0.20, random_state=random_seed, stratify=y_raw
    )
    x_train, x_val, y_train, y_val = train_test_split(
        x_train_val, y_train_val, test_size=0.25, random_state=random_seed, stratify=y_train_val
    )

    print(f"Train samples: {len(x_train)}, Val samples: {len(x_val)}, Test samples: {len(x_test)}")

    print("=== Step 2: Training 64 -> 32 -> 10 Float MLP ===")
    mlp = MLPClassifier(
        hidden_layer_sizes=(32,),
        activation='relu',
        solver='adam',
        alpha=1e-4,
        max_iter=300,
        random_state=random_seed,
        learning_rate_init=0.01,
        early_stopping=True,
        n_iter_no_change=15
    )
    mlp.fit(x_train, y_train)

    train_acc = mlp.score(x_train, y_train)
    val_acc = mlp.score(x_val, y_val)
    test_acc_float = mlp.score(x_test, y_test)
    print(f"Float Model Accuracy -> Train: {train_acc*100:.2f}%, Val: {val_acc*100:.2f}%, Test: {test_acc_float*100:.2f}%")
    assert test_acc_float >= 0.95, f"Float test accuracy {test_acc_float*100:.2f}% below 95% target!"

    # Extract weights and biases
    # mlp.coefs_[0]: (64, 32), mlp.intercepts_[0]: (32,)
    # mlp.coefs_[1]: (32, 10), mlp.intercepts_[1]: (10,)
    w1_float = mlp.coefs_[0]
    b1_float = mlp.intercepts_[0]
    w2_float = mlp.coefs_[1]
    b2_float = mlp.intercepts_[1]

    # Verify float inference in NumPy
    def float_infer(x):
        h = np.maximum(0.0, x @ w1_float + b1_float)
        logits = h @ w2_float + b2_float
        return np.argmax(logits, axis=-1)

    np_float_preds = float_infer(x_test)
    np_test_acc = np.mean(np_float_preds == y_test)
    assert np.isclose(np_test_acc, test_acc_float)

    print("=== Step 3: Calibrating Quantization & Scales ===")
    # Input scale from training/calibration set
    q_x_train, s_x = quantize_tensor_symmetric(x_train)
    print(f"Input scale s_x: {s_x:.6f}")

    # Quantize Layer 1 Weights
    q_w1, s_w1 = quantize_tensor_symmetric(w1_float)
    q_b1 = quantize_bias(b1_float, s_x, s_w1)
    print(f"Layer 1 weight scale s_w1: {s_w1:.6f}")

    # Calibrate hidden activation scale s_y on training set
    h_train_float = np.maximum(0.0, x_train @ w1_float + b1_float)
    q_h_train, s_y = quantize_tensor_symmetric(h_train_float)
    print(f"Layer 1 output (hidden) scale s_y: {s_y:.6f}")

    # Compute Requantization Multiplier and Shift for Layer 1 -> Layer 2
    # target_ratio = (s_x * s_w1) / s_y
    target_ratio_1 = (s_x * s_w1) / s_y
    requant_mult_1, requant_shift_1 = compute_fixed_point_multiplier(target_ratio_1)
    approx_ratio_1 = requant_mult_1 / (1 << requant_shift_1)
    print(f"Layer 1 Requant: target={target_ratio_1:.6f}, mult={requant_mult_1}, shift={requant_shift_1}, approx={approx_ratio_1:.6f}")

    # Quantize Layer 2 Weights (acts on INT8 hidden activations with scale s_y)
    q_w2, s_w2 = quantize_tensor_symmetric(w2_float)
    q_b2 = quantize_bias(b2_float, s_y, s_w2)
    print(f"Layer 2 weight scale s_w2: {s_w2:.6f}")

    print("=== Step 4: Full Integer Inference Evaluation on Test Set ===")
    def integer_infer_single(x_single):
        # 1. Quantize input
        q_in, _ = quantize_tensor_symmetric(x_single, scale=s_x)  # shape (64,)
        # 2. Layer 1 GEMM: (1, 64) @ (64, 32) -> (1, 32)
        raw_1 = q_in.astype(np.int64) @ q_w1.astype(np.int64)
        # Add bias
        biased_1 = raw_1 + q_b1.astype(np.int64)
        # Fixed point scaling + symmetric round shift
        z1 = biased_1 * np.int64(requant_mult_1)
        q1 = np.array([signed_round_shift(int(val), requant_shift_1) for val in z1], dtype=np.int64)
        # ReLU and saturate
        relu_1 = np.maximum(0, q1)
        q_hidden = np.clip(relu_1, -127, 127).astype(np.int8)

        # 3. Layer 2 GEMM: (1, 32) @ (32, 10) -> (1, 10)
        raw_2 = q_hidden.astype(np.int64) @ q_w2.astype(np.int64)
        biased_2 = raw_2 + q_b2.astype(np.int64)
        # Final logits remain biased INT32
        logits = biased_2.astype(np.int32)
        pred_class = int(np.argmax(logits))
        return pred_class, q_in, biased_1.astype(np.int32), q_hidden, logits

    int_preds = []
    sample_intermediates = []

    for idx in range(len(x_test)):
        pred, q_in, b1, q_h, logits = integer_infer_single(x_test[idx])
        int_preds.append(pred)
        if idx < 10:
            sample_intermediates.append({
                "sample_idx": idx,
                "label": int(y_test[idx]),
                "pred": pred,
                "input_i8": q_in.tolist(),
                "layer1_biased_i32": b1.tolist(),
                "layer1_hidden_i8": q_h.tolist(),
                "layer2_logits_i32": logits.tolist()
            })

    int_preds = np.array(int_preds)
    test_acc_int = float(np.mean(int_preds == y_test))
    acc_diff_pp = (test_acc_float - test_acc_int) * 100.0

    print(f"Integer Test Accuracy: {test_acc_int*100:.2f}% (Loss vs float: {acc_diff_pp:.2f} percentage points)")
    assert acc_diff_pp <= 2.0, f"Accuracy drop {acc_diff_pp:.2f} pp exceeds 2.0 pp threshold!"

    print("=== Step 5: Exporting Quantized Model and Fixtures ===")
    model_export = {
        "dataset": "sklearn.datasets.load_digits",
        "architecture": "64 -> 32 -> 10 MLP",
        "random_seed": random_seed,
        "metrics": {
            "float_test_acc": float(test_acc_float),
            "int_test_acc": float(test_acc_int),
            "acc_loss_pp": float(acc_diff_pp)
        },
        "scales": {
            "s_x": float(s_x),
            "s_w1": float(s_w1),
            "s_y": float(s_y),
            "s_w2": float(s_w2)
        },
        "layer1": {
            "shape_w": [64, 32],
            "weights_int8": q_w1.tolist(),
            "bias_int32": q_b1.tolist(),
            "requant_mult": int(requant_mult_1),
            "requant_shift": int(requant_shift_1)
        },
        "layer2": {
            "shape_w": [32, 10],
            "weights_int8": q_w2.tolist(),
            "bias_int32": q_b2.tolist()
        }
    }

    model_path = os.path.join(output_dir, "quantized_model.json")
    with open(model_path, "w") as f:
        json.dump(model_export, f, indent=2)
    print(f"Saved model package to {model_path}")

    # Export test dataset vectors
    test_vectors = {
        "num_samples": len(x_test),
        "test_labels": y_test.tolist(),
        "test_inputs_norm": x_test.tolist(),
        "first_10_intermediates": sample_intermediates
    }
    vectors_path = os.path.join(output_dir, "test_vectors.json")
    with open(vectors_path, "w") as f:
        json.dump(test_vectors, f)
    print(f"Saved test vectors to {vectors_path}")


if __name__ == "__main__":
    train_and_export()
