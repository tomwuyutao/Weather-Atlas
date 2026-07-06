//
//  ListManager.swift
//  Weather
//
//  Purpose: Lets users edit saved city lists, rename lists, reorder cities,
//  and manage list names.
//

import SwiftUI
import CoreLocation
import WeatherKit
#if canImport(Translation)
import Translation
#endif

// MARK: - List Identity

struct CityListID: Identifiable, Equatable, Hashable, Codable {
    let rawValue: String
    let displayName: String
    
    var id: String { rawValue }
    
    static let europe = CityListID(rawValue: "europe", displayName: "Europe")
    static let asia = CityListID(rawValue: "asia", displayName: "Asia")
    static let northAmerica = CityListID(rawValue: "northAmerica", displayName: "North America")
    static let southAmerica = CityListID(rawValue: "southAmerica", displayName: "South America")
    static let africa = CityListID(rawValue: "africa", displayName: "Africa")
    static let australia = CityListID(rawValue: "australia", displayName: "Australia")
    
    func localizedDisplayName(locale: Locale = .current) -> String {
        if let customName = Self.customDisplayName(for: rawValue) {
            return customName
        }
        switch rawValue {
        case "europe": return localizedString("Europe", locale: locale)
        case "asia": return localizedString("Asia", locale: locale)
        case "northAmerica": return localizedString("North America", locale: locale)
        case "southAmerica": return localizedString("South America", locale: locale)
        case "africa": return localizedString("Africa", locale: locale)
        case "australia": return localizedString("Australia", locale: locale)
        default: return displayName
        }
    }

    static let builtInLists: [CityListID] = [.europe, .asia, .northAmerica, .southAmerica, .africa, .australia]
    
    private static let userListsKey = "userCreatedLists"
    private static let deletedBuiltInListsKey = "deletedBuiltInLists"
    private static let listOrderKey = "listOrder"
    private static let customListNamesKey = "customListNames"
    
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
    
    static func restoreBuiltInLists() {
        UserDefaults.standard.removeObject(forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
    }

    static func keepBuiltInLists(withRawValues selectedIDs: Set<String>) {
        let deleted = builtInLists
            .map(\.rawValue)
            .filter { !selectedIDs.contains($0) }
        UserDefaults.standard.set(deleted, forKey: deletedBuiltInListsKey)
        UserDefaults.standard.removeObject(forKey: listOrderKey)
        UserDefaults.standard.removeObject(forKey: customListNamesKey)
    }

    static func addBuiltInLists(withRawValues selectedIDs: Set<String>) {
        var deleted = loadDeletedBuiltInIDs()
        deleted.subtract(selectedIDs)
        UserDefaults.standard.set(Array(deleted), forKey: deletedBuiltInListsKey)
    }
    
    static func createList(name: String) -> CityListID {
        let id = CityListID(rawValue: UUID().uuidString, displayName: name)
        var userLists = loadUserLists()
        userLists.append(id)
        saveUserLists(userLists)
        return id
    }
    
    var defaultCities: [City] {
        DefaultCityCoordinateCatalog.cities(for: rawValue)
    }
}

private enum DefaultCityCoordinateCatalog {
    static func cities(for listID: String) -> [City] {
        citiesByListID[listID] ?? []
    }

    private static let citiesByListID: [String: [City]] = {
        guard let url = Bundle.main.url(forResource: "default_city_coordinates", withExtension: "csv")
                ?? Bundle.main.url(forResource: "default_city_coordinates", withExtension: "csv", subdirectory: "Assets"),
              let csv = try? String(contentsOf: url, encoding: .utf8) else {
            DeveloperWarningCenter.show(
                title: "Default City Coordinates Missing",
                message: "The bundled default_city_coordinates.csv file could not be loaded. Default lists would become empty."
            )
            return [:]
        }

        var grouped: [String: [City]] = [:]
        for (rowIndex, line) in csv.split(whereSeparator: \.isNewline).dropFirst().enumerated() {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard fields.count == 6,
                  let latitude = Double(fields[3]),
                  let longitude = Double(fields[4]) else {
                DeveloperWarningCenter.show(
                    title: "Default City Coordinates Invalid",
                    message: "The bundled default_city_coordinates.csv row \(rowIndex + 2) is malformed and cannot be loaded."
                )
                continue
            }
            let cityName = fields[1]
            let countryName = fields[2]
            let timeZoneIdentifier = fields[5]
            guard TimeZone(identifier: timeZoneIdentifier) != nil else {
                DeveloperWarningCenter.show(
                    title: "Default City Time Zone Invalid",
                    message: "The bundled default_city_coordinates.csv row for \(latitude), \(longitude) has an invalid time zone identifier: \(timeZoneIdentifier)."
                )
                continue
            }
            grouped[fields[0], default: []].append(
                City(
                    name: cityName,
                    country: countryName,
                    latitude: latitude,
                    longitude: longitude,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            )
        }
        return grouped
    }()
}

// MARK: - Weather Service List Access

extension WeatherService {
    func cityListCoordinates(for listID: CityListID? = nil) -> [City] {
        let targetListID = listID ?? activeListID
        return loadSavedCities(for: targetListID) ?? targetListID.defaultCities
    }

    func listContainingCity(named name: String, country: String) -> CityListID? {
        CityListID.allLists.first { listID in
            cityListCoordinates(for: listID).contains { city in
                city.name == name && city.country == country
            }
        }
    }

    func listContainingCity(_ city: City) -> CityListID? {
        CityListID.allLists.first { listID in
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

    func addNewList(name: String) async {
        let newList = CityListID.createList(name: name)
        cityWeatherData = []
        activeListID = newList
        UserDefaults.standard.set(newList.rawValue, forKey: Self.activeListKey)
        lastFetchDate = nil
        // New list starts empty, no fetch needed
    }
    
    func renameCurrentList(to newName: String) {
        let renamed = CityListID(rawValue: activeListID.rawValue, displayName: newName)
        // Load raw user lists without filtering to find lists with empty names
        var userLists: [CityListID] = {
            guard let data = UserDefaults.standard.data(forKey: "userCreatedLists"),
                  let lists = try? JSONDecoder().decode([CityListID].self, from: data) else {
                return []
            }
            return lists
        }()
        if let index = userLists.firstIndex(where: { $0.rawValue == activeListID.rawValue }) {
            userLists[index] = renamed
            CityListID.saveUserLists(userLists)
        }
        activeListID = renamed
    }
    
    func deleteCurrentList() {
        let listToDelete = activeListID
        // Remove stored data for this list
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listToDelete.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listToDelete.rawValue)")
        otherListData[listToDelete.rawValue] = nil
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
        let remaining = CityListID.allLists
        if remaining.isEmpty {
            // All lists deleted — create a new empty list
            let newList = CityListID.createList(name: String(localized: "New List"))
            cityWeatherData = []
            activeListID = newList
            UserDefaults.standard.set(newList.rawValue, forKey: Self.activeListKey)
            lastFetchDate = nil
        } else {
            let nextList = remaining[0]
            activeListID = nextList
            UserDefaults.standard.set(nextList.rawValue, forKey: Self.activeListKey)
            cityWeatherData = otherListData[nextList.rawValue] ?? []
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
    }

    func deleteList(_ listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            deleteCurrentList()
            return
        }

        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        otherListData[listID.rawValue] = nil
        listFetchDates[listID.rawValue] = nil

        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.deleteBuiltInList(listID)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listID.rawValue }
            CityListID.saveUserLists(userLists)
        }
        CityListID.saveListOrder(CityListID.allLists)
    }

    func moveList(_ listID: CityListID, direction: ListMoveDirection) {
        var lists = CityListID.allLists
        guard let index = lists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let newIndex: Int
        switch direction {
        case .up:
            newIndex = max(0, index - 1)
        case .down:
            newIndex = min(lists.count - 1, index + 1)
        }
        guard newIndex != index else { return }
        lists.swapAt(index, newIndex)
        CityListID.saveListOrder(lists)
    }

    func moveLists(from source: IndexSet, to destination: Int) {
        var lists = CityListID.allLists
        lists.move(fromOffsets: source, toOffset: destination)
        CityListID.saveListOrder(lists)
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
        var listData = otherListData[listID.rawValue] ?? []
        listData.removeAll { $0.id == cityWeather.id }
        otherListData[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
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
                // Update otherListData if loaded
                otherListData[listID.rawValue]?.insert(cityWeather, at: 0)
            }
            
        } catch {
            report(error)
        }
    }

    func createCustomList(name: String, cities: [City]) async -> CityListID {
        let listID = CityListID.createList(name: name)
        saveCities(cities, for: listID)
        otherListData[listID.rawValue] = []
        await switchList(to: listID)
        return listID
    }

    func addCities(_ cities: [City], to listID: CityListID) async {
        guard !cities.isEmpty else { return }
        let existingCities = cityListCoordinates(for: listID)
        var mergedCities = existingCities
        for city in cities where !mergedCities.contains(where: { citiesMatch($0, city) }) {
            mergedCities.append(city)
        }

        saveCities(mergedCities, for: listID)
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        otherListData[listID.rawValue] = nil
        listFetchDates[listID.rawValue] = nil

        if listID.rawValue == activeListID.rawValue {
            cityWeatherData = []
            lastFetchDate = nil
            await fetchWeatherForAllCities(forceRefresh: true)
        }
    }

    func moveCity(from source: IndexSet, to destination: Int) {
        var reorderedCities = cityWeatherData
        reorderedCities.move(fromOffsets: source, toOffset: destination)
        cityWeatherData = reorderedCities
        // Update cache after reordering cities
        cacheData(cityWeatherData)
        // Save the updated cities list
        saveCitiesList()
    }

    func moveCity(in listID: CityListID, from source: IndexSet, to destination: Int) {
        if listID.rawValue == activeListID.rawValue {
            moveCity(from: source, to: destination)
            return
        }
        var listData = otherListData[listID.rawValue] ?? []
        listData.move(fromOffsets: source, toOffset: destination)
        otherListData[listID.rawValue] = listData
        saveCities(listData.map(\.city), for: listID)
        cacheData(listData, for: listID)
    }

    func moveCity(id cityID: String, from sourceListID: CityListID, to targetListID: CityListID, destination: Int?) -> Bool {
        var sourceData = weatherData(for: sourceListID)
        guard let sourceIndex = sourceData.firstIndex(where: { $0.id.uuidString == cityID }) else { return false }
        let city = sourceData.remove(at: sourceIndex)

        var targetData = sourceListID == targetListID ? sourceData : weatherData(for: targetListID)
        let rawDestination = destination ?? targetData.count
        let adjustedDestination: Int
        if sourceListID == targetListID, rawDestination > sourceIndex {
            adjustedDestination = max(0, min(targetData.count, rawDestination - 1))
        } else {
            adjustedDestination = max(0, min(targetData.count, rawDestination))
        }
        targetData.insert(city, at: adjustedDestination)

        setWeatherData(sourceData, for: sourceListID)
        if sourceListID == targetListID {
            setWeatherData(targetData, for: sourceListID)
        } else {
            setWeatherData(targetData, for: targetListID)
        }
        return true
    }

    private func setWeatherData(_ data: [CityWeather], for listID: CityListID) {
        if listID.rawValue == activeListID.rawValue {
            cityWeatherData = data
            cacheData(cityWeatherData)
            saveCitiesList()
        } else {
            otherListData[listID.rawValue] = data
            saveCities(data.map(\.city), for: listID)
            cacheData(data, for: listID)
        }
    }
}

enum ListMoveDirection {
    case up
    case down
}

// MARK: - List Manager State and Actions

extension ContentView {

    var managedLists: [CityListID] {
        _ = listOrderRevision
        return CityListID.allLists
    }

    func managedCities(for listID: CityListID) -> [CityWeather] {
        _ = cityOrderRevision
        return weatherService.weatherData(for: listID)
    }

    func managedCityCount(for listID: CityListID) -> Int {
        let cities = managedCities(for: listID)
        return cities.isEmpty ? weatherService.cityListCoordinates(for: listID).count : cities.count
    }

    func refreshListOrder() {
        listOrderRevision += 1
        AppDelegate.updateHomeScreenListShortcuts()
    }

    func refreshCityOrder() {
        cityOrderRevision += 1
    }

    @ViewBuilder
    func listActions(for listID: CityListID) -> some View {
        Button {
            beginRenamingList(listID)
        } label: {
            Label {
                Text(localizedString("Rename", locale: locale))
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)

        Button {
            beginAddingCity(to: listID)
        } label: {
            Label {
                Text(localizedString("Add City", locale: locale))
            } icon: {
                Image(systemName: "plus")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)

        Button {
            weatherService.deleteList(listID)
            refreshListOrder()
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
    }

    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            weatherService.removeCity(city, from: listID)
            refreshCityOrder()
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
    }

    func beginCreatingListFromSwitcher() {
        beginCreatingCustomList()
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
                tappedCity = nil
            }
            centerOnCityTrigger = revealedCity
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
            }
        }
    }

    func revealDefaultCityOnMap(_ city: City, in listID: CityListID) {
        Task {
            pushRoute(.map)

            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showingMapExpandedCard = false
                tappedCity = nil
            }

            let revealedCity = await weatherService.switchList(to: listID, prioritizing: city)
            mapRecenterRequest = .listCoordinates
            refreshCityOrder()

            guard let revealedCity else { return }
            centerOnCityTrigger = revealedCity
            try? await Task.sleep(for: .milliseconds(350))
            await MainActor.run {
                showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
            }
        }
    }

    // MARK: Rename and Add Entry Points

    func commitListManagerNewList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newList = CityListID.createList(name: trimmed)
        refreshListOrder()
        expandedListIDs.insert(newList.rawValue)
        newListName = ""
    }

    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        mapRecenterRequest = .listCoordinates
    }

    private func beginRenamingList(_ listID: CityListID) {
        listToRenameID = listID
        renameAlertText = listID.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func beginAddingCity(to listID: CityListID) {
        searchAddTargetListID = listID
        pushRoute(.map)
        searchText = ""
        activateSearch()
    }
}

// MARK: - List Manager View

extension ContentView {

    var listManagerContent: some View {
        List {
            Section {
                listManagerRows
            }
            .listRowBackground(listManagerBackground)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(listManagerBackground)
        .tint(theme.colors.accent)
        .environment(\.editMode, $listManagerEditMode)
        .onAppear {
            if expandedListIDs.isEmpty {
                expandedListIDs.insert(weatherService.activeListID.rawValue)
            }
        }
    }

    private var listManagerRowsHideWeatherDecorations: Bool {
        listManagerEditMode.isEditing
    }

    // MARK: List Rows

    @ViewBuilder
    private var listManagerRows: some View {
        ForEach(managedLists) { listID in
            DisclosureGroup(isExpanded: listExpansionBinding(for: listID)) {
                let cities = managedCities(for: listID)
                if cities.isEmpty {
                    let defaultCities = weatherService.cityListCoordinates(for: listID)
                    if defaultCities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 10)
                            .padding(.leading, 22)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(defaultCities) { city in
                            Button {
                                revealDefaultCityOnMap(city, in: listID)
                            } label: {
                                listManagerDefaultCityRow(city)
                            }
                            .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    ForEach(cities) { city in
                        Button {
                            revealCityOnMap(city, in: listID)
                        } label: {
                            listManagerCityRow(city)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            cityActions(for: city, in: listID)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        moveManagedCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteManagedCities(in: listID, at: offsets)
                    }
                }
            } label: {
                listManagerListHeader(listID)
                    .contextMenu {
                        listActions(for: listID)
                    }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 28))
            .task(id: listID.rawValue) {
                await weatherService.fetchWeatherForList(listID)
                await MainActor.run {
                    refreshCityOrder()
                }
            }
        }
        .onMove(perform: moveManagedLists)
        .onDelete(perform: deleteManagedLists)
    }

    private func listManagerListHeader(_ listID: CityListID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !listManagerRowsHideWeatherDecorations {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10, height: 18)
                }

                Text(listID.localizedDisplayName(locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if !listManagerRowsHideWeatherDecorations {
                    Text("\(managedCityCount(for: listID))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.colors.mapLand, in: Capsule())
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(theme.colors.primaryText.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, -10)
                .padding(.trailing, -26)
        }
        .contentShape(Rectangle())
    }

    private func listManagerDefaultCityRow(_ city: City) -> some View {
        HStack(spacing: 10) {
            if !listManagerRowsHideWeatherDecorations {
                Circle()
                    .fill(theme.colors.secondaryText.opacity(0.45))
                    .frame(width: 10, height: 10)
                    .frame(width: 10, alignment: .center)
            }

            Text(city.localizedName(locale: locale))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)
        }
        .padding(.vertical, 9)
        .padding(.leading, -18)
        .contentShape(Rectangle())
    }

    private func listManagerCityRow(_ city: CityWeather) -> some View {
        let dotColor = city.weatherIcon.contains("moon") ? theme.colors.moonIconColor : city.condition.dotColor(for: theme.colors)

        return HStack(spacing: 10) {
            if !listManagerRowsHideWeatherDecorations {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.35), radius: 3)
                    .frame(width: 10, alignment: .center)
            }

            Text(city.city.localizedName(locale: locale))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            if !listManagerRowsHideWeatherDecorations {
                Text(tempUnit.display(city.temperature))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
        .padding(.leading, -18)
        .contentShape(Rectangle())
    }

    // MARK: Reordering and Deletion

    private func moveManagedLists(from source: IndexSet, to destination: Int) {
        weatherService.moveLists(from: source, to: destination)
        refreshListOrder()
        Haptics.lightImpact()
    }

    private func deleteManagedLists(at offsets: IndexSet) {
        let lists = managedLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            weatherService.deleteList(lists[index])
        }
        refreshListOrder()
        Haptics.lightImpact()
    }

    private func moveManagedCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        refreshCityOrder()
        Haptics.lightImpact()
    }

    private func deleteManagedCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = managedCities(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        refreshCityOrder()
        Haptics.lightImpact()
    }

    private func listExpansionBinding(for listID: CityListID) -> Binding<Bool> {
        Binding {
            expandedListIDs.contains(listID.rawValue)
        } set: { isExpanded in
            if isExpanded {
                expandedListIDs.insert(listID.rawValue)
                Task { await weatherService.fetchWeatherForList(listID) }
            } else {
                expandedListIDs.remove(listID.rawValue)
            }
        }
    }

}

// MARK: - City List Actions

extension ContentView {
    func cityIsInActiveList(_ cityWeather: CityWeather) -> Bool {
        weatherService.cityWeatherData.contains {
            $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country
        }
    }

    func addCityToActiveList(_ cityWeather: CityWeather) async {
        await weatherService.addCity(cityWeather.city)
        Haptics.lightImpact()
        if let addedCity = weatherService.cityWeatherData.first(where: {
            $0.city.name == cityWeather.city.name && $0.city.country == cityWeather.city.country
        }) {
            tappedCity = addedCity
        }
    }

    func detailActionsMenu(for city: CityWeather) -> some View {
        Menu {
            if cityIsInActiveList(city) {
                Button(localizedString("Delete City", locale: locale), systemImage: "trash", role: .destructive) {
                    weatherService.removeCity(city)
                    dismissRoute(.cityDetail(city.id))
                    showingMapExpandedCard = false
                    tappedCity = nil
                    selectedDayOffset = 0
                    if isMapRoute {
                        mapRecenterRequest = .listCoordinates
                    }
                }
                .tint(theme.colors.destructive)
            } else {
                Button {
                    Task {
                        await addCityToActiveList(city)
                        dismissRoute(.cityDetail(city.id))
                        if isMapRoute {
                            mapRecenterRequest = .listCoordinates
                        }
                    }
                } label: {
                    Label {
                        Text(localizedString("Add City", locale: locale))
                            .foregroundStyle(theme.colors.primaryText)
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.colors.primaryText)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.colors.primaryText)
                .foregroundColor(.primary)
        }
        .menuOrder(.fixed)
        .tint(theme.colors.primaryText)
    }

}
