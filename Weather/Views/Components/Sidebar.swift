//
//  Sidebar.swift
//  Weather
//
//  Purpose: Provides the permanent native Lists sidebar used on iPad.
//

import SwiftUI

// MARK: - iPad Lists Sidebar

extension ContentView {
    /// The permanent, system-styled Lists sidebar for regular iPad layouts.
    /// Each native list row directly switches the app's currently displayed list.
    var listManagementSidebar: some View {
        List(selection: sidebarListSelection) {
            ForEach(managedLists) { listID in
                listManagementSidebarRow(for: listID)
                    .tag(listID)
            }
            .onMove { source, destination in
                weatherService.moveLists(from: source, to: destination)
                refreshListOrder()
            }
            .onDelete { offsets in
                guard let index = offsets.first, managedLists.indices.contains(index) else { return }
                listToDeleteID = managedLists[index]
                showingDeleteListConfirmation = true
            }
        }
        .listStyle(.sidebar)
        .environment(\.editMode, $listManagementState.editMode)
        // The sidebar contains only list choices, so leave its navigation title blank.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if listManagementState.editMode != .active {
                // Keep list creation in the native top toolbar, rather than as
                // a persistent row that competes with the actual list choices.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Reuse the phone's standalone New List sheet instead
                        // of navigating away from the current detail column.
                        addListSheetState.selectedDetent = .medium
                        addListSheetState.isPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(localizedString("New List", locale: locale))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            listManagementState.editMode = .active
                        }
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel(localizedString("Edit", locale: locale))
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        commitInlineListRename()
                        listManagementState.editMode = .inactive
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!isInlineListRenameValid)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 420)
        .alert(localizedString("Delete List", locale: locale), isPresented: $showingDeleteListConfirmation) {
            Button(localizedString("Cancel", locale: locale), role: .cancel) {
                listToDeleteID = nil
            }
            Button(localizedString("Delete", locale: locale), role: .destructive) {
                if let listToDeleteID {
                    weatherService.deleteList(listToDeleteID)
                    refreshListOrder()
                }
                listToDeleteID = nil
            }
        } message: {
            Text(String(
                format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale),
                (listToDeleteID ?? weatherService.activeListID).localizedDisplayName(locale: locale)
            ))
        }
    }

    /// Adapts the active list identity to SwiftUI's native single-row selection.
    private var sidebarListSelection: Binding<CityListID?> {
        Binding(
            get: { weatherService.activeListID },
            set: { selectedListID in
                guard let selectedListID,
                      selectedListID.rawValue != weatherService.activeListID.rawValue else {
                    return
                }
                beginSwitchToList(selectedListID)
            }
        )
    }

    /// A standard tagged sidebar row whose selected state is drawn by SwiftUI.
    @ViewBuilder
    private func listManagementSidebarRow(for listID: CityListID) -> some View {
        if listManagementState.editMode == .active {
            listManagementRow(for: listID)
        } else {
            HStack(spacing: 8) {
                Text(listID.localizedDisplayName(locale: locale))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer(minLength: 8)

                Text(verbatim: String(weatherService.cityListCoordinates(for: listID).count))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .contextMenu {
                listManagementContextMenu(for: listID)
            }
        }
    }
}
