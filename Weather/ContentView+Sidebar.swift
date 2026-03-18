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
        NavigationStack {
            VStack(spacing: 0) {
                if isReorderingLists {
                    listSwitcherReorderContent
                } else if selectedTab == 1 {
                    listSwitcherMapContent
                } else {
                    listSwitcherListContent
                }
            }
            .navigationTitle(localizedString("Lists", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizedString("Done", locale: locale)) {
                        showingListSwitcher = false
                    }
                    .font(.avenir(.body, weight: .medium))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: showingListSwitcher) { _, showing in
            if !showing {
                isReorderingLists = false
                draggingListID = nil
                dragOffset = 0
            }
        }
    }

    // MARK: - List Mode Content (single-select + actions)

    private var listSwitcherListContent: some View {
        List {
            Section {
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
                        HStack(spacing: 12) {
                            Text(listID.localizedDisplayName(locale: locale))
                                .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            if listID == weatherService.activeListID {
                                Circle()
                                    .fill(theme.colors.accent)
                                    .frame(width: 6, height: 6)
                                    .frame(width: 13)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                // Add Custom List
                Button {
                    showingListSwitcher = false
                    startAddingNewList()
                } label: {
                    Label(localizedString("Add Custom List", locale: locale), systemImage: "plus")
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Add Country
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
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Rename List
                Button {
                    showingListSwitcher = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        startEditingListName()
                    }
                } label: {
                    Label(localizedString("Rename List", locale: locale), systemImage: "pencil")
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Reorder Lists
                Button {
                    reorderableLists = CityListID.allLists
                    isReorderingLists = true
                } label: {
                    Label(localizedString("Reorder Lists", locale: locale), systemImage: "arrow.up.arrow.down")
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Delete List
                if CityListID.allLists.count > 1 {
                    Button {
                        showingListSwitcher = false
                        showingDeleteListConfirmation = true
                    } label: {
                        Label(localizedString("Delete List", locale: locale), systemImage: "trash")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(theme.colors.destructive)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Map Mode Content (multi-select checkmarks)

    private var listSwitcherMapContent: some View {
        List {
            Section {
                ForEach(CityListID.allLists) { listID in
                    Button {
                        listSwitcherToggleMapList(listID)
                    } label: {
                        HStack(spacing: 12) {
                            Text(listID.localizedDisplayName(locale: locale))
                                .font(.avenir(.body, weight: mapVisibleListIDs.contains(listID.rawValue) ? .bold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: mapVisibleListIDs.contains(listID.rawValue) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(mapVisibleListIDs.contains(listID.rawValue) ? theme.colors.dotRain : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                // Add Custom List
                Button {
                    showingListSwitcher = false
                    startAddingNewList()
                } label: {
                    Label(localizedString("Add Custom List", locale: locale), systemImage: "plus")
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Add Country
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
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)

                // Reorder Lists
                Button {
                    reorderableLists = CityListID.allLists
                    isReorderingLists = true
                } label: {
                    Label(localizedString("Reorder Lists", locale: locale), systemImage: "arrow.up.arrow.down")
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Reorder Mode Content

    private var listSwitcherReorderContent: some View {
        VStack(spacing: 0) {
            List {
                ForEach(reorderableLists) { listID in
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    reorderableLists.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))

            Button {
                CityListID.saveListOrder(reorderableLists)
                isReorderingLists = false
            } label: {
                Text(localizedString("Done", locale: locale))
                    .font(.avenir(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(theme.colors.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
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
