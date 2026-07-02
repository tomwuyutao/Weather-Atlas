//
//  ListManager.swift
//  Weather
//
//  Purpose: Lets users edit saved city lists, rename lists, reorder cities,
//  and manage translated country/list names.
//

import SwiftUI
import CoreLocation
import WeatherKit
#if canImport(Translation)
import Translation
#endif


// MARK: - List Identity and Persistence

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
        guard let data = UserDefaults.standard.data(forKey: userListsKey),
              let lists = try? JSONDecoder().decode([CityListID].self, from: data) else {
            return []
        }
        // Give empty-named lists a fallback name instead of deleting them
        let fixed = lists.map { list in
            if list.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CityListID(rawValue: list.rawValue, displayName: String(localized: "New List"))
            }
            return list
        }
        if fixed != lists {
            saveUserLists(fixed)
        }
        return fixed
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
    
    static func createList(name: String) -> CityListID {
        let id = CityListID(rawValue: UUID().uuidString, displayName: name)
        var userLists = loadUserLists()
        userLists.append(id)
        saveUserLists(userLists)
        return id
    }
    
    var defaultCities: [City] {
        switch rawValue {
        case "europe":
            return [
                City(name: "Istanbul", country: "Turkey", latitude: 41.0082, longitude: 28.9784),
                City(name: "Moscow", country: "Russia", latitude: 55.7558, longitude: 37.6173),
                City(name: "London", country: "England", latitude: 51.5074, longitude: -0.1278),
                City(name: "Saint Petersburg", country: "Russia", latitude: 59.9311, longitude: 30.3609),
                City(name: "Berlin", country: "Germany", latitude: 52.5200, longitude: 13.4050),
                City(name: "Madrid", country: "Spain", latitude: 40.4168, longitude: -3.7038),
                City(name: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964),
                City(name: "Kyiv", country: "Ukraine", latitude: 50.4501, longitude: 30.5234),
                City(name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522),
                City(name: "Bucharest", country: "Romania", latitude: 44.4268, longitude: 26.1025),
                City(name: "Minsk", country: "Belarus", latitude: 53.9006, longitude: 27.5590),
                City(name: "Vienna", country: "Austria", latitude: 48.2082, longitude: 16.3738),
                City(name: "Hamburg", country: "Germany", latitude: 53.5511, longitude: 9.9937),
                City(name: "Warsaw", country: "Poland", latitude: 52.2297, longitude: 21.0122),
                City(name: "Budapest", country: "Hungary", latitude: 47.4979, longitude: 19.0402),
                City(name: "Barcelona", country: "Spain", latitude: 41.3874, longitude: 2.1686),
                City(name: "Munich", country: "Germany", latitude: 48.1351, longitude: 11.5820),
                City(name: "Milan", country: "Italy", latitude: 45.4642, longitude: 9.1900),
                City(name: "Prague", country: "Czechia", latitude: 50.0755, longitude: 14.4378),
                City(name: "Sofia", country: "Bulgaria", latitude: 42.6977, longitude: 23.3219),
            ]
        case "asia":
            return [
                City(name: "Tokyo", country: "Japan", latitude: 35.6762, longitude: 139.6503),
                City(name: "Delhi", country: "India", latitude: 28.7041, longitude: 77.1025),
                City(name: "Shanghai", country: "China", latitude: 31.2304, longitude: 121.4737),
                City(name: "Dhaka", country: "Bangladesh", latitude: 23.8103, longitude: 90.4125),
                City(name: "Beijing", country: "China", latitude: 39.9042, longitude: 116.4074),
                City(name: "Mumbai", country: "India", latitude: 19.0760, longitude: 72.8777),
                City(name: "Osaka", country: "Japan", latitude: 34.6937, longitude: 135.5023),
                City(name: "Karachi", country: "Pakistan", latitude: 24.8607, longitude: 67.0011),
                City(name: "Chongqing", country: "China", latitude: 29.4316, longitude: 106.9123),
                City(name: "Guangzhou", country: "China", latitude: 23.1291, longitude: 113.2644),
                City(name: "Lahore", country: "Pakistan", latitude: 31.5204, longitude: 74.3587),
                City(name: "Shenzhen", country: "China", latitude: 22.5431, longitude: 114.0579),
                City(name: "Bangalore", country: "India", latitude: 12.9716, longitude: 77.5946),
                City(name: "Chennai", country: "India", latitude: 13.0827, longitude: 80.2707),
                City(name: "Kolkata", country: "India", latitude: 22.5726, longitude: 88.3639),
                City(name: "Bangkok", country: "Thailand", latitude: 13.7563, longitude: 100.5018),
                City(name: "Tehran", country: "Iran", latitude: 35.6892, longitude: 51.3890),
                City(name: "Hyderabad", country: "India", latitude: 17.3850, longitude: 78.4867),
                City(name: "Chengdu", country: "China", latitude: 30.5728, longitude: 104.0668),
                City(name: "Ho Chi Minh City", country: "Vietnam", latitude: 10.8231, longitude: 106.6297),
            ]
        case "northAmerica":
            return [
                City(name: "Mexico City", country: "Mexico", latitude: 19.4326, longitude: -99.1332),
                City(name: "New York", country: "United States", latitude: 40.7128, longitude: -74.0060),
                City(name: "Los Angeles", country: "United States", latitude: 34.0522, longitude: -118.2437),
                City(name: "Toronto", country: "Canada", latitude: 43.6532, longitude: -79.3832),
                City(name: "Chicago", country: "United States", latitude: 41.8781, longitude: -87.6298),
                City(name: "Dallas", country: "United States", latitude: 32.7767, longitude: -96.7970),
                City(name: "Houston", country: "United States", latitude: 29.7604, longitude: -95.3698),
                City(name: "Miami", country: "United States", latitude: 25.7617, longitude: -80.1918),
                City(name: "Philadelphia", country: "United States", latitude: 39.9526, longitude: -75.1652),
                City(name: "Atlanta", country: "United States", latitude: 33.7490, longitude: -84.3880),
                City(name: "Washington", country: "United States", latitude: 38.9072, longitude: -77.0369),
                City(name: "Boston", country: "United States", latitude: 42.3601, longitude: -71.0589),
                City(name: "Phoenix", country: "United States", latitude: 33.4484, longitude: -112.0740),
                City(name: "Monterrey", country: "Mexico", latitude: 25.6866, longitude: -100.3161),
                City(name: "Guadalajara", country: "Mexico", latitude: 20.6597, longitude: -103.3496),
                City(name: "San Francisco", country: "United States", latitude: 37.7749, longitude: -122.4194),
                City(name: "Detroit", country: "United States", latitude: 42.3314, longitude: -83.0458),
                City(name: "Montreal", country: "Canada", latitude: 45.5017, longitude: -73.5673),
                City(name: "Seattle", country: "United States", latitude: 47.6062, longitude: -122.3321),
                City(name: "Minneapolis", country: "United States", latitude: 44.9778, longitude: -93.2650),
            ]
        case "southAmerica":
            return [
                City(name: "Sao Paulo", country: "Brazil", latitude: -23.5558, longitude: -46.6396),
                City(name: "Buenos Aires", country: "Argentina", latitude: -34.6037, longitude: -58.3816),
                City(name: "Rio de Janeiro", country: "Brazil", latitude: -22.9068, longitude: -43.1729),
                City(name: "Lima", country: "Peru", latitude: -12.0464, longitude: -77.0428),
                City(name: "Bogota", country: "Colombia", latitude: 4.7110, longitude: -74.0721),
                City(name: "Santiago", country: "Chile", latitude: -33.4489, longitude: -70.6693),
                City(name: "Belo Horizonte", country: "Brazil", latitude: -19.9167, longitude: -43.9345),
                City(name: "Caracas", country: "Venezuela", latitude: 10.4806, longitude: -66.9036),
                City(name: "Porto Alegre", country: "Brazil", latitude: -30.0346, longitude: -51.2177),
                City(name: "Brasilia", country: "Brazil", latitude: -15.8267, longitude: -47.9218),
                City(name: "Recife", country: "Brazil", latitude: -8.0476, longitude: -34.8770),
                City(name: "Fortaleza", country: "Brazil", latitude: -3.7319, longitude: -38.5267),
                City(name: "Salvador", country: "Brazil", latitude: -12.9777, longitude: -38.5016),
                City(name: "Medellin", country: "Colombia", latitude: 6.2442, longitude: -75.5812),
                City(name: "Guayaquil", country: "Ecuador", latitude: -2.1700, longitude: -79.9224),
                City(name: "Curitiba", country: "Brazil", latitude: -25.4284, longitude: -49.2733),
                City(name: "Quito", country: "Ecuador", latitude: -0.1807, longitude: -78.4678),
                City(name: "Cali", country: "Colombia", latitude: 3.4516, longitude: -76.5320),
                City(name: "Montevideo", country: "Uruguay", latitude: -34.9011, longitude: -56.1645),
                City(name: "Asuncion", country: "Paraguay", latitude: -25.2637, longitude: -57.5759),
            ]
        case "africa":
            return [
                City(name: "Lagos", country: "Nigeria", latitude: 6.5244, longitude: 3.3792),
                City(name: "Cairo", country: "Egypt", latitude: 30.0444, longitude: 31.2357),
                City(name: "Kinshasa", country: "Democratic Republic of the Congo", latitude: -4.4419, longitude: 15.2663),
                City(name: "Johannesburg", country: "South Africa", latitude: -26.2041, longitude: 28.0473),
                City(name: "Luanda", country: "Angola", latitude: -8.8390, longitude: 13.2894),
                City(name: "Dar es Salaam", country: "Tanzania", latitude: -6.7924, longitude: 39.2083),
                City(name: "Khartoum", country: "Sudan", latitude: 15.5007, longitude: 32.5599),
                City(name: "Abidjan", country: "Cote d'Ivoire", latitude: 5.3600, longitude: -4.0083),
                City(name: "Alexandria", country: "Egypt", latitude: 31.2001, longitude: 29.9187),
                City(name: "Nairobi", country: "Kenya", latitude: -1.2921, longitude: 36.8219),
                City(name: "Addis Ababa", country: "Ethiopia", latitude: 8.9806, longitude: 38.7578),
                City(name: "Cape Town", country: "South Africa", latitude: -33.9249, longitude: 18.4241),
                City(name: "Casablanca", country: "Morocco", latitude: 33.5731, longitude: -7.5898),
                City(name: "Accra", country: "Ghana", latitude: 5.6037, longitude: -0.1870),
                City(name: "Durban", country: "South Africa", latitude: -29.8587, longitude: 31.0218),
                City(name: "Dakar", country: "Senegal", latitude: 14.7167, longitude: -17.4677),
                City(name: "Kano", country: "Nigeria", latitude: 12.0022, longitude: 8.5920),
                City(name: "Ibadan", country: "Nigeria", latitude: 7.3775, longitude: 3.9470),
                City(name: "Pretoria", country: "South Africa", latitude: -25.7479, longitude: 28.2293),
                City(name: "Kampala", country: "Uganda", latitude: 0.3476, longitude: 32.5825),
            ]
        case "australia":
            return [
                City(name: "Sydney", country: "Australia", latitude: -33.8688, longitude: 151.2093),
                City(name: "Melbourne", country: "Australia", latitude: -37.8136, longitude: 144.9631),
                City(name: "Brisbane", country: "Australia", latitude: -27.4698, longitude: 153.0251),
                City(name: "Perth", country: "Australia", latitude: -31.9523, longitude: 115.8613),
                City(name: "Adelaide", country: "Australia", latitude: -34.9285, longitude: 138.6007),
                City(name: "Gold Coast", country: "Australia", latitude: -28.0167, longitude: 153.4000),
                City(name: "Canberra", country: "Australia", latitude: -35.2809, longitude: 149.1300),
                City(name: "Newcastle", country: "Australia", latitude: -32.9283, longitude: 151.7817),
                City(name: "Central Coast", country: "Australia", latitude: -33.4267, longitude: 151.3417),
                City(name: "Wollongong", country: "Australia", latitude: -34.4278, longitude: 150.8931),
            ]
        default:
            return [] // User-created lists start empty
        }
    }
}

// MARK: - Weather Service List Mutations

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

    // MARK: - Cities List Persistence
    
    /// Save the current list of cities (just the City objects, not the weather data)
    func saveCitiesList() {
        let cities = cityWeatherData.map { $0.city }
        
        do {
            let encoder = JSONEncoder()
            let encoded = try encoder.encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: citiesListKey)
        } catch {
        }
    }

    func saveCities(_ cities: [City], for listID: CityListID) {
        let key = "savedCitiesList_\(listID.rawValue)"
        do {
            let encoded = try JSONEncoder().encode(cities.map { CachedCity(from: $0) })
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
        }
    }
    
    func isValidPersistedCity(_ city: City) -> Bool {
        let name = city.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { return false }
        guard city.latitude.isFinite, city.longitude.isFinite,
              (-90...90).contains(city.latitude), (-180...180).contains(city.longitude) else { return false }

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
            // Migrate: fill in empty country from default city lists
            let defaults = CityListID.builtInLists.flatMap { $0.defaultCities }
            let cities = cachedCities.compactMap { cached -> City? in
                var city = cached.toCity()
                if city.country.isEmpty,
                   let match = defaults.first(where: { $0.name == city.name }) {
                    city = City(id: city.id, name: city.name, country: match.country, latitude: city.latitude, longitude: city.longitude)
                }
                return isValidPersistedCity(city) ? city : nil
            }
            if cities.count != cachedCities.count {
                saveCities(cities, for: listID)
            }
            return cities
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
    }

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
            let fallback = remaining.first ?? .europe
            activeListID = fallback
            UserDefaults.standard.set(fallback.rawValue, forKey: Self.activeListKey)
            cityWeatherData = otherListData[fallback.rawValue] ?? []
            lastFetchDate = fetchDate(for: fallback)
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

    func renameCity(_ cityWeather: CityWeather, to newName: String) {
        guard let index = cityWeatherData.firstIndex(where: { $0.id == cityWeather.id }) else { return }
        cityWeatherData[index].city.name = newName
        cacheData(cityWeatherData)
        saveCitiesList()
    }

    func renameCity(_ cityWeather: CityWeather, in listID: CityListID, to newName: String) {
        if listID.rawValue == activeListID.rawValue {
            renameCity(cityWeather, to: newName)
            return
        }
        var listData = otherListData[listID.rawValue] ?? []
        guard let index = listData.firstIndex(where: { $0.id == cityWeather.id }) else { return }
        listData[index].city.name = newName
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

// MARK: - Translation Cache

struct CountryCityTranslationCache {
    static let shared = CountryCityTranslationCache()

    private let storageKey = "countryCityNameTranslations"

    func key(for city: City, targetLanguageIdentifier: String) -> String {
        [
            targetLanguageIdentifier,
            city.country,
            city.name,
            String(format: "%.4f", city.latitude),
            String(format: "%.4f", city.longitude)
        ].joined(separator: "|")
    }

    func name(forKey key: String) -> String? {
        load()[key]
    }

    func setName(_ name: String, forKey key: String) {
        var values = load()
        values[key] = name
        save(values)
    }

    private func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private func save(_ values: [String: String]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

// MARK: - List Manager

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
            beginRenamingCity(city, in: listID)
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

    func beginCreatingCountryList(initialCountry: CountryCityGroup? = nil) {
        countryListInitialCountry = initialCountry
        countryListSearchMode = true
        countryListPreviewCountry = initialCountry
        if let initialCountry {
            countryListPreviewCityCount = countryListClampedCityCount(15, for: initialCountry)
        } else {
            countryListPreviewCityCount = 15
        }
        showingCountryListBuilder = false
        showingListManager = false
        showingMapExpandedCard = false
        tappedCity = nil
        inlineSearchText = initialCountry?.name ?? ""

        pushRoute(.map)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = true
        }
        Task { @MainActor in
            await Task.yield()
            inlineSearchFieldPresented = true
        }

        if initialCountry != nil {
            centerMapOnDots(useListCoordinates: true)
        }
    }

    func commitCountryList(_ country: CountryCityGroup, cityCount: Int) {
        addCountry(country, cityCount: cityCount, to: nil)
    }

    func addCountry(_ country: CountryCityGroup, cityCount: Int, to listID: CityListID?) {
        let resolvedCountry = CountryCityCatalog.shared.countryWithCities(for: country) ?? country
        let cities = Array(resolvedCountry.cities.prefix(cityCount))
        guard !cities.isEmpty else { return }
        Task {
            let displayCities = await translatedCountryListCitiesIfNeeded(cities)
            let targetList: CityListID
            if let listID {
                await weatherService.addCities(displayCities, to: listID)
                targetList = listID
            } else {
                targetList = await weatherService.createCustomList(name: resolvedCountry.name, cities: displayCities)
            }

            await MainActor.run {
                refreshListOrder()
                refreshCityOrder()
                expandedListIDs.insert(targetList.rawValue)
                countryListSearchMode = false
                countryListPreviewCountry = nil
                inlineSearchText = ""
                showingInlineSearch = false
                inlineSearchFieldPresented = false
                inlineAddTargetListID = nil
                mapRecenterRequest = .listCoordinates
                PlatformFeedback.lightImpact()
            }
        }
    }

    func translatedCountryListCitiesIfNeeded(_ cities: [City]) async -> [City] {
        let languageCode = (UserDefaults.standard.string(forKey: "appLanguage") ?? "en")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !languageCode.isEmpty, languageCode != "en" else { return cities }

        #if canImport(Translation)
        if #available(iOS 26.0, *) {
            return await translateCountryListCities(cities, targetLanguageIdentifier: languageCode)
        }
        #endif

        return cities
    }

    #if canImport(Translation)
    @available(iOS 26.0, *)
    private func translateCountryListCities(_ cities: [City], targetLanguageIdentifier: String) async -> [City] {
        let cache = CountryCityTranslationCache.shared
        let cacheKeys = cities.map { cache.key(for: $0, targetLanguageIdentifier: targetLanguageIdentifier) }
        var translatedNames = cities.enumerated().map { index, city in
            cache.name(forKey: cacheKeys[index]) ?? city.name
        }

        let missingRequests = cities.enumerated().compactMap { index, city -> (index: Int, request: TranslationSession.Request)? in
            guard cache.name(forKey: cacheKeys[index]) == nil else { return nil }
            return (
                index,
                TranslationSession.Request(
                    sourceText: city.name,
                    clientIdentifier: String(index)
                )
            )
        }

        guard !missingRequests.isEmpty else {
            return cities.enumerated().map { index, city in
                City(id: city.id, name: translatedNames[index], country: city.country, latitude: city.latitude, longitude: city.longitude)
            }
        }

        do {
            let session = TranslationSession(
                installedSource: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: targetLanguageIdentifier)
            )
            let responses = try await session.translations(from: missingRequests.map(\.request))
            for (responseIndex, response) in responses.enumerated() {
                guard missingRequests.indices.contains(responseIndex) else { continue }
                let cityIndex = missingRequests[responseIndex].index
                translatedNames[cityIndex] = response.targetText
                cache.setName(response.targetText, forKey: cacheKeys[cityIndex])
            }
        } catch {
            return cities
        }

        return cities.enumerated().map { index, city in
            City(id: city.id, name: translatedNames[index], country: city.country, latitude: city.latitude, longitude: city.longitude)
        }
    }
    #endif

    func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            let revealedCity = weatherService.cityWeatherData.first {
                $0.city.latitude == city.city.latitude && $0.city.longitude == city.city.longitude
            } ?? city
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
        cityToRename = nil
        cityToRenameListID = nil
        showingCityRenameAlert = false
        listToRenameID = listID
        renameAlertText = listID.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func beginRenamingCity(_ city: CityWeather, in listID: CityListID) {
        listToRenameID = nil
        showingRenameAlert = false
        cityToRename = city
        cityToRenameListID = listID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    private func beginAddingCity(to listID: CityListID) {
        inlineAddTargetListID = listID
        pushRoute(.map)
        inlineSearchText = ""
        activateInlineSearch()
    }
}
#Preview("List Manager") {
    NavigationStack {
        ContentView().nativeListManager
    }
}

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

    private func moveManagedLists(from source: IndexSet, to destination: Int) {
        weatherService.moveLists(from: source, to: destination)
        refreshListOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteManagedLists(at offsets: IndexSet) {
        let lists = managedLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            weatherService.deleteList(lists[index])
        }
        refreshListOrder()
        PlatformFeedback.lightImpact()
    }

    private func moveManagedCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        refreshCityOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteManagedCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = managedCities(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        refreshCityOrder()
        PlatformFeedback.lightImpact()
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
    func detailActionsMenu(for city: CityWeather) -> some View {
        Menu {
            if cityIsInActiveList(city) {
                Button {
                    cityToRename = city
                    cityRenameText = city.city.localizedName(locale: locale)
                    showingCityRenameAlert = true
                } label: {
                    Label {
                        Text(localizedString("Rename", locale: locale))
                    } icon: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.primary)
                    }
                }
                .tint(.primary)

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
                    } icon: {
                        Image(systemName: "plus")
                            .foregroundStyle(.primary)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
        }
        .menuOrder(.fixed)
    }

    @ViewBuilder
    func addCityButton(dismissExpanded: Bool) -> some View {
        let allLists = managedLists
        if allLists.count > 1 {
            Menu {
                ForEach(allLists) { listID in
                    Button(listID.localizedDisplayName(locale: locale)) {
                        if let city = previewCity {
                            Task {
                                if listID == weatherService.activeListID {
                                    await addCityToActiveList(city)
                                } else {
                                    await weatherService.addCityToList(city.city, listID: listID)
                                    PlatformFeedback.lightImpact()
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    if dismissExpanded { showingMapExpandedCard = false }
                                    previewCity = nil
                                }
                            }
                        }
                    }
                }
            } label: {
                addCityButtonLabel
            }
            .buttonStyle(.plain)
        } else {
            Button {
                if let city = previewCity {
                    Task {
                        await addCityToActiveList(city)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if dismissExpanded { showingMapExpandedCard = false }
                            previewCity = nil
                        }
                    }
                }
            } label: {
                addCityButtonLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var addCityButtonLabel: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(AppTheme.shared.colors.accent.opacity(0.85), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.5))
    }
}

#Preview("List Manager") {
    NavigationStack {
        ContentView().nativeListManager
    }
}
