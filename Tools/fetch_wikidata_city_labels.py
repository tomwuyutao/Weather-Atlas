#!/usr/bin/env python3
"""Fetch exact-locale Wikidata labels for the GeoNames IDs in the city audit."""

from __future__ import annotations

import argparse
import csv
import json
import time
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "fr", "de", "it", "ja", "ko", "pt", "ru", "es", "zh-hans", "zh-hant")
OUTPUT_LANGUAGE = {"zh-hans": "zh-Hans", "zh-hant": "zh-Hant"}


def query(identifiers: list[str]) -> list[dict[str, object]]:
    values = " ".join(f'"{identifier}"' for identifier in identifiers)
    languages = ", ".join(f'"{language}"' for language in LANGUAGES)
    sparql = f'''SELECT ?geoname ?language ?label WHERE {{
      VALUES ?geoname {{ {values} }}
      ?item wdt:P1566 ?geoname; rdfs:label ?label.
      BIND(LANG(?label) AS ?language)
      FILTER(?language IN ({languages}))
    }}'''
    request = Request(
        "https://query.wikidata.org/sparql?" + urlencode({"query": sparql, "format": "json"}),
        headers={"Accept": "application/sparql-results+json", "User-Agent": "WeatherAtlas/1.0 city-localization-audit"},
    )
    with urlopen(request, timeout=120) as response:
        return json.load(response)["results"]["bindings"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, default=ROOT / "Tools/city_name_localization_audit.csv")
    parser.add_argument("--output", type=Path, default=ROOT / "Tools/cache/wikidata_city_labels.json")
    args = parser.parse_args()
    with args.audit.open(encoding="utf-8", newline="") as file:
        identifiers = sorted({row["geoname_id"] for row in csv.DictReader(file) if row["geoname_id"]})
    labels: dict[str, dict[str, str]] = {}
    for start in range(0, len(identifiers), 400):
        for row in query(identifiers[start:start + 400]):
            language = OUTPUT_LANGUAGE.get(row["language"]["value"], row["language"]["value"])
            labels.setdefault(row["geoname"]["value"], {})[language] = row["label"]["value"]
        time.sleep(1)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(labels, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote Wikidata labels for {len(labels)} GeoNames IDs to {args.output}")


if __name__ == "__main__":
    main()
