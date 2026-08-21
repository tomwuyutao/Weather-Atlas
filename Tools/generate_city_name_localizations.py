#!/usr/bin/env python3
"""Build GeoNames-backed display labels for the bundled World Cities catalog.

The output is deliberately presentation-only: it maps a World Cities record ID
and a legacy name/country/coordinate key to alternate labels. Swift keeps the
canonical English/source name in saved data and uses the bundle only when a
matching localized label exists.

Official GeoNames archives:

    https://download.geonames.org/export/dump/allCountries.zip
    https://download.geonames.org/export/dump/alternateNamesV2.zip

Example (the GeoNames downloads are not committed):

    python3 -m pip install --target /tmp/weather-atlas-opencc \
      opencc-python-reimplemented
    PYTHONPATH=/tmp/weather-atlas-opencc python3 \
      Tools/generate_city_name_localizations.py \
      --geonames-archive /path/to/allCountries.zip \
      --alternate-names-archive /path/to/alternateNamesV2.zip \
      --require-opencc

Only exact normalized city-name matches in the same country are accepted.
GeoNames primary/ascii names may be up to 50 km apart, which accommodates the
small coordinate differences between the two source catalogues. A GeoNames
alternate-name match must be within 10 km: aliases can describe a nearby
district, so accepting a distant alias would attach the wrong locality label.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
import unicodedata
import zipfile
from collections import Counter, defaultdict
from dataclasses import dataclass
from math import asin, cos, radians, sin, sqrt
from pathlib import Path
from typing import DefaultDict


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "Weather" / "Resources" / "Cities" / "worldcities.csv"
DEFAULT_OUTPUT = (
    ROOT / "Weather" / "Resources" / "Cities" / "city_name_localizations.json"
)
DEFAULT_REPORT = ROOT / "Tools" / "city_name_localization_report.json"

# SimpleMaps separates the West Bank and Gaza while GeoNames represents both
# with Palestine. Svalbard and Jan Mayen are likewise represented differently.
GEONAMES_COUNTRY_CODE = {"XG": "PS", "XW": "PS", "XR": "SJ"}
MAXIMUM_PRIMARY_NAME_MATCH_DISTANCE_KILOMETERS = 50.0
MAXIMUM_ALTERNATE_NAME_MATCH_DISTANCE_KILOMETERS = 10.0

NON_CHINESE_LOCALES = {
    "fr": ("fr",),
    "de": ("de",),
    "it": ("it",),
    "ja": ("ja",),
    "ko": ("ko",),
    "pt": ("pt",),
    "ru": ("ru",),
    "es": ("es",),
}
HANS_LANGUAGE_CODES = ("zh-hans", "zh-cn", "zh-sg")
HANT_LANGUAGE_CODES = ("zh-hant", "zh-tw", "zh-hk", "zh-mo")
OUTPUT_LOCALES = ("en", *NON_CHINESE_LOCALES.keys(), "zh-Hans", "zh-Hant")


@dataclass(frozen=True)
class CatalogCity:
    identifier: str
    city: str
    city_ascii: str
    country: str
    iso2: str
    latitude: float
    longitude: float

    @property
    def geonames_country_code(self) -> str:
        return GEONAMES_COUNTRY_CODE.get(self.iso2.upper(), self.iso2.upper())

    @property
    def normalized_name_keys(self) -> set[str]:
        return {
            key
            for key in (normalized(self.city), normalized(self.city_ascii))
            if key
        }


@dataclass(frozen=True)
class GeoName:
    identifier: int
    latitude: float
    longitude: float
    population: int


@dataclass(frozen=True)
class GeoNameMatch:
    city: GeoName
    uses_primary_or_ascii_name: bool


@dataclass(frozen=True)
class AlternateName:
    value: str
    is_preferred: bool


class ChineseConverter:
    """Converts generic GeoNames `zh` labels into the requested script.

    GeoNames frequently supplies a generic `zh` record rather than a script
    tag. It is never copied straight into both output fields: OpenCC produces
    independent Simplified and Traditional values before they enter the bundle.
    If OpenCC is unavailable, generic labels are omitted rather than risking a
    wrong-script value; direct GeoNames zh-CN/zh-TW/etc. labels remain usable.
    """

    def __init__(self) -> None:
        try:
            from opencc import OpenCC  # type: ignore[import-not-found]
        except ImportError:
            self._to_simplified = None
            self._to_traditional = None
        else:
            self._to_simplified = OpenCC("t2s")
            self._to_traditional = OpenCC("s2t")

    @property
    def is_available(self) -> bool:
        return self._to_simplified is not None and self._to_traditional is not None

    def simplified(self, value: str) -> str | None:
        return self._to_simplified.convert(value) if self._to_simplified else None

    def traditional(self, value: str) -> str | None:
        return self._to_traditional.convert(value) if self._to_traditional else None


def normalized(value: str) -> str:
    """Normalizes city names without discarding non-Latin writing systems."""
    decomposed = unicodedata.normalize("NFKD", value)
    return "".join(
        character.casefold()
        for character in decomposed
        if character.isalnum() and not unicodedata.combining(character)
    )


def distance_kilometers(
    first_latitude: float,
    first_longitude: float,
    second_latitude: float,
    second_longitude: float,
) -> float:
    earth_radius_kilometers = 6_371.0088
    delta_latitude = radians(second_latitude - first_latitude)
    delta_longitude = radians(second_longitude - first_longitude)
    haversine = (
        sin(delta_latitude / 2) ** 2
        + cos(radians(first_latitude))
        * cos(radians(second_latitude))
        * sin(delta_longitude / 2) ** 2
    )
    return 2 * earth_radius_kilometers * asin(sqrt(haversine))


def parse_population(value: str) -> int:
    try:
        return int(value)
    except ValueError:
        return 0


def catalog_city_key(city: CatalogCity) -> str:
    return "|".join(
        (
            city.city,
            city.country,
            f"{city.latitude:.4f}",
            f"{city.longitude:.4f}",
        )
    )


def read_catalog(path: Path) -> list[CatalogCity]:
    with path.open(encoding="utf-8", newline="") as catalog_file:
        return [
            CatalogCity(
                identifier=row["id"].strip(),
                city=row["city"].strip(),
                city_ascii=row["city_ascii"].strip(),
                country=row["country"].strip(),
                iso2=row["iso2"].strip(),
                latitude=float(row["lat"]),
                longitude=float(row["lng"]),
            )
            for row in csv.DictReader(catalog_file)
        ]


def primary_geonames_name_keys(fields: list[str]) -> set[str]:
    return {
        key
        for value in (fields[1], fields[2])
        if (key := normalized(value))
    }


def alternate_geonames_name_keys(fields: list[str]) -> set[str]:
    return {
        key
        for value in fields[3].split(",")
        if (key := normalized(value))
    }


def exact_name_matches(
    catalog: list[CatalogCity], geonames_archive: Path
) -> tuple[list[GeoName | None], Counter[str]]:
    """Streams allCountries and accepts only quality-bounded name matches."""
    requested_indexes: DefaultDict[tuple[str, str], set[int]] = defaultdict(set)
    for index, city in enumerate(catalog):
        for name_key in city.normalized_name_keys:
            requested_indexes[(city.geonames_country_code, name_key)].add(index)

    nearby_candidates: list[dict[int, GeoNameMatch]] = [dict() for _ in catalog]
    too_distant_indexes: set[int] = set()

    with zipfile.ZipFile(geonames_archive) as archive:
        text_name = next(
            name for name in archive.namelist() if name.endswith(".txt")
        )
        with archive.open(text_name) as source_file:
            for raw_line in source_file:
                fields = raw_line.decode("utf-8").rstrip("\n").split("\t")
                if len(fields) < 19 or fields[6] != "P":
                    continue
                country_code = fields[8]
                primary_indexes: set[int] = set()
                for name_key in primary_geonames_name_keys(fields):
                    primary_indexes.update(
                        requested_indexes.get((country_code, name_key), ())
                    )
                alternate_indexes: set[int] = set()
                for name_key in alternate_geonames_name_keys(fields):
                    alternate_indexes.update(
                        requested_indexes.get((country_code, name_key), ())
                    )
                indexes = primary_indexes | alternate_indexes
                if not indexes:
                    continue

                candidate = GeoName(
                    identifier=int(fields[0]),
                    latitude=float(fields[4]),
                    longitude=float(fields[5]),
                    population=parse_population(fields[14]),
                )
                for index in indexes:
                    city = catalog[index]
                    uses_primary_or_ascii_name = index in primary_indexes
                    maximum_distance = (
                        MAXIMUM_PRIMARY_NAME_MATCH_DISTANCE_KILOMETERS
                        if uses_primary_or_ascii_name
                        else MAXIMUM_ALTERNATE_NAME_MATCH_DISTANCE_KILOMETERS
                    )
                    distance = distance_kilometers(
                        city.latitude,
                        city.longitude,
                        candidate.latitude,
                        candidate.longitude,
                    )
                    if distance > maximum_distance:
                        too_distant_indexes.add(index)
                        continue

                    existing = nearby_candidates[index].get(candidate.identifier)
                    # If a record matches both a GeoNames primary name and an
                    # alias, retain the stronger primary-name classification.
                    if (
                        existing is None
                        or (
                            uses_primary_or_ascii_name
                            and not existing.uses_primary_or_ascii_name
                        )
                    ):
                        nearby_candidates[index][candidate.identifier] = GeoNameMatch(
                            city=candidate,
                            uses_primary_or_ascii_name=uses_primary_or_ascii_name,
                        )

    selected: list[GeoName | None] = []
    match_counts: Counter[str] = Counter()
    for index, candidates_by_identifier in enumerate(nearby_candidates):
        city = catalog[index]
        candidates = list(candidates_by_identifier.values())
        if not candidates:
            selected.append(None)
            match_counts[
                "name-too-distant" if index in too_distant_indexes else "unmatched"
            ] += 1
            continue

        selected_candidate = min(
            candidates,
            key=lambda match: (
                # Prefer an exact GeoNames primary/ascii-name match over a
                # nearby alias. This stops a neighbourhood alias from winning
                # merely because it is geographically closer.
                not match.uses_primary_or_ascii_name,
                distance_kilometers(
                    city.latitude,
                    city.longitude,
                    match.city.latitude,
                    match.city.longitude,
                ),
                -match.city.population,
                match.city.identifier,
            ),
        )
        selected.append(selected_candidate.city)
        distance = distance_kilometers(
            city.latitude,
            city.longitude,
            selected_candidate.city.latitude,
            selected_candidate.city.longitude,
        )
        if selected_candidate.uses_primary_or_ascii_name:
            match_counts[
                "primary-name-within-10km"
                if distance <= MAXIMUM_ALTERNATE_NAME_MATCH_DISTANCE_KILOMETERS
                else "primary-name-10-to-50km"
            ] += 1
        else:
            match_counts["alternate-name-within-10km"] += 1
    return selected, match_counts


def normalized_language_code(value: str) -> str:
    return value.replace("_", "-").lower()


def collect_alternate_names(
    archive_path: Path, wanted_identifiers: set[int]
) -> dict[int, dict[str, list[AlternateName]]]:
    relevant_language_codes = {
        *NON_CHINESE_LOCALES.keys(),
        *HANS_LANGUAGE_CODES,
        *HANT_LANGUAGE_CODES,
        "zh",
    }
    values: DefaultDict[int, DefaultDict[str, list[AlternateName]]] = defaultdict(
        lambda: defaultdict(list)
    )

    with zipfile.ZipFile(archive_path) as archive:
        text_name = next(
            name
            for name in archive.namelist()
            if name.endswith("alternateNamesV2.txt")
        )
        with archive.open(text_name) as source_file:
            for raw_line in source_file:
                fields = raw_line.decode("utf-8").rstrip("\n").split("\t")
                if len(fields) < 8:
                    continue
                try:
                    geoname_identifier = int(fields[1])
                except ValueError:
                    continue
                if geoname_identifier not in wanted_identifiers:
                    continue
                language_code = normalized_language_code(fields[2])
                if language_code not in relevant_language_codes:
                    continue
                value = fields[3].strip()
                # Colloquial aliases are not reliable formal locality labels.
                if not value or fields[6] == "1":
                    continue
                values[geoname_identifier][language_code].append(
                    AlternateName(value=value, is_preferred=fields[4] == "1")
                )
    return {
        identifier: dict(names) for identifier, names in values.items()
    }


def preferred_name(candidates: list[AlternateName]) -> str | None:
    if not candidates:
        return None
    candidate = min(
        candidates,
        key=lambda candidate: (
            not candidate.is_preferred,
            len(candidate.value),
            candidate.value,
        ),
    )
    return candidate.value


def first_preferred_name(
    names: dict[str, list[AlternateName]], language_codes: tuple[str, ...]
) -> str | None:
    for language_code in language_codes:
        if value := preferred_name(names.get(language_code, [])):
            return value
    return None


def localized_names(
    canonical_name: str,
    alternate_names: dict[str, list[AlternateName]],
    chinese_converter: ChineseConverter,
) -> dict[str, str]:
    output: dict[str, str] = {}
    for locale, language_codes in NON_CHINESE_LOCALES.items():
        if value := first_preferred_name(alternate_names, language_codes):
            if value != canonical_name:
                output[locale] = value

    simplified = first_preferred_name(alternate_names, HANS_LANGUAGE_CODES)
    traditional = first_preferred_name(alternate_names, HANT_LANGUAGE_CODES)
    generic_chinese = preferred_name(alternate_names.get("zh", []))
    if generic_chinese and chinese_converter.is_available:
        simplified = simplified or chinese_converter.simplified(generic_chinese)
        traditional = traditional or chinese_converter.traditional(generic_chinese)
    if simplified and simplified != canonical_name:
        output["zh-Hans"] = simplified
    if traditional and traditional != canonical_name:
        output["zh-Hant"] = traditional
    return output


def write_audit(
    path: Path,
    catalog: list[CatalogCity],
    matches: list[GeoName | None],
    names_by_identifier: dict[str, dict[str, str]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "catalog_identifier",
        "city",
        "city_ascii",
        "country",
        "iso2",
        "latitude",
        "longitude",
        "geoname_identifier",
        "match_distance_km",
        *OUTPUT_LOCALES,
    ]
    with path.open("w", encoding="utf-8", newline="") as audit_file:
        writer = csv.DictWriter(audit_file, fieldnames=fieldnames)
        writer.writeheader()
        for city, match in zip(catalog, matches):
            match_distance = (
                distance_kilometers(
                    city.latitude,
                    city.longitude,
                    match.latitude,
                    match.longitude,
                )
                if match
                else None
            )
            names = names_by_identifier.get(city.identifier, {})
            writer.writerow(
                {
                    "catalog_identifier": city.identifier,
                    "city": city.city,
                    "city_ascii": city.city_ascii,
                    "country": city.country,
                    "iso2": city.iso2,
                    "latitude": f"{city.latitude:.4f}",
                    "longitude": f"{city.longitude:.4f}",
                    "geoname_identifier": match.identifier if match else "",
                    "match_distance_km": (
                        f"{match_distance:.3f}" if match_distance is not None else ""
                    ),
                    "en": city.city,
                    **names,
                }
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--geonames-archive", type=Path, required=True)
    parser.add_argument("--alternate-names-archive", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--audit-csv", type=Path)
    parser.add_argument(
        "--require-opencc",
        action="store_true",
        help="Fail unless OpenCC can safely convert generic GeoNames zh labels.",
    )
    args = parser.parse_args()

    catalog = read_catalog(args.catalog)
    chinese_converter = ChineseConverter()
    if args.require_opencc and not chinese_converter.is_available:
        parser.error(
            "OpenCC is required. Install opencc-python-reimplemented in a "
            "temporary directory and add it to PYTHONPATH."
        )

    matches, match_counts = exact_name_matches(catalog, args.geonames_archive)
    wanted_identifiers = {
        match.identifier for match in matches if match is not None
    }
    alternate_names = collect_alternate_names(
        args.alternate_names_archive, wanted_identifiers
    )

    names_by_identifier: dict[str, dict[str, str]] = {}
    legacy_identifiers: dict[str, str] = {}
    locale_coverage: Counter[str] = Counter()
    for city, match in zip(catalog, matches):
        if match is None:
            continue
        names = localized_names(
            city.city,
            alternate_names.get(match.identifier, {}),
            chinese_converter,
        )
        for locale in names:
            locale_coverage[locale] += 1
        if not names:
            continue
        names_by_identifier[city.identifier] = names
        legacy_identifiers[catalog_city_key(city)] = city.identifier

    output = {
        "formatVersion": 1,
        "source": "GeoNames allCountries and alternateNamesV2",
        "license": "CC BY 4.0",
        "attributionURL": "https://www.geonames.org/",
        "namesByCatalogIdentifier": dict(sorted(names_by_identifier.items())),
        "catalogIdentifierByLegacyKey": dict(sorted(legacy_identifiers.items())),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(output, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    report = {
        "catalogRows": len(catalog),
        "acceptedMatches": sum(match is not None for match in matches),
        "matchCounts": dict(sorted(match_counts.items())),
        "localizedEntries": len(names_by_identifier),
        "localeCoverage": {
            locale: len(catalog) if locale == "en" else locale_coverage[locale]
            for locale in OUTPUT_LOCALES
        },
        "missingByLocale": {
            locale: 0 if locale == "en" else len(catalog) - locale_coverage[locale]
            for locale in OUTPUT_LOCALES
        },
        "genericChineseConvertedWithOpenCC": chinese_converter.is_available,
        "unmatchedRows": sum(match is None for match in matches),
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    if args.audit_csv:
        write_audit(args.audit_csv, catalog, matches, names_by_identifier)

    print(
        f"Matched {report['acceptedMatches']:,}/{len(catalog):,} catalog rows; "
        f"wrote {len(names_by_identifier):,} localized entries."
    )
    print(f"Wrote {args.output}")
    print(f"Wrote {args.report}")
    if args.audit_csv:
        print(f"Wrote {args.audit_csv}")


if __name__ == "__main__":
    main()
