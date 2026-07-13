//
//  CountrySearch.swift
//  Weather
//
//  Purpose: Presents the country picker used to preview generated country
//  lists before they are added to the user's saved lists.
//

import SwiftUI

// MARK: - Continent List Search

extension ContentView {
    var continentListSearchSheet: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(CityListID.builtInLists) { listID in
                    Button {
                        previewContinentList(listID)
                    } label: {
                        continentListSearchResultRow(listID)
                    }
                    .buttonStyle(.plain)

                    if listID != CityListID.builtInLists.last {
                        Divider()
                            .background(theme.colors.secondaryText.opacity(0.20))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
        .background(theme.colors.background.ignoresSafeArea())
    }

    func continentListSearchResultRow(_ listID: CityListID) -> some View {
        HStack(spacing: 12) {
            Text(listID.localizedDisplayName(locale: locale))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    func activateContinentListSearch() {
        showingContinentListSearchSheet = true
    }
}

// MARK: - Country List Search

extension ContentView {
    var countryListSearchSheet: some View {
        VStack(spacing: 18) {
            countryListSearchBar

            ScrollView {
                VStack(spacing: 0) {
                    let countries = filteredCountryListOptions
                    if countries.isEmpty {
                        Text(localizedString("No countries found.", locale: locale))
                            .font(.avenir(.body, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(countries) { country in
                            Button {
                                previewCountryList(country)
                            } label: {
                                countryListSearchResultRow(country)
                            }
                            .buttonStyle(.plain)

                            if country.id != countries.last?.id {
                                Divider()
                                    .background(theme.colors.secondaryText.opacity(0.20))
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            countryListSearchText = ""
            Task { @MainActor in
                await Task.yield()
                searchFieldFocused = true
            }
        }
    }

    var countryListSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.accent)

            TextField(localizedString("Search for a country", locale: locale), text: $countryListSearchText)
                .font(.avenir(.body, weight: .regular))
                .foregroundStyle(theme.colors.primaryText)
                .focused($searchFieldFocused)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            if !countryListSearchText.isEmpty {
                Button {
                    countryListSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(theme.colors.listCardFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.38), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
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
            Text(country.localizedName(locale: locale))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

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
