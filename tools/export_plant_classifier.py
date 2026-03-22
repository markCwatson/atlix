"""
Export a trained plant classifier from PyTorch to TFLite float16.

Loads the checkpoint from train_plant_classifier.py and converts:
  PyTorch (.pt) → ONNX (TorchScript) → TF SavedModel (onnx2tf) → TFLite float16

Outputs:
  assets/models/plant_classifier_float16.tflite

Usage:
  python tools/export_plant_classifier.py [--checkpoint tools/plant_classifier_best.pt]

NOTE: Requires Python 3.12 (not 3.13) for onnx2tf/tensorflow compatibility.
      Use tools/.export_venv if available:
        tools/.export_venv/bin/python tools/export_plant_classifier.py

Requires: pip install torch timm onnx onnx2tf tensorflow
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn


def build_model(num_classes):
    """Recreate the model architecture (must match training)."""
    try:
        import timm
    except ImportError:
        os.system(f"{sys.executable} -m pip install timm")
        import timm

    model = timm.create_model("efficientnet_lite0", pretrained=False)
    in_features = model.classifier.in_features
    model.classifier = nn.Linear(in_features, num_classes)
    return model


def main():
    parser = argparse.ArgumentParser(description="Export plant classifier to TFLite")
    parser.add_argument(
        "--checkpoint",
        type=str,
        default=str(Path(__file__).parent / "plant_classifier_best.pt"),
        help="Path to trained .pt checkpoint",
    )
    args = parser.parse_args()

    assets_dir = Path(__file__).parent.parent / "assets" / "models"
    assets_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = Path(__file__).parent / "plant_classifier.onnx"
    saved_model_dir = Path(__file__).parent / "plant_classifier_saved_model"
    tflite_dest = assets_dir / "plant_classifier_float16.tflite"

    # Load checkpoint
    print(f"Loading checkpoint: {args.checkpoint}")
    checkpoint = torch.load(args.checkpoint, map_location="cpu", weights_only=False)
    num_classes = checkpoint["num_classes"]
    print(f"Classes: {num_classes}, val_acc: {checkpoint.get('val_acc', 'N/A')}")

    # Rebuild model and load weights
    model = build_model(num_classes)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    # ── Step 1: PyTorch → ONNX ──────────────────────────────────────────
    print("\nStep 1: PyTorch → ONNX (TorchScript exporter)...")
    dummy_input = torch.randn(1, 3, 224, 224)

    # Use legacy TorchScript exporter — the new dynamo exporter produces
    # ONNX ops that onnx2tf cannot reshape correctly.
    traced = torch.jit.trace(model, dummy_input)
    torch.onnx.export(
        traced,
        dummy_input,
        str(onnx_path),
        input_names=["input"],
        output_names=["output"],
        dynamic_axes=None,
        opset_version=13,
        dynamo=False,
    )
    print(
        f"  ONNX saved: {onnx_path} ({onnx_path.stat().st_size / 1024 / 1024:.1f} MB)"
    )

    # ── Step 2: ONNX → TF SavedModel via onnx2tf ────────────────────────
    print("\nStep 2: ONNX → TF SavedModel via onnx2tf...")
    import onnx2tf

    onnx2tf.convert(
        input_onnx_file_path=str(onnx_path),
        output_folder_path=str(saved_model_dir),
        copy_onnx_input_output_names_to_tflite=True,
        non_verbose=True,
    )
    print(f"  SavedModel saved: {saved_model_dir}")

    # ── Step 3: TF SavedModel → TFLite float16 ──────────────────────────
    # onnx2tf produces a SavedModel but not a .tflite directly for this
    # architecture. Convert manually with float16 quantisation.
    print("\nStep 3: SavedModel → TFLite (float16)...")
    import tensorflow as tf

    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    with open(tflite_dest, "wb") as f:
        f.write(tflite_model)
    print(
        f"  TFLite saved: {tflite_dest} ({tflite_dest.stat().st_size / 1024 / 1024:.1f} MB)"
    )

    # ── Cleanup ──────────────────────────────────────────────────────────
    onnx_path.unlink(missing_ok=True)
    if saved_model_dir.exists():
        shutil.rmtree(saved_model_dir, ignore_errors=True)

    # ── Verify ───────────────────────────────────────────────────────────
    print("\nVerifying TFLite model...")
    interpreter = tf.lite.Interpreter(model_path=str(tflite_dest))
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    print(f"  Input:  {input_details[0]['shape']} {input_details[0]['dtype']}")
    print(f"  Output: {output_details[0]['shape']} {output_details[0]['dtype']}")

    dummy = np.random.randn(*input_details[0]["shape"]).astype(np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    out = interpreter.get_tensor(output_details[0]["index"])
    print(f"  Test inference: output shape {out.shape}, sum={out.sum():.4f}")

    print(f"\n{'=' * 60}")
    print("Export complete!")
    print(f"  Model: {tflite_dest}")
    print(f"  Size:  {tflite_dest.stat().st_size / 1024 / 1024:.1f} MB")
    print(f"  Input: {input_details[0]['shape']} float32 (NHWC, ImageNet normalised)")
    print(f"  Output: [1, {num_classes}] logits")


if __name__ == "__main__":
    main()
