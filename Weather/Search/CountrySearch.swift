//
//  CountrySearch.swift
//  Weather
//
//  Purpose: Provides continent and country pickers for generated list previews.
//

import SwiftUI

// MARK: - Shared Picker Row

/// Shared chevron row used by continent and country selection sheets.
struct ListPickerNavigationRow: View {
    /// Localized row title.
    let title: String
    /// Vertical inset selected by the owning picker density.
    let verticalPadding: CGFloat

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme

    /// Builds the title-and-chevron navigation row.
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

/// Scrollable picker for canonical built-in continent sources.
struct ContinentListPickerContent: View {
    /// Built-in list identities shown as creation sources.
    let lists: [CityListID]
    /// Selection callback owned by the presenting workflow.
    let onSelect: (CityListID) -> Void

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// App-selected locale used for canonical continent labels.
    @Environment(\.locale) private var locale

    /// Builds the divided continent picker list.
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

/// Searchable country picker with an injectable search-field view.
struct CountryListPickerContent<SearchBar: View>: View {
    /// Filtered country options currently visible.
    let countries: [CountryListOption]
    /// Search field supplied by the parent workflow.
    let searchBar: SearchBar
    /// Selection callback owned by the presenting workflow.
    let onSelect: (CountryListOption) -> Void

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// App-selected locale used for empty-state copy and labels.
    @Environment(\.locale) private var locale

    /// Builds search and scrollable country result sections.
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

/// Capsule search field shared by generated country-list workflows.
struct CountrySearchField: View {
    /// Query text owned by the parent presentation state.
    @Binding var text: String
    /// Whether the field should claim focus on first appearance.
    var automaticallyFocus = false

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Resolved appearance used to tune border and shadow opacity.
    @Environment(\.colorScheme) private var colorScheme
    /// Contrast preference used to strengthen the outline.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// App-selected locale used by the placeholder.
    @Environment(\.locale) private var locale
    /// Native text-field focus state.
    @FocusState private var isFocused: Bool

    /// Builds the search field, clear action, and adaptive outline.
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
                // Increase Contrast replaces the subtle scheme-aware outline.
                .stroke(
                    colorSchemeContrast == .increased
                        ? theme.colors.primaryText
                        : theme.colors.primaryText.opacity(colorScheme == .dark ? 0.16 : 0.12),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.8
                )
        }
        .shadow(color: theme.colors.shadow.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
        .onAppear {
            if automaticallyFocus {
                isFocused = true
            }
        }
    }

}

// MARK: - Country List Search

extension ContentView {
    /// Builds the searchable country source picker and resets stale query text.
    func countryListSearchContent(
        query: Binding<String>,
        onSelect: @escaping (CountryListOption) -> Void
    ) -> some View {
        let countries = CountryCityCatalog.countries(locale: locale)
        let trimmedQuery = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // Match localized and English names as well as ISO codes.
        let filteredCountries = trimmedQuery.isEmpty ? countries : countries.filter { country in
            country.localizedName(locale: locale).localizedCaseInsensitiveContains(trimmedQuery)
                || country.englishName.localizedCaseInsensitiveContains(trimmedQuery)
                || country.iso2.localizedCaseInsensitiveContains(trimmedQuery)
        }

        return CountryListPickerContent(
            countries: filteredCountries,
            searchBar: CountrySearchField(
                text: query,
                automaticallyFocus: true
            ),
            onSelect: onSelect
        )
        .onAppear {
            query.wrappedValue = ""
        }
    }

}
