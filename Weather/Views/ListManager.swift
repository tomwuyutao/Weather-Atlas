//
//  ListManager.swift
//  Weather
//
//  Purpose: Provides the dedicated sheet for creating, reordering, renaming,
//  and deleting saved city lists.
//

import SwiftUI

// MARK: - Presentation State

/// Navigation and inline-edit state for the Lists management sheet.
struct ListManagementState {
    var isPresented = false
    var showsAddOptions = false
    var showsContinentPicker = false
    var showsCountryPicker = false
    var dismissAction: ListManagementDismissAction?
    var editMode: EditMode = .inactive
    var renamingListID: CityListID?
    var renameText = ""
    var countryQuery = ""
}

enum ListManagementDismissAction {
    case previewContinent(CityListID)
    case previewCountry(CountryListOption)
}

// MARK: - List Creation Actions

extension ContentView {
    func beginCreatingCustomList() {
        newListName = ""
        showingAddListAlert = true
    }

    func commitListManagerNewList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newListName = ""

        Task {
            let listID = await weatherService.createCustomList(name: trimmed, cities: [])
            await switchToList(listID)
            refreshListOrder()
            listManagementState.isPresented = false
            centerMapOnDots(useListCoordinates: true)
        }
    }
}

extension ContentView {
    // MARK: Sheet Composition

    var listManagementSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(managedLists) { listID in
                        listManagementRow(for: listID)
                            .listRowBackground(theme.colors.settingsRowFill)
                    }
                    .onMove { source, destination in
                        weatherService.moveLists(from: source, to: destination)
                        refreshListOrder()
                    }
                    .onDelete(perform: requestListDeletion)
                }

                if listManagementState.editMode != .active {
                    Section {
                        listManagementNewListRow
                    }
                }
            }
            .environment(\.editMode, $listManagementState.editMode)
            .scrollContentBackground(.hidden)
            .background(theme.colors.mapOcean)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $listManagementState.showsAddOptions) {
                listManagementAddOptions
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) {
                            Text(localizedString("New List", locale: locale))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localizedString("Lists", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                if listManagementState.editMode != .active {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                listManagementState.editMode = .active
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        listManagementCloseButton
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        listManagementDoneButton
                    }
                }
            }
        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .presentationBackground(theme.colors.mapOcean)
        // Keep the automatic back control in the nested add-list flow on the
        // app's navy accent instead of the system sheet tint.
        .tint(theme.colors.accent)
        .onDisappear {
            if isInlineListRenameValid {
                commitInlineListRename()
            } else {
                cancelInlineListRename()
            }
            listManagementState.editMode = .inactive
            listManagementState.showsAddOptions = false
            listManagementState.showsContinentPicker = false
            listManagementState.showsCountryPicker = false
        }
    }

    // MARK: Add-List Options

    private var listManagementAddOptions: some View {
        AddSheet(
            onNewEmptyList: {
                listManagementState.showsAddOptions = false
                beginCreatingCustomList()
            },
            onAddContinent: {
                listManagementState.showsContinentPicker = true
            },
            onAddCountry: {
                listManagementState.showsCountryPicker = true
            }
        )
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .toolbarBackground(theme.colors.mapOcean, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // The system Liquid Glass back symbol is always rendered in the system
        // foreground color. Use the same native toolbar position with an explicit
        // label so this app control keeps the theme's navy icon color.
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    listManagementState.showsAddOptions = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(isPresented: $listManagementState.showsContinentPicker) {
            listManagementContinentPicker
                .navigationTitle(localizedString("Add Continent", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $listManagementState.showsCountryPicker) {
            listManagementCountryPicker
                .navigationTitle(localizedString("Add Country", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var listManagementContinentPicker: some View {
        continentListSearchContent { listID in
            listManagementState.dismissAction = .previewContinent(listID)
            listManagementState.isPresented = false
        }
    }

    private var listManagementCountryPicker: some View {
        countryListSearchContent { country in
            listManagementState.dismissAction = .previewCountry(country)
            listManagementState.isPresented = false
        }
    }

    // MARK: List Rows

    @ViewBuilder
    private func listManagementRow(for listID: CityListID) -> some View {
        Group {
            if listManagementState.editMode == .active {
                if listManagementState.renamingListID?.rawValue == listID.rawValue {
                    TextField(localizedString("Name", locale: locale), text: $listManagementState.renameText)
                        .focused($inlineListNameFocused)
                        .defaultFocus($inlineListNameFocused, true)
                        .foregroundStyle(theme.colors.primaryText)
                        .submitLabel(.done)
                        .onSubmit {
                            guard isInlineListRenameValid else { return }
                            commitInlineListRename()
                        }
                } else {
                    Button {
                        beginInlineListRename(listID)
                    } label: {
                        listManagementRowLabel(for: listID, showsSelection: false)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    Task {
                        await switchToList(listID)
                    }
                } label: {
                    listManagementRowLabel(for: listID, showsSelection: true)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            Button {
                activateInlineListRename(listID)
            } label: {
                primaryMenuLabel(localizedString("Rename List", locale: locale), systemImage: "pencil")
            }

            Button {
                confirmListDeletion(listID)
            } label: {
                Label {
                    Text(localizedString("Delete List", locale: locale))
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.colors.destructive)
                }
            }
            .tint(theme.colors.destructive)
        }
    }

    private func listManagementRowLabel(for listID: CityListID, showsSelection: Bool) -> some View {
        HStack {
            Text(listID.localizedDisplayName(locale: locale))
                .foregroundStyle(theme.colors.primaryText)
            Spacer()
            if showsSelection, listID.rawValue == weatherService.activeListID.rawValue {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .contentShape(Rectangle())
    }

    private var listManagementNewListRow: some View {
        Button {
            listManagementState.showsAddOptions = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .fontWeight(.semibold)
                Text(localizedString("New List", locale: locale))
                    .fontWeight(.semibold)
                Spacer()
            }
            .foregroundStyle(theme.colors.primaryText)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.colors.dotSun)
    }

    // MARK: List Manager Toolbar

    private var listManagementCloseButton: some View {
        listManagementToolbarButton(
            systemImage: "xmark"
        ) {
            listManagementState.isPresented = false
        }
    }

    private var listManagementDoneButton: some View {
        listManagementToolbarButton(
            systemImage: "checkmark"
        ) {
            commitInlineListRename()
            listManagementState.editMode = .inactive
        }
        .disabled(!isInlineListRenameValid)
        .opacity(isInlineListRenameValid ? 1 : 0.35)
    }

    private func listManagementToolbarButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: List Manager Actions

    private func requestListDeletion(at offsets: IndexSet) {
        guard let index = offsets.first, managedLists.indices.contains(index) else { return }
        confirmListDeletion(managedLists[index])
    }

    private func confirmListDeletion(_ listID: CityListID) {
        listToDeleteID = listID
        showingDeleteListConfirmation = true
    }

    private func activateInlineListRename(_ listID: CityListID) {
        withAnimation(.smooth(duration: 0.2)) {
            listManagementState.editMode = .active
            beginInlineListRename(listID)
        }
    }

    private func beginInlineListRename(_ listID: CityListID) {
        commitInlineListRename()
        listManagementState.renamingListID = listID
        listManagementState.renameText = listID.localizedDisplayName(locale: locale)
    }

    func performListManagementDismissAction() {
        guard let action = listManagementState.dismissAction else { return }
        listManagementState.dismissAction = nil
        switch action {
        case .previewContinent(let listID):
            previewContinentList(listID)
        case .previewCountry(let country):
            previewCountryList(country)
        }
    }

    private func commitInlineListRename() {
        guard let listID = listManagementState.renamingListID else { return }
        let trimmedName = listManagementState.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        weatherService.renameList(listID, to: trimmedName)
        refreshListOrder()
        listManagementState.renamingListID = nil
        listManagementState.renameText = ""
        inlineListNameFocused = false
    }

    private var isInlineListRenameValid: Bool {
        guard listManagementState.renamingListID != nil else { return true }
        return !listManagementState.renameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func cancelInlineListRename() {
        listManagementState.renamingListID = nil
        listManagementState.renameText = ""
        inlineListNameFocused = false
    }

}
