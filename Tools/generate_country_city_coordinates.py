#!/usr/bin/env python3
"""Generate the bundled country city catalog with IANA time zones.

The app should not infer time zones at runtime for generated lists. This
developer script reads Weather/Assets/worldcities.csv, resolves every city
coordinate with timezonefinder, and writes a deterministic CSV used by the app.
"""

from __future__ import annotations

import csv
from pathlib import Path

from timezonefinder import TimezoneFinder


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Weather" / "Assets" / "worldcities.csv"
OUTPUT = ROOT / "Weather" / "Assets" / "country_city_coordinates.csv"


def main() -> None:
    finder = TimezoneFinder()
    failures: list[tuple[str, str, float, float]] = []

    with SOURCE.open(newline="", encoding="utf-8") as source_file, OUTPUT.open(
        "w", newline="", encoding="utf-8"
    ) as output_file:
        reader = csv.DictReader(source_file)
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

        for row in reader:
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

    print(f"Wrote {OUTPUT}")


if __name__ == "__main__":
    main()
