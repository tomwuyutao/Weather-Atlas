//
//  ContentView+Sidebar.swift
//  Weather
//
//  Slide-from-left sidebar for list switching (single-select in list view,
//  multi-select in map view). Pushes main content to the right.
//

import SwiftUI

extension ContentView {

    // MARK: - Sidebar Container

    /// Wraps the main content in an offset layout so the sidebar pushes it right.
    func withListSidebar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let mainContent = content()
        return GeometryReader { geo in
            let sidebarW = geo.size.width * 0.80
            ZStack(alignment: .leading) {
                // Main content — offset to the right when sidebar is open
                mainContent
                    .frame(width: geo.size.width, height: geo.size.height)
                    .offset(x: showingListSidebar ? sidebarW : 0)
                    .disabled(showingListSidebar)

                // Dimmed tap area over main content when sidebar is open
                if showingListSidebar {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .offset(x: sidebarW)
                        .onTapGesture {
                            closeSidebar()
                        }
                }

                // Sidebar panel
                sidebarPanel
                    .frame(width: sidebarW)
                    .offset(x: showingListSidebar ? 0 : -sidebarW)
                    .gesture(sidebarDismissGesture)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showingListSidebar)
        }
    }

    // MARK: - Dismiss Gesture (swipe left)

    private var sidebarDismissGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -60 {
                    closeSidebar()
                }
            }
    }

    func closeSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingListSidebar = false
        }
    }

    // MARK: - Sidebar Panel

    private var sidebarPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text(localizedString("Lists", locale: locale))
                .font(.avenir(.title2, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 16)

            // List content — drag to reorder
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarListContent
                }
                .padding(.top, 4)
            }

            Divider()
                .padding(.horizontal, 16)

            // Bottom actions
            sidebarActions
                .padding(.top, 8)
                .padding(.bottom, 16)
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

    // MARK: - List Content (with inline drag-to-reorder)

    private var sidebarListContent: some View {
        let isMapMode = selectedTab == 1
        let rowHeight: CGFloat = 40
        return ForEach(Array(sidebarDisplayLists.enumerated()), id: \.element.id) { index, listID in
            sidebarListRow(listID: listID, isMapMode: isMapMode, rowHeight: rowHeight)
        }
    }

    private func sidebarListRow(listID: CityListID, isMapMode: Bool, rowHeight: CGFloat) -> some View {
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
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .scaleEffect(sidebarLongPressedList == listID ? 0.96 : 1.0)
        .opacity(draggingListID == listID ? 0.5 : 1.0)
        .offset(y: draggingListID == listID ? dragOffset : 0)
        .zIndex(draggingListID == listID ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: sidebarLongPressedList?.id)
        .onTapGesture {
            if isMapMode {
                sidebarToggleMapList(listID)
            } else {
                sidebarSelectList(listID)
            }
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .first(true):
                        // Long press recognized — start visual feedback
                        if draggingListID == nil, sidebarLongPressedList == nil {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            draggingListID = listID
                        }
                    case .second(true, let drag):
                        guard draggingListID == listID, let drag = drag else { return }
                        dragOffset = drag.translation.height

                        guard let fromIndex = sidebarDisplayLists.firstIndex(of: listID) else { return }
                        let proposedOffset = Int(round(drag.translation.height / rowHeight))
                        let toIndex = min(max(fromIndex + proposedOffset, 0), sidebarDisplayLists.count - 1)
                        if toIndex != fromIndex {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                sidebarDisplayLists.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                            }
                            let moved = toIndex - fromIndex
                            dragOffset -= CGFloat(moved) * rowHeight
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    if draggingListID != nil {
                        CityListID.saveListOrder(sidebarDisplayLists)
                    }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        dragOffset = 0
                        draggingListID = nil
                    }
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Only show context menu if not dragging
                    if draggingListID == nil || (draggingListID == listID && abs(dragOffset) < 5) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            dragOffset = 0
                            draggingListID = nil
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        sidebarLongPressedList = listID
                    }
                }
        )
        .popover(isPresented: Binding(
            get: { sidebarLongPressedList == listID },
            set: { if !$0 { sidebarLongPressedList = nil } }
        )) {
            sidebarContextMenu(for: listID)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Context Menu (Long Press)

    private func sidebarContextMenu(for listID: CityListID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                sidebarLongPressedList = nil
                closeSidebar()
                // Small delay so popover dismisses first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    editingListName = listID.localizedDisplayName(locale: locale)
                    // Switch to the list first if not active
                    if listID != weatherService.activeListID {
                        Task {
                            await weatherService.switchList(to: listID)
                            isEditingListName = true
                        }
                    } else {
                        isEditingListName = true
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .frame(width: 20, alignment: .center)
                        .foregroundStyle(.secondary)
                    Text(localizedString("Rename", locale: locale))
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 12).padding(.vertical, 4)

            Button {
                sidebarLongPressedList = nil
                closeSidebar()
                // Switch to the list first if needed, then trigger delete
                if listID != weatherService.activeListID {
                    Task {
                        await weatherService.switchList(to: listID)
                        showingDeleteListConfirmation = true
                    }
                } else {
                    showingDeleteListConfirmation = true
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .frame(width: 20, alignment: .center)
                        .foregroundStyle(theme.colors.destructive)
                    Text(localizedString("Delete", locale: locale))
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(theme.colors.destructive)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(width: 180)
        .themedPopoverBackground()
    }

    // MARK: - Bottom Actions

    private var sidebarActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarActionRow(icon: "plus", title: localizedString("Add Custom List", locale: locale)) {
                closeSidebar()
                startAddingNewList()
            }

            sidebarActionRow(icon: "globe", title: localizedString("Add Country", locale: locale)) {
                closeSidebar()
                if isIPad {
                    showingCountrySearch = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingCountrySearch = true
                    }
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
        closeSidebar()
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
