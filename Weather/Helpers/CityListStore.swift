//
//  CityListStore.swift
//  Weather
//
//  Purpose: Persists city lists and provides their list and city mutations.
//

import SwiftUI
import CoreLocation
import WeatherKit

// MARK: - List Identity

enum CityListNameSource: Equatable, Hashable, Codable {
    case country(iso2: String, duplicateIndex: Int?)
    case continent(rawValue: String, duplicateIndex: Int?)

    enum CodingKeys: String, CodingKey {
        case kind
        case value
        case duplicateIndex
    }

    enum Kind: String, Codable {
        case country
        case continent
    }

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

    func withDuplicateIndex(_ index: Int?) -> CityListNameSource {
        switch self {
        case let .country(iso2, _):
            return .country(iso2: iso2, duplicateIndex: index)
        case let .continent(rawValue, _):
            return .continent(rawValue: rawValue, duplicateIndex: index)
        }
    }
}

struct CityListID: Identifiable, Equatable, Hashable, Codable {
    let rawValue: String
    let displayName: String
    let nameSource: CityListNameSource?

    init(rawValue: String, displayName: String, nameSource: CityListNameSource? = nil) {
        self.rawValue = rawValue
        self.displayName = displayName
        self.nameSource = nameSource
    }
    
    var id: String { rawValue }

    static func == (lhs: CityListID, rhs: CityListID) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
    
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    static let asia = CityListID(rawValue: "asia", displayName: "Asia")
    static let northAmerica = CityListID(rawValue: "northAmerica", displayName: "North America")
    static let southAmerica = CityListID(rawValue: "southAmerica", displayName: "South America")
    static let africa = CityListID(rawValue: "africa", displayName: "Africa")
    static let australia = CityListID(rawValue: "australia", displayName: "Australia")
    
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

    static let builtInLists: [CityListID] = [.europe, .asia, .northAmerica, .southAmerica, .africa, .australia]
    
    private static let userListsKey = "userCreatedLists"
    private static let deletedBuiltInListsKey = "deletedBuiltInLists"
    private static let listOrderKey = "listOrder"
    private static let customListNamesKey = "customListNames"
    private static let customCityNamesKey = "customCityNames"
    
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
    
    static func saveListOrder(_ lists: [CityListID]) {
        let ids = lists.map(\.rawValue)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: listOrderKey)
        }
    }

    private static func loadCustomListNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customListNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    static func customDisplayName(for rawValue: String) -> String? {
        loadCustomListNames()[rawValue]
    }

    static func saveCustomDisplayName(_ name: String, for rawValue: String) {
        var names = loadCustomListNames()
        names[rawValue] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: customListNamesKey)
        }
    }

    static func customCityName(for city: City) -> String? {
        loadCustomCityNames()[cityDisplayNameKey(for: city)]
    }

    static func saveCustomCityName(_ name: String, for city: City) {
        var names = loadCustomCityNames()
        names[cityDisplayNameKey(for: city)] = name
        if let data = try? JSONEncoder().encode(names) {
            UserDefaults.standard.set(data, forKey: customCityNamesKey)
        }
    }

    private static func loadCustomCityNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customCityNamesKey),
              let names = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return names
    }

    private static func cityDisplayNameKey(for city: City) -> String {
        "\(city.country)|\(String(format: "%.4f", city.latitude))|\(String(format: "%.4f", city.longitude))"
    }
    
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
    
    static func saveUserLists(_ lists: [CityListID]) {
        if let data = try? JSONEncoder().encode(lists) {
            UserDefaults.standard.set(data, forKey: userListsKey)
        }
    }
    
    private static func loadDeletedBuiltInIDs() -> Set<String> {
        let ids = UserDefaults.standard.stringArray(forKey: deletedBuiltInListsKey) ?? []
        return Set(ids)
    }
    
    static func deleteBuiltInList(_ listID: CityListID) {
        var deleted = loadDeletedBuiltInIDs()
        deleted.insert(listID.rawValue)
        UserDefaults.standard.set(Array(deleted), forKey: deletedBuiltInListsKey)
    }
    
    static func keepBuiltInLists(withRawValues selectedIDs: Set<String>) {
        let deleted = builtInLists
            .map(\.rawValue)
            .filter { !selectedIDs.contains($0) }
        UserDefaults.standard.set(deleted, forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
    }

    static func isBuiltInRawValue(_ rawValue: String) -> Bool {
        builtInLists.contains { $0.rawValue == rawValue }
    }
    
    static func createList(name: String, nameSource: CityListNameSource? = nil) -> CityListID {
        let id = CityListID(rawValue: UUID().uuidString, displayName: name, nameSource: nameSource)
        var userLists = loadUserLists()
        userLists.append(id)
        saveUserLists(userLists)
        return id
    }

    static func availableListName(for baseName: String) -> String {
        let existingNames = Set(allLists.map(\.displayName))
        guard existingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

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
    
    var defaultCities: [City] {
        CountryCityCatalog.topCities(forContinentRawValue: rawValue)
    }
}

// MARK: - Weather Service List Access

extension WeatherService {
    func cityListCoordinates(for listID: CityListID? = nil) -> [City] {
        let targetListID = listID ?? activeListID
        return loadSavedCities(for: targetListID) ?? targetListID.defaultCities
    }

    func listContainingCity(named name: String, country: String) -> CityListID? {
        availableLists.first { listID in
            cityListCoordinates(for: listID).contains { city in
                city.name == name && city.country == country
            }
        }
    }

    func listContainingCity(_ city: City) -> CityListID? {
        availableLists.first { listID in
            cityListCoordinates(for: listID).contains { savedCity in
                abs(savedCity.latitude - city.latitude) < 0.001
                    && abs(savedCity.longitude - city.longitude) < 0.001
            }
        } ?? listContainingCity(named: city.name, country: city.country)
    }

    // MARK: - Cities List Persistence
    
    /// Save the current list of cities (just the City objects, not the weather data)
    func saveCitiesList() {
        let cities = cityWeatherData.map { $0.city }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: citiesListKey)
        } catch {
            DeveloperWarningCenter.show(
                title: "City List Save Failed",
                message: "The active city list could not be encoded and saved: \(error.localizedDescription)"
            )
        }
    }

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
            DeveloperWarningCenter.show(
                title: "Saved City List Corrupt",
                message: "The saved city list for \(listID.rawValue) could not be decoded and was removed."
            )
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }

    // MARK: - List Mutations

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

    func moveLists(from source: IndexSet, to destination: Int) {
        var lists = availableLists
        lists.move(fromOffsets: source, toOffset: destination)
        CityListID.saveListOrder(lists)
        reloadAvailableLists()
    }

    // MARK: - City Mutations

    func removeCity(_ cityWeather: CityWeather) {
        cityWeatherData.removeAll { $0.id == cityWeather.id }
        // Update cache after removing city
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }

    func removeCity(_ cityWeather: CityWeather, from listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            removeCity(cityWeather)
            return
        }
        var listData = weatherDataByListID[listID.rawValue] ?? []
        listData.removeAll { $0.id == cityWeather.id }
        weatherDataByListID[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
    }

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
                destinationData.insert(cityWeather, at: 0)
                weatherDataByListID[destinationListID.rawValue] = destinationData
                cacheData(destinationData, for: destinationListID)
            }
        }

        removeCity(cityWeather, from: sourceListID)
    }
    
    func addCity(_ city: City) async {
        do {
            // Fetch weather for the new city
            errorMessage = nil
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            
            // Convert to our model
            let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
            
            // Add to the beginning of the list
            cityWeatherData.insert(cityWeather, at: 0)
            
            // Update cache with the new city included
            cacheData(cityWeatherData)
            
            // Save the updated cities list
            saveCitiesList()
            
        } catch {
            report(error)
        }
    }
    
    func addCityToList(_ city: City, listID: CityListID) async {
        let listKey = "savedCitiesList_\(listID.rawValue)"
        
        do {
            errorMessage = nil
            let location = CLLocation(latitude: city.latitude, longitude: city.longitude)
            let weather = try await weatherService.weather(for: location)
            let cityWeather = try await convertWeatherKitData(weather: weather, for: city)
            
            // Load existing cities for the target list
            var existingCities: [City] = []
            if let data = UserDefaults.standard.data(forKey: listKey),
               let cached = try? JSONDecoder().decode([CachedCity].self, from: data) {
                existingCities = cached.map { $0.toCity() }
            }
            existingCities.insert(city, at: 0)
            
            // Save updated cities list
            let encoded = try JSONEncoder().encode(existingCities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: listKey)
            
            // If this is the active list, also update in-memory data
            if listID == activeListID {
                cityWeatherData.insert(cityWeather, at: 0)
            } else {
                // Update weatherDataByListID if loaded
                weatherDataByListID[listID.rawValue]?.insert(cityWeather, at: 0)
            }
            
        } catch {
            report(error)
        }
    }

    func createCustomList(name: String, cities: [City], nameSource: CityListNameSource? = nil) async -> CityListID {
        let listID = CityListID.createList(name: name, nameSource: nameSource)
        reloadAvailableLists()
        saveCities(cities, for: listID)
        weatherDataByListID[listID.rawValue] = []
        await switchList(to: listID)
        return listID
    }

}

// MARK: - List Manager State and Actions

extension ContentView {

    var managedLists: [CityListID] {
        weatherService.availableLists
    }

    func refreshListOrder() {
        weatherService.reloadAvailableLists()
        AppDelegate.updateHomeScreenListShortcuts()
    }

    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        let destinationLists = managedLists.filter { $0.rawValue != listID.rawValue }

        if !destinationLists.isEmpty {
            Menu {
                ForEach(destinationLists) { destinationListID in
                    Button {
                        weatherService.moveCity(city, from: listID, to: destinationListID)
                        Haptics.lightImpact()
                    } label: {
                        primaryMenuLabel(
                            destinationListID.localizedDisplayName(locale: locale),
                            systemImage: "list.bullet"
                        )
                    }
                }
            } label: {
                primaryMenuLabel(localizedString("Move", locale: locale), systemImage: "arrow.right")
            }
        }

        Button {
            cityToRename = city.city
            cityRenameText = CityListID.customCityName(for: city.city)
                ?? localizedCityName(for: city.city)
            showingCityRenameAlert = true
        } label: {
            primaryMenuLabel(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button {
            removeDisplayedCity(city, from: listID)
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.colors.destructive)
            }
        }
        .tint(theme.colors.destructive)
    }

    func beginCreatingCustomList() {
        newListName = ""
        showingAddListAlert = true
    }

    // MARK: Map Reveal Actions

    func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            guard let revealedCity = weatherService.cityWeatherData.first(where: {
                $0.city.latitude == city.city.latitude && $0.city.longitude == city.city.longitude
            }) else {
                weatherService.reportDeveloperWarning(
                    title: "Map Reveal Failed",
                    message: "After switching to \(listID.rawValue), the requested city \(city.city.localizedName()) was not found in fetched weather data."
                )
                return
            }
            pushRoute(.map)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showingMapExpandedCard = false
                selectedMapCity = nil
            }
            centerMap(on: revealedCity)
            showMapMarkerCard(revealedCity)
        }
    }

    // MARK: Rename and Add Entry Points

    func commitListManagerNewList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = CityListID.createList(name: trimmed)
        refreshListOrder()
        newListName = ""
    }

    func switchToList(_ listID: CityListID) async {
        isShowingAllLists = false
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        centerMapOnDots(useListCoordinates: true)
    }

    func showAllLists() {
        listEditMode = false
        isShowingAllLists = true
        Task {
            await loadAllListsWeatherData()
            centerMapOnDots(useListCoordinates: true)
        }
    }

    func loadAllListsWeatherData() async {
        for listID in managedLists {
            await weatherService.fetchWeatherForList(listID)
        }

        var cities: [CityWeather] = []
        var sourceListIDs: [String: CityListID] = [:]

        for listID in managedLists {
            for cityWeather in weatherService.weatherData(for: listID) {
                let key = allListsCityKey(for: cityWeather.city)
                guard sourceListIDs[key] == nil else { continue }
                sourceListIDs[key] = listID
                cities.append(cityWeather)
            }
        }

        allListsWeatherData = cities
        allListsSourceListIDs = sourceListIDs
    }

    func sourceListID(for cityWeather: CityWeather) -> CityListID? {
        if isShowingAllLists {
            return allListsSourceListIDs[allListsCityKey(for: cityWeather.city)]
        }
        return weatherService.activeListID
    }

    func removeDisplayedCity(_ cityWeather: CityWeather, from listID: CityListID) {
        weatherService.removeCity(cityWeather, from: listID)
        guard isShowingAllLists else { return }

        let key = allListsCityKey(for: cityWeather.city)
        allListsWeatherData.removeAll { allListsCityKey(for: $0.city) == key }
        allListsSourceListIDs[key] = nil
    }

    private func allListsCityKey(for city: City) -> String {
        "\(city.country)|\(city.latitude)|\(city.longitude)"
    }

}

// MARK: - City List Actions

extension ContentView {
    func addCityToActiveList(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        Haptics.lightImpact()
        if let addedCity = weatherService.cityWeatherData.first(where: {
            $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country
        }) {
            selectedMapCity = addedCity
        }
    }

}
