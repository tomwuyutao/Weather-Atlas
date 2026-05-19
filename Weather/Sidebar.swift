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
        Group {
            if shouldUseIPadLayout {
                List {
                    Section {
                        iOSSidebarListRows
                    }
                }
                .listStyle(.sidebar)
                .tint(theme.colors.primaryText)
            } else {
                List {
                    Section {
                        iOSSidebarListRows
                    }
                    .listRowBackground(theme.colors.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.colors.background)
                .tint(theme.colors.accent)
            }
        }
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
        ForEach(sidebarLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = sidebarCities(for: listID)
                if cities.isEmpty {
                    Text(localizedString("No cities", locale: locale))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                        .padding(.leading, 22)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(cities) { city in
                        Button {
                            revealCityOnMap(city, in: listID)
                        } label: {
                            iOSSidebarCityRow(city)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            cityActions(for: city, in: listID)
                        }
                        .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        moveMacSidebarCities(in: listID, from: source, to: destination)
                    }
                    .onDelete { offsets in
                        deleteMacSidebarCities(in: listID, at: offsets)
                    }
                }
            } label: {
                iOSSidebarListHeader(listID)
                    .contextMenu {
                        listActions(for: listID)
                    }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(shouldUseIPadLayout
                ? EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14)
                : EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 28)
            )
        }
        .onMove(perform: moveMacSidebarLists)
        .onDelete(perform: deleteMacSidebarLists)
    }

    private func iOSSidebarListHeader(_ listID: CityListID) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10, height: 18)

                Text(listID.localizedDisplayName(locale: locale))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("\(sidebarCities(for: listID).count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.colors.mapLand, in: Capsule())
            }
            .padding(.top, 10)
            .padding(.bottom, 8)

            Rectangle()
                .fill(theme.colors.primaryText.opacity(0.18))
                .frame(height: 1)
                .padding(.trailing, -16)
        }
        .contentShape(Rectangle())
    }

    private func iOSSidebarCityRow(_ city: CityWeather) -> some View {
        let dotColor = city.weatherIcon.contains("moon") ? theme.colors.moonIconColor : city.condition.dotColor(for: theme.colors)

        return HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .shadow(color: dotColor.opacity(0.35), radius: 3)

            Text(city.city.localizedName(locale: locale))
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 10)

            Text(tempUnit.display(city.temperature))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 9)
        .padding(.leading, shouldUseIPadLayout ? -6 : -18)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var macSidebarSelectableListRows: some View {
        ForEach(sidebarLists) { listID in
            DisclosureGroup(isExpanded: macSidebarListExpansionBinding(for: listID)) {
                let cities = sidebarCities(for: listID)
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
            .badge(sidebarCities(for: listID).count)
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
        refreshSidebarListOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarLists(at offsets: IndexSet) {
        let lists = sidebarLists
        for index in offsets {
            guard lists.indices.contains(index) else { continue }
            Task {
                await weatherService.deleteList(lists[index])
                await MainActor.run {
                    refreshSidebarListOrder()
                }
            }
        }
        PlatformFeedback.lightImpact()
    }

    private func moveMacSidebarCities(in listID: CityListID, from source: IndexSet, to destination: Int) {
        weatherService.moveCity(in: listID, from: source, to: destination)
        refreshSidebarCityOrder()
        PlatformFeedback.lightImpact()
    }

    private func deleteMacSidebarCities(in listID: CityListID, at offsets: IndexSet) {
        let cities = sidebarCities(for: listID)
        for index in offsets {
            guard cities.indices.contains(index) else { continue }
            weatherService.removeCity(cities[index], from: listID)
        }
        refreshSidebarCityOrder()
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
#if os(iOS)
#Preview("iOS List Manager") {
    NavigationStack {
        ContentView().iPhoneNativeListManager
    }
}
#elseif os(macOS)
#Preview("Sidebar") {
    ContentView()
        .macListManagerSidebar
        .frame(width: 280, height: 520)
}
#endif

