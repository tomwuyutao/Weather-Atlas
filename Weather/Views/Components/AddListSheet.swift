//
//  AddListSheet.swift
//  Weather
//
//  Purpose: Defines the reusable list-creation choices used from both the
//  root Add sheet and List Manager.
//

import SwiftUI

// MARK: - Presentation State

/// Navigation and query state shared by every Add List entry point.
struct AddListSheetPresentationState {
    /// Whether the continent source picker is active.
    var showsContinentPicker = false
    /// Whether the country source picker is active.
    var showsCountryPicker = false
    /// Query filtering country creation sources.
    var countryQuery = ""
}

/// Presentation and deferred-preview state for the standalone New List sheet.
struct AddListSheetContainerState {
    /// Whether the shared New List sheet is presented from the global menu.
    var isPresented = false
    /// Current compact-sheet height, expanded for country search.
    var selectedDetent: PresentationDetent = .medium
    /// Navigation state owned by the shared list-creation choices.
    var creation = AddListSheetPresentationState()
    /// Generated preview to open after this sheet has dismissed.
    var dismissAction: ListManagementDismissAction?
}

/// Empty, continent, and country list choices shared by every entry point.
struct AddListSheet: View {
    @Binding var presentationState: AddListSheetPresentationState
    /// Starts an empty custom list.
    let onNewEmptyList: () -> Void
    /// Handles a continent source selection.
    let onSelectContinent: (CityListID) -> Void
    /// Handles a country source selection.
    let onSelectCountry: (CountryListOption) -> Void
    /// Lets the enclosing sheet expand before country search is pushed.
    var onCountrySearchPresented: (() -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            NewOptionButton(
                title: localizedString("New Continent", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a continent", locale: locale),
                systemImage: "globe.europe.africa",
                action: { presentationState.showsContinentPicker = true }
            )

            Divider()
                .background(theme.colors.secondaryText.opacity(0.16))

            NewOptionButton(
                title: localizedString("New Country", locale: locale),
                subtitle: localizedString("Create a list of the largest cities in a country", locale: locale),
                systemImage: "flag",
                action: {
                    onCountrySearchPresented?()
                    presentationState.showsCountryPicker = true
                }
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
        // These destinations live with the shared creation options, so Add and
        // List Manager always use the same search and selection implementation.
        .navigationDestination(isPresented: $presentationState.showsContinentPicker) {
            ContinentListPickerContent(lists: CityListID.builtInLists, onSelect: onSelectContinent)
                .navigationTitle(localizedString("New Continent", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $presentationState.showsCountryPicker) {
            CountryListSearchPicker(query: $presentationState.countryQuery, onSelect: onSelectCountry)
                .navigationTitle(localizedString("New Country", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Creation Option Row

/// Reusable full-width action row shared by list creation and onboarding.
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
