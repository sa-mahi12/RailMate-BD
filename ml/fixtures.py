"""Synthetic demonstration fixtures for the RailMate BD trip ranker (A09, R-12).

ALL ROWS ARE HAND-WRITTEN SYNTHETIC DEMO DATA. They encode an arbitrary,
made-up preference used only to give the tiny ranker a learnable gradient:

    cheaper fare + shorter duration + earlier departure + more seats free
    => labelled MORE relevant (label 1).

They are NOT observed commuter demand, NOT real predictions, and MUST NEVER
be described as demand data or accuracy claims — in comments, metadata, UI
copy, or handoffs. The on-device label for this ranking is
"experimental ranking from demonstration data" (PRODUCT_CONTRACT).

Raw columns (per row):
  fare_bdt       int   50..2000  (demo BDT fare; Trip.fareBdt)
  duration_min   int   30..720   (derived: Trip.arrivalAt - Trip.departureAt)
  departure_hour int   0..23     (derived: Trip.departureAt hour)
  seats_ratio    float 0..1      (remaining / total seats for the trip)
  transfers      int   always 0 in v1 (kept for schema forward-compat)
  label          int   0/1       synthetic relevance judgement (demo fiction)

Normalization (MUST match train_ranker.py + A10 Dart side exactly):
  fare_norm            = clamp((fare - 50) / (2000 - 50), 0, 1)
  duration_norm        = clamp((duration - 30) / (720 - 30), 0, 1)
  departure_hour_norm  = clamp(hour, 0, 23) / 24
  seats_ratio          = clamp(seats, 0, 1)
  transfers_norm       = clamp(transfers, 0, 2) / 2   (always 0.0 in v1)
"""

# (fare_bdt, duration_min, departure_hour, seats_ratio, transfers, label)
FIXTURES = [
    (150, 90, 7, 0.90, 0, 1),    # 0  cheap, short, morning, plenty seats
    (300, 150, 8, 0.70, 0, 1),   # 1  cheap, short, morning
    (220, 120, 9, 0.50, 0, 1),   # 2  cheap, short, morning
    (450, 200, 10, 0.80, 0, 1),  # 3  mid fare, short, morning, free seats
    (120, 240, 6, 0.40, 0, 1),   # 4  cheapest, longer but dawn departure
    (600, 180, 11, 0.60, 0, 1),  # 5  mid fare, short, late morning
    (350, 300, 12, 0.90, 0, 1),  # 6  mid fare, longer, midday, empty coach
    (1500, 400, 22, 0.10, 0, 0),  # 7  expensive, long, night, nearly full
    (1200, 350, 21, 0.20, 0, 0),  # 8  expensive, long, night
    (900, 500, 20, 0.15, 0, 0),   # 9  pricey, longest, evening, nearly full
    (1800, 600, 23, 0.05, 0, 0),  # 10 priciest, longest, latest, fullest
    (800, 250, 19, 0.30, 0, 0),   # 11 mid-high fare, evening, filling up
    (100, 700, 2, 0.05, 0, 0),    # 12 cheapest fare but longest + night + full
    (700, 260, 16, 0.08, 0, 0),   # 13 mid fare, afternoon, nearly full
]

# (better_index, worse_index): trained score(fixtures[a]) MUST exceed
# score(fixtures[b]). Far-apart pairs only, so any converged linear fit
# passes; enforced by train_ranker.py --self-check in hosted CI.
EXPECTED_ORDER_CHECKS = [
    (0, 10),  # cheapest/morning/empty vs priciest/latest/full
    (1, 7),   # cheap morning vs expensive night
    (3, 9),   # mid morning vs pricey evening
    (4, 12),  # cheap dawn vs cheap-but-longest/night/full
    (5, 13),  # mid morning vs mid afternoon-nearly-full
    (6, 8),   # midday empty vs expensive night
]

# Out-of-range raw inputs the Dart side (A10) MUST clamp before scoring.
# (raw_value_dict, expected_normalized_vector_in_FEATURE_ORDER)
NORMALIZATION_CLAMP_CASES = [
    (
        {"fare_bdt": -5, "duration_min": 5,
         "departure_hour": -2, "seats_ratio": -0.5, "transfers": 0},
        [0.0, 0.0, 0.0, 0.0, 0.0],
    ),
    (
        {"fare_bdt": 99999, "duration_min": 9999,
         "departure_hour": 99, "seats_ratio": 7.5, "transfers": 9},
        [1.0, 1.0, 23.0 / 24.0, 1.0, 1.0],
    ),
]
