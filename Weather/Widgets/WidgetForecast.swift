//
//  WidgetForecast.swift
//  WeatherWidgets
//
//  Purpose: Owns the widget extension's complete forecast lifecycle: timeline
//  scheduling, cache validation, request coalescing, fetching, and snapshots.
//

import AppIntents
import CoreLocation
import Foundation
import OSLog
import WeatherKit
import WidgetKit

// MARK: - WidgetKit Timeline Provider

let widgetForecastLogger = Logger(
    subsystem: "Yutao-Wu.Weather.WeatherWidgets",
    category: "ForecastProvider"
)

/// Shared by the Small, Medium, Large, and Lock Screen widgets so all four use the
/// same WeatherKit request, cache, and refresh policy.
/// AppIntentTimelineProvider is WidgetKit's lifecycle protocol. WidgetKit calls
/// its placeholder, gallery snapshot, and scheduled timeline methods outside
/// the main app's process and decides the actual execution timing.
struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    // MARK: - Refresh Policy

    /// One provider callback must leave time for WidgetKit to archive and render
    /// its timeline before the system's extension execution allowance expires.
    private let providerExecutionBudget: Duration = .seconds(24)

    // MARK: - WidgetKit Lifecycle Callbacks

    /// Supplies immediate gallery content from cache or deterministic preview data.
    /// Placeholder must return synchronously and cheaply; it must not wait for
    /// WeatherKit, because WidgetKit uses it while loading the gallery UI.
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry {
        SunnyHoursLockScreenEntry.preview
    }

    /// Supplies gallery snapshot or performs a direct WeatherKit refresh.
    func snapshot(
        for configuration: SunnyHoursLockScreenConfigurationIntent,
        in context: Context
    ) async -> SunnyHoursLockScreenEntry {
        // Previews should never make a live network request. They use a cached
        // payload when available, otherwise the deterministic fixture below.
        if context.isPreview {
            return SunnyHoursLockScreenEntry.preview
        }
        // Use the same direct WeatherKit path as the timeline so a newly added
        // widget does not wait for WidgetKit's next scheduled refresh.
        let result = await refreshedCity(for: configuration)
        let entryDate = Date.now
        return SunnyHoursLockScreenEntry(
            date: entryDate,
            city: WidgetTimelinePlanner.displayCity(
                for: result,
                at: entryDate
            )
        )
    }

    /// Produces future entries for status changes and current-time-marker
    /// movement, then requests normal or short-retry network timing.
    func timeline(
        for configuration: SunnyHoursLockScreenConfigurationIntent,
        in context: Context
    ) async -> Timeline<SunnyHoursLockScreenEntry> {
        let result = await refreshedCity(for: configuration)
        return WidgetTimelinePlanner.timeline(for: result, now: .now)
    }

    // MARK: - Forecast Refresh

    /// Uses a valid fresh extension cache before making a bounded direct
    /// WeatherKit request. Every response is tied to the selection and reset
    /// generation captured before suspension.
    private func refreshedCity(
        for configuration: SunnyHoursLockScreenConfigurationIntent
    ) async -> WidgetRefreshResult {
        let executionDeadline = ContinuousClock.now.advanced(
            by: providerExecutionBudget
        )
        let capturedCatalog = WidgetDataStore.catalog()
        guard let selectedCatalogCity = selectedCity(
            for: configuration,
            catalog: capturedCatalog
        ) else {
            return WidgetRefreshResult(
                city: nil,
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }

        let resetEpoch = WidgetResetEpoch.current
        let capturedLanguageIdentifier = appLanguageIdentifier(
            in: capturedCatalog
        )
        let capturedDefaultLocationKind = defaultLocationKind(
            for: selectedCatalogCity,
            catalog: capturedCatalog
        )
        let selectionIdentity = WidgetSelectionIdentity(
            city: selectedCatalogCity,
            appLanguageIdentifier: capturedLanguageIdentifier,
            defaultLocationKind: capturedDefaultLocationKind,
            resetEpoch: resetEpoch
        )
        let resolvesDeviceLocation = usesDeviceCurrentLocation(
            configuration,
            catalog: capturedCatalog
        )
        guard selectionStillMatches(
            selectionIdentity,
            configuration: configuration,
            resolvesDeviceLocation: resolvesDeviceLocation
        ) else {
            return resultForCurrentSelection(configuration)
        }

        let city: WidgetDataCity
        let preservesResolvedCityName: Bool
        if resolvesDeviceLocation {
            do {
                let resolved = try await resolvedDeviceLocationCity(
                    replacing: selectedCatalogCity,
                    languageIdentifier: capturedLanguageIdentifier
                )
                city = resolved.city
                preservesResolvedCityName = resolved.hasFreshResolvedCityName
                try Task.checkCancellation()
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
            } catch is CancellationError {
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
                let fallback = await transientCurrentLocationFallback(
                    for: selectedCatalogCity,
                    defaultLocationKind: capturedDefaultLocationKind,
                    selectionIdentity: selectionIdentity,
                    configuration: configuration
                )
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
                return fallback
            } catch let error as WidgetCurrentLocationError {
                switch error {
                case .widgetUpdatesNotAuthorized:
                    // Once location use is disallowed, never keep presenting or
                    // refetching the last app-published device coordinate.
                    guard selectionStillMatches(
                        selectionIdentity,
                        configuration: configuration,
                        resolvesDeviceLocation: true
                    ) else {
                        return resultForCurrentSelection(configuration)
                    }
                    WidgetForecastStore.removeSnapshot(
                        for: WidgetDataStore.currentLocationIdentifier
                    )
                    return WidgetRefreshResult(
                        city: selectedCatalogCity.markingUnavailable(
                            .unresolvedPlace("widget current location permission")
                        ),
                        snapshot: nil,
                        reloadPolicy: .persistentFailure
                    )
                case .locationUnavailable,
                     .timeZoneUnavailable,
                     .timedOut:
                    // Preserve the cache for a later verified coordinate match,
                    // but do not display or refetch an unverified old location.
                    guard selectionStillMatches(
                        selectionIdentity,
                        configuration: configuration,
                        resolvesDeviceLocation: true
                    ) else {
                        return resultForCurrentSelection(configuration)
                    }
                    let fallback = await transientCurrentLocationFallback(
                        for: selectedCatalogCity,
                        defaultLocationKind: capturedDefaultLocationKind,
                        selectionIdentity: selectionIdentity,
                        configuration: configuration
                    )
                    guard selectionStillMatches(
                        selectionIdentity,
                        configuration: configuration,
                        resolvesDeviceLocation: true
                    ) else {
                        return resultForCurrentSelection(configuration)
                    }
                    return fallback
                }
            } catch {
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
                let fallback = await transientCurrentLocationFallback(
                    for: selectedCatalogCity,
                    defaultLocationKind: capturedDefaultLocationKind,
                    selectionIdentity: selectionIdentity,
                    configuration: configuration
                )
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
                return fallback
            }
        } else {
            city = await cityResolvingTimeZoneIfNeeded(selectedCatalogCity)
            preservesResolvedCityName = false
            // Time-zone repair is asynchronous. A Saved Place can be deleted,
            // replaced, or edited while it is suspended, so do not apply a
            // cache or begin WeatherKit work for the captured stale record.
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: false
            ) else {
                return resultForCurrentSelection(configuration)
            }
        }

        if let issue = city.widgetCurrentIssue {
            return WidgetRefreshResult(
                city: city.markingUnavailable(issue),
                snapshot: nil,
                reloadPolicy: reloadPolicy(for: issue)
            )
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude else {
            return WidgetRefreshResult(
                city: city.markingUnavailable(.unresolvedPlace("coordinates")),
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }
        guard let timeZoneIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            return WidgetRefreshResult(
                city: city.markingUnavailable(.missingTimeZone),
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }

        if resolvesDeviceLocation {
            let remainsAuthorized = await WidgetCurrentLocationResolver
                .widgetUpdatesAuthorized()
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: true
            ) else {
                return resultForCurrentSelection(configuration)
            }
            guard remainsAuthorized else {
                WidgetForecastStore.removeSnapshot(
                    for: WidgetDataStore.currentLocationIdentifier
                )
                return WidgetRefreshResult(
                    city: city.markingUnavailable(
                        .unresolvedPlace("widget current location permission")
                    ),
                    snapshot: nil,
                    reloadPolicy: .persistentFailure
                )
            }
        }

        // A normal WidgetKit callback often arrives while the last extension
        // response is still fresh. Reusing it preserves WeatherKit budget and
        // makes the widget independent from main-app launches.
        if let applied = freshAppliedSnapshot(
            for: city,
            defaultLocationKind: capturedDefaultLocationKind,
            preservesResolvedCityName: preservesResolvedCityName
        ) {
            return WidgetRefreshResult(
                city: applied.city,
                snapshot: applied.snapshot,
                reloadPolicy: .normal
            )
        }

        let requestKey = WidgetForecastRequestKey(
            cityID: city.id,
            cityName: city.cityName,
            cityNameLocaleIdentifier: capturedLanguageIdentifier,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            forecastLocalDate: {
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
                return calendar.startOfDay(for: .now)
            }(),
            locationSource: resolvesDeviceLocation
                ? .deviceCurrentLocation
                : .fixedLocation,
            currentLocationGeneration: resolvesDeviceLocation
                ? capturedCatalog?.currentLocationGeneration
                : nil,
            resetEpoch: resetEpoch
        )

        do {
            let snapshot = try await WidgetForecastRequestCoordinator.shared.value(
                for: requestKey
            ) {
                let response = try await WidgetWeatherFetcher.response(
                    for: requestKey,
                    deadline: executionDeadline
                )
                guard let timeZone = TimeZone(
                    identifier: requestKey.timeZoneIdentifier
                ) else {
                    throw WidgetWeatherFetchError.invalidTimeZone
                }
                return try WidgetWeatherSnapshotBuilder.makeWeatherSnapshot(
                    currentWeather: response.currentWeather,
                    dailyForecast: response.dailyForecast,
                    hourlyForecast: response.hourlyForecast,
                    request: requestKey,
                    timeZone: timeZone
                )
            }
            try Task.checkCancellation()

            // WeatherKit and Core Location can both suspend across midnight.
            // Never persist or display a response whose destination-local day
            // ceased to be Today while the request was in flight.
            guard snapshot.representsLocalDay(containing: .now) else {
                throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
            }

            // Do not save or display a response if Reset App, widget selection,
            // city coordinates, timezone, or localized city identity changed
            // while either WeatherKit attempt was suspended.
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ), snapshot.resetEpoch == WidgetResetEpoch.current else {
                return resultForCurrentSelection(configuration)
            }
            if resolvesDeviceLocation {
                let remainsAuthorized = await WidgetCurrentLocationResolver
                    .widgetUpdatesAuthorized()
                // The authorization query itself suspends. Revalidate the app
                // publication before either deleting or persisting a response.
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ), snapshot.resetEpoch == WidgetResetEpoch.current else {
                    return resultForCurrentSelection(configuration)
                }
                guard remainsAuthorized else {
                    WidgetForecastStore.removeSnapshot(
                        for: WidgetDataStore.currentLocationIdentifier
                    )
                    return WidgetRefreshResult(
                        city: city.markingUnavailable(
                            .unresolvedPlace("widget current location permission")
                        ),
                        snapshot: nil,
                        reloadPolicy: .persistentFailure
                    )
                }
            }

            guard let appliedCity = city.applying(
                snapshot,
                preservesResolvedCityName: preservesResolvedCityName
            ) else {
                throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
            }
            WidgetForecastStore.save(snapshot, for: city.id)
            return WidgetRefreshResult(
                city: appliedCity,
                snapshot: snapshot,
                reloadPolicy: .normal
            )
        } catch is CancellationError {
            widgetForecastLogger.error(
                "Widget forecast refresh was cancelled for \(city.id, privacy: .public)"
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            let authorizationFailure = await currentLocationAuthorizationFailure(
                for: city,
                whenRequired: resolvesDeviceLocation
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            if let authorizationFailure {
                WidgetForecastStore.removeSnapshot(
                    for: WidgetDataStore.currentLocationIdentifier
                )
                return authorizationFailure
            }
            if let fallback = cityUsingFallbackWidgetSnapshot(
                for: city,
                defaultLocationKind: capturedDefaultLocationKind,
                preservesResolvedCityName: preservesResolvedCityName
            ) {
                return WidgetRefreshResult(
                    city: fallback.city,
                    snapshot: fallback.snapshot,
                    reloadPolicy: .transientFailure
                )
            }
            return WidgetRefreshResult(
                city: city.markingUnavailable(.missingForecastData(at: .now)),
                snapshot: nil,
                reloadPolicy: .transientFailure
            )
        } catch {
            let errorDescription = String(reflecting: error)
            widgetForecastLogger.error(
                "Widget forecast refresh failed for \(city.id, privacy: .public): \(errorDescription, privacy: .public)"
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            let authorizationFailure = await currentLocationAuthorizationFailure(
                for: city,
                whenRequired: resolvesDeviceLocation
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            if let authorizationFailure {
                WidgetForecastStore.removeSnapshot(
                    for: WidgetDataStore.currentLocationIdentifier
                )
                return authorizationFailure
            }
            if let fallback = cityUsingFallbackWidgetSnapshot(
                for: city,
                defaultLocationKind: capturedDefaultLocationKind,
                preservesResolvedCityName: preservesResolvedCityName
            ) {
                return WidgetRefreshResult(
                    city: fallback.city,
                    snapshot: fallback.snapshot,
                    reloadPolicy: WidgetWeatherFetcher.isTransientError(error)
                        ? .transientFailure
                        : .persistentFailure
                )
            }
            return WidgetRefreshResult(
                city: city.markingUnavailable(
                    .weatherRequestFailed(String(reflecting: type(of: error)))
                ),
                snapshot: nil,
                reloadPolicy: WidgetWeatherFetcher.isTransientError(error)
                    ? .transientFailure
                    : .persistentFailure
            )
        }
    }

}

// MARK: - City Selection and Cache Matching

/// A catalog city paired with the exact private snapshot applied to it.
struct WidgetAppliedSnapshot {
    let city: WidgetDataCity
    let snapshot: WidgetWeatherSnapshot
}

extension SunnyHoursLockScreenProvider {
    // MARK: - Configured City Resolution

    /// Resolves a selection from one captured catalog value so its city, mode,
    /// and language cannot come from different app publications.
    func selectedCity(
        for configuration: SunnyHoursLockScreenConfigurationIntent,
        catalog: WidgetDataCatalog?
    ) -> WidgetDataCity? {
        guard let catalog else {
            let selectedEntity = configuration.city
                ?? .defaultLocation(in: nil)
            return unavailableConfiguredCity(
                selectedEntity,
                issue: .unresolvedPlace("widget location catalog")
            )
        }
        WidgetForecastStore.prune(
            keeping: Set(
                [WidgetDataStore.currentLocationIdentifier]
                    + catalog.cities.flatMap(\.allWidgetIdentifiers)
            )
        )
        let defaultEntity = WidgetCityEntity.defaultLocation(in: catalog)
        let selectedEntity = configuration.city ?? defaultEntity
        let defaultCity = catalog.currentLocation
            ?? unavailableConfiguredCity(
                defaultEntity,
                issue: .unresolvedPlace("default location")
            )
        if selectedEntity.id == WidgetDataStore.currentLocationIdentifier {
            return defaultCity
        }
        if let savedCity = catalog.cities.first(where: {
            $0.id == selectedEntity.id
        }), savedCity.hasResolvableWidgetLocation {
            return savedCity
        }
        if let retiredCity = catalog.resolvedRetiredCities.first(where: {
            $0.id == selectedEntity.id
        }) {
            return retiredCity.markingUnavailable(
                .unresolvedPlace("retired saved widget location")
            )
        }
        if let retiredCity = catalog.resolvedRetiredCities.first(where: {
            $0.matchesWidgetIdentifier(selectedEntity.id)
        }) {
            // A removed Saved Place remains the exact configured identity. Its
            // fetchable fields were deliberately stripped by the app publisher,
            // so the widget stays unavailable under its last known name.
            return retiredCity.markingUnavailable(
                .unresolvedPlace("retired saved widget location")
            )
        }
        if let savedCity = catalog.cities.first(where: {
            $0.matchesWidgetIdentifier(selectedEntity.id)
        }), savedCity.hasResolvableWidgetLocation {
            // A pre-UUID selection continuously migrates to its active owner
            // only when no deleted identity still claims that historic alias.
            return savedCity
        }
        return unavailableConfiguredCity(
            selectedEntity,
            issue: .unresolvedPlace("saved widget location")
        )
    }

    /// Reports whether the stable default slot currently represents live device
    /// location rather than the separately configured fixed Home Location.
    func usesDeviceCurrentLocation(
        _ configuration: SunnyHoursLockScreenConfigurationIntent,
        catalog: WidgetDataCatalog?
    ) -> Bool {
        let selectedEntity = configuration.city
            ?? .defaultLocation(in: catalog)
        return selectedEntity.id == WidgetDataStore.currentLocationIdentifier
            && (catalog?.resolvedDefaultLocationKind ?? .currentLocation)
                == .currentLocation
    }

    /// Mode participating in cache identity only for the stable default slot.
    func defaultLocationKind(
        for city: WidgetDataCity,
        catalog: WidgetDataCatalog?
    ) -> WidgetDefaultLocationKind? {
        guard city.id == WidgetDataStore.currentLocationIdentifier else {
            return nil
        }
        return catalog?.resolvedDefaultLocationKind ?? .currentLocation
    }

    /// Captures one explicit locale identifier without rereading the app group
    /// after reverse geocoding begins.
    func appLanguageIdentifier(
        in catalog: WidgetDataCatalog?
    ) -> String {
        guard let identifier = catalog?.appLanguageIdentifier,
              !identifier.isEmpty else {
            return Locale.autoupdatingCurrent.identifier
        }
        return identifier
    }

    /// Retains a configured entity's stable identity when its catalog record or
    /// fetchable coordinates are unavailable.
    private func unavailableConfiguredCity(
        _ city: WidgetCityEntity,
        issue: WeatherDataIssue
    ) -> WidgetDataCity {
        WidgetDataCity(
            id: city.id,
            cityName: city.cityName,
            configurationSubtitle: city.subtitle,
            timeZoneIdentifier: nil,
            latitude: nil,
            longitude: nil,
            dataIssue: issue
        )
    }

    /// Repairs fixed places whose older catalog record lacks timezone metadata.
    /// This remains extension-local and does not require the app to reopen.
    func cityResolvingTimeZoneIfNeeded(
        _ city: WidgetDataCity
    ) async -> WidgetDataCity {
        if let identifier = city.timeZoneIdentifier,
           TimeZone(identifier: identifier) != nil {
            return city
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude,
              let timeZone = await WidgetTimeZoneResolver.shared.timeZone(
                  latitude: latitude,
                  longitude: longitude
              ) else {
            return city
        }
        return city.replacingTimeZone(with: timeZone.identifier)
    }

    /// Re-resolves the configuration after suspension so catalog/reset changes
    /// cannot be hidden by the provider's earlier value-type copy.
    func selectionStillMatches(
        _ identity: WidgetSelectionIdentity,
        configuration: SunnyHoursLockScreenConfigurationIntent,
        resolvesDeviceLocation: Bool
    ) -> Bool {
        let catalog = WidgetDataStore.catalog()
        guard WidgetResetEpoch.current == identity.resetEpoch,
              let currentCity = selectedCity(
                  for: configuration,
                  catalog: catalog
              ) else {
            return false
        }
        let currentLanguageIdentifier = appLanguageIdentifier(in: catalog)
        let currentDefaultLocationKind = defaultLocationKind(
            for: currentCity,
            catalog: catalog
        )

        // Device Current Location is independent from the app-published
        // coordinate and label. The request key binds the forecast to the
        // extension-resolved coordinate while this checks stable selection.
        if resolvesDeviceLocation {
            return currentCity.id == WidgetDataStore.currentLocationIdentifier
                && usesDeviceCurrentLocation(
                    configuration,
                    catalog: catalog
                )
                && identity.defaultLocationKind == .currentLocation
                && currentDefaultLocationKind == identity.defaultLocationKind
                && currentLanguageIdentifier
                    == identity.appLanguageIdentifier
        }
        return WidgetSelectionIdentity(
            city: currentCity,
            appLanguageIdentifier: currentLanguageIdentifier,
            defaultLocationKind: currentDefaultLocationKind,
            resetEpoch: WidgetResetEpoch.current
        ) == identity
    }

    // MARK: - Forecast Cache Matching

    /// Returns the extension's private snapshot only while it is inside the
    /// normal freshness window and still matches the catalog identity.
    func freshAppliedSnapshot(
        for city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?,
        preservesResolvedCityName: Bool = false
    ) -> WidgetAppliedSnapshot? {
        guard city.widgetCurrentIssue == nil else { return nil }
        let referenceDate = Date.now
        var appliedCity: WidgetDataCity?
        guard let snapshot = WidgetForecastStore.freshSnapshot(
            forAny: city.allWidgetIdentifiers,
            now: referenceDate,
            matching: {
                guard snapshotMatchesCity(
                    $0,
                    city: city,
                    defaultLocationKind: defaultLocationKind
                ), let candidate = city.applying(
                    $0,
                    preservesResolvedCityName: preservesResolvedCityName,
                    at: referenceDate
                ), candidate.widgetCurrentIssue == nil else {
                    return false
                }
                appliedCity = candidate
                return true
            }
        ), let appliedCity else {
            return nil
        }
        return WidgetAppliedSnapshot(city: appliedCity, snapshot: snapshot)
    }

    /// Returns a last-known-good extension snapshot after a direct request
    /// fails, promoting its matching future-day payload after local midnight.
    /// The host app never supplies weather to this path.
    func cityUsingFallbackWidgetSnapshot(
        for city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?,
        preservesResolvedCityName: Bool = false
    ) -> WidgetAppliedSnapshot? {
        let referenceDate = Date.now
        var cachedCity: WidgetDataCity?
        guard let snapshot = WidgetForecastStore.fallbackSnapshot(
            forAny: city.allWidgetIdentifiers,
            now: referenceDate,
            matching: {
                guard snapshotMatchesCity(
                    $0,
                    city: city,
                    defaultLocationKind: defaultLocationKind
                ), let candidate = city.applying(
                    $0,
                    preservesResolvedCityName: preservesResolvedCityName,
                    at: referenceDate
                ), candidate.widgetCurrentIssue == nil else {
                    return false
                }
                cachedCity = candidate
                return true
            }
        ), let cachedCity else {
            return nil
        }
        return WidgetAppliedSnapshot(city: cachedCity, snapshot: snapshot)
    }

    /// Rejects snapshots created for a superseded coordinate or timezone.
    private func snapshotMatchesCity(
        _ snapshot: WidgetWeatherSnapshot,
        city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?
    ) -> Bool {
        let expectedSource: WidgetForecastLocationSource =
            city.id == WidgetDataStore.currentLocationIdentifier
                && defaultLocationKind == .currentLocation
            ? .deviceCurrentLocation
            : .fixedLocation
        guard let cityIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: cityIdentifier) != nil,
              snapshot.timeZoneIdentifier == cityIdentifier,
              snapshot.locationSource == expectedSource,
              let snapshotLatitude = snapshot.latitude,
              let snapshotLongitude = snapshot.longitude,
              let cityLatitude = city.latitude,
              let cityLongitude = city.longitude else {
            return false
        }

        // Current Location tolerates ordinary GPS jitter. Home and Saved places
        // are fixed identities, so their bound prevents nearby cache collisions.
        let snapshotLocation = CLLocation(
            latitude: snapshotLatitude,
            longitude: snapshotLongitude
        )
        let cityLocation = CLLocation(
            latitude: cityLatitude,
            longitude: cityLongitude
        )
        let maximumDistance: CLLocationDistance = expectedSource
            == .deviceCurrentLocation
            ? 2_000
            : 50
        return snapshotLocation.distance(from: cityLocation) <= maximumDistance
    }

    // MARK: - Stale Request Recovery

    /// Produces a safe result for the selection that exists after a stale
    /// request completes. A short WidgetKit retry fetches the replacement.
    func resultForCurrentSelection(
        _ configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> WidgetRefreshResult {
        let catalog = WidgetDataStore.catalog()
        guard let city = selectedCity(
            for: configuration,
            catalog: catalog
        ) else {
            return WidgetRefreshResult(
                city: nil,
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }
        if let issue = city.widgetCurrentIssue {
            return WidgetRefreshResult(
                city: city.markingUnavailable(issue),
                snapshot: nil,
                reloadPolicy: reloadPolicy(for: issue)
            )
        }
        if usesDeviceCurrentLocation(configuration, catalog: catalog) {
            // This synchronous path cannot safely resolve a new coordinate.
            return WidgetRefreshResult(
                city: city.markingUnavailable(
                    .missingForecastData(at: .now)
                ),
                snapshot: nil,
                reloadPolicy: .transientFailure
            )
        }
        if let applied = freshAppliedSnapshot(
            for: city,
            defaultLocationKind: defaultLocationKind(
                for: city,
                catalog: catalog
            )
        ) {
            return WidgetRefreshResult(
                city: applied.city,
                snapshot: applied.snapshot,
                reloadPolicy: .normal
            )
        }
        return WidgetRefreshResult(
            city: city.markingUnavailable(.missingForecastData(at: .now)),
            snapshot: nil,
            reloadPolicy: .transientFailure
        )
    }

    /// Maps validated data issues to WidgetKit retry behavior.
    func reloadPolicy(for issue: WeatherDataIssue) -> WidgetReloadPolicy {
        switch issue.kind {
        case .weatherRequestFailed,
             .missingForecastData:
            return .transientFailure
        case .unresolvedPlace,
             .missingTimeZone:
            return .persistentFailure
        default:
            return .persistentFailure
        }
    }
}

// MARK: - Refresh Result

/// Scheduling class for a provider result. Persistent failures still retry,
/// but avoid the aggressive cadence reserved for temporary outages.
enum WidgetReloadPolicy {
    case normal
    case transientFailure
    case persistentFailure
}

/// Rendered data paired with the refresh behavior appropriate to that result.
struct WidgetRefreshResult {
    let city: WidgetDataCity?
    let snapshot: WidgetWeatherSnapshot?
    let reloadPolicy: WidgetReloadPolicy
}

// MARK: - Timeline Planning

enum WidgetTimelinePlanner {
    /// Failure cadence; WidgetKit treats this as an earliest preferred retry.
    private static let failureRetryInterval: TimeInterval = 15 * 60
    /// Current-time markers advance between network refresh opportunities.
    private static let markerUpdateInterval: TimeInterval = 30 * 60

    /// Reapplies one immutable snapshot at the exact entry timestamp. Provider
    /// refresh, gallery snapshot, and timeline planning can straddle a city-local
    /// midnight, so reusing their earlier applied value could render yesterday.
    static func displayCity(
        for result: WidgetRefreshResult,
        at date: Date
    ) -> WidgetDataCity? {
        guard let city = result.city,
              let snapshot = result.snapshot else {
            return result.city
        }
        guard let appliedCity = city.applying(snapshot, at: date),
              appliedCity.widgetCurrentIssue == nil else {
            return city.markingUnavailable(
                .missingForecastData(at: date)
            )
        }
        return appliedCity
    }

    /// Creates a useful offline timeline from one immutable forecast. Forecast
    /// interval boundaries update sun status, while half-hour checkpoints move
    /// the time marker and countdown if WidgetKit defers the network reload.
    static func timeline(
        for result: WidgetRefreshResult,
        now: Date
    ) -> Timeline<SunnyHoursLockScreenEntry> {
        var preferredReloadDate: Date
        switch result.reloadPolicy {
        case .normal:
            preferredReloadDate = now.addingTimeInterval(
                WidgetForecastCachePolicy.freshnessInterval
            )
            if let snapshot = result.snapshot {
                // Refresh a fresh response when it reaches the normal age, not
                // 30 minutes after a cache-serving provider callback.
                preferredReloadDate = max(
                    now,
                    snapshot.fetchedAt.addingTimeInterval(
                        WidgetForecastCachePolicy.freshnessInterval
                    )
                )
            }
        case .transientFailure:
            preferredReloadDate = now.addingTimeInterval(failureRetryInterval)
        case .persistentFailure:
            preferredReloadDate = now.addingTimeInterval(
                WidgetForecastCachePolicy.freshnessInterval
            )
        }

        guard let city = result.city,
              let snapshot = result.snapshot,
              let displayExpiry = snapshotDisplayExpiry(
                snapshot,
                relativeTo: now
              ),
              displayExpiry > now else {
            // A result can carry an applied city alongside an expired or
            // migration-era snapshot that cannot represent this local day.
            // Clear weather-bearing fields rather than showing a wrong date.
            let city = result.snapshot == nil
                ? result.city
                : result.city?.markingUnavailable(
                    .missingForecastData(at: now)
                )
            let entry = SunnyHoursLockScreenEntry(date: now, city: city)
            return Timeline(
                entries: [entry],
                policy: .after(preferredReloadDate)
            )
        }

        var futureDates = Set<Date>()
        let firstMarker = Date(
            timeIntervalSinceReferenceDate: ceil(
                now.timeIntervalSinceReferenceDate / markerUpdateInterval
            ) * markerUpdateInterval
        )
        var markerDate = firstMarker
        while markerDate < displayExpiry {
            if markerDate > now {
                futureDates.insert(markerDate)
            }
            markerDate = markerDate.addingTimeInterval(markerUpdateInterval)
        }

        // Each stored hour represents [date, date + 1 hour). Include complete
        // future-day products as well as the represented day so an offline
        // timeline rolls to the correct local date after midnight.
        let timelineHours = (snapshot.hourlyWeatherConditions ?? [])
            + (snapshot.sunnyWindowDays ?? []).flatMap {
                $0.hourlyWeatherConditions ?? []
            }
        for condition in timelineHours {
            for boundary in [
                condition.date,
                condition.date.addingTimeInterval(60 * 60)
            ] where boundary > now && boundary < displayExpiry {
                futureDates.insert(boundary)
            }
        }
        let solarBoundaries = [snapshot.sunrise, snapshot.sunset]
            + (snapshot.sunnyWindowDays ?? []).flatMap {
                [$0.sunrise, $0.sunset]
            }
        for boundary in solarBoundaries.compactMap({ $0 })
        where boundary > now && boundary < displayExpiry {
            futureDates.insert(boundary)
        }

        // Add every destination-calendar midnight in the remaining absolute
        // cache lifetime, even when WeatherKit supplied no row for that day.
        // Calendar day arithmetic covers 23/25-hour DST days; an absent payload
        // then becomes unavailable at midnight instead of retaining yesterday.
        if let timeZoneIdentifier = snapshot.timeZoneIdentifier,
           let timeZone = TimeZone(identifier: timeZoneIdentifier) {
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            var dayBoundary = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: now)
            )
            while let boundary = dayBoundary,
                  boundary < displayExpiry {
                if boundary > now {
                    futureDates.insert(boundary)
                }
                guard let nextBoundary = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: boundary
                ), nextBoundary > boundary else {
                    break
                }
                dayBoundary = nextBoundary
            }
        }

        var entries = [
            SunnyHoursLockScreenEntry(
                date: now,
                city: displayCity(for: result, at: now)
            )
        ]
        entries.append(
            contentsOf: futureDates.sorted().map {
                SunnyHoursLockScreenEntry(
                    date: $0,
                    city: displayCity(for: result, at: $0)
                )
            }
        )

        // A terminal entry guarantees a deferred refresh cannot call yesterday
        // "today" or retain a response beyond the cache's display lifetime.
        entries.append(
            SunnyHoursLockScreenEntry(
                date: displayExpiry,
                city: city.markingUnavailable(
                    .missingForecastData(at: displayExpiry)
                )
            )
        )

        // `.after` is an earliest preferred refresh, not a background-task
        // schedule WidgetKit guarantees to honor.
        return Timeline(
            entries: entries,
            policy: .after(min(preferredReloadDate, displayExpiry))
        )
    }

    /// A complete response remains displayable for the same hard 24-hour cache
    /// lifetime used by the main app. Day-specific payload promotion happens
    /// when each entry is built, so local midnight is no longer an expiry.
    private static func snapshotDisplayExpiry(
        _ snapshot: WidgetWeatherSnapshot,
        relativeTo now: Date
    ) -> Date? {
        guard snapshot.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
                != nil,
              snapshot.representedLocalDate != nil else {
            return nil
        }
        let expiry = snapshot.fetchedAt.addingTimeInterval(
            WidgetForecastCachePolicy.retentionInterval
        )
        return expiry > now ? expiry : nil
    }
}

// MARK: - Forecast Cache Policy

/// One source of truth for the widget's normal and offline cache lifetimes.
enum WidgetForecastCachePolicy {
    static let freshnessInterval: TimeInterval = 30 * 60
    static let retentionInterval: TimeInterval = 24 * 60 * 60
}

// MARK: - Persisted Forecast Snapshot

/// Provenance for the coordinate represented by a widget-owned forecast.
/// Current and Home Location deliberately share one public App Intent ID for
/// backward compatibility, so their private snapshots must carry this separate
/// source identity to prevent cross-mode cache reuse.
enum WidgetForecastLocationSource: String, Codable, Hashable, Sendable {
    case deviceCurrentLocation
    case fixedLocation
}

/// Timestamped per-city forecast value owned and persisted only by WeatherWidgets.
/// It stays outside the App Group catalog, so the host app cannot seed, replace,
/// or invalidate a widget forecast.
struct WidgetWeatherSnapshot: Codable, Hashable, Sendable {
    /// The app-group reset generation current when this forecast was fetched.
    /// A mismatch means the person cleared app data after this snapshot was
    /// written, so the extension must not reuse it as a fallback.
    var resetEpoch: String? = nil
    /// Widget-extension WeatherKit fetch time used to enforce cache freshness.
    let fetchedAt: Date
    /// Destination-local calendar day represented by current-day fields.
    let representedLocalDate: Date?
    /// Time zone resolved from the selected city at fetch time.
    let timeZoneIdentifier: String?
    /// Coordinate paired with this direct WeatherKit response.
    var latitude: Double? = nil
    /// Longitude paired with `latitude` for cache identity validation.
    var longitude: Double? = nil
    /// Place name resolved by the widget for this exact coordinate. Current
    /// Location caches retain it atomically with their weather so a moved
    /// forecast can never be shown under the app's older locality label.
    var resolvedCityName: String? = nil
    /// Locale used for `resolvedCityName`; a later app-language change can
    /// decline to reuse a label from a different language.
    var cityNameLocaleIdentifier: String? = nil
    /// Whether the response came from extension-owned Current Location or a
    /// fixed Home/Saved coordinate.
    var locationSource: WidgetForecastLocationSource? = nil
    /// App-published Current Location generation captured before the extension
    /// resolved this snapshot's fresher coordinate. Optional decoding preserves
    /// same-coordinate fallback for snapshots written by earlier versions.
    var currentLocationGeneration: String? = nil
    /// Exact current WeatherKit condition and its source SF Symbol.
    var currentWeather: WidgetWeatherPresentation? = nil
    /// Detailed current-day conditions used by the shared chart renderer.
    var hourlyConditions: [WidgetHourlyCondition]? = nil
    /// Complete current-day hourly conditions, including night, so later
    /// offline timeline entries do not keep the fetch-time condition icon.
    var hourlyWeatherConditions: [WidgetHourlyCondition]? = nil
    /// Exact current-day solar events used to change status copy at the real
    /// sunrise/sunset rather than at a coarse hourly forecast boundary.
    var sunrise: Date? = nil
    var sunset: Date? = nil
    /// Direct WeatherKit rows for the large widget's upcoming-day chart.
    var sunnyWindowDays: [WidgetSunnyWindowDay]? = nil
    /// Snapshot issue metadata, retained only when usable source data exists.
    var dataIssue: WeatherDataIssue? = nil

    /// Snapshots written before widgets persisted source symbols and raw API
    /// conditions must refresh instead of having an icon or condition guessed.
    var hasDirectWeatherPresentation: Bool {
        guard currentWeather != nil,
              let hourlyConditions,
              let hourlyWeatherConditions,
              let sunnyWindowDays else {
            return false
        }
        return hourlyConditions.allSatisfy { $0.weather != nil }
            && hourlyWeatherConditions.allSatisfy { $0.weather != nil }
            && sunnyWindowDays.allSatisfy { day in
                guard let hours = day.hourlyConditions else { return false }
                let completeHoursAreValid = day.hourlyWeatherConditions?
                    .allSatisfy { $0.weather != nil } ?? true
                return hours.allSatisfy { $0.weather != nil }
                    && completeHoursAreValid
            }
    }

    /// Validates current-day fields against the destination's calendar rather
    /// than the device's time zone. Cache reads and timeline expiry share this
    /// single definition so they cannot disagree at a local-day boundary.
    func representsLocalDay(containing date: Date) -> Bool {
        guard let timeZoneIdentifier,
              let timeZone = TimeZone(identifier: timeZoneIdentifier),
              let representedLocalDate else {
            return false
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(representedLocalDate, inSameDayAs: date)
    }
}

// MARK: - Extension-Private Forecast Storage

/// Widget-extension-only persistence for the last successful forecast per city.
/// WidgetKit can terminate and relaunch this extension between timeline calls,
/// so its private defaults provide the durable boundary for direct WeatherKit
/// fetches without involving the host app or the App Group catalog.
enum WidgetForecastStore {
    // MARK: - Storage Key

    /// Prefix keeps widget forecast values separate from any extension settings.
    /// Versioned when the persisted sunny-hour semantics change, so widgets
    /// never reuse a snapshot that merged `.mostlyClear` into clear sunshine.
    private static let cacheKeyPrefix = "widgetForecastSnapshot.v2."

    // MARK: - Snapshot Reads

    /// Reads a canonical UUID cache first, then any legacy App Intent aliases.
    /// The caller validates each candidate before lookup stops, so an obsolete
    /// snapshot under the canonical key cannot hide a matching legacy response.
    static func freshSnapshot(
        forAny cityIDs: [String],
        now: Date = .now,
        matching isValidCandidate: (WidgetWeatherSnapshot) -> Bool
    ) -> WidgetWeatherSnapshot? {
        firstMatchingSnapshot(
            forAny: cityIDs,
            now: now,
            maximumAge: WidgetForecastCachePolicy.freshnessInterval,
            matching: isValidCandidate
        )
    }

    /// Applies the same canonical-then-legacy candidate validation to the
    /// bounded offline fallback window used after a direct request fails.
    static func fallbackSnapshot(
        forAny cityIDs: [String],
        now: Date = .now,
        matching isValidCandidate: (WidgetWeatherSnapshot) -> Bool
    ) -> WidgetWeatherSnapshot? {
        firstMatchingSnapshot(
            forAny: cityIDs,
            now: now,
            maximumAge: nil,
            matching: isValidCandidate
        )
    }

    // MARK: - Snapshot Writes

    /// Writes only a successful widget-owned WeatherKit response.
    static func save(_ snapshot: WidgetWeatherSnapshot, for cityID: String) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            // Preserve the last successfully encoded response if replacement
            // encoding ever fails.
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey(for: cityID))
    }

    /// Removes one private response immediately. Authorization revocation uses
    /// this for Current Location so weather tied to a no-longer-authorized
    /// coordinate cannot remain visible until normal retention expires.
    static func removeSnapshot(for cityID: String) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: cityID))
    }

    /// Removes legacy, expired, reset-invalid, and no-longer-selectable cache
    /// entries. Widget extensions are long-lived across app launches, so lazy
    /// per-city deletion alone would otherwise leak one defaults value for every
    /// city that was ever configured.
    static func prune(
        keeping cityIDs: Set<String>,
        now: Date = .now
    ) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("widgetForecastSnapshot.") {
            guard key.hasPrefix(cacheKeyPrefix) else {
                defaults.removeObject(forKey: key)
                continue
            }

            let cityID = String(key.dropFirst(cacheKeyPrefix.count))
            guard cityIDs.contains(cityID) else {
                defaults.removeObject(forKey: key)
                continue
            }

            // `retainedSnapshot` performs decode, epoch, source, timezone, and
            // retention validation and deletes invalid values in place.
            _ = retainedSnapshot(for: cityID, now: now)
        }
    }

    // MARK: - Private Validation

    /// Reads canonical then legacy cache identities with one shared validation
    /// path. `maximumAge == nil` selects the bounded offline fallback window.
    private static func firstMatchingSnapshot(
        forAny cityIDs: [String],
        now: Date,
        maximumAge: TimeInterval?,
        matching isValidCandidate: (WidgetWeatherSnapshot) -> Bool
    ) -> WidgetWeatherSnapshot? {
        for cityID in cityIDs {
            guard let snapshot = retainedSnapshot(for: cityID, now: now) else {
                continue
            }
            if let maximumAge,
               now.timeIntervalSince(snapshot.fetchedAt) >= maximumAge {
                continue
            }
            if isValidCandidate(snapshot) { return snapshot }
        }
        return nil
    }

    /// Restores a complete last-known-good response while enforcing the same
    /// hard 24-hour retention limit as the main app. Invalid or expired entries
    /// are deleted lazily on access so extension storage cannot accumulate
    /// unusable weather indefinitely.
    private static func retainedSnapshot(
        for cityID: String,
        now: Date
    ) -> WidgetWeatherSnapshot? {
        let key = cacheKey(for: cityID)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }

        guard let snapshot = try? JSONDecoder().decode(
            WidgetWeatherSnapshot.self,
            from: data
        ) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        let age = now.timeIntervalSince(snapshot.fetchedAt)
        guard snapshot.resetEpoch == WidgetResetEpoch.current,
              snapshot.hasDirectWeatherPresentation,
              snapshot.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) != nil,
              snapshot.representedLocalDate != nil,
              age >= 0,
              age < WidgetForecastCachePolicy.retentionInterval else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }

        return snapshot
    }

    private static func cacheKey(for cityID: String) -> String {
        "\(cacheKeyPrefix)\(cityID)"
    }
}

// MARK: - Shared Task Coordination

/// Bridges an independently owned task to one WidgetKit callback.
///
/// WidgetKit may cancel one family while another family still awaits the same
/// location or WeatherKit operation. This waiter ends only the abandoned wait;
/// ownership and cancellation of the shared operation stay with its coordinator.
actor WidgetTaskWaiter<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Error>?
    private var observerTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false

    /// Waits until the shared task finishes or this caller is cancelled.
    func value(of task: Task<Value, Error>) async throws -> Value {
        try await wait(
            for: task,
            timeout: nil,
            timeoutFailure: nil
        )
    }

    /// Adds a caller-specific deadline without cancelling the shared task.
    func value<TimeoutFailure: Error & Sendable>(
        of task: Task<Value, Error>,
        timeout: Duration,
        timeoutError: TimeoutFailure
    ) async throws -> Value {
        guard timeout > .zero else { throw timeoutError }
        return try await wait(
            for: task,
            timeout: timeout,
            timeoutFailure: timeoutError
        )
    }

    private func wait(
        for task: Task<Value, Error>,
        timeout: Duration?,
        timeoutFailure: Error?
    ) async throws -> Value {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(
                    continuation,
                    task: task,
                    timeout: timeout,
                    timeoutFailure: timeoutFailure
                )
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func install(
        _ continuation: CheckedContinuation<Value, Error>,
        task: Task<Value, Error>,
        timeout: Duration?,
        timeoutFailure: Error?
    ) {
        guard !cancellationRequested else {
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        observerTask = Task { [self] in
            do {
                finish(.success(try await task.value))
            } catch {
                finish(.failure(error))
            }
        }

        if let timeout, let timeoutFailure {
            timeoutTask = Task { [self] in
                do {
                    try await Task.sleep(for: timeout)
                    try Task.checkCancellation()
                    finish(.failure(timeoutFailure))
                } catch {
                    // Completion or caller cancellation won the race.
                }
            }
        }
    }

    private func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        observerTask?.cancel()
        timeoutTask?.cancel()
        observerTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }

    private func cancel() {
        cancellationRequested = true
        finish(.failure(CancellationError()))
    }
}

/// Coalesces equal requests while preserving cancellation for each caller.
///
/// Both current-location and forecast refreshes can be requested by several
/// widget families in one WidgetKit batch. The coordinator owns one underlying
/// task, tracks its active callers, and briefly reuses a completed value.
actor WidgetRequestCoordinator<Key: Hashable & Sendable, Value: Sendable> {
    private struct InFlightRequest {
        let id: UUID
        let task: Task<Value, Error>
        var waiterIDs: Set<UUID>
    }

    private struct CompletedRequest {
        let value: Value
        let completedAt: ContinuousClock.Instant
    }

    private var inFlight: [Key: InFlightRequest] = [:]
    private var recentlyCompleted: [Key: CompletedRequest] = [:]
    private let completedReuseInterval: Duration

    init(completedReuseInterval: Duration) {
        self.completedReuseInterval = completedReuseInterval
    }

    func value(
        for key: Key,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        removeExpiredCompletions()
        if let completed = recentlyCompleted[key] {
            return completed.value
        }

        let waiterID = UUID()
        let request: InFlightRequest
        if var existing = inFlight[key] {
            existing.waiterIDs.insert(waiterID)
            inFlight[key] = existing
            request = existing
        } else {
            let task = Task<Value, Error>.detached(priority: .utility) {
                try await operation()
            }
            request = InFlightRequest(
                id: UUID(),
                task: task,
                waiterIDs: [waiterID]
            )
            inFlight[key] = request
        }

        do {
            let value = try await WidgetTaskWaiter<Value>().value(
                of: request.task
            )
            try Task.checkCancellation()
            complete(
                key: key,
                requestID: request.id,
                value: value
            )
            return value
        } catch is CancellationError {
            removeWaiter(
                waiterID,
                key: key,
                requestID: request.id,
                cancelsTaskWhenEmpty: true
            )
            throw CancellationError()
        } catch {
            removeWaiter(
                waiterID,
                key: key,
                requestID: request.id,
                cancelsTaskWhenEmpty: false
            )
            throw error
        }
    }

    private func removeExpiredCompletions() {
        let now = ContinuousClock.now
        recentlyCompleted = recentlyCompleted.filter {
            let age = $0.value.completedAt.duration(to: now)
            return age >= .zero && age < completedReuseInterval
        }
    }

    private func complete(
        key: Key,
        requestID: UUID,
        value: Value
    ) {
        guard inFlight[key]?.id == requestID else { return }
        recentlyCompleted[key] = CompletedRequest(
            value: value,
            completedAt: ContinuousClock.now
        )
        inFlight[key] = nil
    }

    private func removeWaiter(
        _ waiterID: UUID,
        key: Key,
        requestID: UUID,
        cancelsTaskWhenEmpty: Bool
    ) {
        guard var request = inFlight[key],
              request.id == requestID else {
            return
        }
        request.waiterIDs.remove(waiterID)
        if request.waiterIDs.isEmpty {
            if cancelsTaskWhenEmpty {
                request.task.cancel()
            }
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }
}

// MARK: - WeatherKit Request Coordination

/// Immutable identity captured before an asynchronous refresh begins. The app
/// can republish the catalog, move Current Location, or advance Reset App while
/// WeatherKit is suspended, so every completed response is checked against this
/// exact selection before it can be rendered or persisted.
struct WidgetSelectionIdentity: Hashable, Sendable {
    let cityID: String
    let cityName: String
    let latitude: Double?
    let longitude: Double?
    let timeZoneIdentifier: String?
    let appLanguageIdentifier: String
    let defaultLocationKind: WidgetDefaultLocationKind?
    let resetEpoch: String?

    init(
        city: WidgetDataCity,
        appLanguageIdentifier: String,
        defaultLocationKind: WidgetDefaultLocationKind?,
        resetEpoch: String?
    ) {
        cityID = city.id
        cityName = city.cityName
        latitude = city.latitude
        longitude = city.longitude
        timeZoneIdentifier = city.timeZoneIdentifier
        self.appLanguageIdentifier = appLanguageIdentifier
        self.defaultLocationKind = defaultLocationKind
        self.resetEpoch = resetEpoch
    }
}

/// Primitive, process-local key for sharing identical extension requests. It
/// includes reset generation and full forecast identity so neither a moved
/// Current Location nor a reset can inherit an older in-flight response.
struct WidgetForecastRequestKey: Hashable, Sendable {
    let cityID: String
    let cityName: String
    let cityNameLocaleIdentifier: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    /// City-local day requested from WeatherKit. Including it prevents a
    /// pre-midnight in-flight or just-completed task from being reused after
    /// that city crosses midnight.
    let forecastLocalDate: Date
    let locationSource: WidgetForecastLocationSource
    let currentLocationGeneration: String?
    let resetEpoch: String?
}

/// WeatherKit's aggregate tuple is wrapped so an unstructured timeout race can
/// safely hand the immutable response back to the provider. WeatherKit owns the
/// contained value types; this extension only reads them after completion.
struct WidgetWeatherKitResponse: @unchecked Sendable {
    /// Exact current presentation when available, otherwise the nearest
    /// WeatherKit hourly record. The latter lets the widget retain useful
    /// direct forecast data when only the current product is temporarily
    /// unavailable from WeatherKit.
    let currentWeather: WidgetWeatherPresentation
    let dailyForecast: Forecast<DayWeather>
    let hourlyForecast: Forecast<HourWeather>
}

enum WidgetWeatherFetchError: Error {
    case timedOut
    case invalidTimeZone
    case missingHourlyFallback
    case missingCurrentHourlyCoverage
}

enum WidgetWeatherRequestMode: Hashable, Sendable {
    case complete
    case forecastFallback
}

/// Process-local identity for one expensive WeatherKit operation. It excludes
/// presentation-only city metadata so simultaneous widget families querying
/// the same coordinate and forecast interval share one system request.
private struct WidgetWeatherOperationKey: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let forecastStartDate: Date
    let forecastEndDate: Date
    let mode: WidgetWeatherRequestMode
}

/// Owns actual WeatherKit work independently from any one WidgetKit callback.
/// A callback may time out at its provider deadline while the system request
/// ignores cancellation. Retaining that operation briefly lets subsequent
/// Home and Lock Screen callbacks join it instead of stacking another full
/// 10-day WeatherKit request on top of the first one.
actor WidgetWeatherOperationCoordinator {
    static let shared = WidgetWeatherOperationCoordinator()

    private struct InFlightOperation {
        let id: UUID
        let task: Task<WidgetWeatherKitResponse, Error>
        let expiryTask: Task<Void, Never>
    }

    private struct CompletedResponse {
        let response: WidgetWeatherKitResponse
        let completedAt: ContinuousClock.Instant
    }

    private var inFlight: [WidgetWeatherOperationKey: InFlightOperation] = [:]
    private var recentlyCompleted: [WidgetWeatherOperationKey: CompletedResponse] = [:]
    private let completedReuseInterval: Duration = .seconds(30)
    /// Do not retain a genuinely stuck system request forever. This interval is
    /// twice the provider budget, long enough to absorb late completion and a
    /// sequential family batch while allowing a later WidgetKit retry to start
    /// cleanly if WeatherKit never returns.
    private let maximumOperationLifetime: Duration = .seconds(48)

    func response(
        latitude: Double,
        longitude: Double,
        forecastStartDate: Date,
        forecastEndDate: Date,
        timeout: Duration,
        mode: WidgetWeatherRequestMode = .complete
    ) async throws -> WidgetWeatherKitResponse {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetWeatherFetchError.timedOut
        }

        let key = WidgetWeatherOperationKey(
            latitude: latitude,
            longitude: longitude,
            forecastStartDate: forecastStartDate,
            forecastEndDate: forecastEndDate,
            mode: mode
        )
        let now = ContinuousClock.now
        recentlyCompleted = recentlyCompleted.filter {
            let age = $0.value.completedAt.duration(to: now)
            return age >= .zero && age < completedReuseInterval
        }
        if let completed = recentlyCompleted[key] {
            try Task.checkCancellation()
            return completed.response
        }

        let operation: InFlightOperation
        if let existing = inFlight[key] {
            operation = existing
        } else {
            let id = UUID()
            let task = Task<WidgetWeatherKitResponse, Error>.detached(
                priority: .utility
            ) {
                try await Self.performRequest(
                    latitude: latitude,
                    longitude: longitude,
                    forecastStartDate: forecastStartDate,
                    forecastEndDate: forecastEndDate,
                    mode: mode
                )
            }
            let expiryTask = Task.detached(priority: .utility) { [self] in
                do {
                    try await Task.sleep(for: maximumOperationLifetime)
                    try Task.checkCancellation()
                    await expire(key: key, operationID: id)
                } catch {
                    // Normal completion cancels this housekeeping task.
                }
            }
            operation = InFlightOperation(
                id: id,
                task: task,
                expiryTask: expiryTask
            )
            inFlight[key] = operation

            Task.detached(priority: .utility) { [self] in
                let result: Result<WidgetWeatherKitResponse, Error>
                do {
                    result = .success(try await task.value)
                } catch {
                    result = .failure(error)
                }
                await complete(
                    key: key,
                    operationID: id,
                    result: result
                )
            }
        }

        let response = try await WidgetTaskWaiter<WidgetWeatherKitResponse>().value(
            of: operation.task,
            timeout: timeout,
            timeoutError: WidgetWeatherFetchError.timedOut
        )
        try Task.checkCancellation()
        return response
    }

    private func complete(
        key: WidgetWeatherOperationKey,
        operationID: UUID,
        result: Result<WidgetWeatherKitResponse, Error>
    ) {
        guard let operation = inFlight[key],
              operation.id == operationID else {
            return
        }
        operation.expiryTask.cancel()
        inFlight[key] = nil
        if case let .success(response) = result {
            recentlyCompleted[key] = CompletedResponse(
                response: response,
                completedAt: ContinuousClock.now
            )
        }
    }

    private func expire(
        key: WidgetWeatherOperationKey,
        operationID: UUID
    ) {
        guard let operation = inFlight[key],
              operation.id == operationID else {
            return
        }
        operation.task.cancel()
        inFlight[key] = nil
    }

    nonisolated private static func performRequest(
        latitude: Double,
        longitude: Double,
        forecastStartDate: Date,
        forecastEndDate: Date,
        mode: WidgetWeatherRequestMode
    ) async throws -> WidgetWeatherKitResponse {
        let location = CLLocation(
            latitude: latitude,
            longitude: longitude
        )
        switch mode {
        case .complete:
            let (current, daily, hourly) = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .current,
                .daily(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                ),
                .hourly(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                )
            )
            return WidgetWeatherKitResponse(
                currentWeather: WidgetWeatherPresentation(
                    condition: AppWeatherCondition(
                        weatherKit: current.condition
                    ),
                    symbolName: current.symbolName
                ),
                dailyForecast: daily,
                hourlyForecast: hourly
            )
        case .forecastFallback:
            let (daily, hourly) = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .daily(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                ),
                .hourly(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                )
            )
            guard let nearestHour = hourly.forecast.min(by: {
                abs($0.date.timeIntervalSinceNow)
                    < abs($1.date.timeIntervalSinceNow)
            }) else {
                throw WidgetWeatherFetchError.missingHourlyFallback
            }
            return WidgetWeatherKitResponse(
                currentWeather: WidgetWeatherPresentation(
                    condition: AppWeatherCondition(
                        weatherKit: nearestHour.condition
                    ),
                    symbolName: nearestHour.symbolName
                ),
                dailyForecast: daily,
                hourlyForecast: hourly
            )
        }
    }
}

/// Shares complete retry-and-snapshot work across simultaneous widget callbacks.
enum WidgetForecastRequestCoordinator {
    static let shared = WidgetRequestCoordinator<
        WidgetForecastRequestKey,
        WidgetWeatherSnapshot
    >(completedReuseInterval: .seconds(5))
}

// MARK: - WeatherKit Fetch Policy

/// Executes the bounded WeatherKit retry policy shared by every widget family.
enum WidgetWeatherFetcher {
    /// Tries WeatherKit's complete product first, then its independently useful
    /// daily/hourly products. Every attempt shares one absolute provider
    /// deadline, leaving WidgetKit time to archive and render the timeline.
    static func response(
        for request: WidgetForecastRequestKey,
        deadline: ContinuousClock.Instant
    ) async throws -> WidgetWeatherKitResponse {
        guard let timeZone = TimeZone(
            identifier: request.timeZoneIdentifier
        ) else {
            throw WidgetWeatherFetchError.invalidTimeZone
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let forecastStartDate = request.forecastLocalDate
        guard let forecastEndDate = calendar.date(
            byAdding: .day,
            value: 10,
            to: forecastStartDate
        ) else {
            throw WidgetWeatherFetchError.invalidTimeZone
        }

        // Prefer the exact current product and give this aggregate request the
        // remaining budget. A forecast-only duplicate is used only after the
        // complete request actually returns a nonterminal error.
        do {
            let timeout = try weatherRequestTimeout(
                preferred: .seconds(24),
                deadline: deadline
            )
            return try await WidgetWeatherOperationCoordinator.shared.response(
                latitude: request.latitude,
                longitude: request.longitude,
                forecastStartDate: forecastStartDate,
                forecastEndDate: forecastEndDate,
                timeout: timeout,
                mode: .complete
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.isTerminalWeatherRequestError(error)
                || Self.isWeatherRequestTimeout(error) {
                throw error
            }
            // Forecast-only recovery handles partial WeatherKit outages and
            // states where the current product expires before forecast data.
        }

        var finalError: Error = WidgetWeatherFetchError.timedOut
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let timeout = try weatherRequestTimeout(
                    preferred: .seconds(24),
                    deadline: deadline
                )
                return try await WidgetWeatherOperationCoordinator.shared.response(
                    latitude: request.latitude,
                    longitude: request.longitude,
                    forecastStartDate: forecastStartDate,
                    forecastEndDate: forecastEndDate,
                    timeout: timeout,
                    mode: .forecastFallback
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                finalError = error
                guard attempt == 0,
                      Self.isTransientError(error),
                      !Self.isWeatherRequestTimeout(error) else {
                    throw error
                }
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining >= .seconds(1) else {
                    throw finalError
                }
                try await Task.sleep(
                    for: min(.milliseconds(750), remaining)
                )
            }
        }
        throw finalError
    }

    /// Gives each WeatherKit operation only the provider budget still left.
    private static func weatherRequestTimeout(
        preferred: Duration,
        deadline: ContinuousClock.Instant
    ) throws -> Duration {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining >= .milliseconds(250) else {
            throw WidgetWeatherFetchError.timedOut
        }
        return min(preferred, remaining)
    }

    private static func isWeatherRequestTimeout(_ error: Error) -> Bool {
        guard let fetchError = error as? WidgetWeatherFetchError else {
            return false
        }
        if case .timedOut = fetchError {
            return true
        }
        return false
    }

    private static func isTerminalWeatherRequestError(_ error: Error) -> Bool {
        guard let weatherError = error as? WeatherKit.WeatherError else {
            return false
        }
        switch weatherError {
        case .permissionDenied:
            return true
        case .unknown:
            return false
        @unknown default:
            return false
        }
    }

    static func isTransientError(_ error: Error) -> Bool {
        if let fetchError = error as? WidgetWeatherFetchError {
            switch fetchError {
            case .timedOut,
                 .missingCurrentHourlyCoverage:
                return true
            case .invalidTimeZone,
                 .missingHourlyFallback:
                return false
            }
        }
        if let weatherError = error as? WeatherKit.WeatherError {
            switch weatherError {
            case .unknown:
                return true
            case .permissionDenied:
                return false
            @unknown default:
                return true
            }
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

// MARK: - Snapshot Construction

enum WidgetWeatherSnapshotBuilder {
    /// Converts WeatherKit data into a compact rendering payload. Widgets use
    /// WeatherKit's daylight flag directly and derive their chart domains from
    /// the returned hours, without interpreting solar-event edge cases. Current
    /// and hourly data remain usable even when no daily row is available for the
    /// large-widget timeline.
    static func makeWeatherSnapshot(
        currentWeather: WidgetWeatherPresentation,
        dailyForecast: Forecast<DayWeather>,
        hourlyForecast: Forecast<HourWeather>,
        request: WidgetForecastRequestKey,
        timeZone: TimeZone
    ) throws -> WidgetWeatherSnapshot {
        let now = Date()
        // WeatherKit Dates are absolute instants. Interpret both `now` and each
        // forecast date in the configured city's timezone before choosing today.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentLocalDay = request.forecastLocalDate
        guard calendar.isDate(currentLocalDay, inSameDayAs: now) else {
            throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
        }
        let forecastDays = Array(
            dailyForecast.forecast
                .filter { calendar.startOfDay(for: $0.date) >= currentLocalDay }
                .prefix(10)
        )
        // Group WeatherKit's available daylight records once. Both the current
        // card and every large-widget row then reuse the same local-day data.
        let allHourlyForecasts = Array(hourlyForecast.forecast)
            .sorted { $0.date < $1.date }
        let completeHoursByDay = completeHourlyForecastsByDay(
            allHourlyForecasts,
            currentLocalDay: currentLocalDay,
            now: now,
            calendar: calendar
        )
        guard let currentDayHours = completeHoursByDay[currentLocalDay] else {
            throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
        }
        let daylightHoursByDay = Dictionary(
            grouping: allHourlyForecasts.filter { forecast in
                guard completeHoursByDay[
                    calendar.startOfDay(for: forecast.date)
                ] != nil else {
                    return false
                }
                return forecast.isDaylight
            }
        ) {
            calendar.startOfDay(for: $0.date)
        }
        // Retain each daylight record's source condition and symbol unchanged.
        let currentHourlyConditions = widgetForecastHourlyConditions(
            hours: daylightHoursByDay[currentLocalDay] ?? [],
            calendar: calendar
        )
        let currentDayWeatherConditions = widgetForecastHourlyConditions(
            hours: currentDayHours,
            calendar: calendar
        )
        let currentDayForecast = forecastDays.first {
            calendar.startOfDay(for: $0.date) == currentLocalDay
        }

        // The large widget shows each available current/future WeatherKit day,
        // up to its ten-row capacity. Each row uses only WeatherKit's available
        // daylight-marked hourly records.
        let sunnyWindowDays: [WidgetSunnyWindowDay] = forecastDays.compactMap {
            day -> WidgetSunnyWindowDay? in
            let localDay = calendar.startOfDay(for: day.date)
            // Omit a day the hourly product did not cover. An empty daylight
            // group remains valid when that covered day is a polar night.
            guard completeHoursByDay[localDay] != nil else { return nil }
            let hourlyConditions = widgetForecastHourlyConditions(
                hours: daylightHoursByDay[localDay] ?? [],
                calendar: calendar
            )
            let hourlyWeatherConditions = widgetForecastHourlyConditions(
                hours: completeHoursByDay[localDay] ?? [],
                calendar: calendar
            )
            return WidgetSunnyWindowDay(
                date: localDay,
                hourlyConditions: hourlyConditions,
                hourlyWeatherConditions: hourlyWeatherConditions,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset
            )
        }

        return WidgetWeatherSnapshot(
            resetEpoch: request.resetEpoch,
            fetchedAt: now,
            representedLocalDate: calendar.startOfDay(for: now),
            timeZoneIdentifier: timeZone.identifier,
            latitude: request.latitude,
            longitude: request.longitude,
            resolvedCityName: request.cityName,
            cityNameLocaleIdentifier: request.cityNameLocaleIdentifier,
            locationSource: request.locationSource,
            currentLocationGeneration: request.currentLocationGeneration,
            currentWeather: currentWeather,
            hourlyConditions: currentHourlyConditions,
            hourlyWeatherConditions: currentDayWeatherConditions,
            sunrise: currentDayForecast?.sun.sunrise,
            sunset: currentDayForecast?.sun.sunset,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
    }

    /// Returns only local days whose hourly product continuously covers the
    /// portion WeatherKit was asked to provide. Future rows must span their
    /// complete 23/24/25-hour civil day; Today's row may begin at its current
    /// hour because WeatherKit does not promise historical hourly conditions.
    /// This keeps a partial response from being painted as neutral "No Sun".
    private static func completeHourlyForecastsByDay(
        _ forecasts: [HourWeather],
        currentLocalDay: Date,
        now: Date,
        calendar: Calendar
    ) -> [Date: [HourWeather]] {
        let grouped = Dictionary(grouping: forecasts) {
            calendar.startOfDay(for: $0.date)
        }
        let tolerance: TimeInterval = 5 * 60
        return grouped.reduce(into: [:]) { result, pair in
            let day = pair.key
            guard let dayEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                return
            }
            let sorted = Dictionary(
                grouping: pair.value,
                by: \.date
            ).compactMap { $0.value.first }.sorted { $0.date < $1.date }
            guard let first = sorted.first,
                  let last = sorted.last else {
                return
            }
            let expectedStart: Date
            if calendar.isDate(day, inSameDayAs: currentLocalDay) {
                expectedStart = calendar.dateInterval(of: .hour, for: now)?.start
                    ?? now
            } else {
                expectedStart = day
            }
            let coversExpectedStart = sorted.contains { forecast in
                forecast.date <= expectedStart.addingTimeInterval(tolerance)
                    && forecast.date.addingTimeInterval(60 * 60)
                        > expectedStart.addingTimeInterval(-tolerance)
            }
            guard first.date <= expectedStart.addingTimeInterval(tolerance),
                  coversExpectedStart,
                  last.date.addingTimeInterval(60 * 60)
                    >= dayEnd.addingTimeInterval(-tolerance),
                  zip(sorted, sorted.dropFirst()).allSatisfy({ pair in
                      let gap = pair.1.date.timeIntervalSince(pair.0.date)
                      return gap > 0 && gap <= 60 * 60 + tolerance
                  }) else {
                return
            }
            result[day] = sorted
        }
    }
}

// MARK: - Widget Forecast Classification

/// Reduces WeatherKit records to the persistent widget payload without
/// translating their condition or replacing their source symbol.
func widgetForecastHourlyConditions(
    hours: [HourWeather],
    calendar: Calendar
) -> [WidgetHourlyCondition] {
    hours.map { forecast in
        let weather = WidgetWeatherPresentation(
            condition: AppWeatherCondition(weatherKit: forecast.condition),
            symbolName: forecast.symbolName
        )
        let hour = calendar.component(.hour, from: forecast.date)
        return WidgetHourlyCondition(
            date: forecast.date,
            hour: hour,
            weather: weather
        )
    }
}

/// Uses the actual represented hours where possible; a full-day domain is a
/// safe visual fallback when WeatherKit gives no daylight records to narrow it.
func widgetFallbackChartBounds(for hours: [Int]) -> SunnyHoursChartBounds {
    guard let firstHour = hours.min(), let lastHour = hours.max() else {
        return .fullDay
    }
    return SunnyHoursChartBounds(startHour: firstHour, endHour: lastHour + 1)
}

extension WidgetSunnyWindowDay {
    var widgetDaylightBounds: SunnyHoursChartBounds {
        widgetFallbackChartBounds(for: chartHourlyConditions.map(\.hour))
    }
}
