#!/usr/bin/env python3
"""Build the RailMate official timetable dataset.

Input  : tools/official_timetable/transcribed_rows.json (row-by-row transcription
         of the published Bangladesh Railway timetable PDFs)
Output : assets/data/official-timetable.json   (bundled Flutter fallback)
         site/data/official-timetable.json     (GitHub Pages read-only copy)
         site/data/source-manifest.json        (provenance + hashes + coverage)

The script never invents data. It validates the transcription, derives only
facts that follow arithmetically from published times (an arrival at or before
the departure time is on the following day), and writes the same bytes twice so
the app and the public site cannot drift apart.

Run:  python tools/build_official_timetable.py
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROWS_PATH = ROOT / "tools" / "official_timetable" / "transcribed_rows.json"
APP_OUT = ROOT / "assets" / "data" / "official-timetable.json"
SITE_OUT = ROOT / "site" / "data" / "official-timetable.json"
MANIFEST_OUT = ROOT / "site" / "data" / "source-manifest.json"

TIMETABLE_NUMBER = "54"
EFFECTIVE_FROM = "2025-03-10"
RETRIEVED = "2026-11-25"
LAST_VERIFIED = "2026-11-25"
DATASET_ID = "bd-railway-timetable-54-intercity-2025-03-10"

SOURCE_INDEX = "https://railway.gov.bd/pages/static-pages/691997d5933eb65569ddf8e2"

DOCUMENTS = {
    "eastern": {
        "zone_label": "Eastern Zone (পূর্বাঞ্চল)",
        "page_url": "https://railway.gov.bd/pages/static-pages/691997bf933eb65569ddec51",
        "pdf_url": (
            "https://objectstorage.ap-dcc-gazipur-1.oraclecloud15.com/n/axvjbnqprylg/"
            "b/V2Ministry/o/office-railway/2024/12/"
            "667d364484f84ac7b06d7e8e8804b2c9.pdf"
        ),
        "pages": 8,
        "rendering": "scanned pages, no text layer; rows transcribed from the scan",
        "sha256": "d6e1af80252d98b45e8a07e7c30be1ec51f94ddf4b3c942daf4cc3a697137cc9",
        "bytes": 4753066,
    },
    "western": {
        "zone_label": "Western Zone (পশ্চিমাঞ্চল)",
        "page_url": "https://railway.gov.bd/pages/static-pages/691997b8933eb65569dde71d",
        "pdf_url": (
            "https://objectstorage.ap-dcc-gazipur-1.oraclecloud15.com/n/axvjbnqprylg/"
            "b/V2Ministry/o/office-railway/2024/12/"
            "59b5aa56840546f1a05b0741b8cca044.pdf"
        ),
        "pages": 15,
        "rendering": (
            "text layer uses a legacy Bangla font encoding that extracts as mojibake; "
            "rows transcribed from the rendered page image"
        ),
        "sha256": "bc40965826c3f597469d1ddff402b5d78bd340ac3512c22aab944ec28d2de533",
        "bytes": 1817407,
    },
}

OFF_DAYS = {
    "saturday",
    "sunday",
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
}

ZONE_PREFIX = {"eastern": "e", "western": "w"}

# Coverage statement: what this dataset contains, and what the source publishes
# that has NOT been imported yet. Counts are printed by the source tables.
NOT_IMPORTED = [
    {
        "zone": "eastern",
        "section": "কমিউটার ও মেইল ট্রেনের তালিকা (পূর্বাঞ্চল)",
        "pages": "3-8",
        "reason": (
            "the mail/express and commuter summary tables continue for six more "
            "scanned pages and have not been transcribed yet; they are not guessed"
        ),
        "approx_rows_visible_on_page_3": 45,
    },
    {
        "zone": "western",
        "section": "কমিউটার ও মেইল ট্রেনের তালিকা (পশ্চিমাঞ্চল)",
        "pages": "2-15",
        "reason": (
            "the mail/express and commuter summary tables continue for fourteen more "
            "pages and have not been transcribed yet; they are not guessed"
        ),
        "approx_rows_visible_on_page_2": 39,
    },
]


class DatasetError(RuntimeError):
    pass


def fail(msg: str) -> None:
    raise DatasetError(msg)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalise_time(raw: str, where: str) -> str:
    if not isinstance(raw, str) or len(raw) != 5 or raw[2] != ":":
        fail(f"{where}: time {raw!r} is not HH:MM")
    hours, minutes = raw.split(":")
    if not (hours.isdigit() and minutes.isdigit()):
        fail(f"{where}: time {raw!r} is not numeric")
    h, m = int(hours), int(minutes)
    if not (0 <= h <= 23 and 0 <= m <= 59):
        fail(f"{where}: time {raw!r} out of range")
    return f"{h:02d}:{m:02d}"


def build() -> int:
    payload = json.loads(ROWS_PATH.read_text(encoding="utf-8"))
    stations_raw: dict[str, dict] = payload["stations"]
    rows: list[list] = payload["rows"]
    excluded: list[dict] = payload.get("excluded_rows", [])

    seen_ids: set[str] = set()
    trains: list[dict] = []
    seen_serials: dict[tuple[str, str], set[int]] = {}
    used_stations: set[str] = set()

    for index, row in enumerate(rows):
        if len(row) != 12:
            fail(f"row {index}: expected 12 columns, got {len(row)}")
        (
            zone,
            service_class,
            serial,
            number,
            name_bn,
            name_en,
            off_day,
            from_code,
            departure,
            to_code,
            arrival,
            page,
        ) = row

        where = f"{zone} page {page} serial {serial} ({number})"
        if zone not in DOCUMENTS:
            fail(f"{where}: unknown zone {zone!r}")
        if not isinstance(number, str) or not number.replace("/", "").isdigit():
            fail(f"{where}: train number {number!r} is not numeric")
        if not isinstance(serial, int) or serial <= 0:
            fail(f"{where}: serial must be a positive integer")
        if from_code == to_code:
            fail(f"{where}: origin and destination are the same station")
        for code in (from_code, to_code):
            if code not in stations_raw:
                fail(f"{where}: station code {code!r} is not declared")
            used_stations.add(code)
        if off_day is not None and off_day not in OFF_DAYS:
            fail(f"{where}: off day {off_day!r} is not a weekday name")
        if not isinstance(page, int) or page <= 0:
            fail(f"{where}: page must be a positive integer")

        dep = normalise_time(departure, where)
        arr = normalise_time(arrival, where)
        if service_class == "intercity_phased":
            status = "phased"
        else:
            status = "published"
        if name_bn is None and name_en is None:
            fail(f"{where}: a published row must carry at least one name")

        slug = f"{ZONE_PREFIX[zone]}-{service_class[:3]}-{number.replace('/', '-')}-{from_code}-{to_code}"
        if slug in seen_ids:
            fail(f"{where}: duplicate dataset id {slug}")
        seen_ids.add(slug)

        serial_key = (zone, "phased" if service_class == "intercity_phased" else "main")
        seen_serials.setdefault(serial_key, set()).add(serial)

        trains.append(
            {
                "id": slug,
                "zone": zone,
                "service_class": service_class,
                "operational_status": status,
                "train_number": number,
                "name_bn": name_bn,
                "name_en": name_en,
                "off_days": [] if off_day is None else [off_day],
                "origin": {"station": from_code, "departure": dep},
                "destination": {"station": to_code, "arrival": arr},
                # Arithmetic fact only: an arrival at or before the departure
                # time can only be on the following day. The PDFs do not print a
                # day marker, so the UI labels this as inferred.
                "overnight_inferred": arr <= dep,
                "stops": [],
                "stops_note": (
                    "the published summary table lists only the origin and "
                    "destination; intermediate stops are not published here"
                ),
                "source": {
                    "document": zone,
                    "page": page,
                    "serial": serial,
                },
            }
        )

    # Serial numbers must be contiguous inside each section once the rows we
    # deliberately excluded are accounted for; any other gap means a row was
    # skipped during transcription.
    excluded_serials = {
        (item["zone"], int(item["serial"])) for item in excluded if "serial" in item
    }
    for (zone, service_class), serials in sorted(seen_serials.items()):
        expected = set(range(1, max(serials) + 1))
        allowed_gaps = {serial for (z, serial) in excluded_serials if z == zone}
        missing = sorted(expected - serials - allowed_gaps)
        if missing:
            fail(f"{zone}/{service_class}: missing serials {missing}")

    # A service is usually published in both directions with two train numbers.
    # Report any service that has only one direction so the gap is visible in
    # the manifest instead of being silently assumed to be complete.
    services: dict[tuple, list[dict]] = {}
    for train in trains:
        key = (
            train["zone"],
            train["name_bn"],
            frozenset((train["origin"]["station"], train["destination"]["station"])),
        )
        services.setdefault(key, []).append(train)
    single_direction = sorted(
        f"{items[0]['name_en'] or items[0]['name_bn']} ({items[0]['train_number']})"
        for items in services.values()
        if len(items) == 1
    )

    stations = []
    for code in sorted(used_stations):
        entry = stations_raw[code]
        zones = sorted({t["zone"] for t in trains if code in (t["origin"]["station"], t["destination"]["station"])})
        stations.append(
            {
                "id": code,
                "name_bn": entry["bn"],
                "name_en": entry["en"],
                "name_provenance": "transliteration of the published Bangla station name",
                "zones": zones,
                # No coordinate is claimed here: the published timetable does not
                # carry coordinates, so the directory says "not verified" instead
                # of borrowing a pin from the demonstration station guide.
                "coordinates": None,
                "coordinate_provenance": None,
            }
        )

    counts_by_zone: dict[str, int] = {}
    counts_by_class: dict[str, int] = {}
    for train in trains:
        counts_by_zone[train["zone"]] = counts_by_zone.get(train["zone"], 0) + 1
        counts_by_class[train["service_class"]] = counts_by_class.get(train["service_class"], 0) + 1

    dataset = {
        "schema_version": 1,
        "dataset_id": DATASET_ID,
        "generated_at": RETRIEVED,
        "timetable_number": TIMETABLE_NUMBER,
        "effective_from": EFFECTIVE_FROM,
        "retrieved": RETRIEVED,
        "last_verified": LAST_VERIFIED,
        "published_only": True,
        "live_status": False,
        "notice": (
            "Scheduled times republished from Bangladesh Railway Timetable No. 54 "
            "(effective 10 March 2025). This is a published timetable, not live "
            "running status: no location, delay, ETA, platform, seat inventory or "
            "fare is shown. Check the official e-ticket portal for current "
            "availability, fare and purchase."
        ),
        "official_portal": "https://eticket.railway.gov.bd/",
        "coverage": {
            "imported": [
                "আন্তঃনগর ট্রেনের তালিকা (Eastern intercity summary)",
                "পর্যায়ক্রমে বাস্তবায়নযোগ্য আন্তঃনগর ট্রেনের তালিকা (Eastern, phased)",
                "আন্তঃনগর ট্রেনের তালিকা (Western intercity summary, incl. international)",
            ],
            "not_imported": NOT_IMPORTED,
            "rows_transcribed": len(trains),
            "rows_excluded": len(excluded),
            "counts_by_zone": counts_by_zone,
            "counts_by_class": counts_by_class,
            "single_direction_train_numbers": single_direction,
            "intermediate_stops_published": False,
        },
        "documents": DOCUMENTS,
        "stations": stations,
        "trains": trains,
        "excluded_rows": excluded,
    }

    text = json.dumps(dataset, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    APP_OUT.parent.mkdir(parents=True, exist_ok=True)
    SITE_OUT.parent.mkdir(parents=True, exist_ok=True)
    APP_OUT.write_text(text, encoding="utf-8", newline="\n")
    SITE_OUT.write_text(text, encoding="utf-8", newline="\n")

    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    manifest = {
        "dataset_id": DATASET_ID,
        "dataset_sha256": digest,
        "dataset_bytes": len(text.encode("utf-8")),
        "app_path": "assets/data/official-timetable.json",
        "site_path": "site/data/official-timetable.json",
        "generated_at": RETRIEVED,
        "generator": "tools/build_official_timetable.py",
        "transcription": "tools/official_timetable/transcribed_rows.json",
        "timetable_number": TIMETABLE_NUMBER,
        "effective_from": EFFECTIVE_FROM,
        "source_index": SOURCE_INDEX,
        "documents": DOCUMENTS,
        "counts": {
            "trains": len(trains),
            "stations": len(stations),
            "excluded_rows": len(excluded),
            "by_zone": counts_by_zone,
            "by_class": counts_by_class,
        },
        "coverage_gaps": NOT_IMPORTED,
    }
    MANIFEST_OUT.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    print(f"trains={len(trains)} stations={len(stations)} excluded={len(excluded)}")
    print(f"by_zone={counts_by_zone} by_class={counts_by_class}")
    if single_direction:
        print(f"single-direction train numbers: {single_direction}")
    print(f"dataset sha256={digest}")
    print(f"wrote {APP_OUT.relative_to(ROOT)} and {SITE_OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(build())
    except DatasetError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
