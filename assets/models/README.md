# assets/models/ — PLACEHOLDER (A09, R-12)

No `ranker.tflite` binary is committed by the worker: the model artifact is
produced ONLY by the hosted `ml-train` GitHub Actions job
(`ml/train_ranker.py` → `ml/convert_to_tflite.py`) and committed by the
coordinator after verifying the SHA-256 in `ml/metadata.json` against
`assets/models/ranker_info.json`.

Expected contents after the hosted run:

- `ranker.tflite` — 5-input → 1-output sigmoid ranker (float32, < 1 KiB),
  trained on SYNTHETIC demonstration data only.
- `ranker_info.json` — integrity sidecar (sha256, TF version, IO spec).

Consumer: packet A10 (Dart/TFLite on-device scoring + `experimental
ranking from demonstration data` label). Asset `pubspec.yaml` wiring is
left to A10/coordinator — this packet does not touch `pubspec.yaml`.
