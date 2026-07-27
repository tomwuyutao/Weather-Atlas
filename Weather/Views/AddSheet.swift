//
//  AddSheet.swift
//  Weather
//
//  Purpose: Presents the add-list options sheet for creating empty,
//  continent-based, or country-based city lists.
//

import SwiftUI

// MARK: - Standalone Presentation State

/// Navigation and deferred-preview state for list creation launched from Add.
struct AddListPresentationState {
    /// Whether the standalone list-creation sheet is presented.
    var isPresented = false
    /// Whether the continent source picker is active.
    var showsContinentPicker = false
    /// Whether the country source picker is active.
    var showsCountryPicker = false
    /// Query filtering country creation sources.
    var countryQuery = ""
    /// Generated-list preview to open after the sheet dismisses.
    var dismissAction: ListManagementDismissAction?
}

// MARK: - List-Creation Options

/// List-creation entry sheet for empty, continent, and country sources.
struct AddSheet: View {
    /// Starts an empty custom list.
    let onNewEmptyList: () -> Void
    /// Opens the continent source picker.
    let onAddContinent: () -> Void
    /// Opens the country source picker.
    let onAddCountry: () -> Void

    /// App-selected locale used by all sheet copy.
    @Environment(\.locale) private var locale
    /// Active semantic palette.
    @Environment(\.appTheme) private var theme

    /// Builds the three creation options and explanatory header.
    var body: some View {
        VStack(spacing: 0) {
            addListOptionButton(
                title: localizedString("Add Continent", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a continent", locale: locale),
                systemImage: "globe.europe.africa",
                action: onAddContinent
            )

            // Inset separator between creation options.
            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            addListOptionButton(
                title: localizedString("Add Country", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a country", locale: locale),
                systemImage: "flag",
                action: onAddCountry
            )

            // Inset separator between creation options.
            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            addListOptionButton(
                title: localizedString("New Empty List", locale: locale),
                subtitle: localizedString("Start a list from scratch", locale: locale),
                systemImage: "pencil.and.list.clipboard",
                action: onNewEmptyList
            )
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.ignoresSafeArea())
    }

    /// Builds one creation row with consistent icon and typography.
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

// MARK: - Add-List Option Row

/// Reusable full-width action card used by list-creation workflows.
struct AddListOptionButton: View {
    /// Primary action title.
    let title: String
    /// Optional explanatory line below the title.
    let subtitle: String?
    /// SF Symbol representing the creation source.
    let systemImage: String
    /// Configurable title emphasis.
    var titleWeight: Font.Weight = .semibold
    /// Optional foreground override for branded tutorial variants.
    var titleColor: Color? = nil
    /// Whether the icon receives its standard circular backing.
    var showsIconBackground: Bool = true
    /// Optional icon foreground override.
    var iconColor: Color? = nil
    /// Action performed when the card is selected.
    let action: () -> Void

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Resolved appearance used to tune surface shadow.
    @Environment(\.colorScheme) private var colorScheme

    /// Builds the tappable option card.
    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                // Use the standard backed icon outside the branded tutorial variant.
                if showsIconBackground {
                    Image(systemName: systemImage)
                        .font(.system(size: 27, weight: .regular))
                        .foregroundStyle(iconColor ?? theme.colors.accent)
                        .frame(width: 58, height: 58)
                        .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 33, weight: .regular))
                        .foregroundStyle(iconColor ?? theme.colors.primaryText)
                        .frame(width: 58, height: 58)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(titleWeight))
                        .foregroundStyle(titleColor ?? theme.colors.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.vertical, 16)
            .frame(minHeight: subtitle == nil ? 82 : 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
