//
//  ListSwitcherSheet.swift
//  Weather
//
//  List switcher sheet: shows all lists with multi-select checkmarks,
//  plus management actions (add, rename, reorder, delete).
//

import SwiftUI

struct ListSwitcherSheet: View {
    var weatherService: WeatherService
    @Binding var visibleListIDs: Set<String>
    @Binding var isPresented: Bool
    var onRecenter: () -> Void
    var onShowCountrySearch: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    @State private var isEditing: Bool = false
    @State private var isAddingList: Bool = false
    @State private var newListName: String = ""
    @State private var editingListID: CityListID? = nil
    @State private var editingListName: String = ""
    @State private var reorderableLists: [CityListID] = []
    @State private var isLoadingList: Bool = false

    @FocusState private var newListNameFocused: Bool
    @FocusState private var editListNameFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — X button
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
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
                .padding(.top, 12)

                if isEditing {
                    editingView
                } else {
                    selectionView
                    bottomBar
                }
            }
        }

    }

    // MARK: - Selection View (multi-select rows)

    private var selectionView: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(CityListID.allLists) { listID in
                    let isSelected = visibleListIDs.contains(listID.rawValue)
                    Button {
                        toggleList(listID)
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

                // Inline new list row (non-editing mode)
                if isAddingList {
                    HStack(spacing: 12) {
                        TextField(localizedString("New List", locale: locale), text: $newListName)
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(theme.colors.primaryText)
                            .submitLabel(.done)
                            .focused($newListNameFocused)
                            .onSubmit { commitNewList() }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(theme.colors.listCardFill)
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Bottom Bar (non-editing mode)

    private var bottomBar: some View {
        HStack {
            // Add button — context menu
            Menu {
                Button {
                    newListName = ""
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isAddingList = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        newListNameFocused = true
                    }
                } label: {
                    Label(localizedString("Add Custom List", locale: locale), systemImage: "plus")
                }
                Button {
                    isPresented = false
                    onShowCountrySearch()
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

            if isAddingList {
                // Cancel add — dismiss keyboard
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isAddingList = false
                        newListName = ""
                        newListNameFocused = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)
            } else {
                // Edit button
                Button {
                    reorderableLists = CityListID.allLists
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEditing = true
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(reorderableLists) { listID in
                        HStack(spacing: 12) {
                            // Delete button
                            if reorderableLists.count > 1 {
                                Button {
                                    deleteList(listID)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 20))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, theme.colors.destructive)
                                }
                                .buttonStyle(.plain)
                            }

                            // Name — tappable to rename
                            if editingListID?.rawValue == listID.rawValue {
                                TextField("", text: $editingListName)
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(theme.colors.primaryText)
                                    .submitLabel(.done)
                                    .focused($editListNameFocused)
                                    .onSubmit {
                                        commitRename(listID)
                                    }
                            } else {
                                Button {
                                    if let prev = editingListID {
                                        commitRename(prev)
                                    }
                                    editingListID = listID
                                    editingListName = listID.localizedDisplayName(locale: locale)
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

                            // Reorder arrows
                            VStack(spacing: 4) {
                                Button {
                                    moveList(listID, direction: .up)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(reorderableLists.first?.rawValue == listID.rawValue ? theme.colors.primaryText.opacity(0.15) : theme.colors.primaryText.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                                .disabled(reorderableLists.first?.rawValue == listID.rawValue)

                                Button {
                                    moveList(listID, direction: .down)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(reorderableLists.last?.rawValue == listID.rawValue ? theme.colors.primaryText.opacity(0.15) : theme.colors.primaryText.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                                .disabled(reorderableLists.last?.rawValue == listID.rawValue)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(editingListID?.rawValue == listID.rawValue ? Color(hex: 0x1579C7).opacity(0.08) : theme.colors.listCardFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(editingListID?.rawValue == listID.rawValue ? Color(hex: 0x1579C7).opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }

                    // Inline new list row
                    if isAddingList {
                        HStack(spacing: 12) {
                            TextField(localizedString("New List", locale: locale), text: $newListName)
                                .font(.avenir(.body, weight: .medium))
                                .foregroundStyle(theme.colors.primaryText)
                                .submitLabel(.done)
                                .focused($newListNameFocused)
                                .onSubmit { commitNewList() }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(theme.colors.listCardFill)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            // Bottom bar: + button (left) and done checkmark (right)
            HStack {
                // Add list button
                Button {
                    newListName = ""
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isAddingList = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        newListNameFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                        .themedGlass(in: .circle)
                }
                .buttonStyle(.plain)

                Spacer()

                // Done — blue checkmark circle
                Button {
                    if let editingID = editingListID {
                        commitRename(editingID)
                    }
                    if isAddingList {
                        commitNewList()
                    }
                    CityListID.saveListOrder(reorderableLists)
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isEditing = false
                        isAddingList = false
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(theme.colors.accent, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Toggle List Visibility

    private func toggleList(_ listID: CityListID) {
        let id = listID.rawValue
        if visibleListIDs.contains(id) {
            guard visibleListIDs.count > 1 else { return }
            visibleListIDs.remove(id)
            if listID == weatherService.activeListID,
               let remainingID = visibleListIDs.first,
               let newActiveList = CityListID.allLists.first(where: { $0.rawValue == remainingID }) {
                Task {
                    await weatherService.switchList(to: newActiveList)
                    onRecenter()
                }
            } else {
                onRecenter()
            }
        } else {
            visibleListIDs.insert(id)
            if listID != weatherService.activeListID {
                Task {
                    isLoadingList = true
                    await weatherService.fetchWeatherForList(listID)
                    isLoadingList = false
                    onRecenter()
                }
            } else {
                onRecenter()
            }
        }
    }

    // MARK: - Helpers

    private enum MoveDirection { case up, down }

    private func moveList(_ listID: CityListID, direction: MoveDirection) {
        guard let index = reorderableLists.firstIndex(where: { $0.rawValue == listID.rawValue }) else { return }
        let newIndex = direction == .up ? index - 1 : index + 1
        guard reorderableLists.indices.contains(newIndex) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            reorderableLists.swapAt(index, newIndex)
        }
    }

    private func commitRename(_ listID: CityListID) {
        let name = editingListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            editingListID = nil
            editingListName = ""
            return
        }

        let renamed = CityListID(rawValue: listID.rawValue, displayName: name)

        var userLists = CityListID.loadUserLists()
        if let index = userLists.firstIndex(where: { $0.rawValue == listID.rawValue }) {
            userLists[index] = renamed
            CityListID.saveUserLists(userLists)
        }

        if let index = reorderableLists.firstIndex(where: { $0.rawValue == listID.rawValue }) {
            reorderableLists[index] = renamed
        }

        if weatherService.activeListID.rawValue == listID.rawValue {
            weatherService.activeListID = renamed
        }

        editingListID = nil
        editingListName = ""
    }

    private func deleteList(_ listID: CityListID) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            reorderableLists.removeAll { $0.rawValue == listID.rawValue }
        }
        if CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }) {
            CityListID.deleteBuiltInList(listID)
        } else {
            var userLists = CityListID.loadUserLists()
            userLists.removeAll { $0.rawValue == listID.rawValue }
            CityListID.saveUserLists(userLists)
        }
        UserDefaults.standard.removeObject(forKey: "savedCitiesList_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "cachedWeatherData_\(listID.rawValue)")
        UserDefaults.standard.removeObject(forKey: "weatherCacheTimestamp_\(listID.rawValue)")
        // Also remove from visible lists
        visibleListIDs.remove(listID.rawValue)
        if listID.rawValue == weatherService.activeListID.rawValue,
           let first = reorderableLists.first {
            Task {
                await weatherService.switchList(to: first)
            }
        }
    }

    private func commitNewList() {
        let name = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            isAddingList = false
            newListName = ""
            return
        }
        let newList = CityListID.createList(name: name)
        reorderableLists.append(newList)
        isAddingList = false
        newListName = ""
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var showing = true
    @Previewable @State var visibleIDs: Set<String> = ["china"]

    Color.black
        .sheet(isPresented: $showing) {
            ListSwitcherSheet(
                weatherService: WeatherService(),
                visibleListIDs: $visibleIDs,
                isPresented: $showing,
                onRecenter: {},
                onShowCountrySearch: {}
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled()
        }
}
