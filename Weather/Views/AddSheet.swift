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
            .background(Color.secondary.opacity(0.16))
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

struct AddListOptionButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var titleWeight: Font.Weight = .semibold
    var titleColor: Color? = nil
    var showsIconBackground: Bool = true
    var iconColor: Color? = nil
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                addListOptionIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(titleWeight))
                        .foregroundStyle(titleColor ?? theme.colors.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(theme.colors.secondaryText)
                            // Accessibility: Let explanatory copy wrap fully at large text sizes.
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 22, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 16)
            .frame(minHeight: subtitle == nil ? 82 : 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Accessibility: Present the styled row as a single named action; its icon and
        // chevron remain decorative, while the visible subtitle is retained as its value.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
    }

    @ViewBuilder
    private var addListOptionIcon: some View {
        if showsIconBackground {
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(iconColor ?? theme.colors.accent)
                .frame(width: 58, height: 58)
                .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 33, weight: .regular))
                .foregroundStyle(iconColor ?? theme.colors.primaryText)
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)
        }
    }
}
