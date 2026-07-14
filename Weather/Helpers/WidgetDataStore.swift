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
    let temperature: String
    let cloudCover: String
    let conditionIcon: String
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
}

struct WidgetDataList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let listName: String
    let title: String
    let topCityIDs: [String]
    let cities: [WidgetDataCity]
}

struct WidgetDataCatalog: Codable, Hashable {
    let activeListID: String
    let updatedAt: Date
    let lists: [WidgetDataList]
}

enum WidgetDataStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"
    static let kind = "BestSunnyPlacesWidget"

    static func cityIdentifier(for city: City, in listID: CityListID) -> String {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), city.latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), city.longitude)
        return "\(listID.rawValue)|\(city.country)|\(latitude)|\(longitude)"
    }

    static func save(_ catalog: WidgetDataCatalog) {
        guard let data = try? JSONEncoder().encode(catalog) else { return }
        UserDefaults(suiteName: appGroupIdentifier)?.set(data, forKey: catalogKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
