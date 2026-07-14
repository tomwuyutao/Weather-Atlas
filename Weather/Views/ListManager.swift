//
//  ListManager.swift
//  Weather
//
//  Purpose: Provides the dedicated sheet for creating, reordering, renaming,
//  and deleting saved city lists.
//

import SwiftUI

enum ListManagementDismissAction {
    case previewContinent(CityListID)
    case previewCountry(CountryListOption)
}

extension ContentView {
    var listManagementSheet: some View {
        NavigationStack {
            List {
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
                                // Accessibility: Custom toolbar titles need an explicit heading trait.
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localizedString("Manage Lists", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        // Accessibility: Custom toolbar titles need an explicit heading trait.
                        .accessibilityAddTraits(.isHeader)
                }

                if listManagementState.editMode != .active {
                    ToolbarItem(placement: .topBarLeading) {
                        listManagementCloseButton
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                listManagementState.editMode = .active
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(localizedString("Edit", locale: locale))

                        Button {
                            listManagementState.showsAddOptions = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(localizedString("New List", locale: locale))
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
        // Accessibility: Mirror the sheet's visible hierarchy with the standard
        // escape action so no drag gesture is required to leave a nested picker.
        .accessibilityAction(.escape) {
            dismissListManagementAccessibility()
        }
        .onDisappear {
            commitInlineListRename()
            listManagementState.editMode = .inactive
            listManagementState.showsAddOptions = false
            listManagementState.showsContinentPicker = false
            listManagementState.showsCountryPicker = false
        }
    }

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
                            commitInlineListRename()
                        }
                        .accessibilityLabel(localizedString("Name", locale: locale))
                } else {
                    Button {
                        beginInlineListRename(listID)
                    } label: {
                        listManagementRowLabel(for: listID, showsSelection: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(listID.localizedDisplayName(locale: locale))
                    .accessibilityHint(localizedString("Rename List", locale: locale))
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
                // Accessibility: Announce which list is active; the visual checkmark is decorative.
                .accessibilityLabel(listID.localizedDisplayName(locale: locale))
                .accessibilityAddTraits(
                    listID.rawValue == weatherService.activeListID.rawValue ? .isSelected : []
                )
            }
        }
        .contextMenu {
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    listManagementState.editMode = .active
                    beginInlineListRename(listID)
                }
            } label: {
                primaryMenuLabel(localizedString("Rename List", locale: locale), systemImage: "pencil")
            }

            Button(role: .destructive) {
                listToDeleteID = listID
                showingDeleteListConfirmation = true
            } label: {
                Label(localizedString("Delete List", locale: locale), systemImage: "trash")
            }
        }
        // Accessibility: Context-menu operations are duplicated as named actions so
        // VoiceOver and Voice Control do not need a long-press gesture to discover them.
        .accessibilityAction(named: Text(localizedString("Rename List", locale: locale))) {
            withAnimation(.smooth(duration: 0.2)) {
                listManagementState.editMode = .active
                beginInlineListRename(listID)
            }
        }
        .accessibilityAction(named: Text(localizedString("Delete List", locale: locale))) {
            listToDeleteID = listID
            showingDeleteListConfirmation = true
        }
        // Accessibility: Native edit-mode drag handles remain unchanged visually; these
        // actions provide the same reordering workflow without a drag gesture.
        .accessibilityActions {
            if let index = managedLists.firstIndex(where: { $0.rawValue == listID.rawValue }), index > 0 {
                Button(localizedString("Move Up", locale: locale)) {
                    moveListAccessibility(listID, direction: -1)
                }
            }

            if let index = managedLists.firstIndex(where: { $0.rawValue == listID.rawValue }), index < managedLists.count - 1 {
                Button(localizedString("Move Down", locale: locale)) {
                    moveListAccessibility(listID, direction: 1)
                }
            }
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
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    private var listManagementCloseButton: some View {
        // Accessibility: The explicit 44-point label makes the whole circular control tappable.
        Button {
            listManagementState.isPresented = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("Cancel", locale: locale))
    }

    private var listManagementDoneButton: some View {
        // Accessibility: Match the close control's 44-point hit target.
        Button {
            commitInlineListRename()
            listManagementState.editMode = .inactive
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("Done", locale: locale))
    }

    private func requestListDeletion(at offsets: IndexSet) {
        guard let index = offsets.first, managedLists.indices.contains(index) else { return }
        listToDeleteID = managedLists[index]
        showingDeleteListConfirmation = true
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
        if !trimmedName.isEmpty {
            weatherService.renameList(listID, to: trimmedName)
            refreshListOrder()
        }
        listManagementState.renamingListID = nil
        listManagementState.renameText = ""
        inlineListNameFocused = false
    }

    private func moveListAccessibility(_ listID: CityListID, direction: Int) {
        guard let sourceIndex = managedLists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let targetIndex = sourceIndex + direction
        guard managedLists.indices.contains(targetIndex) else { return }

        // Accessibility: Collection move destinations are insertion offsets; moving down
        // one row therefore inserts after the target's original position.
        let destination = direction < 0 ? targetIndex : targetIndex + 1
        weatherService.moveLists(from: IndexSet(integer: sourceIndex), to: destination)
        refreshListOrder()
    }

    // MARK: - Accessibility - List Manager Navigation

    private func dismissListManagementAccessibility() {
        if listManagementState.showsCountryPicker {
            listManagementState.showsCountryPicker = false
        } else if listManagementState.showsContinentPicker {
            listManagementState.showsContinentPicker = false
        } else if listManagementState.showsAddOptions {
            listManagementState.showsAddOptions = false
        } else if listManagementState.editMode == .active {
            commitInlineListRename()
            listManagementState.editMode = .inactive
        } else {
            listManagementState.isPresented = false
        }
    }
}
