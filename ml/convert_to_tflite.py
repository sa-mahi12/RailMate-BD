#!/usr/bin/env python3
"""Convert trained ranker weights to TFLite — HOSTED CI ONLY (A09, R-12).

RUNS WHERE: the `ml-train` GitHub Actions job on ubuntu-latest AFTER
  ml/train_ranker.py. Installs `tensorflow-cpu` via pip in the runner
  (stock runners have no TF preinstalled). NEVER run locally: TF install +
  conversion is a heavy op reserved for the coordinator under the shared
  heavy lock (packet stop-condition).

READS:  ml/ranker_weights.json  (written by train_ranker.py in the same job)
WRITES: assets/models/ranker.tflite      (the ONLY binary model artifact)
        assets/models/ranker_info.json   (sha256 + tf version + io spec,
                                          for the A10 Dart-side integrity
                                          check before bundling/loading)

MODEL MAPPING: one Dense(1, activation="sigmoid") layer, input dim 5 in the
  FEATURE_ORDER of ranker_weights.json. Kernel shape (5, 1) = weights column
  vector; bias shape (1,). Float32, no quantization (5-param model is
  already < 1 KiB; quantization would add risk for zero size benefit).

HONESTY: converts SYNTHETIC demo weights. Output filename/info must keep
  the "demonstration data" provenance; no demand/accuracy claims.
"""

import hashlib
import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)

try:
    import tensorflow as tf
except ImportError:
    print(
        "ERROR: tensorflow is not installed. This converter runs ONLY in "
        "hosted CI (pip install tensorflow-cpu in the ml-train job). "
        "Refusing to run elsewhere.",
        file=sys.stderr,
    )
    sys.exit(2)


def sha256_file(path):
    """SHA-256 hex of a file (integrity value recorded in the sidecar)."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    """Load weights JSON, build 5->1 sigmoid layer, export .tflite."""
    weights_path = os.path.join(SCRIPT_DIR, "ranker_weights.json")
    with open(weights_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)

    feature_order = payload["feature_order"]
    weights = payload["weights"]
    bias = payload["bias"]
    assert len(feature_order) == 5 and len(weights) == 5, (
        "expected 5 features/weights, got %d/%d"
        % (len(feature_order), len(weights))
    )

    model = tf.keras.Sequential(
        [
            tf.keras.layers.Dense(
                1,
                activation="sigmoid",
                input_shape=(5,),
                name="rank",
            )
        ]
    )
    kernel = [[w] for w in weights]  # Dense kernel shape is (5, 1).
    model.layers[0].set_weights(
        [
            tf.constant(kernel, dtype=tf.float32).numpy(),
            tf.constant([bias], dtype=tf.float32).numpy(),
        ]
    )

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_bytes = converter.convert()

    out_dir = os.path.join(REPO_ROOT, "assets", "models")
    os.makedirs(out_dir, exist_ok=True)
    tflite_path = os.path.join(out_dir, "ranker.tflite")
    with open(tflite_path, "wb") as handle:
        handle.write(tflite_bytes)

    info = {
        "model_version": payload.get("model_version", "unknown"),
        "feature_order": feature_order,
        "input": "float32[1,5] in feature_order with ranker_weights.json "
        "normalization (clamped)",
        "output": "float32[1,1] relevance score in (0,1)",
        "tensorflow_version": tf.__version__,
        "converted_by": "ml/convert_to_tflite.py in hosted GitHub Actions",
        "provenance": "SYNTHETIC DEMO weights; experimental ranking from "
        "demonstration data only",
        "tflite_bytes": len(tflite_bytes),
        "tflite_sha256": sha256_file(tflite_path),
    }
    info_path = os.path.join(out_dir, "ranker_info.json")
    with open(info_path, "w", encoding="utf-8") as handle:
        json.dump(info, handle, indent=2)
        handle.write("\n")

    print("tensorflow=%s" % tf.__version__)
    print("wrote %s (%d bytes)" % (tflite_path, len(tflite_bytes)))
    print("sha256=%s" % info["tflite_sha256"])
    print("wrote %s" % info_path)


if __name__ == "__main__":
    main()
