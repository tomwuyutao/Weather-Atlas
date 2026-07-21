//
//  CountrySearch.swift
//  Weather
//
//  Purpose: Provides continent and country pickers for generated list previews.
//

import SwiftUI

// MARK: - Shared Picker Row

struct ListPickerNavigationRow: View {
    let title: String
    let verticalPadding: CGFloat

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}

struct ContinentListPickerContent: View {
    let lists: [CityListID]
    let onSelect: (CityListID) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(lists) { listID in
                    Button {
                        onSelect(listID)
                    } label: {
                        ListPickerNavigationRow(
                            title: listID.canonicalLocalizedDisplayName(locale: locale),
                            verticalPadding: 14
                        )
                    }
                    .buttonStyle(.plain)

                    if listID != lists.last {
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
}

struct CountryListPickerContent<SearchBar: View>: View {
    let countries: [CountryListOption]
    let searchBar: SearchBar
    let onSelect: (CountryListOption) -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 18) {
            searchBar

            ScrollView {
                VStack(spacing: 0) {
                    if countries.isEmpty {
                        Text(localizedString("No countries found.", locale: locale))
                            .font(.body)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(countries) { country in
                            Button {
                                onSelect(country)
                            } label: {
                                ListPickerNavigationRow(
                                    title: country.localizedName(locale: locale),
                                    verticalPadding: 12
                                )
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
    }
}

struct CountrySearchField: View {
    @Binding var text: String
    var automaticallyFocus = false

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.accent)

            TextField(localizedString("Search for a country", locale: locale), text: $text)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .focused($isFocused)
                .defaultFocus($isFocused, automaticallyFocus)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(-13)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(theme.colors.listCardFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(searchFieldBorderColor, lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.8)
        }
        .shadow(color: theme.colors.shadow.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
        .onAppear {
            if automaticallyFocus {
                isFocused = true
            }
        }
    }

    private var searchFieldBorderColor: Color {
        if colorSchemeContrast == .increased {
            return theme.colors.primaryText
        }
        return theme.colors.primaryText.opacity(colorScheme == .dark ? 0.16 : 0.12)
    }
}

// MARK: - Continent List Search

extension ContentView {
    func continentListSearchContent(onSelect: @escaping (CityListID) -> Void) -> some View {
        ContinentListPickerContent(lists: CityListID.builtInLists, onSelect: onSelect)
    }

}

// MARK: - Country List Search

extension ContentView {
    func countryListSearchContent(onSelect: @escaping (CountryListOption) -> Void) -> some View {
        CountryListPickerContent(
            countries: filteredCountryListOptions,
            searchBar: CountrySearchField(
                text: $listManagementState.countryQuery,
                automaticallyFocus: true
            ),
            onSelect: onSelect
        )
        .onAppear {
            listManagementState.countryQuery = ""
        }
    }

    var filteredCountryListOptions: [CountryListOption] {
        let countries = CountryCityCatalog.countries(locale: locale)
        let query = listManagementState.countryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter { country in
            country.localizedName(locale: locale).localizedCaseInsensitiveContains(query)
                || country.englishName.localizedCaseInsensitiveContains(query)
                || country.iso2.localizedCaseInsensitiveContains(query)
        }
    }

}
