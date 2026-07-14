//
//  CountrySearch.swift
//  Weather
//
//  Purpose: Provides continent and country pickers for generated list previews.
//

import SwiftUI

// MARK: - Continent List Search

extension ContentView {
    func continentListSearchContent(onSelect: @escaping (CityListID) -> Void) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(CityListID.builtInLists) { listID in
                    Button {
                        onSelect(listID)
                    } label: {
                        continentListSearchResultRow(listID)
                    }
                    .buttonStyle(.plain)
                    // Accessibility: Name the full-row control and leave its chevron decorative.
                    .accessibilityLabel(listID.localizedDisplayName(locale: locale))

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
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

}

// MARK: - Country List Search

extension ContentView {
    func countryListSearchContent(onSelect: @escaping (CountryListOption) -> Void) -> some View {
        VStack(spacing: 18) {
            countryListSearchBar

            ScrollView {
                VStack(spacing: 0) {
                    let countries = filteredCountryListOptions
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
                                countryListSearchResultRow(country)
                            }
                            .buttonStyle(.plain)
                            // Accessibility: Name the full-row control and leave its chevron decorative.
                            .accessibilityLabel(country.localizedName(locale: locale))

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
            listManagementState.countryQuery = ""
            searchFieldFocused = true
        }
    }

    var countryListSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            TextField(localizedString("Search for a country", locale: locale), text: $listManagementState.countryQuery)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .focused($searchFieldFocused)
                .defaultFocus($searchFieldFocused, true)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .accessibilityLabel(localizedString("Search for a country", locale: locale))

            if !listManagementState.countryQuery.isEmpty {
                Button {
                    listManagementState.countryQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Accessibility: Expand only the clear action's hit region; negative padding
                // keeps the capsule's normal visual spacing unchanged.
                .padding(-13)
                .accessibilityLabel(localizedString("Clear", locale: locale))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(theme.colors.listCardFill, in: Capsule())
        .overlay {
            Capsule()
                // Accessibility: Increase Contrast gives the search-field boundary
                // a measured, opaque outline while preserving its normal appearance.
                .stroke(
                    colorSchemeContrast == .increased
                        ? theme.colors.primaryText
                        : .white.opacity(colorScheme == .dark ? 0.16 : 0.38),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.8
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
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

    func countryListSearchResultRow(_ country: CountryListOption) -> some View {
        HStack(spacing: 12) {
            Text(country.localizedName(locale: locale))
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                // Accessibility: Permit country names to wrap at accessibility text sizes.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

}
