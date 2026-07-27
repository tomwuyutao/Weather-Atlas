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
    var showsAddOptions = false
    /// Whether the continent source destination is active.
    var showsContinentPicker = false
    /// Whether the country source destination is active.
    var showsCountryPicker = false
    /// Work deferred until the management sheet has dismissed.
    var dismissAction: ListManagementDismissAction?
    /// Native list edit mode for reordering, deletion, and inline rename.
    var editMode: EditMode = .inactive
    /// List currently being renamed inline.
    var renamingListID: CityListID?
    /// Staged inline list name.
    var renameText = ""
    /// Query filtering country creation sources.
    var countryQuery = ""
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
    func commitListManagerNewList() {
        let trimmed = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newListName = ""

        Task {
            let listID = await weatherService.createCustomList(name: trimmed, cities: [])
            await switchToList(listID)
            refreshListOrder()
            listManagementState.isPresented = false
            addListState.isPresented = false
            centerMapOnDots()
        }
    }

    /// Opens the route selected by a list-creation sheet after it dismisses.
    func performListCreationDismissAction(_ action: ListManagementDismissAction) {
        switch action {
        case .citySearch:
            presentAddCitySearch()
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

    /// Presents the shared list-creation choices directly from the global Add menu.
    var addListSheet: some View {
        NavigationStack {
            AddSheet(
                onNewEmptyList: {
                    newListName = ""
                    showingAddListAlert = true
                },
                onAddContinent: {
                    addListState.showsContinentPicker = true
                },
                onAddCountry: {
                    addListState.showsCountryPicker = true
                }
            )
            .navigationTitle(localizedString("New List", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    listManagementToolbarButton(systemImage: "xmark") {
                        addListState.isPresented = false
                    }
                }
            }
            .navigationDestination(isPresented: $addListState.showsContinentPicker) {
                ContinentListPickerContent(lists: CityListID.builtInLists) { listID in
                    addListState.dismissAction = .previewContinent(listID)
                    addListState.isPresented = false
                }
                .navigationTitle(localizedString("Add Continent", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $addListState.showsCountryPicker) {
                countryListSearchContent(query: $addListState.countryQuery) { country in
                    addListState.dismissAction = .previewCountry(country)
                    addListState.isPresented = false
                }
                .navigationTitle(localizedString("Add Country", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .presentationBackground(theme.colors.background)
        .tint(theme.colors.accent)
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
                            listManagementState.showsAddOptions = true
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

                    // Keep city search visually separate from list creation.
                    Section {
                        Button {
                            listManagementState.dismissAction = .citySearch
                            listManagementState.isPresented = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .fontWeight(.semibold)
                                Text(localizedString("Add City to List", locale: locale))
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
                        // Dismiss Lists management outside edit mode.
                        listManagementToolbarButton(systemImage: "xmark") {
                            listManagementState.isPresented = false
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
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
        // Keep the automatic back control in the nested add-list flow on the
        // app's navy accent instead of the system sheet tint.
        .tint(theme.colors.accent)
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
            listManagementState.showsAddOptions = false
            listManagementState.showsContinentPicker = false
            listManagementState.showsCountryPicker = false
        }
    }

    // MARK: Add-List Options

    /// Builds the nested empty/continent/country creation destination.
    private var listManagementAddOptions: some View {
        AddSheet(
            onNewEmptyList: {
                listManagementState.showsAddOptions = false
                // Present the native alert for naming an empty custom list.
                newListName = ""
                showingAddListAlert = true
            },
            onAddContinent: {
                listManagementState.showsContinentPicker = true
            },
            onAddCountry: {
                listManagementState.showsCountryPicker = true
            }
        )
        .background(theme.colors.background.ignoresSafeArea())
        .toolbarBackground(theme.colors.background, for: .navigationBar)
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
            // Defer the generated preview until the management sheet dismisses.
            ContinentListPickerContent(lists: CityListID.builtInLists) { listID in
                listManagementState.dismissAction = .previewContinent(listID)
                listManagementState.isPresented = false
            }
                .navigationTitle(localizedString("Add Continent", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $listManagementState.showsCountryPicker) {
            countryListSearchContent(query: $listManagementState.countryQuery) { country in
                listManagementState.dismissAction = .previewCountry(country)
                listManagementState.isPresented = false
            }
                .navigationTitle(localizedString("Add Country", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: List Rows

    @ViewBuilder
    /// Builds a selectable or inline-editable row for one saved list.
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
                        // Commit any previous edit before staging this list's rename.
                        commitInlineListRename()
                        listManagementState.renamingListID = listID
                        listManagementState.renameText = listID.localizedDisplayName(locale: locale)
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
    }

    /// Builds a list name, city count, and optional active-list checkmark.
    private func listManagementRowLabel(for listID: CityListID, showsSelection: Bool) -> some View {
        HStack {
            Text(listID.localizedDisplayName(locale: locale))
                .foregroundStyle(theme.colors.primaryText)
            Spacer()

            Text(verbatim: String(weatherService.cityListCoordinates(for: listID).count))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.colors.secondaryText)

            if showsSelection, listID.rawValue == weatherService.activeListID.rawValue {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.accent)
            }
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

    /// Whether no rename is active or its staged text is nonempty.
    private var isInlineListRenameValid: Bool {
        guard listManagementState.renamingListID != nil else { return true }
        return !listManagementState.renameText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

}
