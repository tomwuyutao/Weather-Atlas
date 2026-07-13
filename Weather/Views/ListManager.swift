//
//  ListManager.swift
//  Weather
//
//  Purpose: Provides the dedicated sheet for creating, reordering, renaming,
//  and deleting saved city lists.
//

import SwiftUI

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
            .environment(\.editMode, $listManagementEditMode)
            .scrollContentBackground(.hidden)
            .background(theme.colors.mapOcean)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showingListManagementAddOptions) {
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
                    Text(localizedString("Manage Lists", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                if listManagementEditMode != .active {
                    ToolbarItem(placement: .topBarLeading) {
                        listManagementCloseButton
                    }

                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                listManagementEditMode = .active
                            }
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .accessibilityLabel(localizedString("Edit", locale: locale))

                        Button {
                            showingListManagementAddOptions = true
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
        .onDisappear {
            commitInlineListRename()
            listManagementEditMode = .inactive
            showingListManagementAddOptions = false
            showingListManagementContinentPicker = false
            showingListManagementCountryPicker = false
        }
    }

    private var listManagementAddOptions: some View {
        AddSheet(
            onNewEmptyList: {
                showingListManagementAddOptions = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(260))
                    beginCreatingCustomList()
                }
            },
            onAddContinent: {
                showingListManagementContinentPicker = true
            },
            onAddCountry: {
                showingListManagementCountryPicker = true
            }
        )
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .toolbarBackground(theme.colors.mapOcean, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(isPresented: $showingListManagementContinentPicker) {
            listManagementContinentPicker
                .navigationTitle(localizedString("Add Continent", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showingListManagementCountryPicker) {
            listManagementCountryPicker
                .navigationTitle(localizedString("Add Country", locale: locale))
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var listManagementContinentPicker: some View {
        continentListSearchContent { listID in
            showingListManagementSheet = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                previewContinentList(listID)
            }
        }
    }

    private var listManagementCountryPicker: some View {
        countryListSearchContent { country in
            showingListManagementSheet = false
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                previewCountryList(country)
            }
        }
    }

    @ViewBuilder
    private func listManagementRow(for listID: CityListID) -> some View {
        Group {
            if listManagementEditMode == .active {
                if inlineListRenameID?.rawValue == listID.rawValue {
                    TextField(localizedString("Name", locale: locale), text: $inlineListName)
                        .focused($inlineListNameFocused)
                        .foregroundStyle(theme.colors.primaryText)
                        .submitLabel(.done)
                        .onSubmit {
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
                withAnimation(.smooth(duration: 0.2)) {
                    listManagementEditMode = .active
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

    private var listManagementCloseButton: some View {
        Button {
            showingListManagementSheet = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var listManagementDoneButton: some View {
        Button {
            commitInlineListRename()
            listManagementEditMode = .inactive
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func requestListDeletion(at offsets: IndexSet) {
        guard let index = offsets.first, managedLists.indices.contains(index) else { return }
        listToDeleteID = managedLists[index]
        showingDeleteListConfirmation = true
    }

    private func beginInlineListRename(_ listID: CityListID) {
        commitInlineListRename()
        inlineListRenameID = listID
        inlineListName = listID.localizedDisplayName(locale: locale)
        Task { @MainActor in
            await Task.yield()
            inlineListNameFocused = true
        }
    }

    private func commitInlineListRename() {
        guard let listID = inlineListRenameID else { return }
        let trimmedName = inlineListName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            weatherService.renameList(listID, to: trimmedName)
            refreshListOrder()
        }
        inlineListRenameID = nil
        inlineListName = ""
        inlineListNameFocused = false
    }
}
