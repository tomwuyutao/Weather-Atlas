//
//  CitySaving.swift
//  Weather
//
//  Purpose: Saves searched cities into lists and reconciles navigation afterward.
//

import SwiftUI

// MARK: - Save City

extension ContentView {
    @discardableResult
    func addCityToActiveList(_ cityWeather: CityWeather) -> Bool {
        let didAdd = weatherService.addCityToList(
            cityWeather,
            listID: weatherService.activeListID
        )
        if didAdd {
            Haptics.lightImpact()
        }
        if let addedCity = weatherService.cityWeatherData.first(where: {
            weatherService.citiesMatch($0.city, cityWeather.city)
        }) {
            selectedMapCity = addedCity
        }
        return didAdd
    }

    func addCity(to listID: CityListID) {
        guard let city = cityPendingAddition else { return }
        let originatedFromTemporaryMapCity = addCityDetailCity == nil

        Task {
            let didAdd: Bool
            if listID == weatherService.activeListID {
                didAdd = addCityToActiveList(city)
            } else {
                didAdd = weatherService.addCityToList(city, listID: listID)
                if didAdd {
                    Haptics.lightImpact()
                }
                await switchToList(listID)
            }

            await MainActor.run {
                guard let savedCity = weatherService.cityWeatherData.first(where: {
                    weatherService.citiesMatch($0.city, city.city)
                }) else {
                    weatherService.reportDeveloperWarning(
                        title: "Added City Missing",
                        message: "After adding \(city.city.localizedName()) to \(listID.rawValue), the saved city could not be found in fetched weather data."
                    )
                    return
                }

                selectedMapCity = savedCity
                citySearchState.temporaryMapCity = nil
                if originatedFromTemporaryMapCity {
                    // A map search should remain on the map after saving; the
                    // temporary card simply becomes the saved city's card.
                    showingMapExpandedCard = true
                } else {
                    if case .addCityDetail = navigationPath.last {
                        navigationPath.removeLast()
                    }
                    pushRoute(.cityDetail(savedCity))
                }
                if didAdd {
                    showCityAddedConfirmation(
                        cityAddedConfirmationMessage(
                            cityName: localizedCityName(for: savedCity.city),
                            listName: listID.localizedDisplayName(locale: locale)
                        )
                    )
                }
            }
        }
    }

}
