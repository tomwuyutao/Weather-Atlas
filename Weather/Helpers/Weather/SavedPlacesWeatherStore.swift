//
//  SavedPlacesWeatherStore.swift
//  Weather
//
//  Purpose: Owns weather snapshots for stable saved, current-location, and
//  transient search place identities without coupling loading to a list.
//
//  Reading guide: this is the app's forecast repository. It first restores a
//  disposable cache, then coordinates per-city WeatherKit requests so screens
//  can share work, avoid stale responses, and never exceed five live requests.
//

import Foundation
import Observation
import OSLog
import WeatherKit

// MARK: - Forecast Repository

/// A recoverable loading problem associated with one place.
/// The failure is keyed by city ID instead of thrown through every list, so one
/// unavailable forecast can show a local message while other cities still load.
struct PlaceWeatherFailure: Equatable {
    /// Exact service/data issue used by native alert presentation.
    let issue: WeatherDataIssue
}

/// Observable forecast repository keyed by stable place identity.
///
/// It is `@MainActor` because published dictionaries/sets drive SwiftUI. Network
/// calls suspend while in flight; actor isolation still prevents two completion
/// handlers from mutating the same place state at the same instant.
@MainActor
@Observable
final class SavedPlacesWeatherStore {
#if DEBUG
    private static let weatherBatchLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Yutao-Wu.Weather",
        category: "WeatherBatch"
    )
#endif

    // MARK: - Observable Forecast State

    /// Latest usable forecast snapshot for each stable place identity.
    private(set) var weatherByID: [City.ID: CityWeather] = [:]
    /// Place identities with an in-flight WeatherKit request.
    private(set) var loadingIDs: Set<City.ID> = []
    /// Most recent failed request for each place.
    private(set) var failuresByID: [City.ID: PlaceWeatherFailure] = [:]
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
    /// Serial background writer keeps JSON encoding and atomic file replacement
    /// away from SwiftUI's main actor while preserving write/reset ordering.
    private let cacheWriter: PlaceWeatherSnapshotWriter
    /// Current request identity for each place. Replacing a token makes any
    /// older overlapping refresh harmless when it eventually returns.
    @ObservationIgnored private var requestTokens: [City.ID: UUID] = [:]
    /// Coalesced per-place work shared by app views and widgets.
    @ObservationIgnored
    private var inFlightByID: [
        City.ID: (token: UUID, task: Task<CityWeather?, Never>)
    ] = [:]
    /// Actor-isolated gate enforcing five concurrent WeatherKit requests.
    /// Unlike a thread semaphore, these continuations suspend async tasks rather
    /// than blocking the main actor while waiting for a network slot.
    @ObservationIgnored private var activeRequests = 0
    @ObservationIgnored
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []
    /// Successful refresh time for each place, so one newly fetched city cannot
    /// make every other cached city appear fresh.
    @ObservationIgnored private var refreshDatesByPlaceID: [City.ID: Date] = [:]
    /// Cache-only values are built once per changed city. A later persistence
    /// pass can shallow-copy these Sendable records instead of remapping every
    /// daily/hourly value on the main actor.
    @ObservationIgnored
    private var cachedWeatherByID: [City.ID: CachedCityWeather] = [:]
    /// Nested batches defer persistence until the outermost group completes.
    @ObservationIgnored private var cacheBatchDepth = 0
    @ObservationIgnored private var cacheIsDirty = false
    /// Monotonic operation identity prevents a delayed save from overtaking an
    /// explicit reset or a newer snapshot at the background writer.
    @ObservationIgnored private var cacheOperation = 0
    /// Wakes when the earliest retained forecast reaches the hard cache-age
    /// limit, so an app that stays open for a day does not keep rendering it.
    @ObservationIgnored private var cacheExpiryTask: Task<Void, Never>?
    /// Apple Weather attribution loads independently from forecasts. Coalescing
    /// its best-effort task prevents several screens from repeating that request.
    @ObservationIgnored private var attributionLoadTask: Task<Void, Never>?

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
        self.cacheWriter = PlaceWeatherSnapshotWriter(cache: cache)
        self.networkConnectivity = networkConnectivity

        if let snapshot = cache.load() {
            // A dictionary assignment safely handles duplicate IDs in an old or
            // corrupt cache. The last complete record wins instead of crashing.
            for cachedWeather in snapshot.weather {
                guard let weather = cachedWeather.toCityWeather() else {
                    continue
                }
                // Optional presentation gaps stay available as cached weather.
                // The specific card that needs a field explains its absence.
                weatherByID[weather.id] = weather
                cachedWeatherByID[weather.id] = cachedWeather
            }
            refreshDatesByPlaceID = snapshot.refreshDatesByPlaceID.filter {
                weatherByID[$0.key] != nil
            }
        }
        scheduleCacheExpiry()
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
    ) -> SavedPlacesWeatherStore {
        SavedPlacesWeatherStore(
            weatherService: WeatherService(),
            cache: .preview,
            networkConnectivity: networkConnectivity
        )
    }

#if DEBUG
    /// Seeds an in-memory preview repository without starting a WeatherKit
    /// request. This keeps route-level Xcode previews deterministic and
    /// isolated from a person's cached weather data.
    func insertPreviewWeather(_ weather: CityWeather) {
        weatherByID[weather.id] = weather
        refreshDatesByPlaceID[weather.id] = .now
        weatherRevision &+= 1
        scheduleCacheExpiry()
    }
#endif

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

    /// The newest retained forecast timestamp supports the shared offline copy.
    var latestCachedWeatherDate: Date? {
        _ = weatherRevision
        return refreshDatesByPlaceID.values.max()
    }

    /// Resolves one city through the same cache and in-flight coalescing as
    /// bulk loads.
    func lookup(
        city: City,
        forceRefresh: Bool = false
    ) async -> CityWeather? {
        discardExpiredWeather()
        // An unevaluated or confirmed-offline path can reuse a retained forecast
        // beyond the normal 30-minute refresh window, but never beyond the hard
        // one-day limit. The first available-path transition restarts loading.
        guard networkConnectivity.status == .available else {
            return weatherByID[city.id]
        }
        startAttributionLoadIfNeeded()

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
        forceRefresh: Bool = false
    ) async {
#if DEBUG
        let debugStartedAt = Date()
        func debugLog(_ message: String) {
            let elapsed = Date().timeIntervalSince(debugStartedAt)
            let detail = "[WeatherBatch +\(String(format: "%.2f", elapsed))s] \(message)"
            Self.weatherBatchLogger.notice("\(detail, privacy: .public)")
        }
#endif
        discardExpiredWeather()
        // Preserve caller order while removing repeated IDs so batch requests and
        // the UI's loading state each represent one task per actual place.
        let uniqueCities = deduplicated(cities)
        guard !uniqueCities.isEmpty else { return }
#if DEBUG
        debugLog("started for \(uniqueCities.count) cities")
#endif

        // Do not begin a blanking refresh before iOS confirms a viable path.
        // Existing cached snapshots remain untouched in both non-available states.
        guard networkConnectivity.status == .available else { return }

        startAttributionLoadIfNeeded()
        beginCacheBatch()
        defer { endCacheBatch() }

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
                    supersedingExisting: forceRefresh
                )
            )
        }
#if DEBUG
        debugLog("awaiting \(tasks.count) new or coalesced forecast requests")
#endif

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
#if DEBUG
        let availableCount = uniqueCities.count(
            where: { weatherByID[$0.id] != nil }
        )
        let failureKinds = Dictionary(
            grouping: uniqueCities.compactMap { failuresByID[$0.id]?.issue.kind.rawValue },
            by: { $0 }
        )
        let failureSummary = failureKinds
            .map { "\($0.key): \($0.value.count)" }
            .sorted()
            .joined(separator: ", ")
        debugLog(
            "completed: \(availableCount)/\(uniqueCities.count) available; failures: \(failureSummary.isEmpty ? "none" : failureSummary)"
        )
#endif
    }

    /// Refreshes one place immediately, preserving its stable saved identity.
    /// `supersedingExisting: true` gives an explicit pull-to-refresh precedence
    /// over an older background request for this one city only.
    @discardableResult
    func refresh(
        city: City
    ) async -> CityWeather? {
        discardExpiredWeather()
        guard networkConnectivity.status == .available else {
            return weatherByID[city.id]
        }
        startAttributionLoadIfNeeded()
        return await startRequest(
            for: city,
            supersedingExisting: true
        ).value
    }

    /// Starts an explicit user-initiated refresh for one place.
    @discardableResult
    func retryMissingData(
        for city: City
    ) async -> CityWeather? {
        await refresh(city: city)
    }

    /// Batch form of the explicit user-initiated refresh API.
    func retryMissingData(
        for cities: [City]
    ) async {
        await load(cities: cities, forceRefresh: true)
    }

    /// Cancels obsolete work and trims transient forecasts outside the model's
    /// explicit saved/current/search scope. This prevents successive nearby and
    /// map searches from making every later cache write progressively larger.
    func retainWeather(for placeIDs: Set<City.ID>) {
        loadingIDs.formIntersection(placeIDs)
        failuresByID = failuresByID.filter { placeIDs.contains($0.key) }
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

        let removesWeather = weatherByID.keys.contains {
            !placeIDs.contains($0)
        }
        let removesRefreshDates = refreshDatesByPlaceID.keys.contains {
            !placeIDs.contains($0)
        }
        guard removesWeather || removesRefreshDates else { return }

        weatherByID = weatherByID.filter { placeIDs.contains($0.key) }
        cachedWeatherByID = cachedWeatherByID.filter {
            placeIDs.contains($0.key)
        }
        refreshDatesByPlaceID = refreshDatesByPlaceID.filter {
            placeIDs.contains($0.key)
        }
        weatherRevision &+= 1
        markCacheDirty()
        scheduleCacheExpiry()
    }

    /// Deletes all cached weather only for an explicit full app reset.
    func clearAllWeather() {
        weatherByID = [:]
        loadingIDs = []
        failuresByID = [:]
        requestTokens = [:]
        inFlightByID.values.forEach { $0.task.cancel() }
        inFlightByID = [:]
        refreshDatesByPlaceID = [:]
        cachedWeatherByID = [:]
        weatherRevision &+= 1
        cacheIsDirty = false
        cacheExpiryTask?.cancel()
        cacheExpiryTask = nil
        cacheOperation &+= 1
        let operation = cacheOperation
        let writer = cacheWriter
        Task {
            await writer.remove(operation: operation)
        }
    }

    /// Starts Apple Weather's legal mark and link load once per app process.
    /// This async compatibility entry point intentionally returns after scheduling:
    /// attribution is independent, and must never delay a forecast request.
    func loadAttributionIfNeeded() async {
        startAttributionLoadIfNeeded()
    }

    /// Coalesces a best-effort attribution request while allowing forecast work
    /// to start immediately. Observation updates an open Attributions page when
    /// the legal mark eventually arrives.
    private func startAttributionLoadIfNeeded() {
        guard networkConnectivity.status == .available,
              weatherAttribution == nil,
              attributionLoadTask == nil else {
            return
        }

        let weatherKitService = weatherService.weatherKitService
        attributionLoadTask = Task { @MainActor [weak self, weatherKitService] in
            let attribution = try? await weatherKitService.attribution
            guard let self else { return }
            attributionLoadTask = nil
            guard !Task.isCancelled, let attribution else { return }
            weatherAttribution = attribution
        }
    }

    // MARK: - Per-Place Request Lifecycle

    /// Starts one place-owned request, optionally replacing only that place's
    /// earlier work. The task commits and cleans itself so every caller can
    /// safely await the same result.
    private func startRequest(
        for city: City,
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
                token: requestToken
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
        token: UUID
    ) async -> CityWeather? {
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

        let weather: CityWeather
        do {
            weather = try await weatherService.fetchWeatherForCity(city)
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
            // The prior snapshot was removed when this replacement request
            // began, so publish only the typed unavailable state.
            failuresByID[city.id] = PlaceWeatherFailure(issue: issue)
            return nil
        }

        guard !Task.isCancelled,
              isCurrentRequest(for: city.id, token: token) else {
            return nil
        }

        // Commit only after the second ownership check. Incrementing the separate
        // revision forces dependent SwiftUI views to redraw a same-ID replacement.
        weatherByID[city.id] = weather
        cachedWeatherByID[city.id] = CachedCityWeather(from: weather)
        // Wrapping addition makes this monotonic render signal safe even after
        // an impractically large number of refreshes; its exact numeric value is
        // never displayed or used as a business value.
        weatherRevision &+= 1
        failuresByID[city.id] = nil
        recordRefresh(for: city.id)
        markCacheDirty()
        return weather
    }

    // MARK: - Request-Concurrency Gate

    /// Suspends excess place requests without blocking the main actor.
    private func acquireRequestSlot() async {
        if activeRequests < 5 {
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
    /// over the existing slot and the count remains exactly five.
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
    /// snapshot is fresh. The only content check here is whether city-local
    /// midnight has made the cached forecast start on the previous day.
    private func shouldRefresh(placeID: City.ID, now: Date = Date()) -> Bool {
        guard let weather = weatherByID[placeID],
              let refreshDate = refreshDatesByPlaceID[placeID] else {
            return true
        }
        let age = now.timeIntervalSince(refreshDate)
        guard age >= 0, age < 30 * 60 else {
            return true
        }
        return !startsOnCurrentLocalDay(weather, now: now)
    }

    /// Cheap freshness boundary needed to interpret a cached day sequence.
    /// WeatherKit's typed measurements and optional fields are trusted here.
    private func startsOnCurrentLocalDay(
        _ weather: CityWeather,
        now: Date
    ) -> Bool {
        guard let firstForecast = weather.dailyForecasts.first else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = weather.timeZone
        return calendar.isDate(firstForecast.date, inSameDayAs: now)
    }

    /// Starts a request and makes it the only request allowed to mutate the
    /// place's weather, failure, and loading state.
    private func beginRequest(for placeID: City.ID) -> UUID {
        let requestToken = UUID()
        requestTokens[placeID] = requestToken
        // A replacement starts from an honest empty/loading state. Do not keep
        // an older forecast on screen while it is being refreshed or after the
        // replacement fails.
        discardCachedWeather(for: placeID)
        loadingIDs.insert(placeID)
        failuresByID[placeID] = nil
        return requestToken
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
        scheduleCacheExpiry()
    }

    /// Removes every representation of a forecast before a replacement request.
    /// Keeping the cache and visible dictionary in sync prevents an older
    /// forecast from reappearing after that replacement fails.
    private func discardCachedWeather(for placeID: City.ID) {
        let removedWeather = weatherByID.removeValue(forKey: placeID) != nil
        let removedCachedWeather = cachedWeatherByID.removeValue(
            forKey: placeID
        ) != nil
        let removedRefreshDate = refreshDatesByPlaceID.removeValue(
            forKey: placeID
        ) != nil

        guard removedWeather || removedCachedWeather || removedRefreshDate else {
            return
        }

        weatherRevision &+= 1
        markCacheDirty()
        scheduleCacheExpiry()
    }

    /// Removes forecasts once their own successful refresh is a day old. A
    /// missing or future timestamp cannot prove a cache entry is current, so it
    /// is treated as expired as well.
    private func discardExpiredWeather(now: Date = Date()) {
        let cachedIDs = Set(weatherByID.keys)
            .union(cachedWeatherByID.keys)
            .union(refreshDatesByPlaceID.keys)
        let expiredIDs = cachedIDs.filter { placeID in
            guard let refreshDate = refreshDatesByPlaceID[placeID] else {
                return true
            }
            return !PlaceWeatherSnapshotCache.isWithinRetention(
                refreshDate,
                now: now
            )
        }

        guard !expiredIDs.isEmpty else {
            scheduleCacheExpiry(now: now)
            return
        }

        weatherByID = weatherByID.filter { !expiredIDs.contains($0.key) }
        cachedWeatherByID = cachedWeatherByID.filter {
            !expiredIDs.contains($0.key)
        }
        refreshDatesByPlaceID = refreshDatesByPlaceID.filter {
            !expiredIDs.contains($0.key)
        }
        weatherRevision &+= 1
        markCacheDirty()
        scheduleCacheExpiry(now: now)
    }

    /// Schedules exactly one cleanup at the next per-city expiry boundary.
    /// The task captures the store weakly so it does not extend the model's
    /// lifetime while the app is backgrounded or reset.
    private func scheduleCacheExpiry(now: Date = Date()) {
        cacheExpiryTask?.cancel()
        guard let nextExpiry = refreshDatesByPlaceID.values
            .map({
                $0.addingTimeInterval(
                    PlaceWeatherSnapshotCache.maximumRetentionInterval
                )
            })
            .min() else {
            cacheExpiryTask = nil
            return
        }

        // Sleep one extra second so a boundary wake cannot reschedule itself
        // repeatedly due to sub-second Date precision.
        let delay = max(0, nextExpiry.timeIntervalSince(now)) + 1
        cacheExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.discardExpiredWeather()
        }
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

    // MARK: - Coalesced Cache Persistence

    /// Defers persistence until a multi-city load has fully settled. Nested or
    /// overlapping batches share the same outer boundary, so one nearby search
    /// cannot schedule one whole-cache write per WeatherKit response.
    private func beginCacheBatch() {
        if cacheBatchDepth == 0, cache.canPersist {
            cacheOperation &+= 1
            let operation = cacheOperation
            let writer = cacheWriter
            Task {
                await writer.cancelPending(operation: operation)
            }
        }
        cacheBatchDepth += 1
    }

    private func endCacheBatch() {
        precondition(cacheBatchDepth > 0)
        cacheBatchDepth -= 1
        if cacheBatchDepth == 0 {
            scheduleCacheWriteIfNeeded()
        }
    }

    /// Only weather or freshness changes dirty the disposable cache. Loading and
    /// failure state are intentionally memory-only and therefore never encode.
    private func markCacheDirty() {
        guard cache.canPersist else { return }
        cacheIsDirty = true
        if cacheBatchDepth == 0 {
            scheduleCacheWriteIfNeeded()
        }
    }

    /// Captures a cheap Sendable DTO snapshot on the main actor, then hands all
    /// JSON encoding and file work to the serial background writer.
    private func scheduleCacheWriteIfNeeded() {
        guard cache.canPersist,
              cacheBatchDepth == 0,
              cacheIsDirty else {
            return
        }
        cacheIsDirty = false
        let snapshot = PlaceWeatherSnapshot(
            weather: Array(cachedWeatherByID.values),
            refreshDatesByPlaceID: refreshDatesByPlaceID.filter {
                cachedWeatherByID[$0.key] != nil
            }
        )
        cacheOperation &+= 1
        let operation = cacheOperation
        let writer = cacheWriter
        Task {
            await writer.schedule(snapshot, operation: operation)
        }
    }
}

// MARK: - Disposable Forecast Cache

/// Codable file representation for the place-keyed forecast cache.
/// This is the in-memory form returned by the cache; its separate `Document`
/// type below contains only JSON-compatible cached forecast snapshots.
nonisolated struct PlaceWeatherSnapshot: Sendable {
    /// Sendable cache values. Domain reconstruction remains on the main actor.
    let weather: [CachedCityWeather]
    /// Independent freshness timestamp for every decoded place.
    let refreshDatesByPlaceID: [City.ID: Date]
}

/// Disposable, atomic cache stored below the system Caches directory.
/// Caches may be purged by iOS at any time, unlike Saved Places in Application
/// Support, so every failure in this type is deliberately recoverable.
nonisolated struct PlaceWeatherSnapshotCache: Sendable {
    // MARK: - Cache Schema

    /// Versioned file format so incompatible forecast snapshots can be discarded.
    /// UUID dictionary keys become `String` because JSON object keys are strings.
    private struct Document: Codable, Sendable {
        let schemaVersion: Int
        let weather: [CachedCityWeather]
        let refreshDatesByPlaceID: [String: Date]
    }

    /// Current cache schema. Version 4 stores WeatherKit's raw condition
    /// values rather than the older app-normalized categories, so earlier
    /// snapshots are discarded instead of being reinterpreted.
    private static let schemaVersion = 4
    /// Forecast snapshots are disposable and must not survive beyond one day,
    /// even when the app has not had a chance to start a network replacement.
    static let maximumRetentionInterval: TimeInterval = 24 * 60 * 60
    /// Dedicated snapshot file.
    private let fileURL: URL?

    /// Lets preview/in-memory stores skip even constructing a snapshot.
    var canPersist: Bool { fileURL != nil }

    // MARK: - Construction

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

    // MARK: - Loading and Retention

    /// Restores only valid current-schema snapshots. A malformed city is dropped
    /// independently so it cannot erase unrelated honest cached forecasts.
    /// Entries older than a day (or without a trustworthy refresh timestamp) are
    /// pruned and persisted immediately, before a view can restore them.
    func load(now: Date = .now) -> PlaceWeatherSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let document = try? JSONDecoder().decode(Document.self, from: data),
              document.schemaVersion == Self.schemaVersion else {
            return nil
        }

        var weatherByID: [City.ID: CachedCityWeather] = [:]
        var placeOrder: [City.ID] = []
        // Be defensive about duplicate IDs in a cache from an earlier version:
        // preserve first-seen display order, while its final complete snapshot
        // replaces the dictionary value without triggering a duplicate-key trap.
        for weather in document.weather {
            let placeID = weather.city.id
            if weatherByID[placeID] == nil {
                placeOrder.append(placeID)
            }
            // Keep the last complete duplicate instead of trapping in
            // Dictionary(uniqueKeysWithValues:).
            weatherByID[placeID] = weather
        }
        var refreshDatesByPlaceID: [City.ID: Date] = [:]
        // A refresh date is the evidence that a forecast is still eligible for
        // the disposable cache. Future timestamps remain corrupt.
        for (rawPlaceID, refreshDate) in document.refreshDatesByPlaceID {
            guard let placeID = UUID(uuidString: rawPlaceID),
                  refreshDate <= now else {
                continue
            }
            refreshDatesByPlaceID[placeID] = refreshDate
        }

        let expiredOrUndatedIDs = Set(placeOrder.filter { placeID in
            guard let refreshDate = refreshDatesByPlaceID[placeID] else {
                return true
            }
            return !Self.isWithinRetention(refreshDate, now: now)
        })
        let weather: [CachedCityWeather] = placeOrder.compactMap { placeID in
            guard !expiredOrUndatedIDs.contains(placeID) else { return nil }
            return weatherByID[placeID]
        }
        let retainedIDs = Set(weather.map(\.city.id))
        refreshDatesByPlaceID = refreshDatesByPlaceID.filter {
            retainedIDs.contains($0.key)
        }

        let snapshot = PlaceWeatherSnapshot(
            weather: weather,
            refreshDatesByPlaceID: refreshDatesByPlaceID
        )
        guard !expiredOrUndatedIDs.isEmpty else {
            return snapshot
        }

        // The store is created before UI hydration. Rewrite or delete now so a
        // terminated app cannot keep the expired entries in its next launch.
        if snapshot.weather.isEmpty {
            remove()
        } else {
            save(snapshot)
        }
        return snapshot.weather.isEmpty ? nil : snapshot
    }

    /// A timestamp must be in the past and strictly younger than one day to
    /// keep its corresponding weather record in memory or on disk.
    static func isWithinRetention(
        _ refreshDate: Date,
        now: Date
    ) -> Bool {
        let age = now.timeIntervalSince(refreshDate)
        return age >= 0 && age < maximumRetentionInterval
    }

    // MARK: - Persistence

    /// Atomically replaces the disposable snapshot.
    /// Cache writes intentionally do not escape errors: a forecast already in
    /// memory remains valid even if the device declines to write its cache file.
    func save(_ snapshot: PlaceWeatherSnapshot) {
        guard let fileURL else { return }
        let document = Document(
            schemaVersion: Self.schemaVersion,
            weather: snapshot.weather,
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

// MARK: - Background Cache Writer

/// Serializes disposable snapshots away from the UI actor. Operation numbers
/// make delayed writes deterministic even when Task delivery order differs from
/// the store's scheduling order.
private actor PlaceWeatherSnapshotWriter {
    private let cache: PlaceWeatherSnapshotCache
    private var latestOperation = 0
    private var pendingSave: Task<Void, Never>?

    init(cache: PlaceWeatherSnapshotCache) {
        self.cache = cache
    }

    func schedule(
        _ snapshot: PlaceWeatherSnapshot,
        operation: Int
    ) {
        guard operation > latestOperation else { return }
        latestOperation = operation
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await self?.persist(snapshot, operation: operation)
        }
    }

    func cancelPending(operation: Int) {
        guard operation > latestOperation else { return }
        latestOperation = operation
        pendingSave?.cancel()
        pendingSave = nil
    }

    func remove(operation: Int) {
        guard operation > latestOperation else { return }
        latestOperation = operation
        pendingSave?.cancel()
        pendingSave = nil
        cache.remove()
    }

    private func persist(
        _ snapshot: PlaceWeatherSnapshot,
        operation: Int
    ) {
        guard operation == latestOperation,
              !Task.isCancelled else {
            return
        }
        cache.save(snapshot)
        pendingSave = nil
    }
}
