//
//  CountryListBuilder.swift
//  Weather
//
//  Country-list creation flow backed by the bundled worldcities.csv file.
//

import SwiftUI
import Foundation

struct CountryCityGroup: Identifiable, Equatable {
    let name: String
    let iso2: String
    let iso3: String
    let aliases: [String]
    let cities: [City]

    var id: String { iso3.isEmpty ? name : iso3 }
}

struct CountryCityCatalog {
    static let shared = CountryCityCatalog()

    let countries: [CountryCityGroup]

    init() {
        countries = Self.loadCountries()
    }

    func searchCountries(matching query: String, limit: Int = 6) -> [CountryCityGroup] {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return countries
            .filter { country in
                let tokens = [country.name, country.iso2, country.iso3] + country.aliases
                return tokens.contains { Self.normalized($0).contains(normalizedQuery) || normalizedQuery.contains(Self.normalized($0)) }
            }
            .sorted { lhs, rhs in
                let lhsName = Self.normalized(lhs.name)
                let rhsName = Self.normalized(rhs.name)
                if lhsName == normalizedQuery { return true }
                if rhsName == normalizedQuery { return false }
                if lhsName.hasPrefix(normalizedQuery) != rhsName.hasPrefix(normalizedQuery) {
                    return lhsName.hasPrefix(normalizedQuery)
                }
                return lhs.name < rhs.name
            }
            .prefix(limit)
            .map { $0 }
    }

    func country(matching text: String) -> CountryCityGroup? {
        let normalizedText = Self.normalized(text)
        guard !normalizedText.isEmpty else { return nil }

        return countries.first { country in
            let tokens = [country.name, country.iso2, country.iso3] + country.aliases
            return tokens.contains { Self.normalized($0) == normalizedText }
        }
    }

    private static func loadCountries() -> [CountryCityGroup] {
        if let countries = loadCountryIndex(), !countries.isEmpty {
            return countries
        }

        guard let url = Bundle.main.url(forResource: "worldcities", withExtension: "csv")
            ?? Bundle.main.url(forResource: "worldcities", withExtension: "csv", subdirectory: "Assets"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        struct ParsedCity {
            let city: City
            let population: Int
            let iso2: String
            let iso3: String
        }

        var grouped: [String: [ParsedCity]] = [:]
        var displayNames: [String: String] = [:]
        var iso2ByCountry: [String: String] = [:]
        var iso3ByCountry: [String: String] = [:]

        for fields in parseCSV(text).dropFirst() {
            guard fields.count >= 10,
                  let latitude = Double(fields[2]),
                  let longitude = Double(fields[3]),
                  let population = Int(fields[9]),
                  population > 0 else { continue }

            let country = fields[4].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !country.isEmpty else { continue }

            let key = normalized(country)
            let city = City(
                name: fields[1].isEmpty ? fields[0] : fields[1],
                country: country,
                latitude: latitude,
                longitude: longitude
            )
            grouped[key, default: []].append(ParsedCity(city: city, population: population, iso2: fields[5], iso3: fields[6]))
            displayNames[key] = country
            iso2ByCountry[key] = fields[5]
            iso3ByCountry[key] = fields[6]
        }

        return grouped.compactMap { key, cities in
            let topCities = cities
                .sorted { $0.population > $1.population }
                .prefix(30)
                .map(\.city)
            guard !topCities.isEmpty, let name = displayNames[key] else { return nil }
            return CountryCityGroup(
                name: name,
                iso2: iso2ByCountry[key] ?? "",
                iso3: iso3ByCountry[key] ?? "",
                aliases: aliases(for: name, iso2: iso2ByCountry[key] ?? "", iso3: iso3ByCountry[key] ?? ""),
                cities: Array(topCities)
            )
        }
        .sorted { $0.name < $1.name }
    }

    func countryWithCities(for country: CountryCityGroup) -> CountryCityGroup? {
        if !country.cities.isEmpty {
            return country
        }

        return Self.loadCountriesFromJSON()?.first { $0.id == country.id }
    }

    private struct CatalogCountryIndex: Decodable {
        let name: String
        let iso2: String
        let iso3: String
    }

    private struct CatalogCountry: Decodable {
        let name: String
        let iso2: String
        let iso3: String
        let cities: [CatalogCity]
    }

    private struct CatalogCity: Decodable {
        let name: String
        let country: String
        let latitude: Double
        let longitude: Double
    }

    private static func loadCountryIndex() -> [CountryCityGroup]? {
        guard let url = Bundle.main.url(forResource: "country_index", withExtension: "json")
            ?? Bundle.main.url(forResource: "country_index", withExtension: "json", subdirectory: "Assets"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode([CatalogCountryIndex].self, from: data) else {
            return nil
        }

        return catalog.map { country in
            CountryCityGroup(
                name: country.name,
                iso2: country.iso2,
                iso3: country.iso3,
                aliases: aliases(for: country.name, iso2: country.iso2, iso3: country.iso3),
                cities: []
            )
        }
    }

    private static func loadCountriesFromJSON() -> [CountryCityGroup]? {
        guard let url = Bundle.main.url(forResource: "country_city_catalog", withExtension: "json")
            ?? Bundle.main.url(forResource: "country_city_catalog", withExtension: "json", subdirectory: "Assets"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode([CatalogCountry].self, from: data) else {
            return nil
        }

        return catalog.map { country in
            CountryCityGroup(
                name: country.name,
                iso2: country.iso2,
                iso3: country.iso3,
                aliases: aliases(for: country.name, iso2: country.iso2, iso3: country.iso3),
                cities: country.cities.map {
                    City(name: $0.name, country: $0.country, latitude: $0.latitude, longitude: $0.longitude)
                }
            )
        }
    }

    private static func aliases(for name: String, iso2: String, iso3: String) -> [String] {
        switch iso2.uppercased() {
        case "GB": return ["UK", "U.K.", "Britain", "Great Britain", "England", "United Kingdom"]
        case "US": return ["USA", "U.S.", "United States", "United States of America", "America"]
        case "KR": return ["South Korea", "Korea"]
        case "KP": return ["North Korea"]
        case "AE": return ["UAE", "United Arab Emirates"]
        default: return [iso2, iso3, name]
        }
    }

    static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append(next)
                    } else {
                        inQuotes = false
                        if next == "," {
                            row.append(field)
                            field = ""
                        } else if next == "\n" {
                            row.append(field)
                            if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                            row = []
                            field = ""
                        } else if next != "\r" {
                            field.append(next)
                        }
                    }
                } else {
                    inQuotes.toggle()
                }
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if character == "\n", !inQuotes {
                row.append(field)
                if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else if character != "\r" {
                field.append(character)
            }
        }

        row.append(field)
        if !row.allSatisfy({ $0.isEmpty }) { rows.append(row) }
        return rows
    }
}

struct CountryListBuilderView: View {
    let initialCountry: CountryCityGroup?
    let onCreate: (CountryCityGroup, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @State private var searchText = ""
    @State private var selectedCountry: CountryCityGroup?
    @State private var cityCount = 15

    private var countries: [CountryCityGroup] {
        let all = CountryCityCatalog.shared.countries
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return all }
        return CountryCityCatalog.shared.searchCountries(matching: searchText, limit: 40)
    }

    private var previewCities: [City] {
        Array((selectedCountry ?? countries.first)?.cities.prefix(cityCount) ?? [])
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                List(countries, selection: Binding(
                    get: { selectedCountry?.id },
                    set: { id in selectedCountry = countries.first { $0.id == id } }
                )) { country in
                    Button {
                        selectedCountry = country
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(country.name)
                                .font(.headline)
                            Text("\(country.cities.count) cities available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .searchable(text: $searchText, prompt: "Search countries")
                .frame(minWidth: 240, idealWidth: 280)

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    if let country = selectedCountry ?? countries.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(country.name)
                                .font(.largeTitle.bold())
                            Text("Country list")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.colors.accent)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Cities")
                                    .font(.headline)
                                Spacer()
                                Text("\(cityCount)")
                                    .font(.headline.monospacedDigit())
                            }
                            Slider(value: Binding(
                                get: { Double(cityCount) },
                                set: { cityCount = Int($0.rounded()) }
                            ), in: 5...Double(min(30, country.cities.count)), step: 1)
                        }

                        List(previewCities) { city in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(city.name)
                                    .font(.headline)
                                Text(city.country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ContentUnavailableView("No countries", systemImage: "globe", description: Text("Check that worldcities.csv is bundled with the app."))
                    }
                }
                .padding(24)
                .frame(minWidth: 340, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .navigationTitle("Add Country List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let country = selectedCountry ?? countries.first else { return }
                        onCreate(country, cityCount)
                        dismiss()
                    }
                    .disabled((selectedCountry ?? countries.first) == nil)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear {
            selectedCountry = initialCountry ?? countries.first
            if let initialCountry {
                searchText = initialCountry.name
            }
            if let selectedCountry {
                cityCount = min(15, selectedCountry.cities.count)
            }
        }
        .onChange(of: selectedCountry) { _, country in
            guard let country else { return }
            cityCount = min(max(5, cityCount), min(30, country.cities.count))
        }
    }
}
