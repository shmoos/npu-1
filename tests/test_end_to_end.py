"""
End-to-End Test Suite for NPU-1.
Verifies complete quantized digits classification across all 360 held-out test samples.
Ensures exact bit-for-bit agreement between direct integer model and tiled 4x4 array scheduling.
"""

import json
import os
import numpy as np
import pytest
from model.inference_ref import IntegerInferenceEngine


@pytest.fixture(scope="module")
def model_and_data():
    model_path = "models/digits/quantized_model.json"
    vectors_path = "models/digits/test_vectors.json"
    assert os.path.exists(model_path), "Quantized model not found"
    assert os.path.exists(vectors_path), "Test vectors not found"

    with open(vectors_path, "r") as f:
        vectors = json.load(f)

    engine = IntegerInferenceEngine(model_path)
    return engine, vectors


def test_end_to_end_360_samples_exact_agreement(model_and_data):
    engine, vectors = model_and_data
    inputs_norm = np.array(vectors["test_inputs_norm"], dtype=np.float64)  # (360, 64)
    labels = np.array(vectors["test_labels"], dtype=np.int32)              # (360,)

    direct_preds = []
    tiled_preds = []

    for i in range(len(inputs_norm)):
        q_in = engine.quantize_input(inputs_norm[i])

        # 1. Direct Integer Execution
        pred_direct, tens_direct = engine.run_direct(q_in)
        direct_preds.append(pred_direct)

        # 2. Tiled 4x4 Systolic Array Execution
        pred_tiled, tens_tiled = engine.run_tiled(q_in)
        tiled_preds.append(pred_tiled)

        # Exact bit-for-bit equivalence check
        assert pred_direct == pred_tiled, f"Sample {i}: Pred mismatch! direct={pred_direct}, tiled={pred_tiled}"
        np.testing.assert_array_equal(tens_direct["hidden_i8"], tens_tiled["hidden_i8"])
        np.testing.assert_array_equal(tens_direct["logits_i32"], tens_tiled["logits_i32"])

    direct_preds = np.array(direct_preds)
    tiled_preds = np.array(tiled_preds)

    # Verify accuracy
    accuracy = float(np.mean(direct_preds == labels))
    print(f"End-to-end verified 360 test samples: Accuracy = {accuracy * 100:.2f}%")
    assert accuracy >= 0.95, f"Accuracy {accuracy*100:.2f}% below 95% target"


def test_first_10_golden_intermediates(model_and_data):
    engine, vectors = model_and_data
    inputs_norm = np.array(vectors["test_inputs_norm"], dtype=np.float64)
    fixtures = vectors["first_10_intermediates"]

    for fix in fixtures:
        idx = fix["sample_idx"]
        q_in = engine.quantize_input(inputs_norm[idx])
        pred, tens = engine.run_direct(q_in)

        assert pred == fix["pred"]
        np.testing.assert_array_equal(tens["input_i8"].flatten(), np.array(fix["input_i8"], dtype=np.int8))
        np.testing.assert_array_equal(tens["biased_1_i32"].flatten(), np.array(fix["layer1_biased_i32"], dtype=np.int32))
        np.testing.assert_array_equal(tens["hidden_i8"].flatten(), np.array(fix["layer1_hidden_i8"], dtype=np.int8))
        np.testing.assert_array_equal(tens["logits_i32"].flatten(), np.array(fix["layer2_logits_i32"], dtype=np.int32))


def test_batch_4_inference(model_and_data):
    engine, vectors = model_and_data
    inputs_norm = np.array(vectors["test_inputs_norm"][:4], dtype=np.float64)  # 4 samples
    q_batch = np.array([engine.quantize_input(x) for x in inputs_norm])       # (4, 64)

    # Run batched tile inference
    sched_l1 = engine.run_tiled(q_batch)
    pred_batch = sched_l1[0]
    logits_batch = sched_l1[1]["logits_i32"]

    assert logits_batch.shape == (4, 10)
    for sample_idx in range(4):
        pred_single, tens_single = engine.run_tiled(q_batch[sample_idx])
        np.testing.assert_array_equal(logits_batch[sample_idx], tens_single["logits_i32"].flatten())
