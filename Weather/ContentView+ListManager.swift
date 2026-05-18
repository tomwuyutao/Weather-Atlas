//
//  ContentView+ListManager.swift
//  Weather
//
//  Shared list-management actions used by the native List sidebars.
//

import SwiftUI

extension ContentView {

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
        showingMapSidebar = false
        inlineSearchText = ""
        activateInlineSearch()
    }
}
