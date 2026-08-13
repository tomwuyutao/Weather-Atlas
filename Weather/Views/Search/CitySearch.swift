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

// MARK: - Search Result Data

/// Identifies the service that supplied a suggestion, so the UI can keep the
/// two independent provider result sets separate.
enum CitySearchProvider: Hashable {
    case appleMaps
    case openMeteo

    var displayName: String {
        switch self {
        case .appleMaps: "Apple Maps"
        case .openMeteo: "Open-Meteo"
        }
    }
}

/// Exact failures produced while turning a provider row into complete place
/// metadata. Search UI can map these cases directly to a native missing-data
/// alert instead of treating every failure as an indistinguishable nil result.
enum CitySearchResolutionError: LocalizedError {
    case sourceDataMissing(place: String)
    case coordinateMissing(place: String)
    case invalidCoordinate(place: String)
    case cityNameMissing(place: String)
    case countryMissing(place: String)
    case timeZoneMissing(place: String)
    case invalidTimeZone(place: String, identifier: String)
    case providerFailed(
        provider: CitySearchProvider,
        place: String,
        reason: String
    )

    var errorDescription: String? {
        switch self {
        case .sourceDataMissing(let place):
            "Search data is missing for \(place)."
        case .coordinateMissing(let place):
            "Location data is missing for \(place)."
        case .invalidCoordinate(let place):
            "Location data is invalid for \(place)."
        case .cityNameMissing(let place):
            "City name data is missing for \(place)."
        case .countryMissing(let place):
            "Country data is missing for \(place)."
        case .timeZoneMissing(let place):
            "Time zone data is missing for \(place)."
        case .invalidTimeZone(let place, let identifier):
            "Time zone data is invalid for \(place): \(identifier)."
        case .providerFailed(let provider, let place, let reason):
            "\(provider.displayName) could not resolve \(place): \(reason)"
        }
    }
}

/// A provider-labelled place suggestion that can be resolved into a City.
/// Apple Maps suggestions need a later resolution request; Open-Meteo returns
/// concrete coordinates immediately, which is why the two payload fields differ.
struct CitySearchResult: Identifiable {
    /// The string identity is stable within the result list, allowing SwiftUI
    /// to retain a row's loading indicator while provider results update.
    let id: String
    let title: String
    let subtitle: String
    let provider: CitySearchProvider
    fileprivate let completion: MKLocalSearchCompletion?
    fileprivate let candidate: CitySearchPlaceCandidate?

    init(completion: MKLocalSearchCompletion) {
        id = "apple-\(completion.title)-\(completion.subtitle)"
        title = completion.title
        subtitle = completion.subtitle
        provider = .appleMaps
        self.completion = completion
        candidate = nil
    }

    fileprivate init(openMeteo result: OpenMeteoGeocodingResult) {
        id = "open-meteo-\(result.id)"
        title = result.name
        subtitle = Self.subtitle(for: result)
        provider = .openMeteo
        completion = nil
        candidate = CitySearchPlaceCandidate(
            cityName: result.name,
            country: result.country ?? result.countryCode ?? "",
            coordinate: CLLocationCoordinate2D(
                latitude: result.latitude,
                longitude: result.longitude
            ),
            timeZoneIdentifier: result.timezone
        )
    }

    /// Builds a concise hierarchy such as "County, Region, Country", removing
    /// duplicate values that would otherwise repeat the city name.
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

// MARK: - Open-Meteo JSON Models

/// Concrete place metadata needed to create a transient City for Map preview.
/// This deliberately omits presentation text and provider-specific objects.
struct CitySearchResolvedPlace {
    let cityName: String
    let country: String
    let coordinate: CLLocationCoordinate2D
    let timeZoneIdentifier: String
}

/// Raw provider fields retained until selection. Keeping them optional here lets
/// the row remain visible while strict resolution reports the exact missing field.
fileprivate struct CitySearchPlaceCandidate {
    let cityName: String?
    let country: String?
    let coordinate: CLLocationCoordinate2D?
    let timeZoneIdentifier: String?
}

/// The small subset of the Open-Meteo JSON response that this app needs.
private struct OpenMeteoGeocodingResponse: Decodable {
    let results: [OpenMeteoGeocodingResult]?
}

/// Mirrors one JSON search result. Optional administrative levels vary by
/// country, so the decoding model preserves their absence rather than guessing.
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

// MARK: - Provider Coordinator

/// Coordinates the two independent city-search providers for one query.
/// `@MainActor` keeps observable UI state mutation safe, while each network
/// operation still suspends instead of blocking the main thread.
@MainActor
@Observable
final class CitySearchManager: NSObject, MKLocalSearchCompleterDelegate {
    // MARK: Observable UI State

    private(set) var appleResults: [CitySearchResult] = []
    private(set) var openMeteoResults: [CitySearchResult] = []
    private(set) var isAppleSearching = false
    private(set) var isOpenMeteoSearching = false
    private(set) var appleErrorMessage: String?
    private(set) var openMeteoErrorMessage: String?

    // MARK: Provider Machinery Excluded From SwiftUI Observation

    /// MapKit's delegate object and task bookkeeping should not trigger view
    /// updates; only the published result/error properties need observation.
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var openMeteoTask: Task<Void, Never>?
    @ObservationIgnored private var appleRetryTask: Task<Void, Never>?
    @ObservationIgnored private var currentQuery = ""
    @ObservationIgnored private var currentLocale = Locale.autoupdatingCurrent
    /// One provider retry belongs to one submitted query. A later edit resets
    /// the allowance, while a persistently unavailable provider settles into
    /// the app's blank-first missing-data state.
    @ObservationIgnored private var hasRetriedAppleQuery = false

    /// Sets Apple Maps autocomplete to global address results. The wide region
    /// avoids unintentionally biasing search toward the device's current area.
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 180, longitudeDelta: 360)
        )
    }

    // MARK: Coordinated Provider Requests

    /// Cancels the previous Open-Meteo request, resets visible state, then
    /// launches both providers for the newest non-empty query.
    func search(query: String, locale: Locale = .autoupdatingCurrent) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        openMeteoTask?.cancel()
        appleRetryTask?.cancel()
        currentQuery = query
        currentLocale = locale
        hasRetriedAppleQuery = false

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
        // Open-Meteo rejects one-character searches. Apple Maps still starts,
        // and the short Open-Meteo task below immediately settles itself.
        isOpenMeteoSearching = query.count >= 2
        completer.queryFragment = query

        openMeteoTask = Task { [weak self] in
            guard let self else { return }
            await self.searchOpenMeteo(query: query, locale: locale)
        }
    }

    /// Apple Maps completions are lightweight text suggestions. Resolving one
    /// performs the extra MapKit lookup needed to obtain coordinates and a zone.
    func resolvePlace(
        for result: CitySearchResult
    ) async throws -> CitySearchResolvedPlace {
        do {
            return try await resolvePlaceOnce(for: result)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A selected Apple result can fail because its lightweight
            // completion expired before its full place request began. Give the
            // provider one fresh request before selection surfaces an alert.
            guard result.provider == .appleMaps else { throw error }
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            return try await resolvePlaceOnce(for: result)
        }
    }

    private func resolvePlaceOnce(
        for result: CitySearchResult
    ) async throws -> CitySearchResolvedPlace {
        // Open-Meteo result objects already contain a resolved coordinate, so
        // validate their exact coordinate with the same factual reverse-geocode
        // path that can supplement an Apple Maps suggestion.
        if let candidate = result.candidate {
            return try await resolvedPlace(
                from: candidate,
                resultTitle: result.title
            )
        }
        guard let completion = result.completion else {
            throw CitySearchResolutionError.sourceDataMissing(
                place: result.title
            )
        }

        do {
            let response = try await MKLocalSearch(
                request: MKLocalSearch.Request(completion: completion)
            ).start()
            guard let item = response.mapItems.first else {
                throw CitySearchResolutionError.sourceDataMissing(
                    place: result.title
                )
            }
            guard let coordinate = item.placemark.location?.coordinate else {
                throw CitySearchResolutionError.coordinateMissing(
                    place: result.title
                )
            }
            guard CLLocationCoordinate2DIsValid(coordinate),
                  coordinate.latitude.isFinite,
                  coordinate.longitude.isFinite else {
                throw CitySearchResolutionError.invalidCoordinate(
                    place: result.title
                )
            }

            let candidate = CitySearchPlaceCandidate(
                // `locality` is the strongest city field. Some valid island
                // results (for example Kiritimati) omit it even though the
                // exact Apple Maps result the person selected supplies a
                // factual place title. Retain that provider metadata rather
                // than inventing a name from the typed query or a nearby city.
                cityName: cleanProviderValue(item.placemark.locality)
                    ?? cleanProviderValue(item.name)
                    ?? cleanProviderValue(result.title),
                country: cleanProviderValue(
                    item.placemark.country ?? item.placemark.isoCountryCode
                ),
                coordinate: coordinate,
                timeZoneIdentifier: cleanProviderValue(
                    item.placemark.timeZone?.identifier
                )
            )

            try Task.checkCancellation()
            return try await resolvedPlace(
                from: candidate,
                resultTitle: result.title
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch let resolutionError as CitySearchResolutionError {
            throw resolutionError
        } catch {
            throw CitySearchResolutionError.providerFailed(
                provider: .appleMaps,
                place: result.title,
                reason: error.localizedDescription
            )
        }
    }

    /// Uses Core Location only to fill concrete fields missing from a provider
    /// result for the exact coordinate; it never promotes region text or a
    /// search query into a city name.
    private func resolvedPlace(
        from candidate: CitySearchPlaceCandidate,
        resultTitle: String
    ) async throws -> CitySearchResolvedPlace {
        guard let coordinate = candidate.coordinate,
              CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            return try validatedPlace(candidate, resultTitle: resultTitle)
        }

        guard candidate.cityName == nil
            || candidate.country == nil
            || validTimeZoneIdentifier(candidate.timeZoneIdentifier) == nil else {
            return try validatedPlace(candidate, resultTitle: resultTitle)
        }

        var completedCandidate = candidate
        do {
            if let placemark = try await CLGeocoder()
                .reverseGeocodeLocation(
                    CLLocation(
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ),
                    preferredLocale: currentLocale
                )
                .first {
                completedCandidate = CitySearchPlaceCandidate(
                    cityName: candidate.cityName
                        ?? cleanProviderValue(placemark.locality),
                    country: candidate.country
                        ?? cleanProviderValue(
                            placemark.country ?? placemark.isoCountryCode
                        ),
                    coordinate: coordinate,
                    timeZoneIdentifier: validTimeZoneIdentifier(
                        candidate.timeZoneIdentifier
                    ) ?? validTimeZoneIdentifier(placemark.timeZone?.identifier)
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Preserve provider facts and let strict validation name the exact
            // remaining field. The outer Apple-resolution retry will make one
            // more source attempt before a selection alert is produced.
        }
        try Task.checkCancellation()
        return try validatedPlace(completedCandidate, resultTitle: resultTitle)
    }

    private func validatedPlace(
        _ candidate: CitySearchPlaceCandidate,
        resultTitle: String
    ) throws -> CitySearchResolvedPlace {
        guard let coordinate = candidate.coordinate else {
            throw CitySearchResolutionError.coordinateMissing(
                place: resultTitle
            )
        }
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite else {
            throw CitySearchResolutionError.invalidCoordinate(
                place: resultTitle
            )
        }
        guard let cityName = cleanProviderValue(candidate.cityName) else {
            throw CitySearchResolutionError.cityNameMissing(
                place: resultTitle
            )
        }
        guard let country = cleanProviderValue(candidate.country) else {
            throw CitySearchResolutionError.countryMissing(
                place: resultTitle
            )
        }
        guard let suppliedTimeZone = cleanProviderValue(
            candidate.timeZoneIdentifier
        ) else {
            throw CitySearchResolutionError.timeZoneMissing(
                place: resultTitle
            )
        }
        guard let timeZoneIdentifier = validTimeZoneIdentifier(
            suppliedTimeZone
        ) else {
            throw CitySearchResolutionError.invalidTimeZone(
                place: resultTitle,
                identifier: suppliedTimeZone
            )
        }
        return CitySearchResolvedPlace(
            cityName: cityName,
            country: country,
            coordinate: coordinate,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    private func cleanProviderValue(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func validTimeZoneIdentifier(_ identifier: String?) -> String? {
        guard let identifier = cleanProviderValue(identifier),
              TimeZone(identifier: identifier) != nil else {
            return nil
        }
        return identifier
    }

    /// Delegate callback from Apple Maps. Filtering again protects against a
    /// broad completion list and limits UI/network work to five suggestions.
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
        let query = currentQuery
        guard !query.isEmpty else { return }
        guard !hasRetriedAppleQuery else {
            appleResults = []
            isAppleSearching = false
            appleErrorMessage = error.localizedDescription
            return
        }

        hasRetriedAppleQuery = true
        appleResults = []
        appleErrorMessage = nil
        isAppleSearching = true
        appleRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  self.currentQuery == query else {
                return
            }
            // Clearing then restoring the fragment starts a genuinely new
            // completion request instead of replaying the failed callback.
            self.completer.queryFragment = ""
            await Task.yield()
            guard !Task.isCancelled,
                  self.currentQuery == query else {
                return
            }
            self.completer.queryFragment = query
        }
    }

    /// Open-Meteo accepts only queries of two or more characters. Comparing
    /// `currentQuery` after suspension prevents stale results overwriting newer
    /// typing, even if cancellation arrives late.
    private func searchOpenMeteo(query: String, locale: Locale) async {
        guard query.count >= 2 else {
            if currentQuery == query {
                isOpenMeteoSearching = false
            }
            return
        }

        do {
            let results = try await fetchOpenMeteoResultsWithOneRetry(
                query: query,
                language: openMeteoLanguage(for: locale)
            )
            guard !Task.isCancelled, currentQuery == query else { return }
            // Keep incomplete provider rows visible. Selection validates every
            // required field and throws an exact missing-data error for the
            // screen's native alert instead of silently dropping the row.
            openMeteoResults = results.map(CitySearchResult.init(openMeteo:))
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

    /// Searches the provider once more before an unavailable result reaches
    /// the UI's native missing-data alert. Cancellation is never retried.
    private func fetchOpenMeteoResultsWithOneRetry(
        query: String,
        language: String
    ) async throws -> [OpenMeteoGeocodingResult] {
        do {
            return try await fetchOpenMeteoResults(
                query: query,
                language: language
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await Task.sleep(for: .milliseconds(250))
            try Task.checkCancellation()
            return try await fetchOpenMeteoResults(
                query: query,
                language: language
            )
        }
    }

    /// Encodes the provider request with `URLComponents`, then validates the
    /// HTTP status before attempting Codable decoding.
    private func fetchOpenMeteoResults(
        query: String,
        language: String
    ) async throws -> [OpenMeteoGeocodingResult] {
        // Use URLComponents so punctuation and non-Latin city names are safely
        // percent-encoded rather than interpolated directly into a URL string.
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

    /// The persisted app language takes priority over the device locale. A few
    /// language tags use Open-Meteo's provider-specific regional spellings.
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
