//
//  NewSheet.swift
//  Weather
//
//  Purpose: Defines the unified New sheet and the nested list-creation
//  choices shared by the global creation flow and Lists manager.
//

import SwiftUI

// MARK: - Presentation State

/// Navigation and deferred-preview state for the unified New sheet.
struct NewSheetPresentationState {
    /// Whether the standalone creation sheet is presented.
    var isPresented = false
    /// Whether city search is pushed within the sheet.
    var showsCitySearch = false
    /// Whether list-creation choices are pushed within the sheet.
    var showsListOptions = false
    /// Whether the continent source picker is active.
    var showsContinentPicker = false
    /// Whether the country source picker is active.
    var showsCountryPicker = false
    /// Current compact-sheet height on iPhone.
    var selectedDetent: PresentationDetent = .medium
    /// Query filtering country creation sources.
    var countryQuery = ""
    /// Generated-list preview to open after the sheet dismisses.
    var dismissAction: ListManagementDismissAction?
}

// MARK: - New Options

/// Root creation choices shown when the global plus button is selected.
struct NewSheetContent: View {
    /// Localized name of the list that receives a newly searched place.
    let cityDestinationName: String
    /// Opens city search for the active list.
    let onNewCity: () -> Void
    /// Opens the nested list-creation choices.
    let onNewList: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            NewOptionButton(
                title: localizedString("New City", locale: locale),
                subtitle: String(
                    format: localizedString("Search for a place and save it to %@.", locale: locale),
                    locale: locale,
                    cityDestinationName
                ),
                systemImage: "building.2",
                action: onNewCity
            )

            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            NewOptionButton(
                title: localizedString("New List", locale: locale),
                subtitle: localizedString("Create a list to organize cities for a trip or region.", locale: locale),
                systemImage: "list.bullet",
                action: onNewList
            )
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.colors.background.ignoresSafeArea())
    }
}

/// Empty, continent, and country choices shown within the New sheet.
struct NewListSheetContent: View {
    /// Starts an empty custom list.
    let onNewEmptyList: () -> Void
    /// Opens the continent source picker.
    let onNewContinent: () -> Void
    /// Opens the country source picker.
    let onNewCountry: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            NewOptionButton(
                title: localizedString("New Continent", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a continent", locale: locale),
                systemImage: "globe.europe.africa",
                action: onNewContinent
            )

            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            NewOptionButton(
                title: localizedString("New Country", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a country", locale: locale),
                systemImage: "flag",
                action: onNewCountry
            )

            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            NewOptionButton(
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
}

// MARK: - Creation Option Row

/// Reusable full-width action row shared by every creation workflow.
struct NewOptionButton: View {
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
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
