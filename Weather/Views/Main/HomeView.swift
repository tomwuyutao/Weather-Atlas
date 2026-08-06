//
//  HomeView.swift
//  Weather
//
//  Purpose: Presents three focused cards for current-location sunny hours,
//  saved-place ranking, and the nearest fully sunny World Cities result.
//

import CoreLocation
import SwiftUI
import UIKit

struct HomeView: View {
    /// Injected observable model; Home needs a binding only for its radius menu.
    @Bindable var model: WeatherAtlasModel
    /// Value-navigation and item-driven presentation coordinator.
    @Bindable var router: AppRouter
    /// Literal date owned exclusively by the shared bottom date control.
    @Binding var selectedDate: Date

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var recentlySavedPlaceID: SavedPlace.ID?
    @State private var saveErrorMessage: String?

    private var sunnySavedRecommendations: [PlaceRecommendation] {
        model.savedRecommendations(on: selectedDate).filter {
            $0.condition == .clear || $0.condition == .partlySunny
        }
    }

    private var savedPlaceIDs: Set<SavedPlace.ID> {
        Set(model.placesStore.allPlaces.map(\.id))
    }

    private var savedPlaceLoadID: [SavedPlace.ID] {
        savedPlaceIDs.sorted { $0.uuidString < $1.uuidString }
    }

    private var homeWeatherTaskID: HomeWeatherTaskID {
        HomeWeatherTaskID(
            date: Calendar.current.startOfDay(for: selectedDate),
            radius: model.nearestSunnySearchRadius,
            localeIdentifier: locale.identifier,
            status: model.locationProvider.status,
            latitude: model.locationProvider.coordinate?.latitude,
            longitude: model.locationProvider.coordinate?.longitude,
            metadata: model.locationProvider.metadata
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                CurrentLocationTimelineCard(
                    weather: model.currentLocationWeather,
                    selectedDate: selectedDate,
                    locationName: model.locationProvider.metadata?.displayName,
                    locationStatus: model.locationProvider.status,
                    isLoading: model.isRefreshingHomeWeather,
                    requestLocation: requestCurrentLocation,
                    openSettings: openLocationSettings,
                    retry: refreshHomeWeather
                )

                BestSunnyPlacesCard(
                    recommendations: sunnySavedRecommendations,
                    showAllPlaces: { router.showPlaces() }
                )

                // Keep this card in the layout for every selected date. The
                // prior conditional removed it whenever the current location
                // was clear, which made a simple date change look like a
                // failed or missing nearest-sunny search.
                NearestSunnyPlaceCard(
                    radius: $model.nearestSunnySearchRadius,
                    recommendation: model.nearestSunnyRecommendation,
                    currentLocationIsFullySunny:
                        model.currentLocationIsFullySunny(on: selectedDate),
                    locationStatus: model.locationProvider.status,
                    isLoading: model.isRefreshingHomeWeather,
                    hasCompletedSearch:
                        model.hasCompletedNearestSunnySearch,
                    checkedCityCount:
                        model.lastNearestSunnyCheckedCityCount,
                    weatherKitQueryCount:
                        model.lastNearestSunnyWeatherQueryCount,
                    errorMessage: model.homeLocationError,
                    isSaved: model.nearestSunnyRecommendation.map {
                        savedPlaceIDs.contains($0.id)
                    } ?? false,
                    requestLocation: requestCurrentLocation,
                    retry: refreshHomeWeather,
                    save: saveNearestSunnyPlace
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(theme.colors.background)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Text("Home")
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                Button("Settings", systemImage: "gearshape") {
                    router.presentedSheet = .settings
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 36, minHeight: 44)

                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates
                )
            }
            .font(.title3)
            .buttonStyle(.plain)
            .foregroundStyle(theme.colors.primaryText)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .refreshable {
            await model.loadSavedWeather(
                forceRefresh: true,
                locale: locale
            )
            if model.locationProvider.hasUsableCoordinate {
                await model.refreshHomeWeather(
                    on: selectedDate,
                    forceRefresh: true,
                    locale: locale
                )
            }
        }
        .task(id: savedPlaceLoadID) {
            await model.loadSavedWeather(locale: locale)
        }
        .task(id: homeWeatherTaskID) {
            // Core Location supplies a valid coordinate before optional display
            // metadata finishes resolving. Start Home weather from that
            // coordinate immediately so both location cards do not depend on
            // reverse geocoding completing successfully.
            guard model.locationProvider.hasUsableCoordinate else {
                return
            }
            await model.refreshHomeWeather(
                on: selectedDate,
                locale: locale
            )
        }
        .alert(
            "Unable to Save Place",
            isPresented: saveErrorIsPresented
        ) {
            Button("OK") {
                saveErrorMessage = nil
            }
        } message: {
            if let saveErrorMessage {
                Text(saveErrorMessage)
            }
        }
        .sensoryFeedback(.success, trigger: recentlySavedPlaceID)
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private func requestCurrentLocation() {
        model.locationProvider.requestCurrentLocation(preferredLocale: locale)
    }

    private func openLocationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private func refreshHomeWeather() {
        if !model.locationProvider.hasUsableCoordinate {
            requestCurrentLocation()
            return
        }
        Task {
            await model.refreshHomeWeather(
                on: selectedDate,
                forceRefresh: true,
                locale: locale
            )
        }
    }

    private func saveNearestSunnyPlace() {
        guard let recommendation = model.nearestSunnyRecommendation else {
            return
        }
        do {
            recentlySavedPlaceID = try model.saveRecommendation(recommendation)
        } catch {
            saveErrorMessage = localizedPlacesErrorDescription(
                error,
                locale: locale
            )
        }
    }
}

private struct HomeWeatherTaskID: Hashable {
    let date: Date
    let radius: NearestSunnySearchRadius
    let localeIdentifier: String
    let status: LocationProviderStatus
    let latitude: Double?
    let longitude: Double?
    let metadata: CurrentLocationMetadata?
}
