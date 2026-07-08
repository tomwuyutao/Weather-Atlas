//
//  CountryListSearch.swift
//  Weather
//
//  Purpose: Presents the country picker used to preview generated country
//  lists before they are added to the user's saved lists.
//

import SwiftUI

// MARK: - Continent List Search

extension ContentView {
    var continentListSearchSheet: some View {
        NavigationStack {
            List {
                ForEach(CityListID.builtInLists) { listID in
                    Button {
                        previewContinentList(listID)
                    } label: {
                        continentListSearchResultRow(listID)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.colors.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(localizedString("Add Continent", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    func continentListSearchResultRow(_ listID: CityListID) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(listID.localizedDisplayName(locale: locale))
                    .font(.avenir(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(cityCountText(CountryCityCatalog.cityCount(forContinentRawValue: listID.rawValue)))
                    .font(.avenir(.subheadline, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    func activateContinentListSearch() {
        showingContinentListSearchSheet = true
    }
}

// MARK: - Country List Search

extension ContentView {
    var countryListSearchSheet: some View {
        NavigationStack {
            List {
                let countries = filteredCountryListOptions
                if countries.isEmpty {
                    Text(localizedString("No countries found.", locale: locale))
                        .font(.avenir(.body, weight: .regular))
                        .foregroundStyle(theme.colors.secondaryText)
                        .listRowBackground(theme.colors.background)
                } else {
                    ForEach(countries) { country in
                        Button {
                            previewCountryList(country)
                        } label: {
                            countryListSearchResultRow(country)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.colors.background)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(localizedString("Add Country", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $countryListSearchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(localizedString("Search for a country", locale: locale))
            )
        }
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            countryListSearchText = ""
            Task { @MainActor in
                await Task.yield()
                searchFieldFocused = true
            }
        }
    }

    var filteredCountryListOptions: [CountryListOption] {
        let countries = CountryCityCatalog.countries(locale: locale)
        let query = countryListSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter { country in
            country.localizedName(locale: locale).localizedCaseInsensitiveContains(query)
                || country.englishName.localizedCaseInsensitiveContains(query)
                || country.iso2.localizedCaseInsensitiveContains(query)
        }
    }

    func countryListSearchResultRow(_ country: CountryListOption) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(country.localizedName(locale: locale))
                    .font(.avenir(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(cityCountText(country.cities.count))
                    .font(.avenir(.subheadline, weight: .regular))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    func activateCountryListSearch() {
        countryListSearchText = ""
        showingCountryListSearchSheet = true
    }
}
