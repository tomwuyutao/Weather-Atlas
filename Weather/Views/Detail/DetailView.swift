//
//  DetailView.swift
//  Weather
//
//  Purpose: Presents the shared card-based Saved Place report.
//

import CoreLocation
import SwiftUI

// MARK: - Shared Detail Report

/// The common forecast-report canvas used by a saved/discovered place and the
/// current physical location. The owning screen still supplies its own loading,
/// permission, retry, and supplementary content; this type only owns the
/// report UI that is genuinely identical between those flows.
struct DetailReportContent<SupplementaryContent: View>: View {
    let locationName: String
    let weather: CityWeather?
    let forecast: DailyForecast?
    @Binding private var selectedDate: Date
    let dailySunnyHoursCard: SunnyHoursTimeline
    let tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline
    let temperatureUnit: TemperatureUnit
    let maximumContentWidth: CGFloat
    let showsTimeZoneFootnote: Bool
    private let onHeaderVisibilityChange: (Bool) -> Void
    private let supplementaryContent: SupplementaryContent

    @Environment(\.locale) private var locale

    init(
        locationName: String,
        weather: CityWeather?,
        forecast: DailyForecast?,
        selectedDate: Binding<Date>,
        dailySunnyHoursCard: SunnyHoursTimeline,
        tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline,
        temperatureUnit: TemperatureUnit,
        maximumContentWidth: CGFloat = .infinity,
        showsTimeZoneFootnote: Bool,
        onHeaderVisibilityChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder supplementaryContent: () -> SupplementaryContent
    ) {
        self.locationName = locationName
        self.weather = weather
        self.forecast = forecast
        _selectedDate = selectedDate
        self.dailySunnyHoursCard = dailySunnyHoursCard
        self.tenDaySunnyHoursTimeline = tenDaySunnyHoursTimeline
        self.temperatureUnit = temperatureUnit
        self.maximumContentWidth = maximumContentWidth
        self.showsTimeZoneFootnote = showsTimeZoneFootnote
        self.onHeaderVisibilityChange = onHeaderVisibilityChange
        self.supplementaryContent = supplementaryContent()
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                LocationReportHeader(
                    locationName: locationName,
                    weather: weather,
                    forecast: forecast
                )
                .onScrollVisibilityChange(threshold: 0.01) { isVisible in
                    onHeaderVisibilityChange(isVisible)
                }

                dailySunnyHoursCard
                tenDaySunnyHoursTimeline
                supplementaryContent

                DetailMetricGrid(
                    city: weather,
                    placeDisplayName: locationName,
                    forecast: forecast,
                    temperatureUnit: temperatureUnit,
                    usesLandscapeIPadLayout: false,
                    selectedForecastDate: $selectedDate
                )

                if showsTimeZoneFootnote,
                   let weather,
                   let forecast,
                   weather.timeZone.identifier
                    != TimeZone.autoupdatingCurrent.identifier {
                    WeatherTimeZoneFootnote(
                        text: SunnyHoursFormatting.localTimeDisclosure(
                            placeName: locationName,
                            timeZone: weather.timeZone,
                            at: forecast.date,
                            locale: locale
                        )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: maximumContentWidth)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Current-location presentation built from the same report canvas as a
/// saved-place detail. Location permission and refresh lifecycle remain in
/// `YourLocationView`; this type only adapts their live values into report UI.
struct CurrentLocationReportContent: View {
    let model: WeatherModel
    let router: AppNavigation
    @Binding var selectedDate: Date
    let requestCurrentLocation: () -> Void
    let openLocationSettings: () -> Void
    let refreshLocation: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    private var locationWeather: CityWeather? {
        model.locationWeather
    }

    private var selectedForecast: DailyForecast? {
        locationWeather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )
    }

    private var locationName: String {
        let resolvedName = model.locationProvider.metadata?.displayName
            ?? locationWeather?.city.name
        return CurrentLocationMetadata.localityName(from: resolvedName) ?? ""
    }

    private var nearbyAssessment: NearbyRecommendationsAssessment {
        model.nearbyRecommendationAssessment(on: selectedDate)
    }

    private var locationSunniness: LocationSunninessAssessment {
        model.locationSunninessAssessment(on: selectedDate)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var metadataRecoveryKey: String {
        guard let coordinate = model.locationProvider.coordinate else {
            return "unavailable"
        }
        return String(
            format: "%.6f,%.6f",
            coordinate.latitude,
            coordinate.longitude
        )
    }

    private var metadataMissingDataReport: MissingDataAlertReport? {
        guard locationName.isEmpty,
              model.locationProvider.status == .readyWithoutMetadata else {
            return nil
        }
        return MissingDataAlertReport(
            key: "your-location-metadata:\(metadataRecoveryKey)",
            title: localizedString("Data Missing", locale: locale),
            message: weatherDataIssueMessage(
                .unresolvedPlace(),
                cityName: localizedString("the current location", locale: locale),
                locale: locale
            )
        )
    }

    var body: some View {
        DetailReportContent(
            locationName: locationName,
            weather: locationWeather,
            forecast: selectedForecast,
            selectedDate: $selectedDate,
            dailySunnyHoursCard: SunnyHoursTimeline(
                weather: locationWeather,
                selectedDate: selectedDate,
                placeDisplayName: locationName,
                locationStatus: model.locationProvider.status,
                isLoading: model.isRefreshingLocation,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                retry: refreshLocation
            ),
            tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline(
                city: locationWeather,
                placeDisplayName: locationName,
                selectedDate: $selectedDate,
                isLoading: model.isRefreshingLocation,
                unavailableMessage: locationWeather == nil
                    ? model.locationError
                    : nil,
                retry: nil
            ),
            temperatureUnit: temperatureUnit,
            maximumContentWidth: 760,
            showsTimeZoneFootnote: true
        ) {
            switch locationSunniness {
            case .sunny:
                EmptyView()
            case .notSunny, .unavailable:
                NearbySunnyPlacesCard(
                    recommendations: nearbyAssessment.recommendations,
                    locationStatus: model.locationProvider.status,
                    isLoading: model.isRefreshingLocation,
                    hasCompletedSearch: model.didSearchNearby,
                    errorMessage: model.nearbySearchError,
                    requestLocation: requestCurrentLocation,
                    openSettings: openLocationSettings,
                    retry: refreshLocation,
                    viewOnMap: {
                        router.showNearbyOnMap(
                            nearbyAssessment.recommendations
                        )
                    }
                )
            }
        }
        .scrollIndicators(.hidden)
        .weatherConditionScreenBackground(
            for: selectedForecast?.condition?.iconTone
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "slider.horizontal.3") {
                    router.presentedSheet = .settings
                }
                .labelStyle(.iconOnly)
            }

            ToolbarItem(placement: .topBarTrailing) {
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(
                        in: model.forecastCalendar
                    )
                )
            }
        }
        .reportingMissingData(
            metadataMissingDataReport,
            recoveryKey: "location-metadata:\(metadataRecoveryKey)",
            retrying: {
                await model.locationProvider.retryMetadataResolution()
            }
        )
    }
}

/// Shared value-routed report for saved and discovered places.
struct DetailView: View {
    // MARK: Route Inputs and View State

    /// Stable identity carried by AppRoute rather than a replaceable snapshot.
    let placeID: City.ID
    /// Root domain model used to resolve the latest place and forecast values.
    let model: WeatherModel
    /// App-wide forecast day controlled by the tab-bar date accessory.
    @Binding private var selectedDate: Date
    /// Optional payload drives the error alert after a persistence mutation.
    @State private var mutationError: PlaceDetailMutationError?
    /// Hides the duplicate compact navigation title while the large in-content
    /// heading is visible at the top of the scrolling report.
    @State private var showsLargeTitle = true

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    init(
        placeID: City.ID,
        selectedDate: Binding<Date>,
        model: WeatherModel
    ) {
        // Routes carry only `placeID`; resolve the live model values below so
        // an open report reflects edits and refreshed forecasts immediately.
        self.placeID = placeID
        self.model = model
        _selectedDate = selectedDate
    }

    // MARK: Live Model Resolution

    private var savedPlace: SavedPlace? {
        model.placesStore.place(id: placeID)
    }

    private var city: City? {
        model.city(for: placeID)
    }

    private var cityWeather: CityWeather? {
        model.weatherStore.weather(for: placeID)
    }

    private var forecast: DailyForecast? {
        cityWeather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: model.forecastCalendar
        )
    }

    private var displayName: String {
        savedPlace?.displayName
            ?? city?.displayName
            ?? ""
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var isForecastLoading: Bool {
        guard let city else { return false }
        return model.weatherStore.isLoading(city.id)
            || (cityWeather == nil
                && model.weatherStore.failuresByID[city.id] == nil)
    }

    private var hasForecastRequestFailure: Bool {
        guard let city else { return false }
        return model.weatherStore.failuresByID[city.id] != nil
    }

    private var forecastUnavailableMessage: String? {
        if cityWeather != nil, forecast == nil {
            return localizedString(
                "Forecast data is unavailable for the selected date.",
                locale: locale
            )
        }
        guard let city,
              let issue = model.weatherStore.failuresByID[city.id]?.issue else {
            return nil
        }
        return weatherDataIssueMessage(
            issue,
            cityName: displayName,
            locale: locale
        )
    }

    var body: some View {
        // The complete report remains mounted through loading, missing-day,
        // and request-failure states. Individual cards own their placeholders
        // and recovery copy, so the screen never collapses into a standalone
        // spinner or retry button.
        DetailReportContent(
            locationName: displayName,
            weather: cityWeather,
            forecast: forecast,
            selectedDate: $selectedDate,
            dailySunnyHoursCard: SunnyHoursTimeline(
                weather: cityWeather,
                selectedDate: selectedDate,
                placeDisplayName: displayName,
                isLoading: isForecastLoading,
                unavailableMessage: forecastUnavailableMessage,
                retry: nil
            ),
            tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline(
                city: cityWeather,
                placeDisplayName: displayName,
                selectedDate: $selectedDate,
                isLoading: isForecastLoading,
                unavailableMessage: forecastUnavailableMessage,
                retry: hasForecastRequestFailure
                    ? { retryForecast() }
                    : nil
            ),
            temperatureUnit: temperatureUnit,
            showsTimeZoneFootnote: true,
            onHeaderVisibilityChange: { isVisible in
                showsLargeTitle = isVisible
            }
        ) {
            EmptyView()
        }
        .background(
            theme.colors.weatherBackgroundColor(
                for: forecast?.condition?.iconTone
            )
        )
        .refreshable {
            guard let city else { return }
            await model.weatherStore.refresh(city: city, locale: locale)
        }
        .weatherConditionScreenBackground(
            for: forecast?.condition?.iconTone
        )
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsLargeTitle {
                // Reserve the principal title slot while the large content
                // heading is visible, preventing a duplicate title in the bar.
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityHidden(true)
                }
            }

            if savedPlace == nil {
                ToolbarItem(placement: .topBarTrailing) {
                    placeActionsMenu
                }
            }

            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }

            ToolbarItem(placement: .topBarTrailing) {
                // The date stepper is separate from place actions so its native
                // hit target and spacing remain predictable in the toolbar.
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                )
            }
        }
        .task(id: placeID) {
            // The repository owns the full missing-data policy: it makes one
            // repair request before committing an incomplete response. Detail
            // therefore only starts the normal lookup and never forces a
            // third WeatherKit request when a card renders blank.
            showsLargeTitle = true
            guard let city else {
                return
            }

            _ = await model.weatherStore.lookup(
                city: city,
                locale: locale
            )
        }
        // The Store owns the bounded forecast request/retry. This route keeps
        // its final unavailable state inline so child cards cannot turn one
        // request failure into a sequence of modal alerts.
        .alert(
            "Places",
            isPresented: showsMutationError,
            presenting: mutationError
        ) { _ in
            Button("OK") {
                mutationError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    private func retryForecast() {
        guard let city else { return }
        Task {
            await model.weatherStore.refresh(city: city, locale: locale)
        }
    }

    // MARK: Saved-Place Actions

    /// Unsaved discovered places can be added from Detail. Saved-place editing
    /// stays in Manage Saved Places, keeping this report toolbar focused.
    @ViewBuilder
    private var placeActionsMenu: some View {
        Button {
            savePlace()
        } label: {
            Image(systemName: "bookmark")
                .accessibilityHidden(true)
        }
        .disabled(city == nil)
        .accessibilityLabel(Text("Save Place"))
        .accessibilityHint(Text("Adds this place to Saved Places"))
    }

    private var showsMutationError: Binding<Bool> {
        // `.alert` requires a Boolean while `mutationError` also supplies its
        // message. Clearing on dismissal keeps the two in sync.
        Binding(
            get: { mutationError != nil },
            set: { isPresented in
                if !isPresented {
                    mutationError = nil
                }
            }
        )
    }

    private func savePlace() {
        // The store owns validation and persistence. The view only translates
        // an error into localized, user-facing alert text.
        guard let city else { return }
        do {
            _ = try model.placesStore.savePlace(city)
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }

}

// MARK: - Mutation Alert Payload

/// Item-driven native error presentation for persistence mutations.
private struct PlaceDetailMutationError: Identifiable {
    let id = UUID()
    let message: String
}

// MARK: - Report Header

/// Large in-content heading shared by every forecast report.
struct LocationReportHeader: View {
    let locationName: String
    let weather: CityWeather?
    let forecast: DailyForecast?

    @Environment(\.appTheme) private var theme
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle)
    private var conditionIconSize: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle)
    private var conditionIconWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .largeTitle)
    private var conditionIconHeight: CGFloat = 58
    @ScaledMetric(relativeTo: .largeTitle)
    private var conditionPlaceholderHeight: CGFloat = 74
    @ScaledMetric(relativeTo: .largeTitle)
    private var titleMinimumHeight: CGFloat = 44

    private var sunStatusText: String? {
        guard let weather,
              let forecast,
              case .success(let data) = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: weather.timeZone
              ) else {
            return nil
        }

        switch SunnyHoursCalculation.dailySunStatus(
            in: data,
            selectedDate: forecast.date,
            timeZone: weather.timeZone,
            selectionCalendar: calendar
        ) {
        case .sunnyForHours(let count):
            return String(
                localized: "Sunny for \(SunnyHoursFormatting.hourCountText(count, locale: locale)) hours",
                locale: locale,
                comment: "Sun-status message shown beneath the location hero for a non-today date. The number counts clear and partly-sunny daylight hours, which need not be consecutive."
            )
        case .sunOutNow:
            return localizedString("Sun Out Now", locale: locale)
        case .sunOutIn(let date):
            return String(
                format: localizedString("Sun Out in %@", locale: locale),
                locale: locale,
                countdownText(to: date)
            )
        case .noSunToday:
            return localizedString("No Sun Today", locale: locale)
        case .noMoreSunToday:
            return localizedString("No More Sun Today", locale: locale)
        case .noSunOnSelectedDay:
            return localizedString("No Sun on this day", locale: locale)
        }
    }

    private var accessibilityLocationName: String {
        let trimmedName = locationName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedName.isEmpty
            ? localizedString("Current Location", locale: locale)
            : trimmedName
    }

    private var accessibilityWeatherSummary: String {
        [
            forecast?.condition?.localizedDisplayName(locale: locale),
            sunStatusText
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }

    var body: some View {
        VStack(spacing: 9) {
            Text(locationName)
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .frame(minHeight: titleMinimumHeight)

            if let forecast {
                if let condition = forecast.condition {
                    let icon = condition.displayIcon
                    Image(systemName: icon)
                        .weatherIconStyle(for: condition.iconTone)
                        .font(
                            .system(
                                size: conditionIconSize,
                                weight: .semibold
                            )
                        )
                        .frame(
                            width: conditionIconWidth,
                            height: conditionIconHeight
                        )
                        .padding(.vertical, 8)
                        .contentTransition(
                            reduceMotion ? .opacity : .symbolEffect(.replace)
                        )
                        .animation(
                            reduceMotion
                                ? nil
                                : .spring(
                                    response: 0.34,
                                    dampingFraction: 0.78
                                ),
                            value: icon
                        )
                        .accessibilityHidden(true)
                } else {
                    Color.clear
                        .frame(
                            width: conditionIconWidth,
                            height: conditionPlaceholderHeight
                        )
                        .accessibilityHidden(true)
                }

                if let sunStatusText {
                    Text(sunStatusText)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                } else {
                    Color.clear
                        .frame(height: 20)
                        .accessibilityHidden(true)
                }
            } else {
                Color.clear
                    .frame(
                        width: conditionIconWidth,
                        height: conditionPlaceholderHeight
                    )
                    .accessibilityHidden(true)

                Color.clear
                    .frame(height: 20)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLocationName)
        .accessibilityValue(accessibilityWeatherSummary)
        .accessibilityAddTraits(.isHeader)
    }

    private func countdownText(to date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        formatter.calendar = calendar
        return formatter.string(
            from: max(0, date.timeIntervalSinceNow)
        ) ?? localizedString("less than one minute", locale: locale)
    }
}
