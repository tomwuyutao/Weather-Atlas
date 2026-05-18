//
//  MacSidebar.swift
//  Weather
//
//  Native list/sidebar management.
//

import SwiftUI

#if os(macOS) || os(iOS)
extension ContentView {

    var macListManagerSidebar: some View {
        #if os(iOS)
        List {
            Section {
                iOSSidebarListRows
            }
            .listRowBackground(theme.colors.mapLand)
        }
        .listStyle(.sidebar)
        .tint(.primary)
        .environment(\.editMode, $sidebarEditMode)
        .onAppear {
            if sidebarExpandedListIDs.isEmpty {
                sidebarExpandedListIDs.insert(weatherService.activeListID.rawValue)
            }
        }
        #else
        List(selection: $macSidebarSelection) {
            Section(localizedString("Lists", locale: locale)) {
                macSidebarSelectableListRows
            }
        }
        .listStyle(.sidebar)
        .tint(theme.colors.accent)
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
        #endif
    }

    @ViewBuilder
    private var iOSSidebarListRows: some View {
        ForEach(CityListID.allLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = weatherService.weatherData(for: listID)
                if cities.isEmpty {
                    Text(localizedString("No cities", locale: locale))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cities) { city in
                        Button {
                            revealCityOnMap(city, in: listID)
                        } label: {
                            Text(city.city.localizedName(locale: locale))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            cityActions(for: city, in: listID)
                        }
                    }
                    .onMove { source, destination in
                        moveMacSidebarCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteMacSidebarCities(in: listID, at: offsets)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(listID.localizedDisplayName(locale: locale))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(weatherService.weatherData(for: listID).count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu {
                listActions(for: listID)
            }
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    @ViewBuilder
    private var macSidebarSelectableListRows: some View {
        ForEach(CityListID.allLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = weatherService.weatherData(for: listID)
                if cities.isEmpty {
                    Text(localizedString("No cities", locale: locale))
                        .foregroundStyle(.secondary)
                        .tag("empty:\(listID.rawValue)")
                } else {
                    ForEach(cities) { city in
                        Text(city.city.localizedName(locale: locale))
                            .lineLimit(1)
                            .tag(macSidebarCityContextID(city, in: listID))
                            .contextMenu {
                                cityActions(for: city, in: listID)
                            }
                    }
                    .onMove { source, destination in
                        moveMacSidebarCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteMacSidebarCities(in: listID, at: offsets)
                    }
                }
            } label: {
                Text(listID.localizedDisplayName(locale: locale))
                    .lineLimit(1)
            }
            .badge(weatherService.weatherData(for: listID).count)
            .tag(macSidebarListContextID(listID))
            .contextMenu {
                listActions(for: listID)
            }
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    private func moveMacSidebarLists(from source: IndexSet, to destination: Int) {
        weatherService.moveLists(from: source, to: destination)
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarLists(at offsets: IndexSet) {
        let lists = CityListID.allLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            Task { await weatherService.deleteList(lists[index]) }
        }
        PlatformFeedback.lightImpact()
    }

    private func moveMacSidebarCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = weatherService.weatherData(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        PlatformFeedback.lightImpact()
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

    private func macSidebarListContextID(_ listID: CityListID) -> String {
        "list:\(listID.rawValue)"
    }

    private func macSidebarCityContextID(_ city: CityWeather, in listID: CityListID) -> String {
        "city:\(listID.rawValue):\(city.id.uuidString)"
    }
}
#endif
