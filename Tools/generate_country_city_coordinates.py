#!/usr/bin/env python3
"""Generate the bundled country city catalog with IANA time zones.

The app should not infer time zones at runtime for generated lists. This
developer script reads Weather/Assets/worldcities.csv, resolves every city
coordinate with timezonefinder, and writes a deterministic top-25-per-country
CSV used by the app.
"""

from __future__ import annotations

import csv
from pathlib import Path

from timezonefinder import TimezoneFinder


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Weather" / "Assets" / "worldcities.csv"
OUTPUT = ROOT / "Weather" / "Assets" / "country_city_coordinates.csv"
MAX_CITIES_PER_COUNTRY = 25


def main() -> None:
    finder = TimezoneFinder()
    failures: list[tuple[str, str, float, float]] = []
    rows_by_country: dict[str, list[dict[str, str | float]]] = {}

    with SOURCE.open(newline="", encoding="utf-8") as source_file:
        reader = csv.DictReader(source_file)
        for row in reader:
            population = int(float(row["population"] or 0))
            rows_by_country.setdefault(row["iso2"], []).append({**row, "population_value": population})

    selected_rows: list[dict[str, str | float]] = []
    for rows in rows_by_country.values():
        selected_rows.extend(
            sorted(rows, key=lambda row: (-int(row["population_value"]), str(row["city"]).casefold()))[
                :MAX_CITIES_PER_COUNTRY
            ]
        )

    with OUTPUT.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file,
            fieldnames=[
                "city",
                "country",
                "iso2",
                "latitude",
                "longitude",
                "time_zone",
                "population",
            ],
        )
        writer.writeheader()

        for row in selected_rows:
            latitude = float(row["lat"])
            longitude = float(row["lng"])
            time_zone = finder.timezone_at(lat=latitude, lng=longitude)
            if not time_zone:
                failures.append((row["city"], row["country"], latitude, longitude))
                continue

            writer.writerow(
                {
                    "city": row["city"],
                    "country": row["country"],
                    "iso2": row["iso2"],
                    "latitude": latitude,
                    "longitude": longitude,
                    "time_zone": time_zone,
                    "population": row["population"] or "0",
                }
            )

    if failures:
        details = "\n".join(f"{city}, {country}: {lat}, {lon}" for city, country, lat, lon in failures[:50])
        raise SystemExit(f"Missing time zones for {len(failures)} rows:\n{details}")

    print(f"Wrote {len(selected_rows)} rows to {OUTPUT}")


if __name__ == "__main__":
    main()
