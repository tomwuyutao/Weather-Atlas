//
//  HomeLocationStore.swift
//  Weather
//
//  Purpose: Persists the optional city that a person chooses as their
//  permanent home location instead of granting device-location access.
//

import Foundation

// MARK: - Manual Home Persistence

/// Small persistence boundary for the manually chosen home location.
///
/// Keeping this separate from Saved Places prevents a home choice from
/// silently becoming a bookmarked destination, while still letting the shared
/// location model use it exactly like a resolved current location.
enum HomeLocationStore {
    private static let storageKey = "weatherAtlas.homeLocation"

    /// Restores only complete, valid city data. A malformed legacy value is
    /// discarded rather than becoming an unusable first-run location.
    static func load() -> City? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let city = try? JSONDecoder().decode(City.self, from: data),
              PlacesLibraryValidator.isValidCity(city) else {
            return nil
        }
        return city
    }

    /// Stores the resolved search result after it has passed the same city
    /// validation used for Saved Places.
    static func save(_ city: City) {
        guard PlacesLibraryValidator.isValidCity(city),
              let data = try? JSONEncoder().encode(city) else {
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Removes only the manual-home preference; it never affects Saved Places.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

// MARK: - Physical-Location Forecast Identity

/// Persists only the repository identity of the last physical-location
/// forecast. The forecast itself remains in `PlaceWeatherSnapshotCache` with
/// its independent timestamp and 24-hour retention policy.
enum CurrentLocationWeatherIdentityStore {
    private static let storageKey =
        "weatherAtlas.currentLocationWeatherPlaceID"

    static func load() -> City.ID? {
        guard let value = UserDefaults.standard.string(forKey: storageKey) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    static func save(_ placeID: City.ID) {
        UserDefaults.standard.set(placeID.uuidString, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
