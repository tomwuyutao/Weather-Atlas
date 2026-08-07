//
//  PlaceWeatherStore.swift
//  Weather
//
//  Purpose: Owns weather snapshots for stable saved, current-location, and
//  transient search place identities without coupling loading to a list.
//

import Foundation
import Observation
import WeatherKit

/// A recoverable loading problem associated with one place.
struct PlaceWeatherFailure: Identifiable, Equatable {
    /// Stable place identity.
    let id: City.ID
    /// User-facing explanation suitable for native alerts and content states.
    let message: String
}

/// Observable forecast repository keyed by stable place identity.
@MainActor
@Observable
final class PlaceWeatherStore {
    /// Latest usable forecast snapshot for each stable place identity.
    private(set) var weatherByPlaceID: [City.ID: CityWeather] = [:]
    /// Place identities with an in-flight WeatherKit request.
    private(set) var loadingPlaceIDs: Set<City.ID> = []
    /// Most recent failed refresh for each place.
    private(set) var failuresByPlaceID: [City.ID: PlaceWeatherFailure] = [:]
    /// Explicit render revision ensures refreshed same-ID snapshots invalidate
    /// consumers even though CityWeather's Hashable identity is place-based.
    private(set) var weatherRevision = 0
    /// Apple Weather attribution shown in Settings alongside every data source.
    private(set) var weatherAttribution: WeatherAttribution?

    /// WeatherKit adapter shared by every place-based app experience.
    private let weatherService: WeatherService
    /// File-backed cache used to render useful results before a network refresh.
    private let cache: PlaceWeatherSnapshotCache
    /// Current request identity for each place. Replacing a token makes any
    /// older overlapping refresh harmless when it eventually returns.
    @ObservationIgnored private var requestTokensByPlaceID: [City.ID: UUID] = [:]
    /// Coalesced per-place work shared by app views and widgets.
    @ObservationIgnored
    private var inFlightRequestsByPlaceID: [
        City.ID: (token: UUID, task: Task<CityWeather?, Never>)
    ] = [:]
    /// Actor-isolated gate enforcing four concurrent WeatherKit requests.
    @ObservationIgnored private var activeRequestCount = 0
    @ObservationIgnored
    private var requestSlotWaiters: [CheckedContinuation<Void, Never>] = []
    /// Successful refresh time for each place, so one newly fetched city cannot
    /// make every other cached city appear fresh.
    @ObservationIgnored private var refreshDatesByPlaceID: [City.ID: Date] = [:]

    /// Creates a place-keyed repository and restores its current cache format.
    init(
        weatherService: WeatherService,
        cache: PlaceWeatherSnapshotCache
    ) {
        self.weatherService = weatherService
        self.cache = cache

        if let snapshot = cache.load() {
            for weather in snapshot.weather {
                // Assignment deliberately makes corrupt duplicate identities safe.
                weatherByPlaceID[weather.id] = weather
            }
            refreshDatesByPlaceID = snapshot.refreshDatesByPlaceID.filter {
                weatherByPlaceID[$0.key] != nil
            }
        }
    }

    /// Convenience used by the live app while preserving main-actor creation of
    /// the WeatherKit service.
    convenience init() {
        self.init(
            weatherService: WeatherService(),
            cache: PlaceWeatherSnapshotCache()
        )
    }

    /// Returns the latest usable weather for a stable place identity.
    func weather(for placeID: City.ID) -> CityWeather? {
        _ = weatherRevision
        return weatherByPlaceID[placeID]
    }

    /// Whether one place is currently waiting for a WeatherKit response.
    func isLoading(_ placeID: City.ID) -> Bool {
        loadingPlaceIDs.contains(placeID)
    }

    /// Resolves one city through the same cache and in-flight coalescing as
    /// bulk loads.
    func lookup(
        city: City,
        forceRefresh: Bool = false,
        retriesOnFailure: Bool = true,
        locale: Locale = .autoupdatingCurrent
    ) async -> CityWeather? {
        await loadAttributionIfNeeded()

        if !forceRefresh,
           let existing = inFlightRequestsByPlaceID[city.id] {
            return await existing.task.value
        }

        if !forceRefresh, !shouldRefresh(placeID: city.id) {
            return weatherByPlaceID[city.id]
        }

        return await startRequest(
            for: city,
            locale: locale,
            supersedingExisting: forceRefresh,
            retriesOnFailure: retriesOnFailure
        ).value
    }

    /// Loads missing or stale places without disturbing independent consumers.
    ///
    /// Home, Map, Places, Search, and detail can request forecasts at once. A
    /// normal overlapping load coalesces with the request already
    /// represented by `loadingPlaceIDs`; a forced refresh supersedes only the
    /// matching place through its per-place request token.
    func load(
        cities: [City],
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        let uniqueCities = deduplicated(cities)
        guard !uniqueCities.isEmpty else { return }

        await loadAttributionIfNeeded()

        var tasks: [Task<CityWeather?, Never>] = []
        for city in uniqueCities {
            if !forceRefresh,
               let existing = inFlightRequestsByPlaceID[city.id] {
                tasks.append(existing.task)
                continue
            }
            guard forceRefresh || shouldRefresh(placeID: city.id) else {
                continue
            }
            tasks.append(
                startRequest(
                    for: city,
                    locale: locale,
                    supersedingExisting: forceRefresh,
                    retriesOnFailure: true
                )
            )
        }

        for task in tasks {
            _ = await task.value
        }
    }

    /// Refreshes one place immediately, preserving its stable saved identity.
    @discardableResult
    func refresh(
        city: City,
        locale: Locale = .autoupdatingCurrent
    ) async -> CityWeather? {
        await loadAttributionIfNeeded()
        return await startRequest(
            for: city,
            locale: locale,
            supersedingExisting: true,
            retriesOnFailure: true
        ).value
    }

    /// Removes snapshots that no longer belong to an explicitly retained
    /// saved or transient identity.
    func retainWeather(for placeIDs: Set<City.ID>) {
        weatherByPlaceID = weatherByPlaceID.filter { placeIDs.contains($0.key) }
        loadingPlaceIDs.formIntersection(placeIDs)
        failuresByPlaceID = failuresByPlaceID.filter { placeIDs.contains($0.key) }
        requestTokensByPlaceID = requestTokensByPlaceID.filter {
            placeIDs.contains($0.key)
        }
        for (placeID, request) in inFlightRequestsByPlaceID
        where !placeIDs.contains(placeID) {
            request.task.cancel()
        }
        inFlightRequestsByPlaceID = inFlightRequestsByPlaceID.filter {
            placeIDs.contains($0.key)
        }
        refreshDatesByPlaceID = refreshDatesByPlaceID.filter {
            placeIDs.contains($0.key)
        }
        persistSnapshot()
    }

    /// Loads Apple Weather's legal mark and link once per app process.
    func loadAttributionIfNeeded() async {
        guard weatherAttribution == nil else { return }
        weatherAttribution = try? await weatherService.weatherKitService.attribution
    }

    /// Starts one place-owned request, optionally replacing only that place's
    /// earlier work. The task commits and cleans itself so every caller can
    /// safely await the same result.
    private func startRequest(
        for city: City,
        locale: Locale,
        supersedingExisting: Bool,
        retriesOnFailure: Bool
    ) -> Task<CityWeather?, Never> {
        if supersedingExisting {
            inFlightRequestsByPlaceID[city.id]?.task.cancel()
        } else if let existing = inFlightRequestsByPlaceID[city.id] {
            return existing.task
        }

        let requestToken = beginRequest(for: city.id)
        failuresByPlaceID[city.id] = nil
        let task: Task<CityWeather?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performRequest(
                for: city,
                token: requestToken,
                retriesOnFailure: retriesOnFailure,
                locale: locale
            )
        }
        inFlightRequestsByPlaceID[city.id] = (
            token: requestToken,
            task: task
        )
        return task
    }

    /// Executes one WeatherKit request behind the shared four-request gate.
    private func performRequest(
        for city: City,
        token: UUID,
        retriesOnFailure: Bool,
        locale: Locale
    ) async -> CityWeather? {
        await acquireRequestSlot()
        defer {
            releaseRequestSlot()
            finishRequest(for: city.id, token: token)
            if inFlightRequestsByPlaceID[city.id]?.token == token {
                inFlightRequestsByPlaceID[city.id] = nil
            }
        }

        guard !Task.isCancelled,
              isCurrentRequest(for: city.id, token: token) else {
            return nil
        }

        guard let fetched = await weatherService.fetchWeatherForCity(
            city,
            retriesOnFailure: retriesOnFailure
        ) else {
            guard !Task.isCancelled,
                  isCurrentRequest(for: city.id, token: token) else {
                return nil
            }
            failuresByPlaceID[city.id] = PlaceWeatherFailure(
                id: city.id,
                message: localizedString(
                    "Weather is temporarily unavailable.",
                    locale: locale
                )
            )
            return nil
        }

        guard !Task.isCancelled,
              isCurrentRequest(for: city.id, token: token) else {
            return nil
        }

        weatherByPlaceID[city.id] = fetched
        weatherRevision &+= 1
        failuresByPlaceID[city.id] = nil
        recordSuccessfulRefresh(for: city.id)
        persistSnapshot()
        return fetched
    }

    /// Suspends excess place requests without blocking the main actor.
    private func acquireRequestSlot() async {
        if activeRequestCount < 4 {
            activeRequestCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            requestSlotWaiters.append(continuation)
        }
    }

    /// Hands a completed request's slot directly to the next waiter.
    private func releaseRequestSlot() {
        if requestSlotWaiters.isEmpty {
            activeRequestCount = max(0, activeRequestCount - 1)
        } else {
            requestSlotWaiters.removeFirst().resume()
        }
    }

    /// Applies the existing 30-minute refresh window independently to each
    /// place. Users still keep stale content if a later request fails.
    private func shouldRefresh(placeID: City.ID, now: Date = Date()) -> Bool {
        guard weatherByPlaceID[placeID] != nil,
              let refreshDate = refreshDatesByPlaceID[placeID] else {
            return true
        }
        return now.timeIntervalSince(refreshDate) >= 30 * 60
    }

    /// Starts a request and makes it the only request allowed to mutate the
    /// place's weather, failure, and loading state.
    private func beginRequest(for placeID: City.ID) -> UUID {
        let requestToken = UUID()
        requestTokensByPlaceID[placeID] = requestToken
        loadingPlaceIDs.insert(placeID)
        return requestToken
    }

    /// Whether a suspended fetch still owns the place it was started for.
    private func isCurrentRequest(
        for placeID: City.ID,
        token: UUID
    ) -> Bool {
        requestTokensByPlaceID[placeID] == token
    }

    /// Clears loading state only when the finishing request still owns it.
    private func finishRequest(
        for placeID: City.ID,
        token: UUID
    ) {
        guard isCurrentRequest(for: placeID, token: token) else { return }
        requestTokensByPlaceID[placeID] = nil
        loadingPlaceIDs.remove(placeID)
    }

    /// Records successful freshness without affecting any other place.
    private func recordSuccessfulRefresh(
        for placeID: City.ID,
        at date: Date = Date()
    ) {
        refreshDatesByPlaceID[placeID] = date
    }

    /// Keeps the first occurrence of each stable identity in user-visible order.
    private func deduplicated(_ cities: [City]) -> [City] {
        var seen: Set<City.ID> = []
        return cities.filter { seen.insert($0.id).inserted }
    }

    /// Writes only complete domain snapshots; persistence failure is recoverable
    /// because WeatherKit remains the source of truth.
    private func persistSnapshot() {
        let snapshot = PlaceWeatherSnapshot(
            weather: Array(weatherByPlaceID.values),
            refreshDatesByPlaceID: refreshDatesByPlaceID
        )
        cache.save(snapshot)
    }
}

/// Codable file representation for the place-keyed forecast cache.
struct PlaceWeatherSnapshot {
    /// Decoded domain values.
    let weather: [CityWeather]
    /// Independent freshness timestamp for every decoded place.
    let refreshDatesByPlaceID: [City.ID: Date]
}

/// Disposable, atomic cache stored below the system Caches directory.
@MainActor
struct PlaceWeatherSnapshotCache {
    /// Versioned file format so incompatible forecast snapshots can be discarded.
    private struct Document: Codable {
        let schemaVersion: Int
        let weather: [CachedCityWeather]
        let refreshDatesByPlaceID: [String: Date]
    }

    /// Current cache schema.
    private static let schemaVersion = 2
    /// Dedicated snapshot file.
    private let fileURL: URL?

    /// Locates the cache without turning a missing directory into app failure.
    init(fileManager: FileManager = .default) {
        let cachesDirectory = try? fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        fileURL = cachesDirectory?
            .appending(path: "WeatherAtlas", directoryHint: .isDirectory)
            .appending(path: "place-weather-v2.json")
    }

    /// Restores current snapshots and silently discards corrupt cache bytes.
    func load() -> PlaceWeatherSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == Self.schemaVersion else {
            return nil
        }

        let decodedWeather = document.weather.compactMap { $0.toCityWeather() }
        guard decodedWeather.count == document.weather.count else { return nil }

        var weatherByPlaceID: [City.ID: CityWeather] = [:]
        var placeOrder: [City.ID] = []
        for weather in decodedWeather {
            if weatherByPlaceID[weather.id] == nil {
                placeOrder.append(weather.id)
            }
            // Keep the last complete duplicate instead of trapping in
            // Dictionary(uniqueKeysWithValues:).
            weatherByPlaceID[weather.id] = weather
        }
        let weather = placeOrder.compactMap { weatherByPlaceID[$0] }

        var refreshDatesByPlaceID: [City.ID: Date] = [:]
        for (rawPlaceID, refreshDate) in document.refreshDatesByPlaceID {
            guard let placeID = UUID(uuidString: rawPlaceID) else { continue }
            refreshDatesByPlaceID[placeID] = refreshDate
        }
        guard weather.allSatisfy({ refreshDatesByPlaceID[$0.id] != nil }) else {
            return nil
        }

        return PlaceWeatherSnapshot(
            weather: weather,
            refreshDatesByPlaceID: refreshDatesByPlaceID
        )
    }

    /// Atomically replaces the disposable snapshot.
    func save(_ snapshot: PlaceWeatherSnapshot) {
        guard let fileURL else { return }
        let document = Document(
            schemaVersion: Self.schemaVersion,
            weather: snapshot.weather.map(CachedCityWeather.init),
            refreshDatesByPlaceID: Dictionary(
                uniqueKeysWithValues: snapshot.refreshDatesByPlaceID.map {
                    ($0.key.uuidString, $0.value)
                }
            )
        )

        do {
            let data = try JSONEncoder().encode(document)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache writes are intentionally non-fatal.
        }
    }
}
