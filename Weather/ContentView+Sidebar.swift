//
//  ContentView+Sidebar.swift
//  Weather
//
//  Slide-from-left sidebar for list switching (single-select in list view,
//  multi-select in map view). Replaces the old popover-based list switcher.
//

import SwiftUI

extension ContentView {

    // MARK: - Sidebar Overlay

    /// Full-screen overlay with dimmed background + slide-in sidebar.
    /// `isMapMode` controls single-select vs multi-select behavior.
    var listSidebarOverlay: some View {
        ZStack(alignment: .leading) {
            // Dimmed background — tap to dismiss
            Color.black.opacity(showingListSidebar ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingListSidebar = false
                        isReorderingLists = false
                    }
                }
                .allowsHitTesting(showingListSidebar)

            // Sidebar panel
            sidebarPanel
                .frame(width: UIScreen.main.bounds.width * 0.80)
                .offset(x: showingListSidebar ? 0 : -(UIScreen.main.bounds.width * 0.80))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingListSidebar)
    }

    // MARK: - Sidebar Panel

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(localizedString("Lists", locale: locale))
                    .font(.avenir(.title2, weight: .bold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingListSidebar = false
                        isReorderingLists = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(theme.colors.glassFill, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 16)

            // List content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isReorderingLists {
                        sidebarReorderContent
                    } else {
                        sidebarListContent
                    }
                }
                .padding(.top, 8)
            }

            Divider()
                .padding(.horizontal, 16)

            // Bottom actions
            if !isReorderingLists {
                sidebarActions
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .background {
            Rectangle()
                .fill(theme.colors.background)
                .overlay {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
                .ignoresSafeArea()
        }
    }

    // MARK: - List Content (Normal Mode)

    private var sidebarListContent: some View {
        let isMapMode = selectedTab == 1
        return ForEach(CityListID.allLists) { listID in
            Button {
                if isMapMode {
                    sidebarToggleMapList(listID)
                } else {
                    sidebarSelectList(listID)
                }
            } label: {
                HStack(spacing: 12) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.avenir(.body, weight: sidebarIsActive(listID) ? .bold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    if isMapMode {
                        Image(systemName: mapVisibleListIDs.contains(listID.rawValue) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundStyle(mapVisibleListIDs.contains(listID.rawValue) ? theme.colors.dotRain : .secondary)
                    } else if listID == weatherService.activeListID {
                        Circle()
                            .fill(theme.colors.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Reorder Content

    private var sidebarReorderContent: some View {
        let rowHeight: CGFloat = 48
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(reorderableLists.enumerated()), id: \.element.id) { index, listID in
                HStack(spacing: 12) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
                .opacity(draggingListID == listID ? 0.5 : 1.0)
                .offset(y: draggingListID == listID ? dragOffset : 0)
                .zIndex(draggingListID == listID ? 1 : 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if draggingListID == nil {
                                draggingListID = listID
                            }
                            guard draggingListID == listID else { return }
                            dragOffset = value.translation.height

                            guard let fromIndex = reorderableLists.firstIndex(of: listID) else { return }
                            let proposedOffset = Int(round(value.translation.height / rowHeight))
                            let toIndex = min(max(fromIndex + proposedOffset, 0), reorderableLists.count - 1)
                            if toIndex != fromIndex {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    reorderableLists.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                }
                                let moved = toIndex - fromIndex
                                dragOffset -= CGFloat(moved) * rowHeight
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                dragOffset = 0
                                draggingListID = nil
                            }
                        }
                )
            }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Button {
                CityListID.saveListOrder(reorderableLists)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isReorderingLists = false
                }
            } label: {
                HStack(spacing: 12) {
                    Text(localizedString("Done", locale: locale))
                        .font(.avenir(.body, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.accent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Bottom Actions

    private var sidebarActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarActionRow(icon: "plus", title: localizedString("Add Custom List", locale: locale)) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showingListSidebar = false
                }
                startAddingNewList()
            }

            sidebarActionRow(icon: "globe", title: localizedString("Add Country", locale: locale)) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showingListSidebar = false
                }
                if isIPad {
                    showingCountrySearch = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingCountrySearch = true
                    }
                }
            }

            // Only show list management actions when not in map mode
            if selectedTab == 0 {
                sidebarActionRow(icon: "pencil", title: localizedString("Rename List", locale: locale)) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingListSidebar = false
                    }
                    startEditingListName()
                }

                sidebarActionRow(icon: "arrow.up.arrow.down", title: localizedString("Reorder Lists", locale: locale)) {
                    reorderableLists = CityListID.allLists
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isReorderingLists = true
                    }
                }

                sidebarActionRow(icon: "trash", title: localizedString("Delete List", locale: locale), isDestructive: true) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingListSidebar = false
                    }
                    showingDeleteListConfirmation = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func sidebarActionRow(icon: String, title: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isDestructive ? theme.colors.destructive : .secondary)
                Text(title)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(isDestructive ? theme.colors.destructive : .primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarIsActive(_ listID: CityListID) -> Bool {
        if selectedTab == 1 {
            return mapVisibleListIDs.contains(listID.rawValue)
        } else {
            return listID == weatherService.activeListID
        }
    }

    private func sidebarSelectList(_ listID: CityListID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingListSidebar = false
        }
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
    }

    private func sidebarToggleMapList(_ listID: CityListID) {
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
