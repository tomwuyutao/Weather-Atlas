//
//  CustomizeDetail.swift
//  Weather
//
//  Purpose: Provides native drag reordering for movable city-detail sections.
//

import SwiftUI

// MARK: - Detail View Customization

/// A native inset-grouped list matching Manage Saved Places. The daily sunny
/// timeline is shown separately because it remains pinned below the city hero.
struct CustomizeDetail: View {
    @AppStorage(DetailReportSection.storageKey)
    private var storedOrder = DetailReportSection.defaultStorageValue

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var orderedSections: [DetailReportSection] {
        DetailReportSection.order(from: storedOrder)
    }

    var body: some View {
        NavigationStack {
            sectionList
                .weatherContentColumn(standardMaximumWidth: .infinity)
                .weatherScreenBackground()
                .navigationTitle("Customize Detail View")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        CloseButton(action: dismiss.callAsFunction)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var sectionList: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Label("Daily Sunny Hours", systemImage: "sun.max")
                        .foregroundStyle(theme.colors.primaryText)

                    Spacer(minLength: 8)

                    Image(systemName: "pin.fill")
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section {
                ForEach(orderedSections) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .foregroundStyle(theme.colors.primaryText)
                }
                .onMove(perform: moveSections)
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
        storedOrder = DetailReportSection.storageValue(
            for: reorderedSections
        )
    }
}

#if DEBUG

#Preview("Customize Detail View") {
    CustomizeDetail()
}
#endif
