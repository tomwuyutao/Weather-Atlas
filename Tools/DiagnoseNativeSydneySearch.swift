//
//  DiagnoseNativeSydneySearch.swift
//  Weather Atlas developer tool
//
//  Purpose: Compares public Apple place-search APIs and configuration modes for
//  Sydney while running behind the device's current regional map service.
//
//  Run from the repository root:
//  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//  xcrun swiftc -parse-as-library Tools/DiagnoseNativeSydneySearch.swift \
//  -o /tmp/diagnose_native_sydney && /tmp/diagnose_native_sydney
//

import Contacts
import CoreLocation
import Foundation
@preconcurrency import MapKit

private let worldRegion = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
    span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
)

private let sydneyCoordinate = CLLocationCoordinate2D(
    latitude: -33.8688,
    longitude: 151.2093
)

private let sydneyRegion = MKCoordinateRegion(
    center: sydneyCoordinate,
    span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
)

// MARK: - Completion Probe

@MainActor
private final class CompletionProbe: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var continuation: CheckedContinuation<[MKLocalSearchCompletion], Error>?

    init(
        region: MKCoordinateRegion,
        regionPriority: MKLocalSearchRegionPriority,
        resultTypes: MKLocalSearchCompleter.ResultType,
        addressFilter: MKAddressFilter? = nil
    ) {
        super.init()
        completer.delegate = self
        completer.region = region
        completer.regionPriority = regionPriority
        completer.resultTypes = resultTypes
        completer.addressFilter = addressFilter
    }

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
}

// MARK: - Diagnostic Entry Point

@main
private struct DiagnoseNativeSydneySearch {
    static func main() async {
        print("Locale: \(Locale.current.identifier)")
        print("Languages: \(Locale.preferredLanguages.joined(separator: ", "))")
        print("Time zone: \(TimeZone.current.identifier)")

        await completionExperiments()
        await localSearchExperiments()
        await landmarkAndCoordinateExperiments()
        await forwardGeocodingExperiments()
        await reverseGeocodingExperiments()
    }

    // MARK: Autocomplete

    @MainActor
    private static func completionExperiments() async {
        let localityFilter = MKAddressFilter(including: [
            .locality,
            .subLocality,
            .administrativeArea,
            .country
        ])
        let experiments: [(String, CompletionProbe)] = [
            (
                "Autocomplete / world / all result types",
                CompletionProbe(
                    region: worldRegion,
                    regionPriority: .default,
                    resultTypes: [.address, .pointOfInterest, .physicalFeature, .query]
                )
            ),
            (
                "Autocomplete / world / addresses only",
                CompletionProbe(
                    region: worldRegion,
                    regionPriority: .default,
                    resultTypes: .address
                )
            ),
            (
                "Autocomplete / Sydney region required / addresses only",
                CompletionProbe(
                    region: sydneyRegion,
                    regionPriority: .required,
                    resultTypes: .address
                )
            ),
            (
                "Autocomplete / Sydney required / locality address filter",
                CompletionProbe(
                    region: sydneyRegion,
                    regionPriority: .required,
                    resultTypes: .address,
                    addressFilter: localityFilter
                )
            )
        ]

        for (label, probe) in experiments {
            print("\n========== \(label) ==========")
            do {
                let results = try await probe.search("Sydney")
                print("Count: \(results.count)")
                for (index, result) in results.prefix(20).enumerated() {
                    print("[\(index + 1)] \(result.title) | \(result.subtitle)")
                }
            } catch {
                printError(error)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: Local Search

    private static func localSearchExperiments() async {
        let localityFilter = MKAddressFilter(including: [
            .locality,
            .subLocality,
            .administrativeArea,
            .country
        ])
        let experiments: [(String, String, MKCoordinateRegion, MKLocalSearchRegionPriority, MKLocalSearch.ResultType, MKAddressFilter?)] = [
            ("Local search / world / address", "Sydney", worldRegion, .default, .address, nil),
            ("Local search / Sydney required / address", "Sydney", sydneyRegion, .required, .address, nil),
            ("Local search / Sydney required / locality filter", "Sydney", sydneyRegion, .required, .address, localityFilter),
            ("Local search / exact Australian address", "Sydney NSW 2000 Australia", sydneyRegion, .required, .address, localityFilter)
        ]

        for (label, query, region, priority, types, addressFilter) in experiments {
            print("\n========== \(label) ==========")
            let request = MKLocalSearch.Request(naturalLanguageQuery: query, region: region)
            request.regionPriority = priority
            request.resultTypes = types
            request.addressFilter = addressFilter
            do {
                let response = try await MKLocalSearch(request: request).start()
                printMapItems(response.mapItems)
            } catch {
                printError(error)
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: Landmark and Coordinate Search

    private static func landmarkAndCoordinateExperiments() async {
        let queries = [
            "Sydney Opera House Australia",
            "Sydney Airport Australia",
            "2000 NSW Australia",
            "33.8688 S 151.2093 E"
        ]

        for query in queries {
            print("\n========== Landmark local search / \(query) ==========")
            let request = MKLocalSearch.Request(
                naturalLanguageQuery: query,
                region: sydneyRegion
            )
            request.regionPriority = .required
            request.resultTypes = [.address, .pointOfInterest, .physicalFeature]
            do {
                printMapItems(try await MKLocalSearch(request: request).start().mapItems)
            } catch {
                printError(error)
            }
            try? await Task.sleep(for: .seconds(2))
        }

        print("\n========== POIs around known Sydney coordinate ==========")
        let request = MKLocalPointsOfInterestRequest(
            center: sydneyCoordinate,
            radius: 10_000
        )
        do {
            printMapItems(try await MKLocalSearch(request: request).start().mapItems)
        } catch {
            printError(error)
        }
    }

    // MARK: Forward Geocoding

    private static func forwardGeocodingExperiments() async {
        if #available(macOS 26.0, *) {
            for query in ["Sydney", "Sydney NSW 2000 Australia", "悉尼 澳大利亚"] {
                print("\n========== MKGeocodingRequest / \(query) ==========")
                guard let request = MKGeocodingRequest(addressString: query) else {
                    print("Could not construct request")
                    continue
                }
                request.region = sydneyRegion
                request.preferredLocale = Locale(identifier: "en_AU")
                do {
                    printMapItems(try await request.mapItems)
                } catch {
                    printError(error)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }

        print("\n========== CLGeocoder / region + en_AU ==========")
        do {
            let region = CLCircularRegion(
                center: sydneyCoordinate,
                radius: 100_000,
                identifier: "Sydney"
            )
            let placemarks = try await CLGeocoder().geocodeAddressString(
                "Sydney NSW 2000 Australia",
                in: region,
                preferredLocale: Locale(identifier: "en_AU")
            )
            printPlacemarks(placemarks)
        } catch {
            printError(error)
        }
        try? await Task.sleep(for: .seconds(2))

        print("\n========== CLGeocoder / structured Australian postal address ==========")
        do {
            let address = CNMutablePostalAddress()
            address.city = "Sydney"
            address.state = "NSW"
            address.postalCode = "2000"
            address.country = "Australia"
            address.isoCountryCode = "AU"
            let placemarks = try await CLGeocoder().geocodePostalAddress(
                address,
                preferredLocale: Locale(identifier: "en_AU")
            )
            printPlacemarks(placemarks)
        } catch {
            printError(error)
        }
    }

    // MARK: Reverse Geocoding

    private static func reverseGeocodingExperiments() async {
        print("\n========== Reverse geocode / known Sydney coordinate ==========")
        let location = CLLocation(
            latitude: sydneyCoordinate.latitude,
            longitude: sydneyCoordinate.longitude
        )

        if #available(macOS 26.0, *) {
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    print("Could not construct MKReverseGeocodingRequest")
                    return
                }
                printMapItems(try await request.mapItems)
            } catch {
                printError(error)
            }
        }

        try? await Task.sleep(for: .seconds(2))
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "en_AU")
            )
            printPlacemarks(placemarks)
        } catch {
            printError(error)
        }
    }

    // MARK: Output

    private static func printMapItems(_ items: [MKMapItem]) {
        print("Count: \(items.count)")
        for (index, item) in items.prefix(20).enumerated() {
            let placemark = item.placemark
            print(
                "[\(index + 1)] name=\(item.name ?? "nil")"
                    + " | subLocality=\(placemark.subLocality ?? "nil")"
                    + " | locality=\(placemark.locality ?? "nil")"
                    + " | administrativeArea=\(placemark.administrativeArea ?? "nil")"
                    + " | country=\(placemark.country ?? "nil")"
                    + " | isoCountryCode=\(placemark.isoCountryCode ?? "nil")"
                    + String(
                        format: " | coordinate=%.6f,%.6f",
                        placemark.coordinate.latitude,
                        placemark.coordinate.longitude
                    )
            )
        }
    }

    private static func printPlacemarks(_ placemarks: [CLPlacemark]) {
        print("Count: \(placemarks.count)")
        for (index, placemark) in placemarks.prefix(20).enumerated() {
            let coordinate = placemark.location?.coordinate
            print(
                "[\(index + 1)] name=\(placemark.name ?? "nil")"
                    + " | subLocality=\(placemark.subLocality ?? "nil")"
                    + " | locality=\(placemark.locality ?? "nil")"
                    + " | administrativeArea=\(placemark.administrativeArea ?? "nil")"
                    + " | country=\(placemark.country ?? "nil")"
                    + " | isoCountryCode=\(placemark.isoCountryCode ?? "nil")"
                    + " | timeZone=\(placemark.timeZone?.identifier ?? "nil")"
                    + String(
                        format: " | coordinate=%.6f,%.6f",
                        coordinate?.latitude ?? .nan,
                        coordinate?.longitude ?? .nan
                    )
            )
        }
    }

    private static func printError(_ error: Error) {
        let nsError = error as NSError
        print(
            "Error: \(nsError.domain) \(nsError.code)"
                + " | \(nsError.localizedDescription)"
                + " | userInfo=\(nsError.userInfo)"
        )
    }
}
