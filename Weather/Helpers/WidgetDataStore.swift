//
//  WidgetDataStore.swift
//  Weather
//
//  Purpose: Shares city weather data with the WidgetKit extension.
//

import Foundation
import WidgetKit

struct WidgetDataCity: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let timeZoneIdentifier: String?
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
}

struct WidgetDataList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let cities: [WidgetDataCity]
}

struct WidgetDataCatalog: Codable, Hashable {
    let lists: [WidgetDataList]
}

enum WidgetDataStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    static let kind = "BestSunnyPlacesWidget"

    static func cityIdentifier(country: String, latitude: Double, longitude: Double, listID: String) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), longitude)
        return "\(listID)|\(country)|\(latitude)|\(longitude)"
    }

    static func catalog() -> WidgetDataCatalog? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetDataCatalog.self, from: data)
    }

    static func save(_ catalog: WidgetDataCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
