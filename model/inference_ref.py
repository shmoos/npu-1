"""
Pure Integer Inference Reference Engine for NPU-1.
Performs layer-by-layer execution of the quantized digits MLP.
Supports both direct integer tensor operations and simulated tile-by-tile scheduling.
"""

import json
from typing import Dict, Any, Tuple
import numpy as np
from model.gemm_ref import signed_round_shift, gemm_reference
from model.quantize import quantize_tensor_symmetric
from model.packing import HostTileScheduler


class IntegerInferenceEngine:
    def __init__(self, model_dict_or_path: str | Dict[str, Any]):
        if isinstance(model_dict_or_path, str):
            with open(model_dict_or_path, "r") as f:
                self.model = json.load(f)
        else:
            self.model = model_dict_or_path

        self.s_x = self.model["scales"]["s_x"]
        self.w1 = np.array(self.model["layer1"]["weights_int8"], dtype=np.int8)  # (64, 32)
        self.b1 = np.array(self.model["layer1"]["bias_int32"], dtype=np.int32)   # (32,)
        self.requant_mult_1 = self.model["layer1"]["requant_mult"]
        self.requant_shift_1 = self.model["layer1"]["requant_shift"]

        self.w2 = np.array(self.model["layer2"]["weights_int8"], dtype=np.int8)  # (32, 10)
        self.b2 = np.array(self.model["layer2"]["bias_int32"], dtype=np.int32)   # (10,)

    def quantize_input(self, x_norm: np.ndarray) -> np.ndarray:
        """Quantizes normalized float input in [0.0, 1.0] to INT8 [-127, 127]."""
        q_x, _ = quantize_tensor_symmetric(x_norm, scale=self.s_x)
        return q_x

    def run_direct(self, q_input: np.ndarray) -> Tuple[int, Dict[str, np.ndarray]]:
        """
        Executes inference directly on INT8 input (shape: (1, 64) or (64,)).
        Returns:
          pred_class: int (0..9)
          tensors: dict of intermediate tensors
        """
        if q_input.ndim == 1:
            q_x = q_input.reshape(1, -1)
        else:
            q_x = q_input

        # Layer 1 GEMM: (1, 64) @ (64, 32) -> (1, 32)
        raw_1 = gemm_reference(q_x, self.w1)
        # Biased INT32
        biased_1 = raw_1 + self.b1.reshape(1, -1)
        # Fixed-point Requant + Symmetric Round Shift + ReLU + Saturation
        z1 = biased_1.astype(np.int64) * np.int64(self.requant_mult_1)
        q1 = np.array([[signed_round_shift(int(val), self.requant_shift_1) for val in row] for row in z1], dtype=np.int64)
        relu_1 = np.maximum(0, q1)
        q_hidden = np.clip(relu_1, -127, 127).astype(np.int8)

        # Layer 2 GEMM: (1, 32) @ (32, 10) -> (1, 10)
        raw_2 = gemm_reference(q_hidden, self.w2)
        # Biased INT32 Logits
        biased_2 = raw_2 + self.b2.reshape(1, -1)
        logits = biased_2.astype(np.int32)
        pred_class = int(np.argmax(logits, axis=-1)[0])

        return pred_class, {
            "input_i8": q_x,
            "raw_1_i32": raw_1,
            "biased_1_i32": biased_1,
            "hidden_i8": q_hidden,
            "raw_2_i32": raw_2,
            "logits_i32": logits
        }

    def run_tiled(self, q_input: np.ndarray) -> Tuple[int, Dict[str, np.ndarray]]:
        """
        Executes inference by tiling operations through simulated 4x4 NPU tiles.
        Emulates host scheduler behavior identically to hardware execution.
        """
        if q_input.ndim == 1:
            q_x = q_input.reshape(1, -1)
        else:
            q_x = q_input

        m_samples = q_x.shape[0]

        # --- Layer 1 Tiling: M=m_samples, N=32, K=64 ---
        # 8 tiles along column dimension (32 / 4 = 8)
        layer1_hidden = np.zeros((m_samples, 32), dtype=np.int8)
        layer1_biased = np.zeros((m_samples, 32), dtype=np.int32)

        sched_l1 = HostTileScheduler(m_samples, 32, 64)
        for r_base, c_base, m_val, n_val, a_tile, b_tile in sched_l1.get_tiles(q_x, self.w1):
            bias_col = self.b1[c_base:c_base + n_val]
            # GEMM reduction
            tile_raw = gemm_reference(a_tile, b_tile)
            tile_biased = tile_raw + bias_col.reshape(1, -1)
            layer1_biased[r_base:r_base + m_val, c_base:c_base + n_val] = tile_biased

            # Mode 2 Post-Processing
            z = tile_biased.astype(np.int64) * np.int64(self.requant_mult_1)
            q = np.array([[signed_round_shift(int(val), self.requant_shift_1) for val in row] for row in z], dtype=np.int64)
            y = np.clip(np.maximum(0, q), -127, 127).astype(np.int8)
            layer1_hidden[r_base:r_base + m_val, c_base:c_base + n_val] = y

        # --- Layer 2 Tiling: M=m_samples, N=10, K=32 ---
        # ceil(10/4) = 3 tiles along column dimension (last tile has N_VALID=2)
        layer2_logits = np.zeros((m_samples, 10), dtype=np.int32)

        sched_l2 = HostTileScheduler(m_samples, 10, 32)
        for r_base, c_base, m_val, n_val, a_tile, b_tile in sched_l2.get_tiles(layer1_hidden, self.w2):
            bias_col = self.b2[c_base:c_base + n_val]
            # Mode 1 Post-Processing (Biased INT32 Logits)
            tile_raw = gemm_reference(a_tile, b_tile)
            tile_biased = tile_raw + bias_col.reshape(1, -1)
            layer2_logits[r_base:r_base + m_val, c_base:c_base + n_val] = tile_biased

        pred_class = int(np.argmax(layer2_logits, axis=-1)[0])

        return pred_class, {
            "hidden_i8": layer1_hidden,
            "logits_i32": layer2_logits
        }
