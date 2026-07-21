//
//  CityActionsMenu.swift
//  Weather
//
//  Purpose: Defines the reusable context-menu actions for a city in a saved
//  list, including move, rename, and delete.
//

import SwiftUI

// MARK: - Saved-City Context Menu

extension ContentView {
    @ViewBuilder
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        let destinationLists = managedLists.filter { $0.rawValue != listID.rawValue }

        if !destinationLists.isEmpty {
            Menu {
                ForEach(destinationLists) { destinationListID in
                    Button {
                        weatherService.moveCity(city, from: listID, to: destinationListID)
                        Haptics.lightImpact()
                    } label: {
                        primaryMenuLabel(
                            destinationListID.localizedDisplayName(locale: locale),
                            systemImage: "list.bullet"
                        )
                    }
                }
            } label: {
                primaryMenuLabel(
                    localizedString("Move", locale: locale),
                    systemImage: "arrow.right"
                )
            }
        }

        Button {
            cityToRename = city.city
            cityRenameText = CityListID.customCityName(for: city.city)
                ?? localizedCityName(for: city.city)
            showingCityRenameAlert = true
        } label: {
            primaryMenuLabel(
                localizedString("Rename", locale: locale),
                systemImage: "pencil"
            )
        }

        Button {
            weatherService.removeCity(city, from: listID)
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.colors.destructive)
            }
        }
        .tint(theme.colors.destructive)
    }
}
