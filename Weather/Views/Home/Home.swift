//
//  Home.swift
//  Weather
//
//  Purpose: Presents current-location sunny hours, saved-place ranking, and
//  the nearest fully sunny World Cities result.
//

import CoreLocation
import SwiftUI
import UIKit

struct HomeView: View {
    /// Injected observable model shared by Home's current-location workflows.
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
    @State private var selectedSection: HomeSection = .currentLocation

    /// Saved Places remain distinct from the user's ephemeral current location.
    private var sunnySavedPlaceRecommendations: [PlaceRecommendation] {
        model.savedRecommendations(on: selectedDate).filter {
            $0.condition == .clear || $0.condition == .partlySunny
        }
    }

    /// Forecast-date planning applies only to places the user explicitly chose
    /// to compare in their saved library.
    private var bestSunnyDateSummaries: [BestSunnyDateSummary] {
        ForecastDateHorizon.dates(in: model.forecastCalendar).map { date in
            let recommendations = model.savedRecommendations(on: date)
            let sunnyScore = recommendations.reduce(into: 0.0) { score, item in
                switch item.condition {
                case .clear:
                    score += 1
                case .partlySunny:
                    score += 0.5
                default:
                    break
                }
            }
            return BestSunnyDateSummary(
                date: date,
                sunnyScore: sunnyScore,
                availableCityCount: recommendations.count
            )
        }
    }

    private var savedPlaceIDs: Set<SavedPlace.ID> {
        Set(model.placesStore.allPlaces.map(\.id))
    }

    private var savedPlaceLoadID: [SavedPlace.ID] {
        savedPlaceIDs.sorted { $0.uuidString < $1.uuidString }
    }

    /// Re-ranks the preloaded nearby-city forecasts locally for the selected
    /// date. Changing this date never creates another WeatherKit request.
    private var nearbySunnyRecommendations: [NearestSunnyPlaceResult] {
        model.nearbySunnyRecommendations(on: selectedDate)
    }

    private var homeWeatherTaskID: HomeWeatherTaskID {
        HomeWeatherTaskID(
            latitude: model.locationProvider.coordinate?.latitude,
            longitude: model.locationProvider.coordinate?.longitude
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                Picker("Home section", selection: $selectedSection) {
                    ForEach(HomeSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                switch selectedSection {
                case .currentLocation:
                    currentLocationSection
                case .savedPlaces:
                    savedPlacesSection
                }
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

                Spacer(minLength: 8)

                Menu {
                    Button {
                        refreshHomeWeather()
                    } label: {
                        Label(refreshMenuTitle, systemImage: "arrow.clockwise")
                    }
                    Button {
                        router.presentedSheet = .settings
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)

                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
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

    private var currentLocationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            CurrentLocationTimelineCard(
                weather: model.currentLocationWeather,
                selectedDate: selectedDate,
                locationName: model.locationProvider.metadata?.displayName
                    ?? model.currentLocationWeather?.city.displayName,
                locationStatus: model.locationProvider.status,
                isLoading: model.isRefreshingHomeWeather,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                retry: refreshHomeWeather
            )

            if let currentLocationWeather = model.currentLocationWeather {
                SunnyHoursOverviewCard(
                    city: currentLocationWeather,
                    selectedDate: $selectedDate
                )

                NavigationLink(value: AppRoute.currentLocation) {
                    subtleNavigationLabel("View Detailed Forecast")
                }
                .buttonStyle(.plain)
            }

            if !model.currentLocationIsSunny(on: selectedDate) {
                NearestSunnyPlaceCard(
                    recommendations: nearbySunnyRecommendations,
                    locationStatus: model.locationProvider.status,
                    isLoading: model.isRefreshingHomeWeather,
                    hasCompletedSearch: model.hasCompletedNearestSunnySearch,
                    errorMessage: model.homeLocationError,
                    savedPlaceIDs: savedPlaceIDs,
                    requestLocation: requestCurrentLocation,
                    retry: refreshHomeWeather,
                    save: saveNearbySunnyPlace
                )
            }
        }
    }

    private var savedPlacesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !model.placesStore.allPlaces.isEmpty {
                BestSunnyDatesCard(
                    summaries: bestSunnyDateSummaries,
                    selectedDate: $selectedDate
                )
            }

            BestSunnyPlacesCard(
                recommendations: sunnySavedPlaceRecommendations
            )

            Button(action: router.showPlaces) {
                subtleNavigationLabel("View Saved Places")
            }
            .buttonStyle(.plain)
        }
    }

    private func subtleNavigationLabel(
        _ title: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
        }
        .font(.callout)
        .foregroundStyle(theme.colors.secondaryText)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(.rect)
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
                forceRefresh: true,
                locale: locale
            )
        }
    }

    private var refreshMenuTitle: String {
        guard let lastHomeRefreshDate = model.lastHomeRefreshDate else {
            return "Refresh (Not yet)"
        }
        return "Refresh (\(lastHomeRefreshDate.formatted(.relative(presentation: .named))))"
    }

    private func saveNearbySunnyPlace(_ recommendation: NearestSunnyPlaceResult) {
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
    let latitude: Double?
    let longitude: Double?
}

private enum HomeSection: CaseIterable, Identifiable {
    case currentLocation
    case savedPlaces

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .currentLocation:
            "Your Location"
        case .savedPlaces:
            "Saved Places"
        }
    }
}
