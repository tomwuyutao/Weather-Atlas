//
//  ContentView+ListManager.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    var listManagerNavigation: some View {
        NavigationStack {
            ZStack {
                theme.colors.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 8) {
                    if sidebarAddingList {
                        listManagerNewListRow
                    }

                    ForEach(CityListID.allLists) { listID in
                        sidebarListRow(for: listID)
                    }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
                }
                .onAppear {
                    if sidebarExpandedListIDs.isEmpty {
                        sidebarExpandedListIDs = Set(CityListID.allLists.map(\.rawValue))
                    }
                }
            }
            .navigationTitle(localizedString("Lists", locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        commitListManagerRenames()
                        showingMapSidebar = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            sidebarAddingList = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sidebarNewListFocused = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #else
                ToolbarItem {
                    Button {
                        commitListManagerRenames()
                        showingMapSidebar = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            sidebarAddingList = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            sidebarNewListFocused = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                #endif
            }
            #if os(iOS)
            .toolbarBackground(theme.colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
    }

    private var listManagerNewListRow: some View {
        HStack(spacing: 8) {
            TextField(localizedString("New List", locale: locale), text: $sidebarNewListName)
                .textFieldStyle(.plain)
                .focused($sidebarNewListFocused)
                .submitLabel(.done)
                .onSubmit { commitListManagerNewList() }

            Button {
                commitListManagerNewList()
            } label: {
                Image(systemName: "checkmark.circle.fill")
            }
            .buttonStyle(.plain)

            Button {
                sidebarAddingList = false
                sidebarNewListName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func listManagerListRow(for listID: CityListID) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if listManagerIsEditing {
                TextField(
                    localizedString("List Name", locale: locale),
                    text: Binding(
                        get: { listRenameDrafts[listID.rawValue] ?? listID.localizedDisplayName(locale: locale) },
                        set: { listRenameDrafts[listID.rawValue] = $0 }
                    )
                )
                .submitLabel(.done)
                .onSubmit {
                    commitListManagerRename(listID)
                }
            } else {
                Text(listID.localizedDisplayName(locale: locale))
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Menu {
                listActions(for: listID)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .frame(width: 38, height: 36)
            }
            .menuOrder(.fixed)

            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    if sidebarExpandedListIDs.contains(listID.rawValue) {
                        sidebarExpandedListIDs.remove(listID.rawValue)
                    } else {
                        sidebarExpandedListIDs.insert(listID.rawValue)
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .rotationEffect(.degrees(sidebarExpandedListIDs.contains(listID.rawValue) ? 0 : -90))
                    .frame(width: 28, height: 36)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.top, 26)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !listManagerIsEditing else { return }
            Task {
                await switchToList(listID)
                showingMapSidebar = false
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                beginRenamingList(listID)
            } label: {
                Label(localizedString("Rename", locale: locale), systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                Task { await weatherService.deleteList(listID) }
            } label: {
                Label(localizedString("Delete", locale: locale), systemImage: "trash")
            }
        }
        .contextMenu {
            listActions(for: listID)
        }
    }

    private func listManagerCityRow(_ city: CityWeather, in listID: CityListID) -> some View {
        Text(city.city.localizedName(locale: locale))
            .font(.title3)
            .foregroundStyle(theme.colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                revealCityOnMap(city, in: listID)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    beginRenamingCity(city, in: listID)
                } label: {
                    Label(localizedString("Rename", locale: locale), systemImage: "pencil")
                }
                .tint(.blue)

                Button(role: .destructive) {
                    weatherService.removeCity(city, from: listID)
                } label: {
                    Label(localizedString("Delete", locale: locale), systemImage: "trash")
                }
            }
            .contextMenu {
                cityActions(for: city, in: listID)
            }
    }

    @ViewBuilder
    func listActions(for listID: CityListID) -> some View {
        Button {
            Task {
                await switchToList(listID)
                showingMapSidebar = false
            }
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginRenamingList(listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button {
            beginAddingCity(to: listID)
        } label: {
            Label(localizedString("Add City", locale: locale), systemImage: "plus")
        }

        Button(role: .destructive) {
            Task {
                await weatherService.deleteList(listID)
            }
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            revealCityOnMap(city, in: listID)
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginRenamingCity(city, in: listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button(role: .destructive) {
            weatherService.removeCity(city, from: listID)
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    private func beginRenamingList(_ listID: CityListID) {
        listToRenameID = listID
        renameAlertText = listID.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    private func beginRenamingCity(_ city: CityWeather, in listID: CityListID) {
        cityToRename = city
        cityToRenameListID = listID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    private func beginAddingCity(to listID: CityListID) {
        inlineAddTargetListID = listID
        showingMapSidebar = false
        inlineSearchText = ""
        activateInlineSearch()
    }

    func createListAtBottom() {
        let newList = CityListID.createList(name: localizedString("New List", locale: locale))
        sidebarExpandedListIDs.insert(newList.rawValue)
        listToRenameID = newList
        renameAlertText = newList.localizedDisplayName(locale: locale)
        showingRenameAlert = true
    }

    func revealCityOnMap(_ city: CityWeather, in listID: CityListID) {
        Task {
            await switchToList(listID)
            let revealedCity = weatherService.cityWeatherData.first {
                $0.city.latitude == city.city.latitude && $0.city.longitude == city.city.longitude
            } ?? city
            showingMapSidebar = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                showingMapExpandedCard = false
                tappedCity = nil
            }
            centerOnCityTrigger = revealedCity
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                showMapMarkerCard(revealedCity, expanded: false, focusesMarker: true)
            }
        }
    }

    func commitListManagerNewList() {
        let trimmed = sidebarNewListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newList = CityListID.createList(name: trimmed)
        sidebarExpandedListIDs.insert(newList.rawValue)
        sidebarNewListName = ""
        sidebarAddingList = false
    }

    private func commitListManagerRename(_ listID: CityListID) {
        guard let draft = listRenameDrafts[listID.rawValue] else { return }
        weatherService.renameList(listID, to: draft)
        listRenameDrafts[listID.rawValue] = nil
    }

    private func commitListManagerRenames() {
        for listID in CityListID.allLists {
            commitListManagerRename(listID)
        }
    }

    private func removeCities(at offsets: IndexSet, from listID: CityListID) {
        let cities = weatherService.weatherData(for: listID)
        for city in offsets.map({ cities[$0] }) {
            weatherService.removeCity(city, from: listID)
        }
    }

    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        recenterOnAllCities = true
    }

    @ViewBuilder
    var mapSidebarOverlay: some View {
        if showingMapSidebar {
            ZStack(alignment: .leading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showingMapSidebar = false
                        }
                    }

                mapSidebar
                    .frame(width: 310)
                    .padding(.top, 54)
                    .padding(.bottom, 86)
                    .padding(.leading, 12)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .zIndex(30)
        }
    }

    private var mapSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizedString("Lists", locale: locale))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        sidebarAddingList = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        sidebarNewListFocused = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        sidebarEditing.toggle()
                        sidebarRenamingListID = nil
                    }
                } label: {
                    Image(systemName: sidebarEditing ? "checkmark" : "pencil")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if sidebarAddingList {
                HStack(spacing: 8) {
                    TextField(localizedString("New List", locale: locale), text: $sidebarNewListName)
                        .textFieldStyle(.plain)
                        .focused($sidebarNewListFocused)
                        .submitLabel(.done)
                        .onSubmit { commitSidebarNewList() }
                    Button {
                        commitSidebarNewList()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Button {
                        sidebarAddingList = false
                        sidebarNewListName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 10)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(CityListID.allLists) { listID in
                        sidebarListRow(for: listID)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .themedGlass(in: .rect(cornerRadius: 24))
    }

    private func sidebarListRow(for listID: CityListID) -> some View {
        let isActive = weatherService.activeListID.rawValue == listID.rawValue
        let isExpanded = sidebarExpandedListIDs.contains(listID.rawValue)
        let cities = weatherService.weatherData(for: listID)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if isExpanded {
                            sidebarExpandedListIDs.remove(listID.rawValue)
                        } else {
                            sidebarExpandedListIDs.insert(listID.rawValue)
                            Task { await weatherService.fetchWeatherForList(listID) }
                        }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)

                if sidebarRenamingListID?.rawValue == listID.rawValue {
                    TextField("", text: $sidebarRenameText)
                        .textFieldStyle(.plain)
                        .focused($sidebarRenameFocused)
                        .submitLabel(.done)
                        .onSubmit { commitSidebarRename(listID) }
                } else {
                    Button {
                        Task {
                            await weatherService.switchList(to: listID)
                            recenterOnAllCities = true
                        }
                    } label: {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.body.weight(isActive ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if sidebarEditing {
                    sidebarListEditingControls(for: listID)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isActive ? Color.primary.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 14))

            if isExpanded {
                VStack(spacing: 4) {
                    if cities.isEmpty {
                        Text(localizedString("No cities", locale: locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 38)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(Array(cities.enumerated()), id: \.element.id) { index, city in
                            sidebarCityRow(city, at: index, in: listID, cities: cities)
                        }
                    }
                }
            }
        }
    }

    private func sidebarListEditingControls(for listID: CityListID) -> some View {
        HStack(spacing: 8) {
            Button {
                sidebarRenamingListID = listID
                sidebarRenameText = listID.localizedDisplayName(locale: locale)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    sidebarRenameFocused = true
                }
            } label: {
                Image(systemName: "pencil")
            }
            .disabled(CityListID.builtInLists.contains(where: { $0.rawValue == listID.rawValue }))

            Button {
                weatherService.moveList(listID, direction: .up)
            } label: {
                Image(systemName: "chevron.up")
            }

            Button {
                weatherService.moveList(listID, direction: .down)
            } label: {
                Image(systemName: "chevron.down")
            }

            Button(role: .destructive) {
                Task { await weatherService.deleteList(listID) }
            } label: {
                Image(systemName: "trash")
            }
        }
        .font(.caption.weight(.semibold))
    }

    private func sidebarCityRow(_ city: CityWeather, at index: Int, in listID: CityListID, cities: [CityWeather]) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    if weatherService.activeListID.rawValue != listID.rawValue {
                        await weatherService.switchList(to: listID)
                    }
                    selectedTab = 1
                    tappedCity = city
                    centerOnCityTrigger = city
                    showingMapExpandedCard = true
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingMapSidebar = false
                    }
                }
            } label: {
                Text(city.city.localizedName(locale: locale))
                    .font(.subheadline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if sidebarEditing {
                Button {
                    if index > 0 {
                        weatherService.moveCity(in: listID, from: IndexSet(integer: index), to: index - 1)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(index == 0)

                Button {
                    if index < cities.count - 1 {
                        weatherService.moveCity(in: listID, from: IndexSet(integer: index), to: index + 2)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(index >= cities.count - 1)

                Button(role: .destructive) {
                    weatherService.removeCity(city, from: listID)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
            }
        }
        .font(.caption)
        .padding(.leading, 38)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
    }

    private func commitSidebarNewList() {
        let name = sidebarNewListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            await weatherService.addNewList(name: name)
            sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            sidebarNewListName = ""
            sidebarAddingList = false
            recenterOnAllCities = true
        }
    }

    private func commitSidebarRename(_ listID: CityListID) {
        weatherService.renameList(listID, to: sidebarRenameText)
        sidebarRenamingListID = nil
        sidebarRenameText = ""
    }


}
