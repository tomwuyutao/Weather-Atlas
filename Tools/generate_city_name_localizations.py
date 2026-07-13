#!/usr/bin/env python3
"""Build static city-name localizations from the GeoNames bulk exports.

The generated JSON is strict: a missing localized value is left empty. The
accompanying CSV keeps every requested locale as a separate column so coverage
can be audited without silently substituting another language.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import unicodedata
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from difflib import SequenceMatcher
from math import asin, cos, radians, sin, sqrt
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Weather" / "Assets" / "country_city_coordinates.csv"
DEFAULT_JSON = ROOT / "Weather" / "Assets" / "city_name_localizations.json"
DEFAULT_CSV = ROOT / "Tools" / "city_name_localization_audit.csv"
DEFAULT_REPORT = ROOT / "Tools" / "city_name_localization_report.json"
DEFAULT_WIKIDATA_LABELS = ROOT / "Tools" / "cache" / "wikidata_city_labels.json"
DEFAULT_REFERENCE_OVERRIDES = ROOT / "Tools" / "city_name_localization_reference_overrides.json"

LANGUAGE_FALLBACKS = {
    "en": ("en",),
    "fr": ("fr",),
    "de": ("de",),
    "it": ("it",),
    "ja": ("ja",),
    "ko": ("ko",),
    "pt": ("pt",),
    "ru": ("ru",),
    "es": ("es",),
    "zh-Hans": ("zh-CN", "zh"),
    "zh-Hant": ("zh-Hant", "zh-TW", "zh"),
}

# SimpleMaps uses separate source codes for the West Bank and Gaza. GeoNames
# records both under Palestine's ISO code.
GEONAMES_COUNTRY_CODE = {"XG": "PS", "XR": "SJ", "XW": "PS"}


@dataclass(frozen=True)
class GeoName:
    identifier: int
    name: str
    ascii_name: str
    alternate_names: str
    latitude: float
    longitude: float
    country_code: str
    population: int


def normalized(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    without_marks = "".join(char for char in decomposed if not unicodedata.combining(char))
    return re.sub(r"[^a-z0-9]", "", without_marks.casefold())


def distance_kilometres(first_lat: float, first_lon: float, second_lat: float, second_lon: float) -> float:
    earth_radius = 6371.0088
    delta_lat = radians(second_lat - first_lat)
    delta_lon = radians(second_lon - first_lon)
    haversine = sin(delta_lat / 2) ** 2 + cos(radians(first_lat)) * cos(radians(second_lat)) * sin(delta_lon / 2) ** 2
    return 2 * earth_radius * asin(sqrt(haversine))


def parse_population(value: str) -> int:
    try:
        return int(value)
    except ValueError:
        return 0


def load_geonames(cities_archive: Path) -> dict[str, list[GeoName]]:
    by_country: dict[str, list[GeoName]] = defaultdict(list)
    with zipfile.ZipFile(cities_archive) as archive:
        text_name = next(name for name in archive.namelist() if name.endswith(".txt"))
        with archive.open(text_name) as raw_file:
            for raw_line in raw_file:
                fields = raw_line.decode("utf-8").rstrip("\n").split("\t")
                if len(fields) < 19 or fields[6] != "P":
                    continue
                by_country[fields[8]].append(
                    GeoName(
                        identifier=int(fields[0]),
                        name=fields[1],
                        ascii_name=fields[2],
                        alternate_names=fields[3],
                        latitude=float(fields[4]),
                        longitude=float(fields[5]),
                        country_code=fields[8],
                        population=parse_population(fields[14]),
                    )
                )
    return by_country


def full_catalog_matches(
    catalog_rows: list[dict[str, str]],
    matches: list[tuple[GeoName | None, str, float | None]],
    full_cities_archive: Path,
) -> list[tuple[GeoName | None, str, float | None]]:
    pending_by_country: dict[str, list[int]] = defaultdict(list)
    for index, (row, (matched_city, _, _)) in enumerate(zip(catalog_rows, matches)):
        if matched_city is None:
            pending_by_country[GEONAMES_COUNTRY_CODE.get(row["iso2"], row["iso2"])].append(index)
    if not pending_by_country:
        return matches

    nearby_candidates: dict[int, list[GeoName]] = defaultdict(list)
    with zipfile.ZipFile(full_cities_archive) as archive:
        text_name = next(name for name in archive.namelist() if name.endswith(".txt"))
        with archive.open(text_name) as raw_file:
            for raw_line in raw_file:
                fields = raw_line.decode("utf-8").rstrip("\n").split("\t")
                if len(fields) < 19 or fields[6] != "P" or fields[8] not in pending_by_country:
                    continue
                candidate = GeoName(
                    identifier=int(fields[0]),
                    name=fields[1],
                    ascii_name=fields[2],
                    alternate_names=fields[3],
                    latitude=float(fields[4]),
                    longitude=float(fields[5]),
                    country_code=fields[8],
                    population=parse_population(fields[14]),
                )
                for index in pending_by_country[candidate.country_code]:
                    row = catalog_rows[index]
                    distance = distance_kilometres(float(row["latitude"]), float(row["longitude"]), candidate.latitude, candidate.longitude)
                    if distance <= 50 or name_match_quality(row["city"], candidate) >= 2:
                        nearby_candidates[index].append(candidate)

    resolved = list(matches)
    for index, candidates in nearby_candidates.items():
        city, status, distance = match_city(catalog_rows[index], candidates)
        if city is None:
            city, status, distance = match_city_by_name(catalog_rows[index], candidates)
        if city is not None:
            resolved[index] = (city, status if status.startswith("full-") else f"full-{status}", distance)
    return resolved


def name_match_quality(city_name: str, candidate: GeoName) -> int:
    city_key = normalized(city_name)
    candidate_names = [candidate.name, candidate.ascii_name, *candidate.alternate_names.split(",")]
    candidate_keys = {normalized(name) for name in candidate_names if name}
    if city_key in candidate_keys:
        return 3
    similarity = max((SequenceMatcher(None, city_key, key).ratio() for key in candidate_keys), default=0)
    if similarity >= 0.92:
        return 2
    if similarity >= 0.86:
        return 1
    return 0


def match_city(row: dict[str, str], candidates: list[GeoName]) -> tuple[GeoName | None, str, float | None]:
    latitude = float(row["latitude"])
    longitude = float(row["longitude"])
    ranked: list[tuple[float, int, GeoName]] = []
    for candidate in candidates:
        distance = distance_kilometres(latitude, longitude, candidate.latitude, candidate.longitude)
        if distance > 50:
            continue
        quality = name_match_quality(row["city"], candidate)
        if quality == 0 and distance > 2:
            continue
        score = distance + (3 - quality) * 8
        ranked.append((score, quality, candidate))

    if not ranked:
        return None, "unmatched", None

    score, quality, candidate = min(ranked, key=lambda item: item[0])
    distance = distance_kilometres(latitude, longitude, candidate.latitude, candidate.longitude)
    if quality == 3 and distance <= 10:
        return candidate, "exact", distance
    if quality >= 2 and distance <= 25:
        return candidate, "fuzzy", distance
    if quality == 1 and distance <= 5:
        return candidate, "close-fuzzy", distance
    if distance <= 1:
        return candidate, "coordinate", distance
    return None, "unmatched", None


def match_city_by_name(row: dict[str, str], candidates: list[GeoName]) -> tuple[GeoName | None, str, float | None]:
    latitude = float(row["latitude"])
    longitude = float(row["longitude"])
    ranked: list[tuple[int, float, GeoName]] = []
    for candidate in candidates:
        quality = name_match_quality(row["city"], candidate)
        if quality < 2:
            continue
        distance = distance_kilometres(latitude, longitude, candidate.latitude, candidate.longitude)
        if quality == 2 and distance > 250:
            continue
        ranked.append((-quality, distance, candidate))
    if not ranked:
        return None, "unmatched", None

    quality, distance, candidate = min(ranked, key=lambda item: (item[0], item[1]))
    return candidate, "full-name-exact" if quality == -3 else "full-name-fuzzy", distance


def preferred_alternate_names(alternate_names_archive: Path, wanted_ids: set[int]) -> dict[int, dict[str, str]]:
    selections: dict[int, dict[str, tuple[int, str]]] = defaultdict(dict)
    with zipfile.ZipFile(alternate_names_archive) as archive:
        text_name = next(name for name in archive.namelist() if name.endswith("alternateNamesV2.txt"))
        with archive.open(text_name) as raw_file:
            for raw_line in raw_file:
                fields = raw_line.decode("utf-8").rstrip("\n").split("\t")
                if len(fields) < 8:
                    continue
                geoname_id = int(fields[1])
                if geoname_id not in wanted_ids:
                    continue
                language = fields[2]
                alternate_name = fields[3].strip()
                if not alternate_name or fields[6] == "1":
                    continue
                priority = 2 if fields[4] == "1" else 1
                existing = selections[geoname_id].get(language)
                if existing is None or priority > existing[0] or (priority == existing[0] and len(alternate_name) < len(existing[1])):
                    selections[geoname_id][language] = (priority, alternate_name)
    return {
        geoname_id: {language: selection[1] for language, selection in names.items()}
        for geoname_id, names in selections.items()
    }


def localized_names(canonical_name: str, alternate_names: dict[str, str]) -> dict[str, str]:
    output: dict[str, str] = {"en": canonical_name}
    for app_language, fallbacks in LANGUAGE_FALLBACKS.items():
        if app_language == "en":
            continue
        for language in fallbacks:
            if alternate_names.get(language):
                output[app_language] = alternate_names[language]
                break
    return output


def city_key(row: dict[str, str]) -> str:
    return "|".join((row["city"], row["country"], f"{float(row['latitude']):.4f}", f"{float(row['longitude']):.4f}"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cities-archive", type=Path, required=True)
    parser.add_argument("--alternate-names-archive", type=Path, required=True)
    parser.add_argument("--full-cities-archive", type=Path)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output-json", type=Path, default=DEFAULT_JSON)
    parser.add_argument("--audit-csv", type=Path, default=DEFAULT_CSV)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--wikidata-labels", type=Path, default=DEFAULT_WIKIDATA_LABELS)
    parser.add_argument("--reference-overrides", type=Path, default=DEFAULT_REFERENCE_OVERRIDES)
    args = parser.parse_args()

    with args.catalog.open(encoding="utf-8", newline="") as catalog_file:
        catalog_rows = list(csv.DictReader(catalog_file))
    wikidata_labels = json.loads(args.wikidata_labels.read_text(encoding="utf-8")) if args.wikidata_labels.exists() else {}
    reference_overrides = json.loads(args.reference_overrides.read_text(encoding="utf-8")) if args.reference_overrides.exists() else {}

    geonames_by_country = load_geonames(args.cities_archive)
    matches = [
        match_city(row, geonames_by_country.get(GEONAMES_COUNTRY_CODE.get(row["iso2"], row["iso2"]), []))
        for row in catalog_rows
    ]
    if args.full_cities_archive:
        matches = full_catalog_matches(catalog_rows, matches, args.full_cities_archive)
    matched_ids = {match.identifier for match, _, _ in matches if match is not None}
    alternate_names_by_id = preferred_alternate_names(args.alternate_names_archive, matched_ids)

    output_rows: list[dict[str, object]] = []
    audit_rows: list[dict[str, object]] = []
    match_counts: Counter[str] = Counter()
    locale_coverage: Counter[str] = Counter()
    wikidata_values_applied = 0
    reference_overrides_applied = 0

    for row, (matched_city, match_status, distance) in zip(catalog_rows, matches):
        match_counts[match_status] += 1
        geonames_names = localized_names(row["city"], alternate_names_by_id.get(matched_city.identifier, {})) if matched_city else {}
        names = {language: geonames_names.get(language, "") for language in LANGUAGE_FALLBACKS}
        wikidata_names = wikidata_labels.get(str(matched_city.identifier), {}) if matched_city else {}
        for language, name in wikidata_names.items():
            if language in names and name and not names[language]:
                names[language] = name
                wikidata_values_applied += 1
        reference_override = reference_overrides.get(city_key(row))
        if reference_override:
            names.update(reference_override["names"])
            reference_overrides_applied += 1
        for language in LANGUAGE_FALLBACKS:
            if language in geonames_names:
                locale_coverage[language] += 1

        output_rows.append(
            {
                "key": city_key(row),
                "geonameId": matched_city.identifier if matched_city else None,
                "names": names,
                "geoNamesLanguages": sorted(geonames_names),
                "nameSource": reference_override["source"] if reference_override else "GeoNames + Wikidata",
            }
        )
        audit_rows.append(
            {
                "city": row["city"],
                "country": row["country"],
                "iso2": row["iso2"],
                "latitude": row["latitude"],
                "longitude": row["longitude"],
                "geoname_id": matched_city.identifier if matched_city else "",
                "match_status": match_status,
                "match_distance_km": f"{distance:.3f}" if distance is not None else "",
                "reference_source": reference_override["source"] if reference_override else "",
                **names,
            }
        )

    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(
            {
                "source": "GeoNames + Wikidata",
                "license": "CC BY 4.0",
                "cities": output_rows,
            },
            ensure_ascii=False,
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    with args.audit_csv.open("w", encoding="utf-8", newline="") as audit_file:
        writer = csv.DictWriter(audit_file, fieldnames=list(audit_rows[0]))
        writer.writeheader()
        writer.writerows(audit_rows)
    args.report.write_text(
        json.dumps(
            {
                "catalogRows": len(catalog_rows),
                "matchCounts": dict(sorted(match_counts.items())),
                "localeCoverage": {language: locale_coverage[language] for language in LANGUAGE_FALLBACKS},
                "missingByLocale": {language: len(catalog_rows) - locale_coverage[language] for language in LANGUAGE_FALLBACKS},
                "wikidataValuesApplied": wikidata_values_applied,
                "referenceOverridesApplied": reference_overrides_applied,
                "unresolvedCities": sum(1 for row in output_rows if row["geonameId"] is None and not any(row["names"].values())),
            },
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(output_rows)} localizations to {args.output_json}")
    print(f"Wrote audit data to {args.audit_csv}")
    print(f"Wrote coverage report to {args.report}")


if __name__ == "__main__":
    main()
