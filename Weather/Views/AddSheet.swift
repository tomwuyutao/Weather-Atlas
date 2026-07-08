//
//  AddSheet.swift
//  Weather
//
//  Purpose: Presents the add-list options sheet for creating empty,
//  continent-based, or country-based city lists.
//

import SwiftUI

// MARK: - Add List Options

extension ContentView {
    var addListOptionsSheet: some View {
        AddSheet(
            onNewEmptyList: {
                showingAddListOptionsSheet = false
                Task { @MainActor in
                    await Task.yield()
                    beginCreatingListFromSwitcher()
                }
            },
            onAddContinent: {
                showingAddListOptionsSheet = false
                Task { @MainActor in
                    await Task.yield()
                    activateContinentListSearch()
                }
            },
            onAddCountry: {
                showingAddListOptionsSheet = false
                Task { @MainActor in
                    await Task.yield()
                    activateCountryListSearch()
                }
            }
        )
    }

    func activateAddListOptions() {
        showingAddListOptionsSheet = true
    }
}

struct AddSheet: View {
    let onNewEmptyList: () -> Void
    let onAddContinent: () -> Void
    let onAddCountry: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                addListOptionButton(
                    title: localizedString("New Empty List", locale: locale),
                    subtitle: localizedString("Start a list from scratch", locale: locale),
                    systemImage: "plus",
                    action: onNewEmptyList
                )

                addListOptionButton(
                    title: localizedString("Add Continent", locale: locale),
                    subtitle: localizedString("Create a list of the largest cities in a continent", locale: locale),
                    systemImage: "globe.europe.africa",
                    action: onAddContinent
                )

                addListOptionButton(
                    title: localizedString("Add Country", locale: locale),
                    subtitle: localizedString("Create a list of the largest cities in a country", locale: locale),
                    systemImage: "flag",
                    action: onAddCountry
                )
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(localizedString("Add List", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private func addListOptionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 36, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.avenir(.headline, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text(subtitle)
                        .font(.avenir(.footnote, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Add Sheet") {
    AddSheet(
        onNewEmptyList: {},
        onAddContinent: {},
        onAddCountry: {}
    )
}
