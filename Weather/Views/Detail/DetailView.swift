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
struct DetailReportContent<SupplementaryContent: View, FooterContent: View>: View {
    /// The large report and navigation heading. A direct map query can retain
    /// its fuller locality-and-area name here.
    let locationName: String
    /// Ordinary labels within the report retain the concise locality.
    let placeDisplayName: String
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
    private let footerContent: FooterContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale

    init(
        locationName: String,
        placeDisplayName: String? = nil,
        weather: CityWeather?,
        forecast: DailyForecast?,
        selectedDate: Binding<Date>,
        dailySunnyHoursCard: SunnyHoursTimeline,
        tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline,
        temperatureUnit: TemperatureUnit,
        maximumContentWidth: CGFloat = 760,
        showsTimeZoneFootnote: Bool,
        onHeaderVisibilityChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder supplementaryContent: () -> SupplementaryContent,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.locationName = locationName
        self.placeDisplayName = placeDisplayName ?? locationName
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
        self.footerContent = footerContent()
    }

    var body: some View {
        GeometryReader { geometry in
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

                if showsTimeZoneFootnote,
                   let weather,
                   let forecast,
                   weather.timeZone.identifier
                    != TimeZone.autoupdatingCurrent.identifier {
                    WeatherTimeZoneFootnote(
                        text: SunnyHoursFormatting.localTimeDisclosure(
                            placeName: placeDisplayName,
                            timeZone: weather.timeZone,
                            at: forecast.date,
                            locale: locale
                        )
                    )
                }

                supplementaryContent

                DetailMetricGrid(
                    city: weather,
                    forecast: forecast,
                    temperatureUnit: temperatureUnit,
                    usesLandscapeIPadLayout: false,
                    selectedForecastDate: $selectedDate
                )

                footerContent
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .frame(maxWidth: reportContentWidth(for: geometry.size))
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Every forecast report uses the same focused landscape-iPad column.
    /// Phone and portrait layouts retain the established 760-point maximum,
    /// while landscape iPad narrows to 640 points across Your Location, Saved
    /// Places, and place Detail.
    private func reportContentWidth(for size: CGSize) -> CGFloat {
        guard horizontalSizeClass == .regular,
              size.width > size.height,
              maximumContentWidth.isFinite else {
            return maximumContentWidth
        }
        return min(maximumContentWidth, 640)
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
    let refreshCurrentLocation: () -> Void
    let searchNearby: () -> Void
    let onNearbyVisibilityChange: (Bool) -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    /// Mirrors a place report's compact title once its in-content hero scrolls
    /// away, without showing a duplicate title while the hero is visible.
    @State private var showsLargeTitle = true
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

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    /// Prefer the resolved locality, while retaining a meaningful label during
    /// the short interval before reverse geocoding finishes.
    private var navigationTitle: String {
        let trimmedName = locationName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmedName.isEmpty
            ? localizedString("Your Location", locale: locale)
            : trimmedName
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
                locationStatus: model.locationProvider.status,
                isLoading: model.isRefreshingLocation,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                retry: refreshCurrentLocation
            ),
            tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline(
                city: locationWeather,
                selectedDate: $selectedDate,
                isLoading: model.isRefreshingLocation,
                unavailableMessage: locationWeather == nil
                    ? model.locationError
                    : nil,
                retry: nil
            ),
            temperatureUnit: temperatureUnit,
            maximumContentWidth: 760,
            showsTimeZoneFootnote: true,
            onHeaderVisibilityChange: { isVisible in
                showsLargeTitle = isVisible
            }
        ) {
            NearbySunnyPlacesSection(
                model: model,
                selectedDate: selectedDate,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                retry: searchNearby,
                onVisibilityChange: onNearbyVisibilityChange,
                viewOnMap: {
                    router.showMap(findingSunIn: .nearMe)
                }
            )
        } footerContent: {
            EmptyView()
        }
        .scrollIndicators(.hidden)
        .weatherConditionScreenBackground(
            for: selectedForecast?.condition?.iconTone
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsLargeTitle {
                // Match `DetailView`: reserve the compact title slot while
                // the same title is already represented by the report hero.
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)

                }
            }

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

/// Keeps nearby ranking and repository observation below the lazy report
/// boundary. Current-weather updates no longer make the whole Home report scan
/// every candidate while this lower card is offscreen.
private struct NearbySunnyPlacesSection: View {
    let model: WeatherModel
    let selectedDate: Date
    let requestLocation: () -> Void
    let openSettings: () -> Void
    let retry: () -> Void
    let onVisibilityChange: (Bool) -> Void
    let viewOnMap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        let assessment = model.nearbyRecommendationAssessment(
            on: selectedDate,
            locale: locale
        )
        NearbySunnyPlacesCard(
            recommendations: assessment.recommendations,
            locationStatus: model.locationProvider.status,
            isLoading: model.isSearchingNearby,
            hasCompletedSearch: model.didSearchNearby,
            errorMessage: model.nearbySearchError,
            requestLocation: requestLocation,
            openSettings: openSettings,
            retry: retry,
            viewOnMap: viewOnMap
        )
        .onScrollVisibilityChange(threshold: 0.05) { isVisible in
            onVisibilityChange(isVisible)
        }
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

    /// A fuller reverse-geocoded locality belongs only in the report's title.
    /// A custom saved-place name still takes precedence when the person chose
    /// one explicitly.
    private var detailTitle: String {
        savedPlace?.customName
            ?? city?.titleDisplayName
            ?? displayName
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
            locationName: detailTitle,
            placeDisplayName: displayName,
            weather: cityWeather,
            forecast: forecast,
            selectedDate: $selectedDate,
            dailySunnyHoursCard: SunnyHoursTimeline(
                weather: cityWeather,
                selectedDate: selectedDate,
                isLoading: isForecastLoading,
                unavailableMessage: forecastUnavailableMessage,
                retry: nil
            ),
            tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline(
                city: cityWeather,
                selectedDate: $selectedDate,
                isLoading: isForecastLoading,
                unavailableMessage: forecastUnavailableMessage,
                retry: hasForecastRequestFailure
                    ? { retryForecast() }
                    : nil
            ),
            temperatureUnit: temperatureUnit,
            maximumContentWidth: 760,
            showsTimeZoneFootnote: true,
            onHeaderVisibilityChange: { isVisible in
                showsLargeTitle = isVisible
            }
        ) {
            EmptyView()
        } footerContent: {
            savedPlaceAction
        }
        .background(
            theme.colors.weatherBackgroundColor(
                for: forecast?.condition?.iconTone
            )
        )
        .refreshable {
            guard let city else { return }
            await model.weatherStore.refresh(city: city)
        }
        .weatherConditionScreenBackground(
            for: forecast?.condition?.iconTone
        )
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsLargeTitle {
                // Reserve the principal title slot while the large content
                // heading is visible, preventing a duplicate title in the bar.
                ToolbarItem(placement: .principal) {
                    Color.clear
                        .frame(width: 1, height: 1)

                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                // Persistence stays in the report footer, leaving forecast
                // navigation as the toolbar's single trailing control.
                TopForecastDateSwitcher(
                    selection: $selectedDate,
                    availableDates: ForecastDateHorizon.dates(in: model.forecastCalendar)
                )
            }
        }
        .task(id: placeID) {
            // The repository owns caching and transient request retries. Detail
            // starts the normal lookup once; each card handles an optional input
            // locally without triggering another WeatherKit request.
            showsLargeTitle = true
            guard let city else {
                return
            }

            _ = await model.weatherStore.lookup(
                city: city
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
            await model.weatherStore.refresh(city: city)
        }
    }

    // MARK: Saved-Place Actions

    /// The report ends with the same quiet secondary text-action language as
    /// Saved Places. Saving or deleting updates this control in place without
    /// leaving the detail screen.
    @ViewBuilder
    private var savedPlaceAction: some View {
        if savedPlace == nil {
            Button {
                savePlace()
            } label: {
                SecondaryTextActionLabel(
                    title: "Save Place",
                    systemImage: "bookmark",
                    iconIsLeading: true
                )
            }
            .buttonStyle(.plain)
        } else {
            Button(role: .destructive) {
                deleteSavedPlace()
            } label: {
                SecondaryTextActionLabel(
                    title: "Delete from Saved Places",
                    systemImage: "trash",
                    iconIsLeading: true
                )
            }
            .buttonStyle(.plain)
        }
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
                message: localizedPlacesErrorDescription(error)
            )
        }
    }

    private func deleteSavedPlace() {
        guard let savedPlace else { return }
        // The report may have been opened from the saved-place manager, whose
        // city is otherwise no longer discoverable once its persistence row is
        // removed. Retain a transient lookup source so this same report can
        // immediately offer Save Place again rather than becoming blank.
        let city = savedPlace.city
        do {
            model.registerTransientCity(city)
            try model.placesStore.deletePlace(id: savedPlace.id)
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(error)
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
    @ScaledMetric(relativeTo: .body)
    private var sunStatusHeight: CGFloat = 20

    /// Retain the live sun-status vocabulary for today's forecast. Only the
    /// original “Sunny for …” result (a non-today total) takes the shared Map
    /// card treatment below.
    private var sunStatus: SunnyHoursCalculation.DailySunStatus? {
        guard let weather,
              let forecast,
              case .success(let data) = SunnyHoursCalculation.sunnyHoursData(
                for: forecast,
                timeZone: weather.timeZone
              ) else {
            return nil
        }
        return SunnyHoursCalculation.dailySunStatus(
            in: data,
            selectedDate: forecast.date,
            timeZone: weather.timeZone,
            selectionCalendar: calendar
        )
    }

    private func sunStatusText(
        for sunStatus: SunnyHoursCalculation.DailySunStatus
    ) -> String {
        switch sunStatus {
        case .sunnyForHours(let count):
            return SunnyHoursStatusLine.statusText(hours: count, locale: locale)
        case .sunOutNow:
            return sunOutNowText
        case .sunOutIn(let date):
            return "\(sunOutInPrefix) \(countdownText(to: date))"
        case .noSunToday:
            if let nextSunnyRelativeDateText {
                return String(
                    format: localizedString(
                        "There’s no sun today. Sun coming out %@.",
                        locale: locale
                    ),
                    locale: locale,
                    nextSunnyRelativeDateText
                )
            }
            return localizedString("No Sun Today", locale: locale)
        case .noMoreSunToday:
            if let nextSunnyRelativeDateText {
                return String(
                    format: localizedString(
                        "There’s no more sun today. Sun coming out %@.",
                        locale: locale
                    ),
                    locale: locale,
                    nextSunnyRelativeDateText
                )
            }
            return localizedString("No More Sun Today", locale: locale)
        case .noSunOnSelectedDay:
            return localizedString("No Sun on this day", locale: locale)
        }
    }

    /// Formats the next proven sunny forecast relative to the selected
    /// city-local day, yielding locale-native copy such as “tomorrow” or
    /// “in 2 days” without assembling translated date fragments by hand.
    private var nextSunnyRelativeDateText: String? {
        guard let weather,
              let forecast,
              let nextDate = SunnyHoursCalculation.nextSunnyForecastDate(
                after: forecast,
                in: weather.dailyForecasts,
                timeZone: weather.timeZone,
                selectionCalendar: calendar
              ) else {
            return nil
        }

        var cityCalendar = calendar
        cityCalendar.timeZone = weather.timeZone
        return Date.AnchoredRelativeFormatStyle(
            anchor: nextDate,
            allowedFields: [.day],
            presentation: .named,
            unitsStyle: .wide,
            locale: locale,
            calendar: cityCalendar,
            capitalizationContext: .middleOfSentence
        ).format(forecast.date)
    }

    /// Detail-only sentence casing keeps the status line calm beneath the
    /// large weather icon without changing the title-style widget strings.
    private var sunOutNowText: String {
        localizedString("Sun out now", locale: locale)
    }

    private var sunOutInPrefix: String {
        localizedString("Sun out in", locale: locale)
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
                        .contentTransition(.symbolEffect(.replace))
                        .animation(
                            .spring(
                                response: 0.34,
                                dampingFraction: 0.78
                            ),
                            value: icon
                        )

                } else {
                    Color.clear
                        .frame(
                            width: conditionIconWidth,
                            height: conditionPlaceholderHeight
                        )

                }

                Group {
                    if let sunStatus {
                        switch sunStatus {
                        case .sunnyForHours(let count):
                            SunnyHoursStatusLine(hours: count)
                        case .sunOutNow:
                            HStack(spacing: 3) {
                                Image(systemName: "sun.max")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.colors.dotSun)


                                Text(sunOutNowText)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.colors.dotSun)
                            }


                        case .sunOutIn(let date):
                            HStack(spacing: 3) {
                                Image(systemName: "sun.max")
                                    .font(.body.weight(.regular))
                                    .foregroundStyle(theme.colors.secondaryText)


                                HStack(spacing: 0) {
                                    Text("\(sunOutInPrefix) ")
                                        .font(.body)
                                        .foregroundStyle(theme.colors.secondaryText)

                                    Text(countdownText(to: date))
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(theme.colors.dotSun)
                                }
                            }


                        default:
                            Text(sunStatusText(for: sunStatus))
                                // Keep the neutral status copy on the same body
                                // baseline as the non-emphasized text in the
                                // other status variants. The yellow, emphasized
                                // spans retain their own styling.
                                .font(.body)
                                .foregroundStyle(theme.colors.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .frame(minHeight: sunStatusHeight)
            } else {
                Color.clear
                    .frame(
                        width: conditionIconWidth,
                        height: conditionPlaceholderHeight
                    )


                Color.clear
                    .frame(height: sunStatusHeight)

            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)




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
