//
//  WidgetTimeZoneResolver.swift
//  WeatherWidgets
//
//  Purpose: Resolves a coordinate to a validated IANA time zone locally.
//

@preconcurrency import CoreLocation
import Foundation
import SwiftTimeZoneLookup

/// Serializes access to the package's bundled time-zone boundary databases.
///
/// WidgetKit can request multiple timelines concurrently. Keeping the lookup
/// object actor-isolated avoids concurrent access to its C database handles and
/// avoids reopening the bundled databases for every forecast request.
actor WidgetTimeZoneResolver {
    static let shared = WidgetTimeZoneResolver()

    private let lookup: SwiftTimeZoneLookup?

    private init() {
        lookup = try? SwiftTimeZoneLookup()
    }

    /// Returns a Foundation time zone only when the coordinate and the package's
    /// IANA identifier are both valid. No approximate longitude fallback is used.
    func timeZone(for coordinate: CLLocationCoordinate2D) -> TimeZone? {
        timeZone(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }

    /// Convenience overload for persisted latitude and longitude values.
    func timeZone(latitude: Double, longitude: Double) -> TimeZone? {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              let identifier = lookup?.simple(
                  latitude: Float(latitude),
                  longitude: Float(longitude)
              ),
              let timeZone = TimeZone(identifier: identifier) else {
            return nil
        }
        return timeZone
    }
}
