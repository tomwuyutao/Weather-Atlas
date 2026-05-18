//
//  ListManager.swift
//  Weather
//
//  Shared list-management actions used by the native List sidebars.
//

import SwiftUI

extension ContentView {

    var sidebarLists: [CityListID] {
        _ = listOrderRevision
        return CityListID.allLists
    }

    func sidebarCities(for listID: CityListID) -> [CityWeather] {
        _ = cityOrderRevision
        return weatherService.weatherData(for: listID)
    }

    func refreshSidebarListOrder() {
        listOrderRevision += 1
    }

    func refreshSidebarCityOrder() {
        cityOrderRevision += 1
    }

    @ViewBuilder
    func listActions(for listID: CityListID) -> some View {
        Button {
            Task {
                await switchToList(listID)
                #if os(iOS)
                pushIPhoneRoute(.map)
                #else
                showingMapSidebar = false
                #endif
            }
        } label: {
            Label {
                Text(localizedString("Reveal on Map", locale: locale))
            } icon: {
                Image(systemName: "map")
                    .foregroundStyle(.primary)
            }
        }

        Button {
            beginRenamingList(listID)
        } label: {
            Label {
                Text(localizedString("Rename", locale: locale))
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
        }

        Button {
            beginAddingCity(to: listID)
        } label: {
            Label {
                Text(localizedString("Add City", locale: locale))
            } icon: {
                Image(systemName: "plus")
                    .foregroundStyle(.primary)
            }
        }

        Button(localizedString("Delete", locale: locale), systemImage: "trash", role: .destructive) {
            Task {
                await weatherService.deleteList(listID)
            }
        }
        .tint(theme.colors.destructive)
    }

    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        Button {
            revealCityOnMap(city, in: listID)
        } label: {
            Label {
                Text(localizedString("Reveal on Map", locale: locale))
            } icon: {
                Image(systemName: "map")
                    .foregroundStyle(.primary)
            }
        }

        Button {
            beginRenamingCity(city, in: listID)
        } label: {
            Label {
                Text(localizedString("Rename", locale: locale))
            } icon: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
        }

        Button(localizedString("Delete", locale: locale), systemImage: "trash", role: .destructive) {
            weatherService.removeCity(city, from: listID)
            refreshSidebarCityOrder()
        }
        .tint(theme.colors.destructive)
    }

    func createListAtBottom() {
        let newList = CityListID.createList(name: localizedString("New List", locale: locale))
        refreshSidebarListOrder()
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
            #if os(iOS)
            pushIPhoneRoute(.map)
            #else
            showingMapSidebar = false
            #endif
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
        refreshSidebarListOrder()
        sidebarExpandedListIDs.insert(newList.rawValue)
        sidebarNewListName = ""
    }

    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
        recenterOnAllCities = true
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
        #if os(iOS)
        pushIPhoneRoute(.map)
        #else
        showingMapSidebar = false
        #endif
        inlineSearchText = ""
        activateInlineSearch()
    }
}
