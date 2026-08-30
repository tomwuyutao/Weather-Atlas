//
//  CustomizeSavedPlaces.swift
//  Weather
//
//  Purpose: Provides native drag reordering for Saved Places dashboard
//  sections and their cards.
//

import SwiftUI

// MARK: - Saved Places Dashboard Customization

/// A native inset-grouped list matching Customize Detail and Manage Saved
/// Places. Each level persists independently so adding a future card does not
/// disturb the person's higher-level dashboard section order.
struct CustomizeSavedPlaces: View {
    @AppStorage(SavedPlacesDashboardSection.storageKey)
    private var storedSectionOrder =
        SavedPlacesDashboardSection.defaultStorageValue
    @AppStorage(SavedPlacesSelectedDayCard.storageKey)
    private var storedSelectedDayCardOrder =
        SavedPlacesSelectedDayCard.defaultStorageValue
    @AppStorage(SavedPlacesPlanAheadCard.storageKey)
    private var storedPlanAheadCardOrder =
        SavedPlacesPlanAheadCard.defaultStorageValue

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var orderedSections: [SavedPlacesDashboardSection] {
        SavedPlacesDashboardSection.order(from: storedSectionOrder)
    }

    private var orderedSelectedDayCards: [SavedPlacesSelectedDayCard] {
        SavedPlacesSelectedDayCard.order(
            from: storedSelectedDayCardOrder
        )
    }

    private var orderedPlanAheadCards: [SavedPlacesPlanAheadCard] {
        SavedPlacesPlanAheadCard.order(from: storedPlanAheadCardOrder)
    }

    var body: some View {
        NavigationStack {
            customizationList
                .weatherContentColumn(standardMaximumWidth: .infinity)
                .weatherScreenBackground()
                .navigationTitle("Customize Saved Places")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        CloseButton(action: dismiss.callAsFunction)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var customizationList: some View {
        List {
            Section("Sections") {
                ForEach(orderedSections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .foregroundStyle(theme.colors.primaryText)
                }
                .onMove(perform: moveSections)
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section("Selected Day") {
                if orderedSelectedDayCards.count > 1 {
                    ForEach(orderedSelectedDayCards) { card in
                        selectedDayCardLabel(card)
                    }
                    .onMove(perform: moveSelectedDayCards)
                } else {
                    ForEach(orderedSelectedDayCards) { card in
                        selectedDayCardLabel(card)
                    }
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section("Plan Ahead") {
                ForEach(orderedPlanAheadCards) { card in
                    Label(card.title, systemImage: card.systemImage)
                        .foregroundStyle(theme.colors.primaryText)
                }
                .onMove(perform: movePlanAheadCards)
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .weatherScrollableBackground()
    }

    private func moveSections(
        from source: IndexSet,
        to destination: Int
    ) {
        var reorderedSections = orderedSections
        reorderedSections.move(
            fromOffsets: source,
            toOffset: destination
        )
        storedSectionOrder = SavedPlacesDashboardSection.storageValue(
            for: reorderedSections
        )
    }

    private func selectedDayCardLabel(
        _ card: SavedPlacesSelectedDayCard
    ) -> some View {
        Label(card.title, systemImage: card.systemImage)
            .foregroundStyle(theme.colors.primaryText)
    }

    private func moveSelectedDayCards(
        from source: IndexSet,
        to destination: Int
    ) {
        var reorderedCards = orderedSelectedDayCards
        reorderedCards.move(
            fromOffsets: source,
            toOffset: destination
        )
        storedSelectedDayCardOrder = SavedPlacesSelectedDayCard.storageValue(
            for: reorderedCards
        )
    }

    private func movePlanAheadCards(
        from source: IndexSet,
        to destination: Int
    ) {
        var reorderedCards = orderedPlanAheadCards
        reorderedCards.move(
            fromOffsets: source,
            toOffset: destination
        )
        storedPlanAheadCardOrder = SavedPlacesPlanAheadCard.storageValue(
            for: reorderedCards
        )
    }
}

#if DEBUG

#Preview("Customize Saved Places") {
    CustomizeSavedPlaces()
}
#endif
