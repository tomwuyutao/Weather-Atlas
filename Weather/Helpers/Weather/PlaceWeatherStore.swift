//
//  PlaceWeatherStore.swift
//  Weather
//
//  Purpose: Owns weather snapshots for stable saved, current-location, and
//  transient search place identities without coupling loading to a list.
//
//  Reading guide: this is the app's forecast repository. It first restores a
//  disposable cache, then coordinates per-city WeatherKit requests so screens
//  can share work, avoid stale responses, and never exceed four live requests.
//

import Foundation
import Observation
import WeatherKit

/// A recoverable loading problem associated with one place.
/// The failure is keyed by city ID instead of thrown through every list, so one
/// unavailable forecast can show a local message while other cities still load.
struct PlaceWeatherFailure: Identifiable, Equatable {
    /// Stable place identity.
    let id: City.ID
    /// Place name retained even when no weather snapshot can be rendered.
    let cityName: String
    /// Exact service/data issue used by native alert presentation.
    let issue: WeatherDataIssue
    /// User-facing explanation suitable for native alerts and content states.
    /// Kept for compatibility while views migrate to the structured `issue`.
    let message: String
}

/// Observable forecast repository keyed by stable place identity.
///
/// It is `@MainActor` because published dictionaries/sets drive SwiftUI. Network
/// calls suspend while in flight; actor isolation still prevents two completion
/// handlers from mutating the same place state at the same instant.
@MainActor
@Observable
final class PlaceWeatherStore {
    // MARK: - Observable Forecast State

    /// Latest usable forecast snapshot for each stable place identity.
    private(set) var weatherByID: [City.ID: CityWeather] = [:]
    /// Place identities with an in-flight WeatherKit request.
    private(set) var loadingIDs: Set<City.ID> = []
    /// Most recent failed refresh for each place.
    private(set) var failuresByID: [City.ID: PlaceWeatherFailure] = [:]
    /// Missing optional fields retained alongside otherwise usable snapshots.
    /// Fatal failures are also represented in `failuresByID`; this dictionary
    /// gives alert orchestration one uniform source of structured issues.
    private(set) var issuesByID: [City.ID: [WeatherDataIssue]] = [:]
    /// Explicit render revision ensures refreshed same-ID snapshots invalidate
    /// consumers even though CityWeather's Hashable identity is place-based.
    private(set) var weatherRevision = 0
    /// Apple Weather attribution shown in Settings alongside every data source.
    private(set) var weatherAttribution: WeatherAttribution?
    /// Shared reachability state avoids replacing a useful cache while offline.
    private let networkConnectivity: NetworkConnectivity

    // MARK: - Internal Dependencies and Concurrency State

    /// WeatherKit adapter shared by every place-based app experience.
    private let weatherService: WeatherService
    /// File-backed cache used to render useful results before a network refresh.
    private let cache: PlaceWeatherSnapshotCache
    /// Current request identity for each place. Replacing a token makes any
    /// older overlapping refresh harmless when it eventually returns.
    @ObservationIgnored private var requestTokens: [City.ID: UUID] = [:]
    /// Coalesced per-place work shared by app views and widgets.
    @ObservationIgnored
    private var inFlightByID: [
        City.ID: (token: UUID, task: Task<CityWeather?, Never>)
    ] = [:]
    /// Actor-isolated gate enforcing four concurrent WeatherKit requests.
    /// Unlike a thread semaphore, these continuations suspend async tasks rather
    /// than blocking the main actor while waiting for a network slot.
    @ObservationIgnored private var activeRequests = 0
    @ObservationIgnored
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    /// Successful refresh time for each place, so one newly fetched city cannot
    /// make every other cached city appear fresh.
    @ObservationIgnored private var refreshDatesByPlaceID: [City.ID: Date] = [:]

    // MARK: - Initialization and Cache Restoration

    /// Creates a place-keyed repository and restores its current cache format.
    /// The cache makes the first render useful offline, but it never prevents a
    /// later refresh when a specific city's own freshness timestamp has expired.
    init(
        weatherService: WeatherService,
        cache: PlaceWeatherSnapshotCache,
        networkConnectivity: NetworkConnectivity
    ) {
        self.weatherService = weatherService
        self.cache = cache
        self.networkConnectivity = networkConnectivity

        if let snapshot = cache.load() {
            // A dictionary assignment safely handles duplicate IDs in an old or
            // corrupt cache. The last complete record wins instead of crashing.
            for weather in snapshot.weather {
                // Optional presentation gaps stay available as cached weather.
                // The specific card that needs a field explains its absence.
                weatherByID[weather.id] = weather
            }
            refreshDatesByPlaceID = snapshot.refreshDatesByPlaceID.filter {
                weatherByID[$0.key] != nil
            }
        }
    }

    /// Convenience used by the live app while preserving main-actor creation of
    /// the WeatherKit service.
    convenience init(networkConnectivity: NetworkConnectivity) {
        self.init(
            weatherService: WeatherService(),
            cache: PlaceWeatherSnapshotCache(),
            networkConnectivity: networkConnectivity
        )
    }

    /// Isolated repository used by Xcode previews. Its cache is intentionally
    /// in memory so opening a canvas never reads or writes user forecast data.
    static func preview(
        networkConnectivity: NetworkConnectivity
    ) -> PlaceWeatherStore {
        PlaceWeatherStore(
            weatherService: WeatherService(),
            cache: .preview,
            networkConnectivity: networkConnectivity
        )
    }

    // MARK: - Public Forecast Access

    /// Returns the latest usable weather for a stable place identity.
    /// Reading `weatherRevision` intentionally establishes an Observation
    /// dependency even when `CityWeather` equality/identity stays place-based.
    func weather(for placeID: City.ID) -> CityWeather? {
        _ = weatherRevision
        return weatherByID[placeID]
    }

    /// Whether one place is currently waiting for a WeatherKit response.
    func isLoading(_ placeID: City.ID) -> Bool {
        loadingIDs.contains(placeID)
    }

    /// Structured partial or fatal issues for one place.
    func issues(for placeID: City.ID) -> [WeatherDataIssue] {
        issuesByID[placeID] ?? []
    }

    /// The newest retained forecast timestamp supports the shared offline copy.
    var latestCachedWeatherDate: Date? {
        _ = weatherRevision
        return refreshDatesByPlaceID.values.max()
    }

    /// Resolves one city through the same cache and in-flight coalescing as
    /// bulk loads.
    func lookup(
        city: City,
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async -> CityWeather? {
        // Offline mode reads the last cached value regardless of its normal
        // 30-minute freshness window; the root banner makes its age explicit.
        guard !networkConnectivity.isOffline else {
            return weatherByID[city.id]
        }
        await loadAttributionIfNeeded()

        // If another screen has already started the same city request, await that
        // task instead of spending a second WeatherKit quota/network request.
        if !forceRefresh,
           let existing = inFlightByID[city.id] {
            return await existing.task.value
        }

        // Fresh data is returned immediately. Freshness is per place, so London
        // being refreshed does not accidentally make Paris appear current too.
        if !forceRefresh, !shouldRefresh(placeID: city.id) {
            return weatherByID[city.id]
        }

        return await startRequest(
            for: city,
            locale: locale,
            supersedingExisting: forceRefresh
        ).value
    }

    /// Loads missing or stale places without disturbing independent consumers.
    ///
    /// Your Location, Map, Places, Search, and detail can request forecasts at once. A
    /// normal overlapping load coalesces with the request already
    /// represented by `loadingIDs`; a forced refresh supersedes only the
    /// matching place through its per-place request token.
    func load(
        cities: [City],
        forceRefresh: Bool = false,
        locale: Locale = .autoupdatingCurrent
    ) async {
        // Preserve caller order while removing repeated IDs so batch requests and
        // the UI's loading state each represent one task per actual place.
        let uniqueCities = deduplicated(cities)
        guard !uniqueCities.isEmpty else { return }

        // Do not begin a blanking refresh without a viable network path.
        guard !networkConnectivity.isOffline else { return }

        await loadAttributionIfNeeded()

        var tasks: [Task<CityWeather?, Never>] = []
        for city in uniqueCities {
            if !forceRefresh,
               let existing = inFlightByID[city.id] {
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
                    supersedingExisting: forceRefresh
                )
            )
        }

        // Await all started/coalesced tasks. They were created before this loop,
        // so requests can run concurrently up to the internal four-slot limit.
        for task in tasks {
            _ = await task.value
        }

        // A forced refresh from another screen can supersede one of the tasks
        // captured above while this batch is suspended. Await the task that
        // currently owns each city as well, so callers never resume in the
        // cancellation gap and mistake an actively replacing request for
        // silently missing weather.
        for city in uniqueCities {
            await awaitCurrentRequest(for: city.id)
        }
    }

    /// Refreshes one place immediately, preserving its stable saved identity.
    /// `supersedingExisting: true` gives an explicit pull-to-refresh precedence
    /// over an older background request for this one city only.
    @discardableResult
    func refresh(
        city: City,
        locale: Locale = .autoupdatingCurrent
    ) async -> CityWeather? {
        guard !networkConnectivity.isOffline else {
            return weatherByID[city.id]
        }
        await loadAttributionIfNeeded()
        return await startRequest(
            for: city,
            locale: locale,
            supersedingExisting: true
        ).value
    }

    /// Starts a new, blank-first missing-data recovery episode for one place.
    ///
    /// The normal lookup, batch load, and refresh paths already perform one
    /// response-level repair fetch automatically. This API is for an explicit
    /// user-initiated retry after the final result remained incomplete; it never
    /// reuses a stale snapshot and it still limits that new episode to one repair
    /// fetch before exposing its final issue.
    @discardableResult
    func retryMissingData(
        for city: City,
        locale: Locale = .autoupdatingCurrent
    ) async -> CityWeather? {
        await refresh(city: city, locale: locale)
    }

    /// Batch form of the explicit recovery API. Each stable city identity is
    /// deduplicated and receives the same blank-first, one-repair-attempt policy
    /// as an individual lookup.
    func retryMissingData(
        for cities: [City],
        locale: Locale = .autoupdatingCurrent
    ) async {
        await load(cities: cities, forceRefresh: true, locale: locale)
    }

    /// Cancels obsolete work while preserving decoded snapshots as offline
    /// history. Normal navigation must not erase last-known weather.
    func retainWeather(for placeIDs: Set<City.ID>) {
        // Request/failure bookkeeping follows the active route scope. Weather
        // snapshots and refresh dates deliberately remain available offline.
        loadingIDs.formIntersection(placeIDs)
        failuresByID = failuresByID.filter { placeIDs.contains($0.key) }
        issuesByID = issuesByID.filter { placeIDs.contains($0.key) }
        requestTokens = requestTokens.filter {
            placeIDs.contains($0.key)
        }
        // Cancellation is cooperative, so token checks in `performRequest` still
        // protect state if WeatherKit returns after this task has been cancelled.
        for (placeID, request) in inFlightByID
        where !placeIDs.contains(placeID) {
            request.task.cancel()
        }
        inFlightByID = inFlightByID.filter {
            placeIDs.contains($0.key)
        }
    }

    /// Deletes all cached weather only for an explicit full app reset.
    func clearAllWeather() {
        weatherByID = [:]
        loadingIDs = []
        failuresByID = [:]
        issuesByID = [:]
        requestTokens = [:]
        inFlightByID.values.forEach { $0.task.cancel() }
        inFlightByID = [:]
        refreshDatesByPlaceID = [:]
        weatherRevision &+= 1
        cache.remove()
    }

    /// Loads Apple Weather's legal mark and link once per app process.
    /// Attribution is independent of a forecast request and failures are benign:
    /// the app can show weather even if the legal image/link arrives later.
    func loadAttributionIfNeeded() async {
        guard weatherAttribution == nil else { return }
        weatherAttribution = try? await weatherService.weatherKitService.attribution
    }

    // MARK: - Per-Place Request Lifecycle

    /// Starts one place-owned request, optionally replacing only that place's
    /// earlier work. The task commits and cleans itself so every caller can
    /// safely await the same result.
    private func startRequest(
        for city: City,
        locale: Locale,
        supersedingExisting: Bool
    ) -> Task<CityWeather?, Never> {
        // Forced refresh replaces only this city's task. A normal lookup instead
        // reuses it, which is the per-place coalescing policy described above.
        if supersedingExisting {
            inFlightByID[city.id]?.task.cancel()
        } else if let existing = inFlightByID[city.id] {
            return existing.task
        }

        // The UUID token is the ownership proof used after every `await`. Once a
        // newer request replaces it, an older completion may return but cannot
        // write weather, failure, or loading state for the place.
        let requestToken = beginRequest(for: city.id)
        // This task inherits MainActor isolation so its bookkeeping accesses are
        // safe. `await weatherService...` still suspends rather than blocking UI.
        let task: Task<CityWeather?, Never> = Task { @MainActor [weak self] in
            guard let self else { return nil }
            return await self.performRequest(
                for: city,
                token: requestToken,
                locale: locale
            )
        }
        inFlightByID[city.id] = (
            token: requestToken,
            task: task
        )
        return task
    }

    /// Executes one WeatherKit request behind the shared four-request gate.
    /// The `defer` block runs on every return path, including cancellation and
    /// service failure, so a failed request cannot leak a slot or spinner.
    private func performRequest(
        for city: City,
        token: UUID,
        locale: Locale
    ) async -> CityWeather? {
        // On a failed refresh, return this retained value so callers do not
        // replace a useful report with an empty state.
        let cachedWeather = weatherByID[city.id]
        await acquireRequestSlot()
        defer {
            releaseRequestSlot()
            finishRequest(for: city.id, token: token)
            if inFlightByID[city.id]?.token == token {
                inFlightByID[city.id] = nil
            }
        }

        // Check both generic task cancellation and the per-place token. Task
        // cancellation is cooperative; the token is what blocks stale results.
        guard !Task.isCancelled,
              isCurrentRequest(for: city.id, token: token) else {
            return nil
        }

        let response: WeatherServiceResponse
        do {
            response = try await fetchResponseWithOneMissingDataRepair(city)
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled,
                  isCurrentRequest(for: city.id, token: token) else {
                return nil
            }
            let issue: WeatherDataIssue
            if let serviceError = error as? WeatherServiceError {
                issue = serviceError.dataIssue
            } else {
                issue = .weatherRequestFailed(error.localizedDescription)
            }
            // Retain the older snapshot and record why it could not refresh.
            issuesByID[city.id] = [issue]
            failuresByID[city.id] = PlaceWeatherFailure(
                id: city.id,
                cityName: city.displayName,
                issue: issue,
                message: missingWeatherMessage(
                    cityName: city.displayName,
                    locale: locale
                )
            )
            weatherRevision &+= 1
            persistSnapshot()
            return cachedWeather
        }

        guard !Task.isCancelled,
              isCurrentRequest(for: city.id, token: token) else {
            return nil
        }

        // Commit only after the second ownership check. Incrementing the separate
        // revision forces dependent SwiftUI views to redraw a same-ID replacement.
        weatherByID[city.id] = response.weather
        // Wrapping addition makes this monotonic render signal safe even after
        // an impractically large number of refreshes; its exact numeric value is
        // never displayed or used as a business value.
        weatherRevision &+= 1
        failuresByID[city.id] = nil
        issuesByID[city.id] = completeResponseIssues(for: response)
        recordRefresh(for: city.id)
        persistSnapshot()
        return response.weather
    }

    // MARK: - Request-Concurrency Gate

    /// Suspends excess place requests without blocking the main actor.
    private func acquireRequestSlot() async {
        if activeRequests < 4 {
            activeRequests += 1
            return
        }
        // Store the continuation FIFO. A later `resume()` transfers the released
        // slot directly to this task, so activeRequests does not change here.
        await withCheckedContinuation { continuation in
            slotWaiters.append(continuation)
        }
    }

    /// Hands a completed request's slot directly to the next waiter.
    /// If nobody waits, decrement the count; otherwise the resumed task takes
    /// over the existing slot and the count remains exactly four.
    private func releaseRequestSlot() {
        if slotWaiters.isEmpty {
            activeRequests = max(0, activeRequests - 1)
        } else {
            slotWaiters.removeFirst().resume()
        }
    }

    // MARK: - Freshness and Request Ownership

    /// Applies the 30-minute refresh window independently to each place.
    /// A future timestamp is corrupt/clock-skewed metadata, never proof that a
    /// snapshot is fresh. A response that was complete when it arrived can also
    /// become incomplete at a destination-local midnight, when its ten-day
    /// horizon no longer starts on today; detect that newly created issue before
    /// a view gets a chance to alert. A response that already exhausted its one
    /// repair attempt stays settled until the normal freshness window or an
    /// explicit user retry, preventing a redraw-driven retry loop.
    private func shouldRefresh(placeID: City.ID, now: Date = Date()) -> Bool {
        guard let weather = weatherByID[placeID],
              let refreshDate = refreshDatesByPlaceID[placeID] else {
            return true
        }
        let age = now.timeIntervalSince(refreshDate)
        guard age >= 0, age < 30 * 60 else {
            return true
        }
        guard issuesByID[placeID, default: []].isEmpty else {
            return false
        }
        return !completeResponseIssues(for: weather).isEmpty
    }

    /// Starts a request and makes it the only request allowed to mutate the
    /// place's weather, failure, and loading state.
    private func beginRequest(for placeID: City.ID) -> UUID {
        let requestToken = UUID()
        requestTokens[placeID] = requestToken
        loadingIDs.insert(placeID)
        // Keep the last good snapshot until a successful replacement arrives.
        // A failed request must not turn cached weather into a blank report.
        failuresByID[placeID] = nil
        issuesByID[placeID] = nil
        weatherRevision &+= 1
        persistSnapshot()
        return requestToken
    }

    /// Compatibility copy for existing views. New alert presenters should use
    /// `PlaceWeatherFailure.issue` and the centralized issue-message formatter.
    private func missingWeatherMessage(
        cityName: String,
        locale: Locale
    ) -> String {
        String(
            format: localizedString(
                "Missing weather data for %@.",
                locale: locale
            ),
            locale: locale,
            cityName
        )
    }

    /// Fetches one response and makes exactly one fresh repair request whenever
    /// that first source attempt fails or proves incomplete. Both attempts
    /// deliberately disable the adapter's independent transient-network retry,
    /// so this store owns one bounded two-source-attempt episode rather than
    /// multiplying retries at two layers.
    private func fetchResponseWithOneMissingDataRepair(
        _ city: City
    ) async throws -> WeatherServiceResponse {
        let initialResponse: WeatherServiceResponse
        do {
            initialResponse = try await weatherService.fetchWeatherForCity(
                city,
                retriesOnFailure: false
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // A typed WeatherService error and an ordinary request failure are
            // both a failed source attempt. Keep the presentation blank and make
            // the single repair attempt required before an alert can surface.
            try Task.checkCancellation()
            return try await weatherService.fetchWeatherForCity(
                city,
                retriesOnFailure: false
            )
        }

        guard !completeResponseIssues(for: initialResponse).isEmpty else {
            return initialResponse
        }

        // A provider response can arrive successfully while omitting one of the
        // values needed by a chart or ranking. Keep the UI blank and make exactly
        // one fresh request before committing any incomplete result.
        try Task.checkCancellation()
        return try await weatherService.fetchWeatherForCity(
            city,
            retriesOnFailure: false
        )
    }

    /// Whether a suspended fetch still owns the place it was started for.
    private func isCurrentRequest(
        for placeID: City.ID,
        token: UUID
    ) -> Bool {
        requestTokens[placeID] == token
    }

    /// Clears loading state only when the finishing request still owns it.
    /// A superseded task must not clear the spinner belonging to its replacement.
    private func finishRequest(
        for placeID: City.ID,
        token: UUID
    ) {
        guard isCurrentRequest(for: placeID, token: token) else { return }
        requestTokens[placeID] = nil
        loadingIDs.remove(placeID)
    }

    /// Records successful freshness without affecting any other place.
    private func recordRefresh(
        for placeID: City.ID,
        at date: Date = Date()
    ) {
        refreshDatesByPlaceID[placeID] = date
    }

    /// Applies general forecast-structure validation. `ForecastValidation` owns
    /// the response-level policy; the rolling hourly series is deliberately
    /// inspected only by the feature that consumes it.
    private func completeResponseIssues(
        for response: WeatherServiceResponse
    ) -> [WeatherDataIssue] {
        ForecastValidation.responseDataIssues(for: response.weather)
    }

    /// Convenience used for legacy cache validation before a WeatherServiceResponse
    /// exists. Keeping it on the same path avoids a cold launch treating a stale
    /// incomplete snapshot more generously than a live response.
    private func completeResponseIssues(
        for weather: CityWeather
    ) -> [WeatherDataIssue] {
        ForecastValidation.responseDataIssues(for: weather)
    }

    /// Keeps the first occurrence of each stable identity in user-visible order.
    /// `Set.insert(...).inserted` provides a compact stable-order deduplication
    /// pattern: true only for each ID's first encounter.
    private func deduplicated(_ cities: [City]) -> [City] {
        var seen: Set<City.ID> = []
        return cities.filter { seen.insert($0.id).inserted }
    }

    /// Follows request ownership until the latest task for one city settles.
    /// Tokens normally advance at most once here; the set also guarantees a
    /// corrupt/reintroduced entry cannot make a batch wait forever.
    private func awaitCurrentRequest(for placeID: City.ID) async {
        var awaitedTokens: Set<UUID> = []
        while let request = inFlightByID[placeID],
              awaitedTokens.insert(request.token).inserted {
            _ = await request.task.value
        }
    }

    // MARK: - Cache Write-Through

    /// Writes every structurally valid snapshot. Offline mode can present old
    /// data, so optional response gaps must not discard the last known forecast.
    private func persistSnapshot() {
        let snapshot = PlaceWeatherSnapshot(
            weather: Array(weatherByID.values),
            refreshDatesByPlaceID: refreshDatesByPlaceID.filter {
                weatherByID[$0.key] != nil
            }
        )
        cache.save(snapshot)
    }
}

// MARK: - Disposable Forecast Cache

/// Codable file representation for the place-keyed forecast cache.
/// This is the in-memory form returned by the cache; its separate `Document`
/// type below contains only JSON-compatible cached forecast snapshots.
struct PlaceWeatherSnapshot {
    /// Decoded domain values.
    let weather: [CityWeather]
    /// Independent freshness timestamp for every decoded place.
    let refreshDatesByPlaceID: [City.ID: Date]
}

/// Disposable, atomic cache stored below the system Caches directory.
/// Caches may be purged by iOS at any time, unlike Saved Places in Application
/// Support, so every failure in this type is deliberately recoverable.
@MainActor
struct PlaceWeatherSnapshotCache {
    /// Versioned file format so incompatible forecast snapshots can be discarded.
    /// UUID dictionary keys become `String` because JSON object keys are strings.
    private struct Document: Codable {
        let schemaVersion: Int
        let weather: [CachedCityWeather]
        let refreshDatesByPlaceID: [String: Date]
    }

    /// Current cache schema.
    private static let schemaVersion = 3
    /// Dedicated snapshot file.
    private let fileURL: URL?

    /// Locates the cache without turning a missing directory into app failure.
    /// A nil URL simply turns cache reads/writes into no-ops; fresh WeatherKit
    /// requests continue to work normally.
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

    /// Keeps Xcode previews isolated from the on-device forecast cache.
    static var preview: PlaceWeatherSnapshotCache {
        PlaceWeatherSnapshotCache(fileURL: nil)
    }

    /// Internal construction used when a caller deliberately wants a cache
    /// that has no backing file, such as a self-contained SwiftUI preview.
    private init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// Restores only valid current-schema snapshots. A malformed city is dropped
    /// independently so it cannot erase unrelated honest cached forecasts.
    func load() -> PlaceWeatherSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == Self.schemaVersion else {
            return nil
        }

        // Each cached city validates its own timezone and nested forecasts.
        let decodedWeather = document.weather.compactMap { $0.toCityWeather() }

        var weatherByID: [City.ID: CityWeather] = [:]
        var placeOrder: [City.ID] = []
        // Be defensive about duplicate IDs in a cache from an earlier version:
        // preserve first-seen display order, while its final complete snapshot
        // replaces the dictionary value without triggering a duplicate-key trap.
        for weather in decodedWeather {
            if weatherByID[weather.id] == nil {
                placeOrder.append(weather.id)
            }
            // Keep the last complete duplicate instead of trapping in
            // Dictionary(uniqueKeysWithValues:).
            weatherByID[weather.id] = weather
        }
        var refreshDatesByPlaceID: [City.ID: Date] = [:]
        // A date is presentation metadata, not a validity deadline. Retain old
        // timestamps so the app can show cached forecasts offline with an
        // honest “Last updated” value. Future timestamps remain corrupt.
        for (rawPlaceID, refreshDate) in document.refreshDatesByPlaceID {
            guard let placeID = UUID(uuidString: rawPlaceID),
                  refreshDate <= .now else {
                continue
            }
            refreshDatesByPlaceID[placeID] = refreshDate
        }

        let weather = placeOrder.compactMap { weatherByID[$0] }
        let retainedIDs = Set(weather.map(\.id))
        refreshDatesByPlaceID = refreshDatesByPlaceID.filter {
            retainedIDs.contains($0.key)
        }

        return PlaceWeatherSnapshot(
            weather: weather,
            refreshDatesByPlaceID: refreshDatesByPlaceID
        )
    }

    /// Atomically replaces the disposable snapshot.
    /// Cache writes intentionally do not escape errors: a forecast already in
    /// memory remains valid even if the device declines to write its cache file.
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
            // File `Data.WritingOptions.atomic` prevents an interrupted cache
            // write from replacing a good previous snapshot with partial bytes.
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

    /// Removes the on-disk snapshot after the person explicitly resets the app.
    func remove() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
