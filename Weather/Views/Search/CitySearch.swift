//
//  CitySearch.swift
//  Weather
//
//  Purpose: Combines Apple Maps autocomplete with translated Open-Meteo
//  geocoding for the dedicated Search tab.
//

import CoreLocation
import Foundation
import MapKit
import Observation

enum CitySearchProvider: Hashable {
    case appleMaps
    case openMeteo
}

/// A provider-labelled place suggestion that can be resolved into a City.
struct CitySearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let provider: CitySearchProvider
    fileprivate let completion: MKLocalSearchCompletion?
    fileprivate let resolvedPlace: CitySearchResolvedPlace?

    init(completion: MKLocalSearchCompletion) {
        id = "apple-\(completion.title)-\(completion.subtitle)"
        title = completion.title
        subtitle = completion.subtitle
        provider = .appleMaps
        self.completion = completion
        resolvedPlace = nil
    }

    fileprivate init(openMeteo result: OpenMeteoGeocodingResult) {
        id = "open-meteo-\(result.id)"
        title = result.name
        subtitle = Self.subtitle(for: result)
        provider = .openMeteo
        completion = nil
        resolvedPlace = CitySearchResolvedPlace(
            cityName: result.name,
            country: result.country ?? result.countryCode ?? "",
            coordinate: CLLocationCoordinate2D(
                latitude: result.latitude,
                longitude: result.longitude
            ),
            timeZoneIdentifier: result.timezone
        )
    }

    private static func subtitle(for result: OpenMeteoGeocodingResult) -> String {
        var values: [String] = []
        for value in [result.admin4, result.admin3, result.admin2, result.admin1, result.country] {
            guard let value,
                  !value.isEmpty,
                  value.localizedCaseInsensitiveCompare(result.name) != .orderedSame,
                  !values.contains(where: {
                      $0.localizedCaseInsensitiveCompare(value) == .orderedSame
                  }) else {
                continue
            }
            values.append(value)
        }
        return values.joined(separator: ", ")
    }
}

/// Concrete place metadata needed to load a transient Detail report.
struct CitySearchResolvedPlace {
    let cityName: String
    let country: String
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String?
}

private struct OpenMeteoGeocodingResponse: Decodable {
    let results: [OpenMeteoGeocodingResult]?
}

private struct OpenMeteoGeocodingResult: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let countryCode: String?
    let admin1: String?
    let admin2: String?
    let admin3: String?
    let admin4: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, country, admin1, admin2, admin3, admin4, timezone
        case countryCode = "country_code"
    }
}

/// Coordinates the two independent city-search providers for one query.
@MainActor
@Observable
final class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var appleResults: [CitySearchResult] = []
    private(set) var openMeteoResults: [CitySearchResult] = []
    private(set) var isAppleSearching = false
    private(set) var isOpenMeteoSearching = false
    private(set) var appleErrorMessage: String?
    private(set) var openMeteoErrorMessage: String?

    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var openMeteoTask: Task<Void, Never>?
    @ObservationIgnored private var currentQuery = ""
    @ObservationIgnored private var currentLocale = Locale.autoupdatingCurrent

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }

    func search(query: String, locale: Locale = .autoupdatingCurrent) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        openMeteoTask?.cancel()
        currentQuery = query
        currentLocale = locale

        guard !query.isEmpty else {
            appleResults = []
            openMeteoResults = []
            isAppleSearching = false
            isOpenMeteoSearching = false
            appleErrorMessage = nil
            openMeteoErrorMessage = nil
            completer.queryFragment = ""
            return
        }

        appleResults = []
        openMeteoResults = []
        appleErrorMessage = nil
        openMeteoErrorMessage = nil
        isAppleSearching = true
        isOpenMeteoSearching = query.count >= 2
        completer.queryFragment = query

        openMeteoTask = Task { [weak self] in
            guard let self else { return }
            await self.searchOpenMeteo(query: query, locale: locale)
        }
    }

    func resolvePlace(for result: CitySearchResult) async -> CitySearchResolvedPlace? {
        if let resolvedPlace = result.resolvedPlace {
            return resolvedPlace
        }
        guard let completion = result.completion else { return nil }

        do {
            let response = try await MKLocalSearch(
                request: MKLocalSearch.Request(completion: completion)
            ).start()
            guard let item = response.mapItems.first,
                  let coordinate = item.placemark.location?.coordinate else {
                return nil
            }
            let timeZoneIdentifier: String?
            if let mapKitTimeZone = item.placemark.timeZone?.identifier {
                timeZoneIdentifier = mapKitTimeZone
            } else {
                timeZoneIdentifier = try? await CLGeocoder()
                    .reverseGeocodeLocation(
                        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    )
                    .first?
                    .timeZone?
                    .identifier
            }
            return CitySearchResolvedPlace(
                cityName: result.title,
                country: item.placemark.country ?? item.placemark.isoCountryCode ?? "",
                coordinate: coordinate,
                timeZoneIdentifier: timeZoneIdentifier
            )
        } catch {
            return nil
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let query = currentQuery
        guard !query.isEmpty else { return }
        appleResults = completer.results.lazy.filter { completion in
            completion.title.localizedCaseInsensitiveContains(query)
                || completion.subtitle.localizedCaseInsensitiveContains(query)
        }
        .prefix(5)
        .map(CitySearchResult.init(completion:))
        isAppleSearching = false
        appleErrorMessage = nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        appleResults = []
        isAppleSearching = false
        appleErrorMessage = error.localizedDescription
    }

    private func searchOpenMeteo(query: String, locale: Locale) async {
        guard query.count >= 2 else {
            if currentQuery == query {
                isOpenMeteoSearching = false
            }
            return
        }

        do {
            let results = try await fetchOpenMeteoResults(
                query: query,
                language: openMeteoLanguage(for: locale)
            )
            guard !Task.isCancelled, currentQuery == query else { return }
            openMeteoResults = results
                .filter { result in
                    guard let timezone = result.timezone else { return false }
                    return TimeZone(identifier: timezone) != nil
                }
                .map(CitySearchResult.init(openMeteo:))
            isOpenMeteoSearching = false
            openMeteoErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard currentQuery == query else { return }
            openMeteoResults = []
            isOpenMeteoSearching = false
            openMeteoErrorMessage = error.localizedDescription
        }
    }

    private func fetchOpenMeteoResults(
        query: String,
        language: String
    ) async throws -> [OpenMeteoGeocodingResult] {
        var components = URLComponents(
            string: "https://geocoding-api.open-meteo.com/v1/search"
        )
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "5"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse,
              200..<300 ~= response.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder()
            .decode(OpenMeteoGeocodingResponse.self, from: data)
            .results ?? []
    }

    private func openMeteoLanguage(for locale: Locale) -> String {
        let language = UserDefaults.standard.string(
            forKey: AppLanguageDefaults.storageKey
        ) ?? locale.language.minimalIdentifier
        switch language {
        case "zh-Hans": return "zh_CN"
        case "zh-Hant": return "zh_TW"
        case "pt": return "pt_BR"
        default: return language
        }
    }
}
