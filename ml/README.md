# ml/ — tiny hosted ranker training (A09, R-12)

Single-layer synthetic trip-search ranker. Hosted training only.

## Files

| File | Purpose |
|---|---|
| `fixtures.py` | 14 hand-written SYNTHETIC demo rows + expected order pairs + clamp cases |
| `train_ranker.py` | stdlib-only trainer → `ranker_weights.json` + `metadata.json` (optional `--emit-tflite PATH`: TF export if importable, else `TFLITE_MANIFEST.txt` note, never crashes) |
| `metadata.json` | PLACEHOLDER (SHA `PENDING_HOSTED_CI_RUN`); overwritten by the hosted train run |
| `convert_to_tflite.py` | CI-only converter (needs `tensorflow-cpu`) → `assets/models/ranker.tflite` + `ranker_info.json` |

## What runs where (binding)

1. **Hosted CI (`ml-train` workflow, ubuntu-latest)** — coordinator runs:
   `python ml/train_ranker.py --self-check` (stock runner, no extra deps),
   then `pip install tensorflow-cpu` + `python ml/convert_to_tflite.py`.
   Artifacts uploaded; coordinator commits `.tflite` + JSON after SHA check.
2. **Worker machines** — NEVER train/convert locally (packet stop-condition).
   Only `python -m py_compile` syntax checks are permitted.

## Model

`score = sigmoid(w·x + b)`, 5 normalized inputs in fixed `FEATURE_ORDER`
(`fare_norm`, `duration_norm`, `departure_hour_norm`, `seats_ratio`,
`transfers_norm`; transfers always 0 in v1). Constants in `metadata.json`.

## Honesty rules

SYNTHETIC demo data only — never claim observed commuter demand or real
accuracy. On-device UI label: `experimental ranking from demonstration
data`. A plain deterministic sort fallback is explicitly non-ML (A10).
