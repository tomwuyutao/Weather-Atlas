//
//  DiagnoseMapKitSearch.swift
//  Weather Atlas developer tool
//
//  Purpose: Prints raw MapKit autocomplete and local-search results without
//  changing production search behavior. Run from the repository root:
//  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//  xcrun swiftc -parse-as-library Tools/DiagnoseMapKitSearch.swift \
//  -o /tmp/diagnose_mapkit_search && /tmp/diagnose_mapkit_search
//

import Foundation
@preconcurrency import MapKit

// MARK: - Completion Probe

/// Converts `MKLocalSearchCompleter` delegate callbacks into one async result.
@MainActor
private final class CompletionProbe: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Error>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .physicalFeature, .query]
        completer.region = Self.worldRegion
    }

    /// Requests one raw completion batch in MapKit relevance order.
    func search(_ query: String) async throws -> [MKLocalSearchCompletion] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            completer.queryFragment = query
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        continuation?.resume(returning: completer.results)
        continuation = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private static let worldRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
    )
}

// MARK: - Entry Point

@main
private struct DiagnoseMapKitSearch {
    /// Compares APIs for English and common Simplified/Traditional Chinese names.
    static func main() async {
        print("Locale: \(Locale.current.identifier)")
        print("Languages: \(Locale.preferredLanguages.joined(separator: ", "))")
        print("Time zone: \(TimeZone.current.identifier)")

        for query in CommandLine.arguments.dropFirst().isEmpty
            ? ["Sydney", "悉尼", "雪梨"]
            : Array(CommandLine.arguments.dropFirst()) {
            await diagnose(query)
        }
    }

    /// Prints autocomplete first, then an independent natural-language search.
    @MainActor
    private static func diagnose(_ query: String) async {
        print("\n========== QUERY: \(query) ==========")

        do {
            let completions = try await CompletionProbe().search(query)
            print("\nAutocomplete: \(completions.count) result(s)")
            for (index, completion) in completions.prefix(20).enumerated() {
                print("[C\(index + 1)] \(completion.title) | \(completion.subtitle)")
                do {
                    let request = MKLocalSearch.Request(completion: completion)
                    let response = try await MKLocalSearch(request: request).start()
                    for (itemIndex, item) in response.mapItems.prefix(3).enumerated() {
                        printMapItem(item, prefix: "    [resolved \(itemIndex + 1)]")
                    }
                } catch {
                    print("    resolution error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Autocomplete error: \(error.localizedDescription)")
        }

        do {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest, .physicalFeature]
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
            )
            let response = try await MKLocalSearch(request: request).start()
            print("\nDirect local search: \(response.mapItems.count) result(s)")
            for (index, item) in response.mapItems.prefix(20).enumerated() {
                printMapItem(item, prefix: "[D\(index + 1)]")
            }
        } catch {
            print("Direct local-search error: \(error.localizedDescription)")
        }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(query)
            print("\nCore Location geocoder: \(placemarks.count) result(s)")
            for (index, placemark) in placemarks.prefix(20).enumerated() {
                let coordinate = placemark.location?.coordinate
                let coordinateDescription = coordinate.map {
                    String(format: "%.6f,%.6f", $0.latitude, $0.longitude)
                } ?? "nil"
                let fields = [
                    "name=\(placemark.name ?? "nil")",
                    "subLocality=\(placemark.subLocality ?? "nil")",
                    "locality=\(placemark.locality ?? "nil")",
                    "subAdministrativeArea=\(placemark.subAdministrativeArea ?? "nil")",
                    "administrativeArea=\(placemark.administrativeArea ?? "nil")",
                    "country=\(placemark.country ?? "nil")",
                    "isoCountryCode=\(placemark.isoCountryCode ?? "nil")",
                    "coordinate=\(coordinateDescription)"
                ]
                print("[G\(index + 1)] \(fields.joined(separator: " | "))")
            }
        } catch {
            print("Core Location geocoder error: \(error.localizedDescription)")
        }
    }

    /// Prints the place hierarchy needed to identify locality promotion or bias.
    private static func printMapItem(_ item: MKMapItem, prefix: String) {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        let fields = [
            "name=\(item.name ?? "nil")",
            "subLocality=\(placemark.subLocality ?? "nil")",
            "locality=\(placemark.locality ?? "nil")",
            "subAdministrativeArea=\(placemark.subAdministrativeArea ?? "nil")",
            "administrativeArea=\(placemark.administrativeArea ?? "nil")",
            "country=\(placemark.country ?? "nil")",
            "isoCountryCode=\(placemark.isoCountryCode ?? "nil")",
            String(format: "coordinate=%.6f,%.6f", coordinate.latitude, coordinate.longitude)
        ]
        print("\(prefix) \(fields.joined(separator: " | "))")
    }
}
