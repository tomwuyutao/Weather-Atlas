//
//  ContentView+Sidebar.swift
//  Weather
//
//  List switcher sheet: shows all lists with single-select (list view) or
//  multi-select (map view), plus management actions (add, rename, reorder, delete).
//

import SwiftUI

extension ContentView {

    // MARK: - List Switcher Sheet

    var listSwitcherSheet: some View {
        ZStack(alignment: .top) {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — X button always visible
                HStack {
                    Spacer()
                    Button {
                        showingListSwitcher = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .themedGlass(in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                if isAddingListInSheet {
                    listSwitcherNewListView
                } else if isEditingSheetLists {
                    listSwitcherEditingView
                } else {
                    // List selection content
                    ScrollView {
                        VStack(spacing: 10) {
                            if selectedTab == 1 {
                                listSwitcherMapRows
                            } else {
                                listSwitcherListRows
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }

                    // Bottom bar with + and Edit
                    HStack {
                        // Add button — context menu
                        Menu {
                            Button {
                                newSheetListName = ""
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isAddingListInSheet = true
                                    listSheetDetent = .large
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    newListNameFocused = true
                                }
                            } label: {
                                Label(localizedString("Add Custom List", locale: locale), systemImage: "plus")
                            }
                            Button {
                                showingListSwitcher = false
                                if isIPad {
                                    showingCountrySearch = true
                                } else {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                        showingCountrySearch = true
                                    }
                                }
                            } label: {
                                Label(localizedString("Add Country", locale: locale), systemImage: "globe")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .frame(width: 44, height: 44)
                                .themedGlass(in: .circle)
                        }

                        Spacer()

                        // Edit button
                        Button {
                            reorderableLists = CityListID.allLists
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                isEditingSheetLists = true
                            }
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .frame(width: 44, height: 44)
                                .themedGlass(in: .circle)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: showingListSwitcher) { _, showing in
            if !showing {
                isReorderingLists = false
                isEditingSheetLists = false
                isAddingListInSheet = false
                newSheetListName = ""
                editingSheetListID = nil
                editingSheetListName = ""
                draggingListID = nil
                dragOffset = 0
                listSheetDetent = .medium
            }
        }
    }

    // MARK: - List Mode Rows (single-select + actions)

    @ViewBuilder
    private var listSwitcherListRows: some View {
        ForEach(CityListID.allLists) { listID in
            Button {
                showingListSwitcher = false
                guard listID != weatherService.activeListID else { return }
                mapHasInitialized = false
                recenterOnAllCities = false
                withAnimation(.easeOut(duration: 0.15)) {
                    listContentOpacity = 0
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    await weatherService.switchList(to: listID)
                    withAnimation(.easeIn(duration: 0.2)) {
                        listContentOpacity = 1
                    }
                    recenterOnAllCities = true
                }
            } label: {
                HStack(spacing: 14) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.avenir(.body, weight: listID == weatherService.activeListID ? .semibold : .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    if listID == weatherService.activeListID {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: 0x1579C7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(listID == weatherService.activeListID ? Color(hex: 0x1579C7).opacity(0.08) : theme.colors.listCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(listID == weatherService.activeListID ? Color(hex: 0x1579C7).opacity(0.4) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Map Mode Rows (multi-select checkmarks)

    @ViewBuilder
    private var listSwitcherMapRows: some View {
        ForEach(CityListID.allLists) { listID in
            let isSelected = mapVisibleListIDs.contains(listID.rawValue)
            Button {
                listSwitcherToggleMapList(listID)
            } label: {
                HStack(spacing: 14) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.avenir(.body, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isSelected ? Color(hex: 0x1579C7) : .secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color(hex: 0x1579C7).opacity(0.08) : theme.colors.listCardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color(hex: 0x1579C7).opacity(0.4) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - New List View

    private var listSwitcherNewListView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Text(localizedString("New List", locale: locale))
                    .font(.avenir(.title2, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                TextField(localizedString("List Name", locale: locale), text: $newSheetListName)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.colors.listCardFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(hex: 0x1579C7).opacity(0.4), lineWidth: 1)
                    )
                    .focused($newListNameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitNewListInSheet() }

                Button {
                    commitNewListInSheet()
                } label: {
                    Text(localizedString("Create", locale: locale))
                        .font(.avenir(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: 0x1579C7), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .opacity(newSheetListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .disabled(newSheetListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
    }

    private func commitNewListInSheet() {
        let name = newSheetListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task {
            await weatherService.addNewList(name: name)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isAddingListInSheet = false
                listSheetDetent = .medium
            }
        }
    }

    // MARK: - Editing View

    private var listSwitcherEditingView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(reorderableLists.enumerated()), id: \.element.id) { index, listID in
                        HStack(spacing: 12) {
                            // Delete button
                            if reorderableLists.count > 1 {
                                Button {
                                    deleteSheetList(listID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 20))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, theme.colors.destructive)
                                }
                                .buttonStyle(.plain)
                            }

                            // Name — tappable to rename
                            if editingSheetListID?.rawValue == listID.rawValue {
                                TextField("", text: $editingSheetListName)
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(theme.colors.primaryText)
                                    .submitLabel(.done)
                                    .focused($editListNameFocused)
                                    .onSubmit {
                                        commitSheetListRename(listID)
                                    }
                            } else {
                                Button {
                                    // Commit previous rename if any
                                    if let prev = editingSheetListID {
                                        commitSheetListRename(prev)
                                    }
                                    editingSheetListID = listID
                                    editingSheetListName = listID.localizedDisplayName(locale: locale)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        editListNameFocused = true
                                    }
                                } label: {
                                    Text(listID.localizedDisplayName(locale: locale))
                                        .font(.avenir(.body, weight: .medium))
                                        .foregroundStyle(theme.colors.primaryText)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            // Move up/down buttons
                            HStack(spacing: 4) {
                                Button {
                                    guard index > 0 else { return }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        reorderableLists.swapAt(index, index - 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(index > 0 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.2))
                                        .frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(index == 0)

                                Button {
                                    guard index < reorderableLists.count - 1 else { return }
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        reorderableLists.swapAt(index, index + 1)
                                    }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(index < reorderableLists.count - 1 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.2))
                                        .frame(width: 30, height: 30)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(index == reorderableLists.count - 1)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(editingSheetListID?.rawValue == listID.rawValue ? Color(hex: 0x1579C7).opacity(0.08) : theme.colors.listCardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(editingSheetListID?.rawValue == listID.rawValue ? Color(hex: 0x1579C7).opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            // Done button
            HStack {
                Spacer()
                Button {
                    // Commit any in-progress rename
                    if let editingID = editingSheetListID {
                        commitSheetListRename(editingID)
                    }
                    CityListID.saveListOrder(reorderableLists)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEditingSheetLists = false
                    }
                } label: {
                    Text(localizedString("Done", locale: locale))
                        .font(.avenir(.body, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1579C7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Sheet List Helpers

    private func commitSheetListRename(_ listID: CityListID) {
        let name = editingSheetListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            editingSheetListID = nil
            editingSheetListName = ""
            return
        }

        let renamed = CityListID(rawValue: listID.rawValue, displayName: name)

        // Update user lists in UserDefaults
        var userLists = CityListID.loadUserLists()
        if let index = userLists.firstIndex(where: { $0.rawValue == listID.rawValue }) {
            userLists[index] = renamed
            CityListID.saveUserLists(userLists)
        }

        // Update reorderableLists
        if let index = reorderableLists.firstIndex(where: { $0.rawValue == listID.rawValue }) {
            reorderableLists[index] = renamed
        }

        // If this was the active list, update it
        if weatherService.activeListID.rawValue == listID.rawValue {
            weatherService.activeListID = renamed
        }

        editingSheetListID = nil
        editingSheetListName = ""
    }

    private func deleteSheetList(_ listID: CityListID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            reorderableLists.removeAll { $0.rawValue == listID.rawValue }
        }
        // Persist deletion
        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.deleteBuiltInList(listID)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listID.rawValue }
            CityListID.saveUserLists(userLists)
        }
        // Clean up stored data
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        // If we deleted the active list, switch to the first remaining
        if listID.rawValue == weatherService.activeListID.rawValue,
           let first = reorderableLists.first {
            Task {
                await weatherService.switchList(to: first)
            }
        }
    }

    // MARK: - Map List Toggle Helper

    private func listSwitcherToggleMapList(_ listID: CityListID) {
        let id = listID.rawValue
        if mapVisibleListIDs.contains(id) {
            guard mapVisibleListIDs.count > 1 else { return }
            mapVisibleListIDs.remove(id)
            if listID == weatherService.activeListID,
               let remainingID = mapVisibleListIDs.first,
               let newActiveList = CityListID.allLists.first(where: { $0.rawValue == remainingID }) {
                Task {
                    await weatherService.switchList(to: newActiveList)
                    recenterOnAllCities = true
                }
            } else {
                recenterOnAllCities = true
            }
        } else {
            mapVisibleListIDs.insert(id)
            if listID != weatherService.activeListID {
                Task {
                    isLoadingMapList = true
                    await weatherService.fetchWeatherForList(listID)
                    isLoadingMapList = false
                    recenterOnAllCities = true
                }
            } else {
                recenterOnAllCities = true
            }
        }
    }
}
