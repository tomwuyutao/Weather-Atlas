//
//  RefreshDefaultCityCoordinates.swift
//  Weather Atlas developer tool
//
//  Purpose: Regenerates the bundled default_city_coordinates.csv by resolving
//  each starter city through Apple Maps search. Build/run from the repo root:
//  swiftc -parse-as-library Tools/RefreshDefaultCityCoordinates.swift -o /tmp/refresh_default_city_coordinates
//  /tmp/refresh_default_city_coordinates
//

import Foundation
import MapKit

// MARK: - Models

private struct SeedQuery {
    let listID: String
    let query: String
}

private struct ResolvedCity {
    let listID: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
}

private enum RefreshError: LocalizedError {
    case missingSeedFile(URL)
    case invalidSeedRow(Int)
    case noAppleResult(String)
    case appleSearchFailed(String, String)
    case missingAppleCityName(String)
    case missingAppleCountry(String)
    case missingAppleTimeZone(String)
    case appleTimeZoneLookupFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .missingSeedFile(let url):
            return "Missing seed query file: \(url.path)"
        case .invalidSeedRow(let row):
            return "Invalid seed query CSV row \(row)."
        case .noAppleResult(let query):
            return "Apple Maps returned no result for: \(query)"
        case .appleSearchFailed(let query, let reason):
            return "Apple Maps search failed for \(query): \(reason)"
        case .missingAppleCityName(let query):
            return "Apple Maps returned no locality/city name for: \(query)"
        case .missingAppleCountry(let query):
            return "Apple Maps returned no country for: \(query)"
        case .missingAppleTimeZone(let query):
            return "Apple Maps returned no time zone for: \(query)"
        case .appleTimeZoneLookupFailed(let query, let reason):
            return "Apple reverse geocoding failed while resolving the time zone for \(query): \(reason)"
        }
    }
}

// MARK: - Entry Point

@main
private struct RefreshDefaultCityCoordinates {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let seedURL = root
            .appendingPathComponent("Tools")
            .appendingPathComponent("default_city_seed_queries.csv")
        let outputURL = root
            .appendingPathComponent("Weather")
            .appendingPathComponent("Assets")
            .appendingPathComponent("default_city_coordinates.csv")

        guard FileManager.default.fileExists(atPath: seedURL.path) else {
            throw RefreshError.missingSeedFile(seedURL)
        }

        let seeds = try loadSeeds(from: seedURL)
        var resolvedCities: [ResolvedCity] = []
        resolvedCities.reserveCapacity(seeds.count)

        for (index, seed) in seeds.enumerated() {
            let resolved = try await resolve(seed)
            resolvedCities.append(resolved)
            print("[\(index + 1)/\(seeds.count)] \(seed.query) -> \(resolved.city), \(resolved.country)")
            fflush(stdout)

            // Keep this polite. MapKit search is user-facing infrastructure, not a bulk geocoder.
            try await Task.sleep(for: .milliseconds(900))
        }

        try write(resolvedCities, to: outputURL)
        print("Wrote \(resolvedCities.count) Apple Maps-resolved default cities to \(outputURL.path)")
    }
}

// MARK: - Apple Maps Resolution

private func resolve(_ seed: SeedQuery) async throws -> ResolvedCity {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = seed.query
    request.resultTypes = .address
    request.region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
    )

    let response = try await startSearch(request, query: seed.query)
    guard let mapItem = response.mapItems.first else {
        throw RefreshError.noAppleResult(seed.query)
    }

    let placemark = mapItem.placemark
    guard let appleCity = clean(placemark.locality ?? mapItem.name) else {
        throw RefreshError.missingAppleCityName(seed.query)
    }
    guard let appleCountry = clean(placemark.country) else {
        throw RefreshError.missingAppleCountry(seed.query)
    }
    let timeZoneIdentifier = try await resolveTimeZoneIdentifier(
        mapKitTimeZone: mapItem.timeZone,
        coordinate: placemark.coordinate,
        query: seed.query
    )

    guard !timeZoneIdentifier.isEmpty else {
        throw RefreshError.missingAppleTimeZone(seed.query)
    }

    return ResolvedCity(
        listID: seed.listID,
        city: appleCity,
        country: appleCountry,
        latitude: placemark.coordinate.latitude,
        longitude: placemark.coordinate.longitude,
        timeZoneIdentifier: timeZoneIdentifier
    )
}

private func startSearch(_ request: MKLocalSearch.Request, query: String) async throws -> MKLocalSearch.Response {
    var lastError: Error?
    for attempt in 1...4 {
        do {
            return try await MKLocalSearch(request: request).start()
        } catch {
            lastError = error
        }
        try await Task.sleep(for: .milliseconds(1_000 * attempt))
    }

    throw RefreshError.appleSearchFailed(query, lastError?.localizedDescription ?? "unknown error")
}

private func resolveTimeZoneIdentifier(
    mapKitTimeZone: TimeZone?,
    coordinate: CLLocationCoordinate2D,
    query: String
) async throws -> String {
    if let identifier = mapKitTimeZone?.identifier {
        return identifier
    }

    var lastError: Error?
    for attempt in 1...4 {
        do {
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if #available(macOS 26.0, *) {
                let request = MKReverseGeocodingRequest(location: location)
                guard let mapItems = try await request?.mapItems else {
                    throw RefreshError.missingAppleTimeZone(query)
                }
                if let identifier = mapItems.first?.placemark.timeZone?.identifier {
                    return identifier
                }
            } else {
                let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
                if let identifier = placemarks.first?.timeZone?.identifier {
                    return identifier
                }
            }
        } catch {
            lastError = error
        }

        try await Task.sleep(for: .milliseconds(1_000 * attempt))
    }

    if let lastError {
        throw RefreshError.appleTimeZoneLookupFailed(query, lastError.localizedDescription)
    }
    throw RefreshError.missingAppleTimeZone(query)
}

private func clean(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
}

// MARK: - CSV Loading

private func loadSeeds(from url: URL) throws -> [SeedQuery] {
    let lines = try String(contentsOf: url, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)

    return try lines.dropFirst().enumerated().map { index, line in
        let fields = parseCSVLine(line)
        guard fields.count == 2 else {
            throw RefreshError.invalidSeedRow(index + 2)
        }
        return SeedQuery(
            listID: fields[0],
            query: fields[1]
        )
    }
}

private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var isQuoted = false
    var iterator = line.makeIterator()

    while let character = iterator.next() {
        if character == "\"" {
            if isQuoted {
                if let next = iterator.next() {
                    if next == "\"" {
                        current.append("\"")
                    } else {
                        isQuoted = false
                        if next == "," {
                            fields.append(current)
                            current = ""
                        } else {
                            current.append(next)
                        }
                    }
                } else {
                    isQuoted = false
                }
            } else {
                isQuoted = true
            }
        } else if character == ",", !isQuoted {
            fields.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }

    fields.append(current)
    return fields
}

// MARK: - CSV Writing

private func write(_ cities: [ResolvedCity], to url: URL) throws {
    var output = "list_id,city,country,latitude,longitude,time_zone\n"
    for city in cities {
        output += [
            city.listID,
            city.city,
            city.country,
            String(format: "%.6f", city.latitude),
            String(format: "%.6f", city.longitude),
            city.timeZoneIdentifier
        ]
        .map(escapeCSVField)
        .joined(separator: ",")
        + "\n"
    }
    try output.write(to: url, atomically: true, encoding: .utf8)
}

private func escapeCSVField(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
        return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
