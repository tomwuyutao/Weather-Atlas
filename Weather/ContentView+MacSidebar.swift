//
//  ContentView+MacSidebar.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

#if os(macOS) || os(iOS)
extension ContentView {

    var macListManagerSidebar: some View {
        List(selection: $macSidebarSelection) {
            #if os(iOS)
            Section {
                macSidebarListRows
            }
            .listRowBackground(theme.colors.mapLand)
            #else
            Section(localizedString("Lists", locale: locale)) {
                macSidebarListRows
            }
            #endif
        }
        .listStyle(.sidebar)
        .tint(theme.colors.accent)
        #if os(iOS)
        .environment(\.editMode, $sidebarEditMode)
        #endif
        .id(macSidebarRefreshTick)
        .onAppear {
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            }
            macSidebarSelection = macSidebarListContextID(weatherService.activeListID)
        }
        .onChange(of: weatherService.activeListID) { _, newListID in
            let selection = macSidebarListContextID(newListID)
            if macSidebarSelection != selection {
                macSidebarSelection = selection
            }
        }
        .onChange(of: macSidebarSelection) { _, newSelection in
            handleMacSidebarSelection(newSelection)
        }
    }

    @ViewBuilder
    private var macSidebarListRows: some View {
        if sidebarAddingList {
            macSidebarNewListRow
        }

        ForEach(CityListID.allLists) { listID in
            macSidebarNativeListFolder(for: listID)
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    @ViewBuilder
    private func macSidebarNativeListFolder(for listID: CityListID) -> some View {
        let cities = weatherService.weatherData(for: listID)
        let isExpanded = sidebarExpandedListIDs.contains(listID.rawValue)

        HStack(spacing: 4) {
            Button {
                macSidebarSetList(listID, expanded: !isExpanded)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 14, height: 18)
            }
            .buttonStyle(.plain)

            if sidebarRenamingListID == listID {
                TextField(localizedString("Name", locale: locale), text: $sidebarRenameText)
                    .textFieldStyle(.plain)
                    .focused($sidebarRenameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitMacSidebarListRename(listID) }
                    .onChange(of: sidebarRenameFocused) { _, focused in
                        if !focused, sidebarRenamingListID == listID {
                            commitMacSidebarListRename(listID)
                        }
                    }
            } else {
                Text(listID.localizedDisplayName(locale: locale))
                    .lineLimit(1)
            }
        }
        .badge(cities.count)
        .tag(macSidebarListContextID(listID))
        .contextMenu {
            macSidebarListActions(for: listID)
        }

        if isExpanded {
            if cities.isEmpty {
                Text(localizedString("No cities", locale: locale))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
                    .tag("empty:\(listID.rawValue)")
            } else {
                ForEach(cities) { city in
                    let contextID = macSidebarCityContextID(city, in: listID)
                    Group {
                        if sidebarRenamingCityContextID == contextID {
                            TextField(localizedString("Name", locale: locale), text: $sidebarRenameText)
                                .textFieldStyle(.plain)
                                .focused($sidebarRenameFocused)
                                .submitLabel(.done)
                                .onSubmit { commitMacSidebarCityRename(city, in: listID) }
                                .onChange(of: sidebarRenameFocused) { _, focused in
                                    if !focused, sidebarRenamingCityContextID == contextID {
                                        commitMacSidebarCityRename(city, in: listID)
                                    }
                                }
                        } else {
                            Text(city.city.localizedName(locale: locale))
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 36)
                    .tag(contextID)
                    .contextMenu {
                        macSidebarCityActions(for: city, in: listID)
                    }
                }
                .onMove { source, destination in
                    moveMacSidebarCities(in: listID, from: source, to: destination)
                }
                .onDelete { offsets in
                    deleteMacSidebarCities(in: listID, at: offsets)
                }
            }
        }
    }

    private func macSidebarSetList(_ listID: CityListID, expanded: Bool) {
        if expanded {
            sidebarExpandedListIDs.insert(listID.rawValue)
            Task { await weatherService.fetchWeatherForList(listID) }
        } else {
            sidebarExpandedListIDs.remove(listID.rawValue)
        }
    }

    private func moveMacSidebarLists(from source: IndexSet, to destination: Int) {
        weatherService.moveLists(from: source, to: destination)
        macSidebarRefreshTick += 1
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarLists(at offsets: IndexSet) {
        let lists = CityListID.allLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            Task { await weatherService.deleteList(lists[index]) }
        }
        macSidebarRefreshTick += 1
        PlatformFeedback.lightImpact()
    }

    private func moveMacSidebarCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        macSidebarRefreshTick += 1
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = weatherService.weatherData(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        macSidebarRefreshTick += 1
        PlatformFeedback.lightImpact()
    }

    @ViewBuilder
    private func macSidebarListActions(for listID: CityListID) -> some View {
        Button {
            Task { await switchToList(listID) }
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginMacSidebarListRename(listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button {
            beginMacSidebarAddingCity(to: listID)
        } label: {
            Label(localizedString("Add City", locale: locale), systemImage: "plus")
        }

        Button(role: .destructive) {
            Task { await weatherService.deleteList(listID) }
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    @ViewBuilder
    private func macSidebarCityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            revealCityOnMap(city, in: listID)
        } label: {
            Label(localizedString("Reveal on Map", locale: locale), systemImage: "map")
        }

        Button {
            beginMacSidebarCityRename(city, in: listID)
        } label: {
            Label(localizedString("Rename", locale: locale), systemImage: "pencil")
        }

        Button(role: .destructive) {
            weatherService.removeCity(city, from: listID)
        } label: {
            Label(localizedString("Delete", locale: locale), systemImage: "trash")
        }
    }

    private func beginMacSidebarAddingCity(to listID: CityListID) {
        inlineAddTargetListID = listID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showingInlineSearch = true
            inlineSearchText = ""
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inlineSearchFocused = true
        }
    }

    private func beginMacSidebarListRename(_ listID: CityListID) {
        sidebarRenamingCityContextID = nil
        sidebarRenamingListID = listID
        sidebarRenameText = listID.localizedDisplayName(locale: locale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sidebarRenameFocused = true
        }
    }

    private func beginMacSidebarCityRename(_ city: CityWeather, in listID: CityListID) {
        sidebarRenamingListID = nil
        sidebarRenamingCityContextID = macSidebarCityContextID(city, in: listID)
        sidebarRenameText = city.city.localizedName(locale: locale)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            sidebarRenameFocused = true
        }
    }

    private func commitMacSidebarListRename(_ listID: CityListID) {
        let trimmed = sidebarRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            weatherService.renameList(listID, to: trimmed)
        }
        sidebarRenamingListID = nil
        sidebarRenameText = ""
        macSidebarRefreshTick += 1
    }

    private func commitMacSidebarCityRename(_ city: CityWeather, in listID: CityListID) {
        let trimmed = sidebarRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            weatherService.renameCity(city, in: listID, to: trimmed)
        }
        sidebarRenamingCityContextID = nil
        sidebarRenameText = ""
        macSidebarRefreshTick += 1
    }

    private func macSidebarListExpansionBinding(for listID: CityListID) -> Binding<Bool> {
        Binding {
            sidebarExpandedListIDs.contains(listID.rawValue)
        } set: { isExpanded in
            if isExpanded {
                sidebarExpandedListIDs.insert(listID.rawValue)
                Task { await weatherService.fetchWeatherForList(listID) }
            } else {
                sidebarExpandedListIDs.remove(listID.rawValue)
            }
        }
    }

    private func handleMacSidebarSelection(_ selection: String?) {
        guard let selection else { return }
        let parts = selection.split(separator: ":").map(String.init)
        guard let kind = parts.first else { return }

        if kind == "list", parts.count == 2,
           let listID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
           listID != weatherService.activeListID {
            Task { await switchToList(listID) }
            return
        }

        if kind == "city", parts.count == 3,
           let listID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
           let city = weatherService.weatherData(for: listID).first(where: { $0.id.uuidString == parts[2] }) {
            revealCityOnMap(city, in: listID)
        }
    }

    private var macSidebarNewListRow: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func macSidebarListSection(for listID: CityListID) -> some View {
        let isExpanded = sidebarExpandedListIDs.contains(listID.rawValue)
        let cities = weatherService.weatherData(for: listID)
        let isActive = listID == weatherService.activeListID
        let contextID = macSidebarListContextID(listID)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Task { await switchToList(listID) }
                } label: {
                    Text(listID.localizedDisplayName(locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isActive ? theme.colors.accent : theme.colors.secondaryText.opacity(0.68))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

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
                    ZStack {
                        Color.clear
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    }
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background {
                ZStack {
                    macSidebarContextOutline(isVisible: macSidebarContextTarget == contextID)
                    macSidebarRightClickReader(contextID)
                }
            }
            .overlay(alignment: .top) {
                if macSidebarDropTarget == contextID {
                    Capsule()
                        .fill(theme.colors.accent)
                        .frame(height: 2)
                        .padding(.horizontal, 12)
                }
            }
            .onDrag {
                macSidebarContextTarget = nil
                return macSidebarItemProvider(payload: macSidebarListDragPayload(listID), type: .weatherSidebarList)
            } preview: {
                Color.clear
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
            }
            .onDrop(
                of: [.weatherSidebarList, .weatherSidebarCity],
                delegate: macSidebarDropDelegate(contextID, acceptedTypes: [.weatherSidebarList, .weatherSidebarCity]) { providers in
                    loadMacSidebarDrop(providers, onList: listID)
                }
            )
            .contextMenu {
                macSidebarContextMenuMarker(contextID)
                listActions(for: listID)
            }

            Rectangle()
                .fill(theme.colors.secondaryText.opacity(0.22))
                .frame(height: 1)
                .padding(.horizontal, 14)

            if isExpanded {
                if cities.isEmpty {
                    Text(localizedString("No cities", locale: locale))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                } else {
                    ForEach(cities) { city in
                        macSidebarCityRow(city, in: listID)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    private func macSidebarCityRow(_ city: CityWeather, in listID: CityListID) -> some View {
        let isActive = listID == weatherService.activeListID
        let contextID = macSidebarCityContextID(city, in: listID)

        return HStack(spacing: 10) {
            Circle()
                .fill(sidebarDotColor(for: city))
                .frame(width: 9, height: 9)
                .shadow(color: sidebarDotColor(for: city).opacity(0.5), radius: 2)

            Text(city.city.localizedName(locale: locale))
                .font(.callout.weight(.medium))
                .foregroundStyle(isActive ? theme.colors.primaryText : theme.colors.secondaryText.opacity(0.72))
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            ZStack {
                macSidebarContextOutline(isVisible: macSidebarContextTarget == contextID)
                macSidebarRightClickReader(contextID)
            }
        }
        .overlay(alignment: .top) {
            if macSidebarDropTarget == contextID {
                Capsule()
                    .fill(theme.colors.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 14)
            }
        }
        .onTapGesture {
            if isActive {
                revealCityOnMap(city, in: listID)
            }
        }
        .onDrag {
            macSidebarContextTarget = nil
            return macSidebarItemProvider(payload: macSidebarCityDragPayload(city, in: listID), type: .weatherSidebarCity)
        } preview: {
            Color.clear
                .frame(width: 1, height: 1)
                .opacity(0.01)
        }
        .onDrop(
            of: [.weatherSidebarCity],
            delegate: macSidebarDropDelegate(contextID, acceptedTypes: [.weatherSidebarCity]) { providers in
                loadMacSidebarDrop(providers, onCity: city, in: listID)
            }
        )
        .contextMenu {
            macSidebarContextMenuMarker(contextID)
            cityActions(for: city, in: listID)
        }
    }

    private func macSidebarContextOutline(isVisible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isVisible ? theme.colors.accent.opacity(0.10) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isVisible ? theme.colors.accent.opacity(0.42) : Color.clear, lineWidth: 1)
            }
            .padding(.horizontal, 8)
            .animation(.easeOut(duration: 0.12), value: isVisible)
    }

    private func macSidebarContextMenuMarker(_ id: String) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onDisappear {
                DispatchQueue.main.async {
                    if macSidebarContextTarget == id {
                        macSidebarContextTarget = nil
                    }
                }
            }
    }

    @ViewBuilder
    private func macSidebarRightClickReader(_ id: String) -> some View {
        #if os(macOS)
        MacSidebarRightClickReader(id: id) { target in
            macSidebarContextTarget = target
        }
        #else
        Color.clear
        #endif
    }

    private func macSidebarListContextID(_ listID: CityListID) -> String {
        "list:\(listID.rawValue)"
    }

    private func macSidebarCityContextID(_ city: CityWeather, in listID: CityListID) -> String {
        "city:\(listID.rawValue):\(city.id.uuidString)"
    }

    private func macSidebarListDragPayload(_ listID: CityListID) -> String {
        "list|\(listID.rawValue)"
    }

    private func macSidebarCityDragPayload(_ city: CityWeather, in listID: CityListID) -> String {
        "city|\(listID.rawValue)|\(macSidebarStableCityKey(city))"
    }

    private func macSidebarStableCityKey(_ city: CityWeather) -> String {
        [
            city.city.name,
            city.city.country,
            String(format: "%.5f", city.city.latitude),
            String(format: "%.5f", city.city.longitude)
        ].joined(separator: "~")
    }

    private func macSidebarResolvedCityID(_ payloadID: String, in listID: CityListID) -> String? {
        weatherService.weatherData(for: listID).first { city in
            city.id.uuidString == payloadID || macSidebarStableCityKey(city) == payloadID
        }?.id.uuidString
    }

    private func macSidebarItemProvider(payload: String, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider(object: payload as NSString)
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(payload.data(using: .utf8), nil)
            return nil
        }
        return provider
    }

    private func macSidebarDropDelegate(_ id: String, acceptedTypes: [UTType], perform: @escaping ([NSItemProvider]) -> Bool) -> MacSidebarMoveDropDelegate {
        MacSidebarMoveDropDelegate(
            id: id,
            acceptedTypes: acceptedTypes,
            setTarget: { macSidebarDropTarget = $0 },
            clearTarget: {
                if macSidebarDropTarget == $0 {
                    macSidebarDropTarget = nil
                }
            },
            perform: perform
        )
    }

    private func loadMacSidebarDrop(_ providers: [NSItemProvider], onList listID: CityListID) -> Bool {
        loadMacSidebarDropPayload(from: providers) { payload in
            _ = handleMacSidebarDrop([payload], onList: listID)
        }
    }

    private func loadMacSidebarDrop(_ providers: [NSItemProvider], onCity city: CityWeather, in listID: CityListID) -> Bool {
        loadMacSidebarDropPayload(from: providers) { payload in
            _ = handleMacSidebarDrop([payload], onCity: city, in: listID)
        }
    }

    private func loadMacSidebarDropPayload(from providers: [NSItemProvider], perform action: @escaping (String) -> Void) -> Bool {
        let acceptedTypeIDs = [UTType.weatherSidebarList.identifier, UTType.weatherSidebarCity.identifier, UTType.text.identifier]
        guard let provider = providers.first(where: { provider in
            acceptedTypeIDs.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }) else {
            macSidebarDropTarget = nil
            return false
        }

        if let typeID = acceptedTypeIDs.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            provider.loadDataRepresentation(forTypeIdentifier: typeID) { data, _ in
                guard let data, let payload = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    action(payload)
                    macSidebarDropTarget = nil
                }
            }
        }
        return true
    }

    private func handleMacSidebarDrop(_ payloads: [String], onList targetListID: CityListID) -> Bool {
        guard let payload = payloads.first else { return false }
        let parts = payload.split(separator: "|").map(String.init)
        guard let kind = parts.first else { return false }

        if kind == "list", parts.count == 2 {
            var lists = CityListID.allLists
            guard let source = lists.firstIndex(where: { $0.rawValue == parts[1] }),
                  let target = lists.firstIndex(of: targetListID),
                  source != target else { return false }
            let moved = lists.remove(at: source)
            lists.insert(moved, at: target)
            CityListID.saveListOrder(lists)
            macSidebarRefreshTick += 1
            PlatformFeedback.lightImpact()
            return true
        }

        if kind == "city", parts.count == 3 {
            guard let sourceListID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
                  let cityID = macSidebarResolvedCityID(parts[2], in: sourceListID) else { return false }
            let moved = weatherService.moveCity(id: cityID, from: sourceListID, to: targetListID, destination: nil)
            if moved {
                macSidebarRefreshTick += 1
                PlatformFeedback.lightImpact()
            }
            return moved
        }

        return false
    }

    private func handleMacSidebarDrop(_ payloads: [String], onCity targetCity: CityWeather, in targetListID: CityListID) -> Bool {
        guard let payload = payloads.first else { return false }
        let parts = payload.split(separator: "|").map(String.init)
        let targetKey = macSidebarStableCityKey(targetCity)
        guard parts.count == 3, parts[0] == "city",
              let sourceListID = CityListID.allLists.first(where: { $0.rawValue == parts[1] }),
              let cityID = macSidebarResolvedCityID(parts[2], in: sourceListID),
              let targetIndex = weatherService.weatherData(for: targetListID).firstIndex(where: { $0.id == targetCity.id || macSidebarStableCityKey($0) == targetKey }) else {
            return false
        }
        let moved = weatherService.moveCity(id: cityID, from: sourceListID, to: targetListID, destination: targetIndex)
        if moved {
            macSidebarRefreshTick += 1
            PlatformFeedback.lightImpact()
        }
        return moved
    }

    private func sidebarDotColor(for cityWeather: CityWeather) -> Color {
        let isNow = selectedDayOffset == -1
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))

        switch mapOverlayMode {
        case "temperature":
            return temperatureOverlayColor(isNow ? cityWeather.temperature : forecast.dailyHigh)
        case "cloudCover":
            let cover = isNow ? cityWeather.currentCloudCover : forecast.cloudCover
            guard let cover else { return .gray }
            return Color(
                red: Double(0x15) / 255.0 + cover * (1.0 - Double(0x15) / 255.0),
                green: Double(0x79) / 255.0 + cover * (1.0 - Double(0x79) / 255.0),
                blue: Double(0xC7) / 255.0 + cover * (1.0 - Double(0xC7) / 255.0)
            )
        case "precipitation":
            let chance: Double
            if isNow {
                chance = [.rain, .drizzle, .snow].contains(cityWeather.condition) ? 1.0 : 0.0
            } else {
                guard let precipitation = forecast.precipitationChance else { return .gray }
                chance = precipitation
            }
            return Color(
                red: 1.0 + chance * (Double(0x57) / 255.0 - 1.0),
                green: 1.0 + chance * (Double(0xD3) / 255.0 - 1.0),
                blue: 1.0 + chance * (Double(0xE5) / 255.0 - 1.0)
            )
        case "windSpeed":
            let speed = isNow ? cityWeather.currentWindSpeed : forecast.windSpeed
            guard let speed else { return .gray }
            let fraction = min(1.0, speed / 100.0)
            return Color(
                red: 1.0 + fraction * (Double(0xFD) / 255.0 - 1.0),
                green: 1.0 + fraction * (Double(0xA4) / 255.0 - 1.0),
                blue: 1.0 + fraction * (Double(0x09) / 255.0 - 1.0)
            )
        case "uvIndex":
            let uv = isNow ? cityWeather.currentUVIndex : forecast.uvIndex
            guard let uv else { return .gray }
            let fraction = min(1.0, Double(uv) / 11.0)
            return Color(
                red: 1.0 + fraction * (Double(0xFB) / 255.0 - 1.0),
                green: 1.0 + fraction * (Double(0x43) / 255.0 - 1.0),
                blue: 1.0 + fraction * (Double(0x68) / 255.0 - 1.0)
            )
        case "humidity":
            let humidity = isNow ? cityWeather.currentHumidity : forecast.maxHumidity
            guard let humidity else { return .gray }
            return Color(
                red: 1.0 + humidity * (Double(0xBE) / 255.0 - 1.0),
                green: 1.0 + humidity * (Double(0x9A) / 255.0 - 1.0),
                blue: 1.0 + humidity * (Double(0xED) / 255.0 - 1.0)
            )
        case "visibility":
            let visibility = isNow ? cityWeather.currentVisibility : forecast.maxVisibility
            guard let visibility else { return .gray }
            let fraction = min(1.0, visibility / 30.0)
            return Color(
                red: 1.0 + fraction * (Double(0x15) / 255.0 - 1.0),
                green: 1.0 + fraction * (Double(0x79) / 255.0 - 1.0),
                blue: 1.0 + fraction * (Double(0xC7) / 255.0 - 1.0)
            )
        default:
            if isNow && cityWeather.weatherIcon.contains("moon") {
                return AppTheme.shared.colors.moonIconColor
            }
            return (isNow ? cityWeather.condition : forecast.condition).dotColor
        }
    }

    private func temperatureOverlayColor(_ tempC: Double) -> Color {
        if tempC <= 0 {
            let t = max(0, min(1, (tempC - (-20)) / 20.0))
            return Color(
                red: Double(0x15) / 255.0 + t * Double(0x57 - 0x15) / 255.0,
                green: Double(0x79) / 255.0 + t * Double(0xD3 - 0x79) / 255.0,
                blue: Double(0xC7) / 255.0 + t * Double(0xE5 - 0xC7) / 255.0
            )
        } else if tempC <= 10 {
            let t = max(0, min(1, tempC / 10.0))
            return Color(
                red: Double(0x57) / 255.0 + t * Double(0x7D - 0x57) / 255.0,
                green: Double(0xD3) / 255.0 + t * Double(0xD4 - 0xD3) / 255.0,
                blue: Double(0xE5) / 255.0 + t * Double(0xA0 - 0xE5) / 255.0
            )
        } else if tempC <= 20 {
            let t = max(0, min(1, (tempC - 10) / 10.0))
            return Color(
                red: Double(0x7D) / 255.0 + t * Double(0xFD - 0x7D) / 255.0,
                green: Double(0xD4) / 255.0 + t * Double(0xA4 - 0xD4) / 255.0,
                blue: Double(0xA0) / 255.0 + t * Double(0x09 - 0xA0) / 255.0
            )
        } else {
            let t = max(0, min(1, (tempC - 20) / 20.0))
            return Color(
                red: Double(0xFD) / 255.0 + t * Double(0xFB - 0xFD) / 255.0,
                green: Double(0xA4) / 255.0 + t * Double(0x43 - 0xA4) / 255.0,
                blue: Double(0x09) / 255.0 + t * Double(0x68 - 0x09) / 255.0
            )
        }
    }
}

#if os(macOS)
private struct MacSidebarRightClickReader: NSViewRepresentable {
    let id: String
    let setTarget: (String?) -> Void

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        view.id = id
        view.setTarget = setTarget
        return view
    }

    func updateNSView(_ nsView: EventView, context: Context) {
        nsView.id = id
        nsView.setTarget = setTarget
    }

    final class EventView: NSView {
        var id: String = ""
        var setTarget: (String?) -> Void = { _ in }
        private var monitor: Any?
        private var menuObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            if let menuObserver {
                NotificationCenter.default.removeObserver(menuObserver)
            }
        }

        private func updateMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            if let menuObserver {
                NotificationCenter.default.removeObserver(menuObserver)
                self.menuObserver = nil
            }
            guard window != nil else { return }

            menuObserver = NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setTarget(nil)
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, self.window === event.window else { return event }

                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    if event.type == .rightMouseDown {
                        self.setTarget(self.id)
                    }
                } else if event.type == .leftMouseDown {
                    self.setTarget(nil)
                }

                return event
            }
        }
    }
}
#endif
#endif
