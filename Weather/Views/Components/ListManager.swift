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
    /// Whether the Lists management sheet is presented.
    var isPresented = false
    /// Whether the nested list-creation options are visible.
    var showsNewListOptions = false
    /// Shared navigation state for the nested list-creation flow.
    var listCreation = AddListSheetPresentationState()
    /// Current compact-sheet height, expanded for nested country search.
    var selectedDetent: PresentationDetent = .medium
    /// Work deferred until the management sheet has dismissed.
    var dismissAction: ListManagementDismissAction?
    /// Native list edit mode for reordering, deletion, and inline rename.
    var editMode: EditMode = .inactive
    /// List currently being renamed inline.
    var renamingListID: CityListID?
    /// Staged inline list name.
    var renameText = ""
}

/// Destination to open after dismissing the management sheet.
enum ListManagementDismissAction {
    case citySearch
    case previewContinent(CityListID)
    case previewCountry(CountryListOption)
}

// MARK: - List Creation Actions

extension ContentView {
    /// Validates, creates, activates, and dismisses after an empty-list save.
    func commitNewList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newListName = ""

        Task {
            let listID = await weatherService.createCustomList(name: trimmed, cities: [])
            await switchToList(listID)
            refreshListOrder()
            if isIPad {
                listManagementState.showsNewListOptions = false
            } else {
                listManagementState.isPresented = false
            }
            addListSheetState.isPresented = false
            centerMapOnDots()
        }
    }

    /// Opens the route selected by a list-creation sheet after it dismisses.
    func performListCreationDismissAction(_ action: ListManagementDismissAction) {
        switch action {
        case .citySearch:
            presentNewCitySearch()
        case .previewContinent(let listID):
            let cities = CountryCityCatalog.topCities(
                forContinentRawValue: listID.rawValue,
                limit: CountryCityCatalog.maxCountryCityCount
            )
            previewGeneratedList(
                name: listID.canonicalLocalizedDisplayName(locale: locale),
                cities: cities.isEmpty ? listID.defaultCities : cities,
                nameSource: .continent(rawValue: listID.rawValue, duplicateIndex: nil)
            )
        case .previewCountry(let country):
            previewGeneratedList(
                name: country.localizedName(locale: locale),
                cities: CountryCityCatalog.topCities(
                    for: country,
                    limit: CountryCityCatalog.maxCountryCityCount
                ),
                nameSource: .country(iso2: country.iso2, duplicateIndex: nil)
            )
        }
    }
}

extension ContentView {
    // MARK: Sheet Composition

    /// Shared New List workflow presented from the global plus menu.
    var addListSheet: some View {
        NavigationStack {
            addListSheetContent
                .navigationTitle(localizedString("New List", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .presentationBackground(theme.colors.background)
        .tint(theme.colors.accent)
    }

    /// List choices and source selection shared with the List Manager.
    private var addListSheetContent: some View {
        AddListSheet(
            presentationState: $addListSheetState.creation,
            onNewEmptyList: {
                newListName = ""
                showingNewListAlert = true
            },
            onSelectContinent: { listID in
                addListSheetState.dismissAction = .previewContinent(listID)
                addListSheetState.isPresented = false
            },
            onSelectCountry: { country in
                addListSheetState.dismissAction = .previewCountry(country)
                addListSheetState.isPresented = false
            },
            onCountrySearchPresented: {
                // Country search is a full-height task within this stack.
                addListSheetState.selectedDetent = .large
            }
        )
    }

    /// Composes list selection, editing, creation navigation, and toolbar state.
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
                    .onDelete { offsets in
                        // Convert native offsets into the pending delete confirmation.
                        guard let index = offsets.first, managedLists.indices.contains(index) else { return }
                        listToDeleteID = managedLists[index]
                        showingDeleteListConfirmation = true
                    }
                }

                if listManagementState.editMode != .active {
                    Section {
                        Button {
                            listManagementState.showsNewListOptions = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .fontWeight(.semibold)
                                Text(localizedString("New List", locale: locale))
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            // Yellow action rows keep the same dark foreground
                            // in every appearance for stable contrast.
                            .foregroundStyle(AppPalette.light.titleText)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.colors.dotSun)
                    }

                }
            }
            .environment(\.editMode, $listManagementState.editMode)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $listManagementState.showsNewListOptions) {
                listManagementNewListOptions
                    .navigationTitle(localizedString("New List", locale: locale))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localizedString("Lists", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                if listManagementState.editMode != .active {
                    ToolbarItem(placement: .topBarLeading) {
                        if !isIPad {
                            // The compact sheet needs its own dismissal control.
                            // On iPad, the detail-column sidebar button owns this.
                            listManagementToolbarButton(systemImage: "xmark") {
                                listManagementState.isPresented = false
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                listManagementState.editMode = .active
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                    }

                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        // Commit a valid inline rename and leave edit mode.
                        listManagementToolbarButton(systemImage: "checkmark") {
                            commitInlineListRename()
                            listManagementState.editMode = .inactive
                        }
                        .disabled(!isInlineListRenameValid)
                        .opacity(isInlineListRenameValid ? 1 : 0.35)
                    }
                }
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .presentationBackground(theme.colors.background)
        // Keep the automatic back control in the nested new-list flow on the
        // app's navy accent instead of the system sheet tint.
        .tint(theme.colors.accent)
        // Present from the manager itself. An alert attached to the underlying
        // root view makes SwiftUI dismiss this sheet before showing the alert.
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
        .onDisappear {
            if isInlineListRenameValid {
                commitInlineListRename()
            } else {
                // Discard the invalid staged rename and release field focus.
                listManagementState.renamingListID = nil
                listManagementState.renameText = ""
                inlineListNameFocused = false
            }
            listManagementState.editMode = .inactive
            listManagementState.showsNewListOptions = false
            listManagementState.listCreation = AddListSheetPresentationState()
            listManagementState.selectedDetent = .medium
        }
    }

    // MARK: New-List Options

    /// Finishes a list-creation route without dismissing the permanent iPad sidebar.
    private func completeListManagementSelection(_ action: ListManagementDismissAction) {
        if isIPad {
            listManagementState.showsNewListOptions = false
            performListCreationDismissAction(action)
        } else {
            listManagementState.dismissAction = action
            listManagementState.isPresented = false
        }
    }

    /// Builds the nested empty/continent/country creation destination.
    var listManagementNewListOptions: some View {
        AddListSheet(
            presentationState: $listManagementState.listCreation,
            onNewEmptyList: {
                listManagementState.showsNewListOptions = false
                // Present the native alert for naming an empty custom list.
                newListName = ""
                showingNewListAlert = true
            },
            onSelectContinent: { listID in
                completeListManagementSelection(.previewContinent(listID))
            },
            onSelectCountry: { country in
                completeListManagementSelection(.previewCountry(country))
            },
            onCountrySearchPresented: {
                listManagementState.selectedDetent = .large
            }
        )
        .if(!isIPad) { view in
            view
                .background(theme.colors.background.ignoresSafeArea())
                .toolbarBackground(theme.colors.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    // MARK: List Rows

    @ViewBuilder
    /// Builds a selectable or inline-editable row for one saved list.
    func listManagementRow(for listID: CityListID) -> some View {
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
                        // Commit any previous edit before staging this list's rename.
                        commitInlineListRename()
                        listManagementState.renamingListID = listID
                        listManagementState.renameText = listID.localizedDisplayName(locale: locale)
                    } label: {
                        // The iPad sidebar already highlights the active row;
                        // avoid a second selection indicator while editing it.
                        listManagementRowLabel(for: listID, showsSelection: !isIPad)
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
        .contextMenu { listManagementContextMenu(for: listID) }
    }

    /// Provides the shared native contextual actions for a saved list.
    @ViewBuilder
    func listManagementContextMenu(for listID: CityListID) -> some View {
        Button {
            // Enter edit mode and focus this list's inline name field.
            withAnimation(.smooth(duration: 0.2)) {
                listManagementState.editMode = .active
                commitInlineListRename()
                listManagementState.renamingListID = listID
                listManagementState.renameText = listID.localizedDisplayName(locale: locale)
            }
        } label: {
            primaryMenuLabel(localizedString("Rename List", locale: locale), systemImage: "pencil")
        }

        Button {
            // Capture the identity before presenting the destructive native alert.
            listToDeleteID = listID
            showingDeleteListConfirmation = true
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

    /// Builds a list name, city count, and optional active-list checkmark.
    private func listManagementRowLabel(for listID: CityListID, showsSelection: Bool) -> some View {
        HStack {
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.accent)
                .frame(width: 20)
                .opacity(showsSelection && listID.rawValue == weatherService.activeListID.rawValue ? 1 : 0)

            Text(listID.localizedDisplayName(locale: locale))
                .foregroundStyle(theme.colors.primaryText)
            Spacer()

            Text(verbatim: String(weatherService.cityListCoordinates(for: listID).count))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.colors.secondaryText)
        }
        .contentShape(Rectangle())
    }

    // MARK: List Manager Toolbar

    /// Builds a consistently sized native list-manager toolbar action.
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

    /// Persists a valid trimmed inline name and clears editing state.
    func commitInlineListRename() {
        guard let listID = listManagementState.renamingListID else { return }
        let trimmedName = listManagementState.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        weatherService.renameList(listID, to: trimmedName)
        refreshListOrder()
        listManagementState.renamingListID = nil
        listManagementState.renameText = ""
        inlineListNameFocused = false
    }

    /// Whether no rename is active or its staged text is nonempty.
    var isInlineListRenameValid: Bool {
        guard listManagementState.renamingListID != nil else { return true }
        return !listManagementState.renameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

}
