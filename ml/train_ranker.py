#!/usr/bin/env python3
"""Train the RailMate BD single-layer synthetic trip ranker (A09, R-12).

WHAT: single dense layer, 5 normalized inputs -> 1 sigmoid output:
        score = sigmoid(w . x + b)
      trained with full-batch gradient descent (logistic regression) on the
      SYNTHETIC demo fixtures in ml/fixtures.py. Deterministic: zero init,
      no RNG, fixed hyper-parameters -> identical weights on every run.

RUNS WHERE: hosted GitHub Actions (ubuntu-latest) via the `ml-train`
  workflow proposed in handoff A09. BINDING STOP-CONDITION: do NOT run
  training locally as a heavy op; the only permitted local command is a
  syntax check (`python -m py_compile ml/train_ranker.py ml/fixtures.py`).
  The coordinator executes this script in cloud CI and commits artifacts.

DEPENDS ON: Python 3 stdlib ONLY (argparse, hashlib, json, math, os, sys)
  plus ml/fixtures.py in the same directory. No numpy / tensorflow needed,
  so it runs on stock ubuntu-latest runners.

READS:  ml/fixtures.py (this directory)
WRITES: ml/ranker_weights.json  (feature order, weights, bias, normalization)
        ml/metadata.json        (architecture, normalization, hyper-params,
                                 fixtures SHA-256, weights SHA-256, final
                                 loss/accuracy, synthetic/demo provenance)
        optionally: a .tflite at --emit-tflite PATH, else a TFLITE_MANIFEST
        note (see OPTIONAL CONVERTER SECTION below; never crashes).

HONESTY: fixtures are hand-written synthetic demo rows, NOT observed
  commuter demand. Nothing here measures real prediction accuracy. The
  transfers_norm weight stays exactly 0.0 because transfers are always 0
  in v1 (zero feature => zero gradient); the input slot is kept so A10/the
  .tflite schema can carry transfers later without reordering features.
"""

import argparse
import hashlib
import json
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

import fixtures  # noqa: E402  (ml/fixtures.py — synthetic demo rows, same dir)

FEATURE_ORDER = [
    "fare_norm",
    "duration_norm",
    "departure_hour_norm",
    "seats_ratio",
    "transfers_norm",
]

# Normalization constants shared with metadata + A10 Dart side. DO NOT
# change without bumping MODEL_VERSION and retraining in hosted CI.
NORM = {
    "fare_min_bdt": 50,
    "fare_max_bdt": 2000,
    "duration_min_minutes": 30,
    "duration_max_minutes": 720,
    "departure_hour_min": 0,
    "departure_hour_max": 23,
    "seats_ratio_min": 0.0,
    "seats_ratio_max": 1.0,
    "transfers_min": 0,
    "transfers_max": 2,
}

MODEL_VERSION = "a09-v1"
DEFAULT_EPOCHS = 2000
DEFAULT_LR = 0.5


def clamp(value, low, high):
    """Clamp value into [low, high]; NaN-safe (non-numbers become low)."""
    try:
        number = float(value)
    except (TypeError, ValueError):
        return float(low)
    if math.isnan(number):
        return float(low)
    if number < low:
        return float(low)
    if number > high:
        return float(high)
    return number


def normalize(raw):
    """Map one raw fixture row to the 5-vector in FEATURE_ORDER."""
    fare = clamp(
        (raw["fare_bdt"] - NORM["fare_min_bdt"])
        / (NORM["fare_max_bdt"] - NORM["fare_min_bdt"]),
        0.0,
        1.0,
    )
    duration = clamp(
        (raw["duration_min"] - NORM["duration_min_minutes"])
        / (NORM["duration_max_minutes"] - NORM["duration_min_minutes"]),
        0.0,
        1.0,
    )
    hour = (
        clamp(
            raw["departure_hour"],
            NORM["departure_hour_min"],
            NORM["departure_hour_max"],
        )
        / 24.0
    )
    seats = clamp(
        raw["seats_ratio"], NORM["seats_ratio_min"], NORM["seats_ratio_max"]
    )
    transfers = clamp(
        raw["transfers"], NORM["transfers_min"], NORM["transfers_max"]
    ) / float(NORM["transfers_max"])
    return [fare, duration, hour, seats, transfers]


def sigmoid(z):
    """Numerically guarded logistic function (stdlib only)."""
    if z >= 0:
        return 1.0 / (1.0 + math.exp(-z))
    tail = math.exp(z)
    return tail / (1.0 + tail)


def train(rows, epochs, lr):
    """Full-batch gradient descent on binary cross-entropy. Deterministic."""
    weights = [0.0] * len(FEATURE_ORDER)
    bias = 0.0
    loss = float("inf")
    for _ in range(epochs):
        grad_w = [0.0] * len(FEATURE_ORDER)
        grad_b = 0.0
        loss = 0.0
        for x, y in rows:
            pred = sigmoid(sum(w * v for w, v in zip(weights, x)) + bias)
            pred = min(max(pred, 1e-12), 1.0 - 1e-12)
            loss += -(y * math.log(pred) + (1.0 - y) * math.log(1.0 - pred))
            err = pred - y
            for i, v in enumerate(x):
                grad_w[i] += err * v
            grad_b += err
        count = float(len(rows))
        loss /= count
        for i in range(len(weights)):
            weights[i] -= lr * grad_w[i] / count
        bias -= lr * grad_b / count
    return weights, bias, loss


def score(weights, bias, x):
    """Ranker inference: identical math the Dart/TFLite side must reproduce."""
    return sigmoid(sum(w * v for w, v in zip(weights, x)) + bias)


def sha256_file(path):
    """SHA-256 hex of a file (used for fixtures + weights provenance)."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


# ---------------------------------------------------------------------------
# OPTIONAL TFLITE CONVERTER SECTION (clearly marked; default OFF).
#
# Hosted-CI convenience only: when --emit-tflite PATH is passed, this tries
# `import tensorflow` and exports the just-trained 5->1 sigmoid layer to
# PATH. If tensorflow is NOT importable (stock ubuntu-latest runners,
# worker machines), it writes a TFLITE_MANIFEST.txt note next to the
# weights JSON and returns normally — it NEVER raises/crashes, and the
# weights JSON + metadata.json are always written regardless. Canonical CI
# conversion path remains ml/convert_to_tflite.py (which hard-requires
# tensorflow-cpu and records the integrity sidecar). SYNTHETIC demo
# weights only; no demand/accuracy claims.
# ---------------------------------------------------------------------------
def maybe_emit_tflite(weights, bias, out_dir, tflite_path):
    """Try a TF export; fall back to a MANIFEST note. Never raises."""
    manifest_path = os.path.join(out_dir, "TFLITE_MANIFEST.txt")
    try:
        import tensorflow as tf  # pylint: disable=import-outside-toplevel
    except ImportError:
        with open(manifest_path, "w", encoding="utf-8") as handle:
            handle.write(
                "TFLITE NOT EMITTED (synthetic demo ranker).\n"
                "tensorflow is not importable in this environment, so no "
                ".tflite was written. Weights JSON + metadata.json ARE "
                "complete. To produce assets/models/ranker.tflite, run "
                "ml/convert_to_tflite.py in hosted GitHub Actions "
                "(pip install tensorflow-cpu in the ml-train job).\n"
            )
        print("tensorflow unavailable; wrote %s" % manifest_path)
        return "manifest"
    try:
        model = tf.keras.Sequential(
            [
                tf.keras.layers.Dense(
                    1, activation="sigmoid", input_shape=(5,), name="rank"
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
        tflite_bytes = tf.lite.TFLiteConverter.from_keras_model(
            model
        ).convert()
        with open(tflite_path, "wb") as handle:
            handle.write(tflite_bytes)
        digest = hashlib.sha256(tflite_bytes).hexdigest()
        print("wrote %s (%d bytes)" % (tflite_path, len(tflite_bytes)))
        print("sha256=%s" % digest)
        return "tflite"
    except Exception as exc:  # never crash the training step
        with open(manifest_path, "w", encoding="utf-8") as handle:
            handle.write(
                "TFLITE NOT EMITTED (synthetic demo ranker).\n"
                "tensorflow conversion failed (%s: %s); no .tflite was "
                "written. Weights JSON + metadata.json ARE complete. "
                "Retry ml/convert_to_tflite.py in hosted GitHub Actions.\n"
                % (type(exc).__name__, exc)
            )
        print("tflite conversion failed; wrote %s" % manifest_path)
        return "manifest"


def self_check(weights, bias):
    """Smoke assertions over synthetic fixtures; raises on failure.

    Only far-apart EXPECTED_ORDER_CHECKS pairs plus generic monotonicity
    probes (raising fare / emptying seats must lower the same trip's
    score). Synthetic-data checks only — NOT a claim about real demand.
    """
    vectors = []
    for row in fixtures.FIXTURES:
        raw = {
            "fare_bdt": row[0],
            "duration_min": row[1],
            "departure_hour": row[2],
            "seats_ratio": row[3],
            "transfers": row[4],
        }
        vectors.append(normalize(raw))
    scores = [score(weights, bias, v) for v in vectors]
    for better, worse in fixtures.EXPECTED_ORDER_CHECKS:
        if not scores[better] > scores[worse]:
            raise AssertionError(
                "ORDER CHECK FAILED (synthetic): fixture %d (%.4f) must "
                "outscore fixture %d (%.4f)"
                % (better, scores[better], worse, scores[worse])
            )
    # Monotonicity probes on fixture 0 (cheap/morning/empty baseline).
    base = dict(
        zip(
            ("fare_bdt", "duration_min", "departure_hour",
             "seats_ratio", "transfers"),
            fixtures.FIXTURES[0][:5],
        )
    )
    base_score = score(weights, bias, normalize(base))
    pricey = dict(base)
    pricey["fare_bdt"] = NORM["fare_max_bdt"]
    if not score(weights, bias, normalize(pricey)) < base_score:
        raise AssertionError(
            "MONOTONICITY FAILED (synthetic): max fare must lower the score"
        )
    full = dict(base)
    full["seats_ratio"] = 0.0
    if not score(weights, bias, normalize(full)) < base_score:
        raise AssertionError(
            "MONOTONICITY FAILED (synthetic): zero seats must lower the score"
        )
    accuracy = sum(
        1
        for (row, s) in zip(fixtures.FIXTURES, scores)
        if (s >= 0.5) == bool(row[5])
    ) / float(len(scores))
    return scores, accuracy


def main(argv=None):
    """CLI entry point; returns process exit code (0 = ok)."""
    parser = argparse.ArgumentParser(
        description="Train single-layer synthetic trip ranker (stdlib only)."
    )
    parser.add_argument("--epochs", type=int, default=DEFAULT_EPOCHS)
    parser.add_argument("--lr", type=float, default=DEFAULT_LR)
    parser.add_argument(
        "--self-check",
        action="store_true",
        default=True,
        help="run synthetic order/monotonicity assertions (default: on)",
    )
    parser.add_argument(
        "--no-self-check",
        dest="self_check",
        action="store_false",
        help="skip assertions (NOT recommended for CI)",
    )
    parser.add_argument(
        "--out-dir",
        default=SCRIPT_DIR,
        help="output directory for weights/metadata JSON (default: ml/)",
    )
    parser.add_argument(
        "--emit-tflite",
        default=None,
        metavar="PATH",
        help="OPTIONAL converter (default off): also emit a .tflite to "
        "PATH via tensorflow if importable; otherwise writes a "
        "TFLITE_MANIFEST.txt note and still exits 0 (never crashes).",
    )
    args = parser.parse_args(argv)

    rows = []
    for row in fixtures.FIXTURES:
        raw = {
            "fare_bdt": row[0],
            "duration_min": row[1],
            "departure_hour": row[2],
            "seats_ratio": row[3],
            "transfers": row[4],
        }
        rows.append((normalize(raw), float(row[5])))

    weights, bias, loss = train(rows, args.epochs, args.lr)

    accuracy = None
    if args.self_check:
        _, accuracy = self_check(weights, bias)
        if loss > 0.5:
            raise AssertionError(
                "LOSS TOO HIGH (synthetic): %.4f > 0.5" % loss
            )

    weights_payload = {
        "model_version": MODEL_VERSION,
        "feature_order": FEATURE_ORDER,
        "weights": weights,
        "bias": bias,
        "normalization": NORM,
        "note": "SYNTHETIC DEMO weights. Experimental ranking from "
        "demonstration data only; NOT trained on observed commuter demand.",
    }
    weights_path = os.path.join(args.out_dir, "ranker_weights.json")
    with open(weights_path, "w", encoding="utf-8") as handle:
        json.dump(weights_payload, handle, indent=2)
        handle.write("\n")

    fixtures_path = os.path.join(SCRIPT_DIR, "fixtures.py")
    metadata = {
        "model_version": MODEL_VERSION,
        "architecture": "single dense layer 5->1 with sigmoid "
        "(logistic regression); score = sigmoid(w.x + b)",
        "feature_order": FEATURE_ORDER,
        "normalization": NORM,
        "hyperparameters": {
            "epochs": args.epochs,
            "learning_rate": args.lr,
            "init": "zeros",
            "optimizer": "full-batch gradient descent",
            "loss": "binary cross-entropy",
            "dependencies": "python3 stdlib only (no numpy/tensorflow)",
        },
        "fixtures": {
            "source": "ml/fixtures.py",
            "rows": len(fixtures.FIXTURES),
            "sha256": sha256_file(fixtures_path),
            "provenance": "SYNTHETIC hand-written demo rows; NOT observed "
            "commuter demand; NO real prediction-accuracy claim.",
        },
        "training": {
            "final_loss_bce": loss,
            "train_accuracy_synthetic": accuracy,
            "runs_where": "hosted GitHub Actions (ubuntu-latest), "
            "workflow ml-train; never heavy local training",
        },
        "weights_file": "ml/ranker_weights.json",
        "weights_sha256": sha256_file(weights_path),
        "tflite": "assets/models/ranker.tflite — produced ONLY by "
        "ml/convert_to_tflite.py in hosted CI (tensorflow-cpu); "
        "committed after SHA integrity check; integrity sidecar "
        "assets/models/ranker_info.json",
    }
    metadata_path = os.path.join(args.out_dir, "metadata.json")
    with open(metadata_path, "w", encoding="utf-8") as handle:
        json.dump(metadata, handle, indent=2)
        handle.write("\n")

    print("epochs=%d lr=%s loss=%.6f accuracy=%s" % (
        args.epochs, args.lr, loss,
        ("%.4f" % accuracy) if accuracy is not None else "n/a",
    ))
    print("weights=%s" % (["%.6f" % w for w in weights],))
    print("bias=%.6f" % bias)
    print("wrote %s" % weights_path)
    print("wrote %s" % metadata_path)
    if args.emit_tflite:
        maybe_emit_tflite(weights, bias, args.out_dir, args.emit_tflite)
    return 0


if __name__ == "__main__":
    sys.exit(main())
