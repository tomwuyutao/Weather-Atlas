//
//  AddSheet.swift
//  Weather
//
//  Purpose: Presents the add-list options sheet for creating empty,
//  continent-based, or country-based city lists.
//

import SwiftUI

struct AddSheet: View {
    let onNewEmptyList: () -> Void
    let onAddContinent: () -> Void
    let onAddCountry: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            addListOptionButton(
                title: localizedString("New Empty List", locale: locale),
                subtitle: localizedString("Start a list from scratch", locale: locale),
                systemImage: "plus",
                action: onNewEmptyList
            )

            addSheetDivider

            addListOptionButton(
                title: localizedString("Add Continent", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a continent", locale: locale),
                systemImage: "globe.europe.africa",
                action: onAddContinent
            )

            addSheetDivider

            addListOptionButton(
                title: localizedString("Add Country", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a country", locale: locale),
                systemImage: "flag",
                action: onAddCountry
            )
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.mapOcean.ignoresSafeArea())
    }

    private var addSheetDivider: some View {
        Divider()
            .background(theme.colors.secondaryText.opacity(0.16))
    }

    private func addListOptionButton(
        title: String,
        subtitle: String?,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        AddListOptionButton(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            action: action
        )
    }
}
