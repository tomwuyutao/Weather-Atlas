//
//  CityListStore.swift
//  Weather
//
//  Purpose: Persists city lists and provides their list and city mutations.
//

import SwiftUI

// MARK: - List Identity

/// Canonical geographic origin retained separately from a list's editable name.
enum CityListNameSource: Equatable, Hashable, Codable {
    case country(iso2: String, duplicateIndex: Int?)
    case continent(rawValue: String, duplicateIndex: Int?)

    /// Stable encoded fields for the associated-value enum.
    enum CodingKeys: String, CodingKey {
        case kind
        case value
        case duplicateIndex
    }

    /// Discriminator persisted alongside the source value.
    enum Kind: String, Codable {
        case country
        case continent
    }

    /// Restores a country or continent source from its stable tagged payload.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let value = try container.decode(String.self, forKey: .value)
        let duplicateIndex = try container.decodeIfPresent(Int.self, forKey: .duplicateIndex)

        switch kind {
        case .country:
            self = .country(iso2: value, duplicateIndex: duplicateIndex)
        case .continent:
            self = .continent(rawValue: value, duplicateIndex: duplicateIndex)
        }
    }

    /// Persists the source kind, canonical value, and optional duplicate suffix.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .country(iso2, duplicateIndex):
            try container.encode(Kind.country, forKey: .kind)
            try container.encode(iso2, forKey: .value)
            try container.encodeIfPresent(duplicateIndex, forKey: .duplicateIndex)
        case let .continent(rawValue, duplicateIndex):
            try container.encode(Kind.continent, forKey: .kind)
            try container.encode(rawValue, forKey: .value)
            try container.encodeIfPresent(duplicateIndex, forKey: .duplicateIndex)
        }
    }

    /// Resolves the canonical geographic label and optional duplicate number.
    func localizedDisplayName(locale: Locale) -> String {
        let baseName: String
        let duplicateIndex: Int?

        switch self {
        case let .country(iso2, index):
            baseName = locale.localizedString(forRegionCode: iso2) ?? iso2
            duplicateIndex = index
        case let .continent(rawValue, index):
            baseName = CityListID.localizedBuiltInDisplayName(for: rawValue, locale: locale) ?? rawValue
            duplicateIndex = index
        }

        guard let duplicateIndex else { return baseName }
        return "\(baseName) \(duplicateIndex)"
    }

    /// Copies the geographic source while replacing only its duplicate suffix.
    func withDuplicateIndex(_ index: Int?) -> CityListNameSource {
        switch self {
        case let .country(iso2, _):
            return .country(iso2: iso2, duplicateIndex: index)
        case let .continent(rawValue, _):
            return .continent(rawValue: rawValue, duplicateIndex: index)
        }
    }
}

/// Stable list identity plus editable and canonical naming metadata.
struct CityListID: Identifiable, Equatable, Hashable, Codable {
    /// Persistence key; equality and hashing intentionally use only this value.
    let rawValue: String
    /// Stored display name used for custom lists and migration compatibility.
    let displayName: String
    /// Optional canonical country/continent origin for generated lists.
    let nameSource: CityListNameSource?

    /// Creates a list identity from stable and user-facing naming values.
    init(rawValue: String, displayName: String, nameSource: CityListNameSource? = nil) {
        self.rawValue = rawValue
        self.displayName = displayName
        self.nameSource = nameSource
    }
    
    /// SwiftUI identity matching the persisted raw value.
    var id: String { rawValue }

    /// Compares stable list identity rather than an editable name.
    static func == (lhs: CityListID, rhs: CityListID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    /// Hashes stable list identity to match equality semantics.
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
    
    /// Built-in Europe list identity.
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    /// Built-in Asia list identity.
    static let asia = CityListID(rawValue: "asia", displayName: "Asia")
    /// Built-in North America list identity.
    static let northAmerica = CityListID(rawValue: "northAmerica", displayName: "North America")
    /// Built-in South America list identity.
    static let southAmerica = CityListID(rawValue: "southAmerica", displayName: "South America")
    /// Built-in Africa list identity.
    static let africa = CityListID(rawValue: "africa", displayName: "Africa")
    /// Built-in Australia list identity.
    static let australia = CityListID(rawValue: "australia", displayName: "Australia")

    /// Resolves custom rename, canonical source, localization, then stored name.
    func localizedDisplayName(locale: Locale = .current) -> String {
        if let customName = Self.customDisplayName(for: rawValue),
           !(Self.isBuiltInRawValue(rawValue) && customName == displayName) {
            return customName
        }
        if let nameSource {
            return nameSource.localizedDisplayName(locale: locale)
        }
        if displayName == "New List" {
            return localizedString("New List", locale: locale)
        }
        return Self.localizedBuiltInDisplayName(for: rawValue, locale: locale) ?? displayName
    }

    /// The canonical place name used by list-creation catalogs. Unlike
    /// `localizedDisplayName`, this intentionally ignores a saved list rename.
    func canonicalLocalizedDisplayName(locale: Locale = .current) -> String {
        if let nameSource {
            return nameSource.localizedDisplayName(locale: locale)
        }
        return Self.localizedBuiltInDisplayName(for: rawValue, locale: locale) ?? displayName
    }

    /// Returns the localized canonical label for a known built-in raw value.
    static func localizedBuiltInDisplayName(for rawValue: String, locale: Locale = .current) -> String? {
        switch rawValue {
        case "europe": return localizedString("Europe", locale: locale)
        case "asia": return localizedString("Asia", locale: locale)
        case "northAmerica": return localizedString("North America", locale: locale)
        case "southAmerica": return localizedString("South America", locale: locale)
        case "africa": return localizedString("Africa", locale: locale)
        case "australia": return localizedString("Australia", locale: locale)
        default: return nil
        }
    }

    /// Complete built-in list catalog in its default order.
    static let builtInLists: [CityListID] = [.europe, .asia, .northAmerica, .southAmerica, .africa, .australia]

    /// Preference key containing encoded user-created list identities.
    private static let userListsKey = "userCreatedLists"
    /// Preference key containing hidden built-in raw values.
    private static let deletedBuiltInListsKey = "deletedBuiltInLists"
    /// Preference key containing the user's cross-list order.
    private static let listOrderKey = "listOrder"
    /// Preference key mapping list raw values to user renames.
    private static let customListNamesKey = "customListNames"
    /// Preference key mapping stable city keys to user renames.
    private static let customCityNamesKey = "customCityNames"

    /// Available built-in and custom lists, reconciled with the saved order.
    static var allLists: [CityListID] {
        let deletedIDs = loadDeletedBuiltInIDs()
        // Build the unordered pool of available lists
        let availableBuiltIn = builtInLists.filter { !deletedIDs.contains($0.rawValue) }
        let userLists = loadUserLists()
        let allAvailable = availableBuiltIn + userLists
        
        // Apply custom order if saved
        if let orderData = UserDefaults.standard.data(forKey: listOrderKey),
           let orderedIDs = try? JSONDecoder().decode([String].self, from: orderData) {
            let lookup = Dictionary(uniqueKeysWithValues: allAvailable.map { ($0.rawValue, $0) })
            var ordered = orderedIDs.compactMap { lookup[$0] }
            // Append any lists not in the saved order (newly created)
            let orderedSet = Set(orderedIDs)
            for list in allAvailable where !orderedSet.contains(list.rawValue) {
                ordered.append(list)
            }
            return ordered
        }
        
        return allAvailable
    }
    
    /// Persists only stable raw values for the current cross-list order.
    static func saveListOrder(_ lists: [CityListID]) {
        let ids = lists.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: listOrderKey)
        }
    }

    /// Decodes the custom list-name lookup, returning empty on absent storage.
    private static func loadCustomListNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customListNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    /// Looks up a user rename for one stable list raw value.
    static func customDisplayName(for rawValue: String) -> String? {
        loadCustomListNames()[rawValue]
    }

    /// Persists a user rename without mutating the list's canonical source.
    static func saveCustomDisplayName(_ name: String, for rawValue: String) {
        var names = loadCustomListNames()
        names[rawValue] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: customListNamesKey)
        }
    }

    /// Looks up a city rename using current and legacy stable keys.
    static func customCityName(for city: City) -> String? {
        let names = loadCustomCityNames()
        let stableLocale = Locale(identifier: "en_US_POSIX")
        let latitude = String(format: "%.4f", locale: stableLocale, city.latitude)
        let longitude = String(format: "%.4f", locale: stableLocale, city.longitude)
        return names[cityDisplayNameKey(for: city)]
            // Preserve names saved by versions whose key omitted the city name.
            ?? names["\(city.country)|\(latitude)|\(longitude)"]
    }

    /// Persists a user-facing city rename under the current stable key format.
    static func saveCustomCityName(_ name: String, for city: City) {
        var names = loadCustomCityNames()
        names[cityDisplayNameKey(for: city)] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: customCityNamesKey)
        }
    }

    /// Decodes the custom city-name lookup, returning empty on absent storage.
    private static func loadCustomCityNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customCityNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    /// Builds a locale-stable city key from name, country, and rounded coordinates.
    private static func cityDisplayNameKey(for city: City) -> String {
        let stableLocale = Locale(identifier: "en_US_POSIX")
        let latitude = String(format: "%.4f", locale: stableLocale, city.latitude)
        let longitude = String(format: "%.4f", locale: stableLocale, city.longitude)
        return "\(city.name)|\(city.country)|\(latitude)|\(longitude)"
    }

    /// Decodes and validates user-created list identities from preferences.
    static func loadUserLists() -> [CityListID] {
        guard let data = UserDefaults.standard.data(forKey: userListsKey) else {
            return []
        }
        guard let lists = try? JSONDecoder().decode([CityListID].self, from: data) else {
            DeveloperWarningCenter.show(
                title: "User Lists Corrupt",
                message: "The saved user-created lists could not be decoded."
            )
            return []
        }
        let validLists = lists.filter { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if validLists.count != lists.count {
            DeveloperWarningCenter.show(
                title: "User List Name Missing",
                message: "A saved user-created list had an empty name and was removed instead of being renamed automatically."
            )
            saveUserLists(validLists)
        }
        return validLists
    }
    
    /// Encodes all user-created list identities into preferences.
    static func saveUserLists(_ lists: [CityListID]) {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: userListsKey)
        }
    }
    
    /// Returns built-in raw values the user has chosen to hide.
    private static func loadDeletedBuiltInIDs() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: deletedBuiltInListsKey) ?? []
        return Set(ids)
    }
    
    /// Marks a built-in identity hidden without deleting its catalog definition.
    static func deleteBuiltInList(_ listID: CityListID) {
        var deleted = loadDeletedBuiltInIDs()
        deleted.insert(listID.rawValue)
        UserDefaults.standard.set(Array(deleted), forKey: deletedBuiltInListsKey)
    }
    
    /// Replaces the visible built-in set during first-list tutorial selection.
    static func keepBuiltInLists(withRawValues selectedIDs: Set<String>) {
        let deleted = builtInLists
            .map(\.rawValue)
            .filter { !selectedIDs.contains($0) }
        UserDefaults.standard.set(deleted, forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
    }

    /// Whether a raw value belongs to the immutable built-in catalog.
    static func isBuiltInRawValue(_ rawValue: String) -> Bool {
        builtInLists.contains { $0.rawValue == rawValue }
    }
    
    /// Creates and persists a new user list with a UUID-backed identity.
    static func createList(name: String, nameSource: CityListNameSource? = nil) -> CityListID {
        let id = CityListID(rawValue: UUID().uuidString, displayName: name, nameSource: nameSource)
        var userLists = loadUserLists()
        userLists.append(id)
        saveUserLists(userLists)
        return id
    }

    /// Appends the first available numeric suffix to a duplicate list name.
    static func availableListName(for baseName: String) -> String {
        let existingNames = Set(allLists.map(\.displayName))
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    /// Finds an unused localized name while preserving canonical source metadata.
    static func availableGeneratedListIdentity(
        for source: CityListNameSource,
        locale: Locale
    ) -> (displayName: String, nameSource: CityListNameSource) {
        let sourceWithoutSuffix = source.withDuplicateIndex(nil)
        let existingNames = Set(allLists.map { $0.localizedDisplayName(locale: locale) })
        let baseName = sourceWithoutSuffix.localizedDisplayName(locale: locale)
        guard existingNames.contains(baseName) else {
            return (baseName, sourceWithoutSuffix)
        }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return ("\(baseName) \(suffix)", sourceWithoutSuffix.withDuplicateIndex(suffix))
    }
    
    /// Population-ranked bundled cities for this built-in continent identity.
    var defaultCities: [City] {
        CountryCityCatalog.topCities(forContinentRawValue: rawValue)
    }
}

// MARK: - Weather Service List Access

extension WeatherService {
    /// Returns a saved coordinate list or the built-in list's catalog defaults.
    func cityListCoordinates(for listID: CityListID? = nil) -> [City] {
        let targetListID = listID ?? activeListID
        return loadSavedCities(for: targetListID) ?? targetListID.defaultCities
    }

    /// Finds the first available list containing a coordinate-equivalent city.
    func listContainingCity(_ city: City) -> CityListID? {
        availableLists.first { listID in
            cityListCoordinates(for: listID).contains {
                citiesMatch($0, city)
            }
        }
    }

    // MARK: - Cities List Persistence
    
    /// Save the current list of cities (just the City objects, not the weather data)
    func saveCitiesList() {
        let cities = cityWeatherData.map { $0.city }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(cities.map { CachedCity(from: $0) })
            // Preserve the active list's legacy saved-coordinate key.
            UserDefaults.standard.set(
                encoded,
                forKey: "savedCitiesList_\(activeListID.rawValue)"
            )
        } catch {
            DeveloperWarningCenter.show(
                title: "City List Save Failed",
                message: "The active city list could not be encoded and saved: \(error.localizedDescription)"
            )
        }
    }

    /// Persists source city coordinates for a specific list identity.
    func saveCities(_ cities: [City], for listID: CityListID) {
        let key = "savedCitiesList_\(listID.rawValue)"
        do {
            let encoded = try JSONEncoder().encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
            DeveloperWarningCenter.show(
                title: "City List Save Failed",
                message: "The city list for \(listID.rawValue) could not be encoded and saved: \(error.localizedDescription)"
            )
        }
    }
    
    /// Rejects impossible coordinates, excessive names, and unsafe characters.
    func isValidPersistedCity(_ city: City) -> Bool {
        let name = city.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return false }
        guard name.count <= 80 else { return false }
        if name.isEmpty { return true }

        let allowedNameScalars = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-'’.(),"))
        return name.unicodeScalars.allSatisfy { allowedNameScalars.contains($0) }
    }
    
    /// Load the saved cities list (returns nil if no list was saved)
    func loadSavedCities(for listID: CityListID) -> [City]? {
        let key = "savedCitiesList_\(listID.rawValue)"
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            let cachedCities = try decoder.decode([CachedCity].self, from: data)
            let cities = cachedCities.compactMap { cached -> City? in
                let city = cached.toCity()
                return isValidPersistedCity(city) ? city : nil
            }
            if cities.count != cachedCities.count {
                saveCities(cities, for: listID)
            }
            return cities
        } catch {
            DeveloperWarningCenter.showOnce(
                key: "saved-city-list-corrupt-\(listID.rawValue)",
                title: "Saved City List Corrupt",
                message: "The saved city list for \(listID.rawValue) could not be decoded. Its cities will remain hidden until the list is replaced or edited."
            )
            // Keep the corrupt payload distinguishable from an absent payload.
            // Returning an explicit empty list prevents bundled defaults from
            // silently replacing the user's missing persisted data.
            return []
        }
    }

    // MARK: - List Mutations

    /// Deletes the active list, its cache, and selects or creates a replacement.
    func deleteCurrentList() {
        let listToDelete = activeListID
        // Remove stored data for this list
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listToDelete.rawValue)")
        removeCache(for: listToDelete)
        weatherDataByListID[listToDelete.rawValue] = nil
        listFetchDates[listToDelete.rawValue] = nil
        // Remove from user lists or mark built-in as deleted
        if CityListID.builtInLists.contains(where: { $0.rawValue == listToDelete.rawValue }) {
            CityListID.deleteBuiltInList(listToDelete)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listToDelete.rawValue }
            CityListID.saveUserLists(userLists)
        }
        // Switch to the first available list, or create a default one if none left
        reloadAvailableLists()
        let remaining = availableLists
        if remaining.isEmpty {
            // All lists deleted — create a new empty list
            let appLanguage = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            let newList = CityListID.createList(
                name: localizedString("New List", locale: Locale(identifier: appLanguage))
            )
            reloadAvailableLists()
            cityWeatherData = []
            activeListID = newList
            UserDefaults.standard.set(newList.rawValue, forKey: Self.activeListKey)
            lastFetchDate = nil
        } else {
            let nextList = remaining[0]
            activeListID = nextList
            UserDefaults.standard.set(nextList.rawValue, forKey: Self.activeListKey)
            cityWeatherData = weatherDataByListID[nextList.rawValue] ?? []
            lastFetchDate = fetchDate(for: nextList)
            Task {
                await fetchWeatherForAllCities()
            }
        }
    }

    /// Persists a trimmed rename while preserving stable and canonical identity.
    func renameList(_ listID: CityListID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.saveCustomDisplayName(trimmed, for: listID.rawValue)
            if activeListID.rawValue == listID.rawValue {
                activeListID = CityListID(rawValue: listID.rawValue, displayName: trimmed)
            }
            reloadAvailableLists()
            return
        }

        var userLists = CityListID.loadUserLists()
        guard let index = userLists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let renamed = CityListID(rawValue: listID.rawValue, displayName: trimmed)
        userLists[index] = renamed
        CityListID.saveUserLists(userLists)
        if activeListID.rawValue == listID.rawValue {
            activeListID = renamed
        }
        reloadAvailableLists()
    }

    /// Deletes any list, delegating active-list replacement when necessary.
    func deleteList(_ listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            deleteCurrentList()
            return
        }

        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listID.rawValue)")
        removeCache(for: listID)
        weatherDataByListID[listID.rawValue] = nil
        listFetchDates[listID.rawValue] = nil

        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.deleteBuiltInList(listID)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listID.rawValue }
            CityListID.saveUserLists(userLists)
        }
        CityListID.saveListOrder(CityListID.allLists)
        reloadAvailableLists()
    }

    /// Applies and persists a user drag-reorder across all available lists.
    func moveLists(from source: IndexSet, to destination: Int) {
        var lists = availableLists
        lists.move(fromOffsets: source, toOffset: destination)
        CityListID.saveListOrder(lists)
        reloadAvailableLists()
    }

    // MARK: - City Mutations

    /// Removes a city from the active list, weather cache, and coordinate store.
    func removeCity(_ cityWeather: CityWeather) {
        cityWeatherData.removeAll { citiesMatch($0.city, cityWeather.city) }
        // Update cache after removing city
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }

    /// Removes a city from an arbitrary loaded or unloaded list.
    func removeCity(_ cityWeather: CityWeather, from listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            removeCity(cityWeather)
            return
        }

        let savedCities = cityListCoordinates(for: listID)
        let updatedCities = savedCities.filter {
            !citiesMatch($0, cityWeather.city)
        }
        saveCities(updatedCities, for: listID)

        if var listData = weatherDataByListID[listID.rawValue] {
            listData.removeAll { citiesMatch($0.city, cityWeather.city) }
            weatherDataByListID[listID.rawValue] = listData
            cacheData(listData, for: listID)
        } else {
            // The persisted coordinate list is authoritative when this list has
            // not been loaded in the current process.
            removeCache(for: listID)
        }
    }

    /// Adds a city to its destination before removing it from the source list.
    func moveCity(_ cityWeather: CityWeather, from sourceListID: CityListID, to destinationListID: CityListID) {
        guard sourceListID.rawValue != destinationListID.rawValue else { return }

        let destinationCities = cityListCoordinates(for: destinationListID)
        let alreadyInDestination = destinationCities.contains {
            citiesMatch($0, cityWeather.city)
        }

        if !alreadyInDestination {
            let updatedDestinationCities = [cityWeather.city] + destinationCities
            saveCities(updatedDestinationCities, for: destinationListID)

            if destinationListID.rawValue == activeListID.rawValue {
                cityWeatherData.insert(cityWeather, at: 0)
                cacheData(cityWeatherData)
            } else if var destinationData = weatherDataByListID[destinationListID.rawValue] {
                if !destinationData.contains(where: { citiesMatch($0.city, cityWeather.city) }) {
                    destinationData.insert(cityWeather, at: 0)
                }
                weatherDataByListID[destinationListID.rawValue] = destinationData
                cacheData(destinationData, for: destinationListID)
            } else {
                // The saved city list is authoritative. An unloaded destination may
                // still have a fresh snapshot that does not contain the moved city.
                removeCache(for: destinationListID)
            }
        }

        removeCity(cityWeather, from: sourceListID)
    }
    
    /// Inserts a unique city and reconciles loaded weather and persisted caches.
    @discardableResult
    func addCityToList(_ cityWeather: CityWeather, listID: CityListID) -> Bool {
        let city = cityWeather.city
        let existingCities = cityListCoordinates(for: listID)
        guard !existingCities.contains(where: { citiesMatch($0, city) }) else {
            return false
        }

        saveCities([city] + existingCities, for: listID)

        if listID.rawValue == activeListID.rawValue {
            if !cityWeatherData.contains(where: { citiesMatch($0.city, city) }) {
                cityWeatherData.insert(cityWeather, at: 0)
            }
            cacheData(cityWeatherData)
        } else if var listData = weatherDataByListID[listID.rawValue] {
            if !listData.contains(where: { citiesMatch($0.city, city) }) {
                listData.insert(cityWeather, at: 0)
            }
            weatherDataByListID[listID.rawValue] = listData
            cacheData(listData, for: listID)
        } else {
            // Prevent a fresh, unloaded snapshot from hiding the newly saved city.
            removeCache(for: listID)
        }

        return true
    }

    /// Creates, seeds, activates, and fetches a custom city collection.
    func createCustomList(name: String, cities: [City], nameSource: CityListNameSource? = nil) async -> CityListID {
        let listID = CityListID.createList(name: name, nameSource: nameSource)
        reloadAvailableLists()
        saveCities(cities, for: listID)
        weatherDataByListID[listID.rawValue] = []
        await switchList(to: listID)
        return listID
    }

}
