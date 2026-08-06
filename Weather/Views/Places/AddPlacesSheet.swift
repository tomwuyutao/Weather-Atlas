//
//  AddPlacesSheet.swift
//  Weather
//
//  Purpose: Reuses the former Add List workflow to add population-ranked
//  country or continent cities directly to Saved Places.
//

import SwiftUI

/// Geographic bulk-add workflow. It creates no list or grouping.
struct AddPlacesSheet: View {
    let placesStore: PlacesStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var path: [AddPlacesRoute] = []
    @State private var didComplete = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button {
                    path.append(.continents)
                } label: {
                    Label("Add a Continent", systemImage: "globe.europe.africa")
                }
                Button {
                    path.append(.countries)
                } label: {
                    Label("Add a Country", systemImage: "flag")
                }
            }
            .navigationTitle("Add Places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
            .navigationDestination(for: AddPlacesRoute.self) { destination in
                destinationView(for: destination)
            }
        }
        .onChange(of: didComplete) { _, complete in
            if complete { dismiss() }
        }
    }

    @ViewBuilder
    private func destinationView(for route: AddPlacesRoute) -> some View {
        switch route {
        case .continents:
            List(ContinentPlacesOption.allCases) { continent in
                Button(continent.localizedName(locale: locale)) {
                    path.append(.preview(
                        AddPlacesSource(
                            name: continent.localizedName(locale: locale),
                            cities: CountryCityCatalog.topCities(for: continent, limit: CountryCityCatalog.maximumGeneratedCityCount)
                        )
                    ))
                }
            }
            .navigationTitle("Add a Continent")
        case .countries:
            AddPlacesCountryPicker(path: $path)
        case .preview(let source):
            AddPlacesPreview(
                placesStore: placesStore,
                source: source,
                didComplete: $didComplete
            )
        }
    }
}

private enum AddPlacesRoute: Hashable {
    case continents
    case countries
    case preview(AddPlacesSource)
}

private struct AddPlacesSource: Hashable {
    let name: String
    let cities: [City]
}

private struct AddPlacesCountryPicker: View {
    @Binding var path: [AddPlacesRoute]
    @Environment(\.locale) private var locale
    @State private var query = ""

    private var countries: [CountryPlacesOption] {
        CountryCityCatalog.countries(locale: locale).filter {
            query.isEmpty || $0.localizedName(locale: locale).localizedStandardContains(query)
                || $0.englishName.localizedStandardContains(query)
        }
    }

    var body: some View {
        List(countries) { country in
            Button(country.localizedName(locale: locale)) {
                path.append(.preview(
                    AddPlacesSource(
                        name: country.localizedName(locale: locale),
                        cities: CountryCityCatalog.topCities(for: country, limit: CountryCityCatalog.maximumGeneratedCityCount)
                    )
                ))
            }
        }
        .navigationTitle("Add a Country")
        .searchable(text: $query, prompt: "Search countries")
    }
}

private struct AddPlacesPreview: View {
    let placesStore: PlacesStore
    let source: AddPlacesSource
    @Binding var didComplete: Bool

    @Environment(\.locale) private var locale
    @State private var cityCount: Int
    @State private var errorMessage: String?

    init(placesStore: PlacesStore, source: AddPlacesSource, didComplete: Binding<Bool>) {
        self.placesStore = placesStore
        self.source = source
        _didComplete = didComplete
        _cityCount = State(initialValue: min(CountryCityCatalog.defaultGeneratedCityCount, source.cities.count))
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: $cityCount, in: 1...max(1, source.cities.count)) {
                    LabeledContent("Number of Cities") { Text(cityCount, format: .number) }
                }
            } footer: {
                Text("These cities will be added directly to Saved Places without creating a list.")
            }
            Section("Cities") {
                ForEach(Array(source.cities.prefix(cityCount))) { city in
                    LabeledContent(city.name, value: city.country)
                }
            }
        }
        .navigationTitle(source.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { addCities() }
                    .disabled(source.cities.isEmpty)
            }
        }
        .alert("Couldn’t Add Places", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addCities() {
        do {
            _ = try placesStore.savePlaces(Array(source.cities.prefix(cityCount)))
            didComplete = true
        } catch {
            errorMessage = localizedPlacesErrorDescription(error, locale: locale)
        }
    }
}
