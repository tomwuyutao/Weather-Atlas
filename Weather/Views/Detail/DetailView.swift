//
//  DetailView.swift
//  Weather
//
//  Purpose: Composes the shared card-based forecast report for current and
//  saved locations.
//

import CoreLocation
import SwiftUI

// MARK: - Report Color Resolution

/// The report canvas must use the same source that powers the large header
/// symbol. In particular, a clear night has a `.clear` condition but a moon
/// symbol, which intentionally uses the purple night color.
private func detailScreenColorSource(
    weather: CityWeather?,
    forecast: DailyForecast?
) -> (tone: WeatherIconTone?, symbolName: String?) {
    guard let forecast else { return (nil, nil) }

    if let weather,
       let displayedCondition = weather.displayedCondition(for: forecast) {
        return (
            displayedCondition.condition?.iconTone,
            displayedCondition.symbolName
        )
    }

    if weather != nil {
        // A current-local-day cache without a live observation must not use
        // the daily forecast to tint the page or imply a condition icon.
        return (nil, nil)
    }

    return (
        forecast.condition?.iconTone,
        forecast.symbolName.isEmpty ? nil : forecast.symbolName
    )
}

/// Keeps every large in-content report heading aligned across Detail, Your
/// Location, and Saved Places while still leaving phone room for the tab bar.
func detailStyleTitleTopPadding(
    for size: CGSize,
    dynamicTypeSize: DynamicTypeSize
) -> CGFloat {
    guard UIDevice.current.userInterfaceIdiom == .phone,
          !dynamicTypeSize.isAccessibilitySize else {
        return 8
    }
    return min(52, max(8, size.height * 0.055))
}

/// The split report needs enough room for a readable 40% summary pane and a
/// 60% detail pane after the latter's horizontal reading insets are applied.
/// Smaller Stage Manager and Split View windows retain the phone-style flow.
enum LandscapeReportLayout {
    static let minimumWidth: CGFloat = 960

    static func usesSplit(for size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad
            && size.width > size.height
            && size.width >= minimumWidth
    }
}

/// Landscape panes have fixed neighbouring content, so iOS 26's default
/// scroll-edge material reads as an unwanted solid mask rather than a screen
/// transition. Older systems do not add that effect.
private struct LandscapePaneScrollEdgeEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(for: .vertical)
        } else {
            content
        }
    }
}

extension View {
    func hidesLandscapePaneScrollEdgeEffects() -> some View {
        modifier(LandscapePaneScrollEdgeEffectModifier())
    }
}

// MARK: - Shared Detail Report

/// The common forecast-report canvas used by a saved/discovered place and the
/// current physical location. The owning screen still supplies its own loading,
/// permission, retry, and supplementary content; this type only owns the
/// report UI that is genuinely identical between those flows.
struct DetailReportContent<HeaderAccessory: View, SupplementaryContent: View>: View {
    // MARK: - Inputs and Environment

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
    let sectionOrder: [DetailReportSection]
    private let onHeaderVisibilityChange: (Bool) -> Void
    private let headerAccessory: HeaderAccessory
    private let supplementaryContent: SupplementaryContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // MARK: - Initialization

    init(
        locationName: String,
        placeDisplayName: String? = nil,
        weather: CityWeather?,
        forecast: DailyForecast?,
        selectedDate: Binding<Date>,
        dailySunnyHoursCard: SunnyHoursTimeline,
        tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline,
        temperatureUnit: TemperatureUnit,
        maximumContentWidth: CGFloat = AppContentLayout.standardMaximumWidth,
        showsTimeZoneFootnote: Bool,
        sectionOrder: [DetailReportSection],
        onHeaderVisibilityChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder supplementaryContent: () -> SupplementaryContent
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
        self.sectionOrder = sectionOrder
        self.onHeaderVisibilityChange = onHeaderVisibilityChange
        self.headerAccessory = headerAccessory()
        self.supplementaryContent = supplementaryContent()
    }

    // MARK: - Presentation

    var body: some View {
        GeometryReader { geometry in
            let usesLandscapeIPadSplit = LandscapeReportLayout.usesSplit(
                for: geometry.size
            )
            let topPadding = detailStyleTitleTopPadding(
                for: geometry.size,
                dynamicTypeSize: dynamicTypeSize
            )

            if usesLandscapeIPadSplit {
                reportLayout(
                    usesLandscapeIPadSplit: true,
                    centersDailyTimeline: UIDevice.current.userInterfaceIdiom == .pad,
                    landscapeContentWidth: geometry.size.width - 32,
                    landscapeContentHeight: geometry.size.height - topPadding - 24
                )
                .padding(.horizontal, 16)
                .padding(.top, topPadding)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    reportLayout(
                        usesLandscapeIPadSplit: false,
                        centersDailyTimeline: UIDevice.current.userInterfaceIdiom == .pad,
                        landscapeContentWidth: 0,
                        landscapeContentHeight: 0
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, topPadding)
                    .padding(.bottom, 24)
                    .frame(maxWidth: reportContentWidth(for: geometry.size))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Report Sections

    @ViewBuilder
    private func reportLayout(
        usesLandscapeIPadSplit: Bool,
        centersDailyTimeline: Bool,
        landscapeContentWidth: CGFloat,
        landscapeContentHeight: CGFloat
    ) -> some View {
        if usesLandscapeIPadSplit {
            let splitWidth = max(0, landscapeContentWidth - 20)
            let leftColumnWidth = splitWidth * 0.4
            let rightColumnWidth = splitWidth - leftColumnWidth
            let rightColumnContentInset: CGFloat = 80
            let timelineHeight: CGFloat = 100
            let timelineTopSpacing: CGFloat = 48
            let headerHeight = max(
                0,
                landscapeContentHeight - timelineHeight - timelineTopSpacing
            )

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 0) {
                    reportHeader(landscapeHeight: headerHeight)
                    dailyTimeline(
                        centersInItsColumn: centersDailyTimeline,
                        constrainsLandscapeHeight: true
                    )
                        // Preserve the timeline's natural height while giving
                        // the left column deliberate visual separation.
                        .padding(.top, 48)
                }
                .frame(height: landscapeContentHeight, alignment: .top)
                .frame(width: leftColumnWidth, alignment: .top)
                // Balance the visual weight introduced by the right column's
                // large leading inset without changing either column's width.
                .offset(x: rightColumnContentInset / 2)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        reportDetails
                    }
                    // Insets belong inside the fixed 60% column so they limit
                    // readable line length without widening the split itself.
                    .padding(.horizontal, rightColumnContentInset)
                    .frame(width: rightColumnWidth, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .hidesLandscapePaneScrollEdgeEffects()
                .scrollClipDisabled()
                .frame(height: landscapeContentHeight)
                .frame(width: rightColumnWidth, alignment: .top)
            }
        } else {
            LazyVStack(spacing: 14) {
                reportHeader()
                dailyTimeline(
                    centersInItsColumn: centersDailyTimeline,
                    constrainsLandscapeHeight: false
                )
                reportDetails
            }
        }
    }

    private func reportHeader(landscapeHeight: CGFloat? = nil) -> some View {
        LocationReportHeader(
            locationName: locationName,
            weather: weather,
            forecast: forecast,
            landscapeHeight: landscapeHeight,
            landscapeConditionVerticalOffset: landscapeHeight == nil ? 0 : 18
        ) {
            headerAccessory
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible in
            onHeaderVisibilityChange(isVisible)
        }
    }

    @ViewBuilder
    private func dailyTimeline(
        centersInItsColumn: Bool,
        constrainsLandscapeHeight: Bool
    ) -> some View {
        dailySunnyHoursCard
            // The phone-width chart keeps capsule dimensions and gaps stable
            // on iPad instead of using surplus column width to stretch them.
            .frame(maxWidth: centersInItsColumn ? 400 : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            // The shared capsule chart uses GeometryReader for its track. Give
            // it an explicit landscape height so a split-column proposal never
            // turns the capsules into a full-height timeline.
            .frame(height: constrainsLandscapeHeight ? 100 : nil)
    }

    @ViewBuilder
    private var reportDetails: some View {
        ForEach(sectionOrder) { section in
            reportSection(section)
        }

        // Local-time context qualifies the complete report rather than only
        // the ten-day card, so it always follows every movable section.
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
    }

    @ViewBuilder
    private func reportSection(_ section: DetailReportSection) -> some View {
        switch section {
        case .tenDaySunnyHours:
            tenDaySunnyHoursTimeline
        case .basicWeatherData:
            DetailMetricGrid(
                city: weather,
                forecast: forecast,
                temperatureUnit: temperatureUnit,
                usesLandscapeIPadLayout: false,
                selectedForecastDate: $selectedDate
            )
        case .nearbySunnyPlaces:
            supplementaryContent
        }
    }

    // MARK: - Responsive Layout

    /// Phone and portrait layouts retain the established focused report width.
    private func reportContentWidth(for size: CGSize) -> CGFloat {
        AppContentLayout.maximumWidth(
            for: size,
            horizontalSizeClass: horizontalSizeClass,
            standardMaximumWidth: maximumContentWidth
        )
    }
}

// MARK: - Route Preview

#if DEBUG
#Preview("Detail View") {
    DetailViewRoutePreview()
}
#endif

// MARK: - Current Location Report

/// Current-location presentation built from the same report canvas as a
/// saved-place detail. Location permission and refresh lifecycle remain in
/// `YourLocationView`; this type only adapts their live values into report UI.
struct CurrentLocationReportContent: View {
    // MARK: - Inputs and Presentation State

    let model: WeatherModel
    let router: AppNavigation
    @Binding var selectedDate: Date
    let requestCurrentLocation: () -> Void
    let openLocationSettings: () -> Void
    let refreshCurrentLocation: () -> Void

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(NetworkConnectivity.self) private var networkConnectivity
    /// Mirrors a place report's compact title once its in-content hero scrolls
    /// away, without showing a duplicate title while the hero is visible.
    @State private var showsLargeTitle = true
    @State private var mutationError: PlaceDetailMutationError?
    @State private var presentedSheet: PlaceDetailSheet?
    @AppStorage(DetailReportSection.storageKey)
    private var storedDetailSectionOrder =
        DetailReportSection.defaultStorageValue
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    // MARK: - Derived Report Values

    private var locationWeather: CityWeather? {
        model.locationWeather
    }

    private var selectedForecast: DailyForecast? {
        locationWeather?.forecastIfAvailable(
            on: selectedDate,
            selectionCalendar: calendar
        )
    }

    /// Weather supplies the most recently resolved current-location city. A
    /// configured home location remains usable while its weather is loading.
    private var locationCity: City? {
        model.currentLocationPlaceCity
    }

    private var savedPlace: SavedPlace? {
        guard let locationCity,
              let savedID = model.placesStore.savedPlaceID(
                matching: locationCity
              ) else {
            return nil
        }
        return model.placesStore.place(id: savedID)
    }

    private var locationName: String {
        model.currentLocationDisplayName(locale: locale)
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var detailSectionOrder: [DetailReportSection] {
        DetailReportSection.order(from: storedDetailSectionOrder)
    }

    /// A confirmed offline path is a settled unavailable state. This keeps a
    /// request that was interrupted while iOS evaluated reachability from
    /// holding either current-location timeline on a spinner indefinitely.
    private var isLocationForecastLoading: Bool {
        model.isRefreshingLocation && !networkConnectivity.isOffline
    }

    private var locationForecastUnavailableMessage: String? {
        guard locationWeather == nil else { return nil }
        if networkConnectivity.isOffline {
            return localizedString(
                "Weather is temporarily unavailable.",
                locale: locale
            )
        }
        return model.locationError
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

    private var screenColorSource: (
        tone: WeatherIconTone?,
        symbolName: String?
    ) {
        detailScreenColorSource(
            weather: locationWeather,
            forecast: selectedForecast
        )
    }

    // MARK: - Presentation

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
                isLoading: isLocationForecastLoading,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                retry: refreshCurrentLocation
            ),
            tenDaySunnyHoursTimeline: TenDaySunnyHoursTimeline(
                city: locationWeather,
                selectedDate: $selectedDate,
                isLoading: isLocationForecastLoading,
                unavailableMessage: locationForecastUnavailableMessage,
                retry: nil
            ),
            temperatureUnit: temperatureUnit,
            maximumContentWidth: AppContentLayout.standardMaximumWidth,
            showsTimeZoneFootnote: true,
            sectionOrder: detailSectionOrder,
            onHeaderVisibilityChange: { isVisible in
                guard showsLargeTitle != isVisible else { return }
                showsLargeTitle = isVisible
            },
            headerAccessory: {
                placeActionsMenu
            }
        ) {
            NearbySunnyPlacesSection(
                model: model,
                selectedDate: selectedDate,
                reference: .currentLocation,
                requestLocation: requestCurrentLocation,
                openSettings: openLocationSettings,
                viewOnMap: {
                    router.showMap(
                        findingSunIn: .nearMe,
                        on: selectedDate
                    )
                }
            )
        }
        .scrollIndicators(.hidden)
        .weatherConditionScreenBackground(
            for: screenColorSource.tone,
            symbolName: screenColorSource.symbolName
        )
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .customize:
                CustomizeDetail()
            }
        }
        .toolbar {
            // Keep the toolbar preference tree stable while scrolling. Adding
            // and removing the principal item in response to header visibility
            // can feed layout back into visibility on iPad when report content
            // changes height (for example, when nearby results arrive).
            ToolbarItem(placement: .principal) {
                Text(navigationTitle)
                    .lineLimit(1)
                    .opacity(showsLargeTitle ? 0 : 1)
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
        // A legacy current-location row can have been saved before the more
        // precise locality arrived. Repair only that exact transient UUID;
        // ordinary saved catalog cities are not candidates for this migration.
        .task(id: locationCity) {
            do {
                try model.synchronizeSavedCurrentLocationIdentity()
            } catch {
                mutationError = PlaceDetailMutationError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
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

    // MARK: - Place Actions

    private var placeActionsMenu: some View {
        PlaceDetailActionsMenu(
            isSaved: savedPlace != nil,
            canUsePlace: locationCity != nil,
            viewOnMap: viewOnMap,
            savePlace: savePlace,
            removePlace: removeSavedPlace,
            customizeDetailView: {
                presentedSheet = .customize
            }
        )
    }

    private var showsMutationError: Binding<Bool> {
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
        guard let locationCity else { return }
        do {
            _ = try model.placesStore.savePlace(locationCity)
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(error, locale: locale)
            )
        }
    }

    private func removeSavedPlace() {
        guard let savedPlace else { return }
        do {
            try model.placesStore.deletePlace(id: savedPlace.id)
        } catch {
            mutationError = PlaceDetailMutationError(
                message: localizedPlacesErrorDescription(error, locale: locale)
            )
        }
    }

    private func viewOnMap() {
        guard let locationCity else { return }
        if let savedPlace {
            router.showMap(placeID: savedPlace.id)
        } else {
            router.showMap(previewing: locationCity)
        }
    }
}

// MARK: - Nearby Recommendation Adapter

/// Identifies both the geographic center and sunny-hours baseline for the card.
private enum NearbySunnyPlacesReference {
    case currentLocation
    case place(city: City?, displayName: String)
}

/// Keeps nearby ranking and repository observation below the lazy report
/// boundary. Weather updates no longer make an entire report scan every nearby
/// candidate while this lower card is offscreen.
private struct NearbySunnyPlacesSection: View {
    let model: WeatherModel
    let selectedDate: Date
    let reference: NearbySunnyPlacesReference
    let requestLocation: () -> Void
    let openSettings: () -> Void
    let viewOnMap: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        NearbySunnyPlacesCard(
            recommendations: recommendations,
            locationStatus: model.locationProvider.status,
            requiresCurrentLocation: requiresCurrentLocation,
            distanceReferenceName: distanceReferenceName,
            isLoading: isLoading,
            hasCompletedSearch: hasCompletedSearch,
            errorMessage: errorMessage,
            requestLocation: requestLocation,
            openSettings: openSettings,
            viewOnMap: viewOnMap
        )
    }

    // MARK: Search-State Selection

    private var recommendations: [NearestSunnyPlaceResult] {
        switch reference {
        case .currentLocation:
            return model.nearbyRecommendations(
                on: selectedDate,
                locale: locale
            )
        case .place(let city, _):
            guard let city else { return [] }
            return model.nearbyRecommendations(
                around: city,
                on: selectedDate,
                locale: locale
            )
        }
    }

    private var requiresCurrentLocation: Bool {
        if case .currentLocation = reference { return true }
        return false
    }

    private var distanceReferenceName: String? {
        guard case .place(_, let displayName) = reference else { return nil }
        return displayName
    }

    private var hasMatchingPlaceSearch: Bool {
        guard case .place(let city, _) = reference,
              let city else { return false }
        return model.placeNearbySearchOriginID == city.id
    }

    private var isLoading: Bool {
        switch reference {
        case .currentLocation:
            model.isSearchingNearby
        case .place:
            hasMatchingPlaceSearch && model.isSearchingPlaceNearby
        }
    }

    private var hasCompletedSearch: Bool {
        switch reference {
        case .currentLocation:
            model.didSearchNearby
        case .place:
            hasMatchingPlaceSearch && model.didSearchPlaceNearby
        }
    }

    private var errorMessage: String? {
        switch reference {
        case .currentLocation:
            model.nearbySearchError
        case .place:
            hasMatchingPlaceSearch ? model.placeNearbySearchError : nil
        }
    }
}

// MARK: - Saved Place Report

/// Restarts a route's skipped lookup once reachability has been evaluated or
/// recovered, without rebuilding the surrounding navigation destination.
private struct PlaceForecastTaskID: Hashable {
    let placeID: City.ID
    let connectivityStatus: NetworkConnectivityStatus
}

/// Shared value-routed report for saved and discovered places.
struct DetailView: View {
    // MARK: - Route Inputs and View State

    /// Stable identity carried by AppRoute rather than a replaceable snapshot.
    let placeID: City.ID
    /// Root domain model used to resolve the latest place and forecast values.
    let model: WeatherModel
    /// Shared navigation coordinator used by the nearby card's recovery and
    /// Map actions.
    let router: AppNavigation
    /// App-wide forecast day controlled by the tab-bar date accessory.
    @Binding private var selectedDate: Date
    /// Optional payload drives the error alert after a persistence mutation.
    @State private var mutationError: PlaceDetailMutationError?
    /// Item-driven presentation keeps the customization workflow separate
    /// from the menu that launches it.
    @State private var presentedSheet: PlaceDetailSheet?
    /// Hides the duplicate compact navigation title while the large in-content
    /// heading is visible at the top of the scrolling report.
    @State private var showsLargeTitle = true
    /// A transient Detail lookup is not part of root saved/current recovery.
    /// Remember an offline interruption so this route can supersede its own
    /// older repository task when connectivity returns.
    @State private var forecastWasInterruptedByOffline = false

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @Environment(NetworkConnectivity.self) private var networkConnectivity
    @AppStorage(DetailReportSection.storageKey)
    private var storedDetailSectionOrder =
        DetailReportSection.defaultStorageValue
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue

    init(
        placeID: City.ID,
        selectedDate: Binding<Date>,
        model: WeatherModel,
        router: AppNavigation
    ) {
        // Routes carry only `placeID`; resolve the live model values below so
        // an open report reflects edits and refreshed forecasts immediately.
        self.placeID = placeID
        self.model = model
        self.router = router
        _selectedDate = selectedDate
    }

    // MARK: - Live Model Resolution

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

    private var detailSectionOrder: [DetailReportSection] {
        DetailReportSection.order(from: storedDetailSectionOrder)
    }

    private var isForecastLoading: Bool {
        guard let city else { return false }
        guard !networkConnectivity.isOffline else { return false }
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
        if cityWeather == nil, networkConnectivity.isOffline {
            return localizedString(
                "Weather is temporarily unavailable.",
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

    private var screenColorSource: (
        tone: WeatherIconTone?,
        symbolName: String?
    ) {
        detailScreenColorSource(weather: cityWeather, forecast: forecast)
    }

    // MARK: - Presentation and Loading

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
            maximumContentWidth: AppContentLayout.standardMaximumWidth,
            showsTimeZoneFootnote: true,
            sectionOrder: detailSectionOrder,
            onHeaderVisibilityChange: { isVisible in
                guard showsLargeTitle != isVisible else { return }
                showsLargeTitle = isVisible
            },
            headerAccessory: {
                placeActionsMenu
            }
        ) {
            NearbySunnyPlacesSection(
                model: model,
                selectedDate: selectedDate,
                reference: .place(
                    city: city,
                    displayName: displayName
                ),
                requestLocation: {
                    model.useCurrentLocation(preferredLocale: locale)
                },
                openSettings: {
                    router.presentedSheet = .settings
                },
                viewOnMap: {
                    guard let city else { return }
                    router.showMap(
                        findingSunIn: .nearPlace(city),
                        on: selectedDate
                    )
                }
            )
        }
        .background(
            theme.colors.weatherBackgroundColor(
                for: screenColorSource.tone,
                symbolName: screenColorSource.symbolName
            )
        )
        .refreshable {
            guard let city else { return }
            await model.weatherStore.refresh(city: city)
            guard !Task.isCancelled else { return }
            await model.searchNearbyPlaces(
                around: city,
                forceRefresh: true,
                locale: locale
            )
        }
        .weatherConditionScreenBackground(
            for: screenColorSource.tone,
            symbolName: screenColorSource.symbolName
        )
        .navigationTitle(detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Keep one principal item mounted so scroll-driven title changes
            // update only its value, not the toolbar preference structure.
            ToolbarItem(placement: .principal) {
                Text(detailTitle)
                    .lineLimit(1)
                    .opacity(showsLargeTitle ? 0 : 1)
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
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .customize:
                CustomizeDetail()
            }
        }
        .onChange(of: networkConnectivity.status, initial: true) { _, status in
            if status == .offline {
                forecastWasInterruptedByOffline = true
            }
        }
        // Full-detail navigation from Nearby Sunnier Places, Find Sun results,
        // and Map cards converges here. Keep this independent from the forecast
        // task so a connectivity transition cannot falsely refresh recency.
        .task(id: city) {
            guard let city else { return }
            model.recordRecentCityAccess(city)
        }
        .task(
            id: PlaceForecastTaskID(
                placeID: placeID,
                connectivityStatus: networkConnectivity.status
            )
        ) {
            // The repository owns caching and transient request retries. Detail
            // starts the normal lookup once; each card handles an optional input
            // locally without triggering another WeatherKit request.
            showsLargeTitle = true
            guard networkConnectivity.status == .available,
                  let city else {
                return
            }

            _ = await model.weatherStore.lookup(
                city: city,
                forceRefresh: forecastWasInterruptedByOffline
            )
            guard !Task.isCancelled,
                  networkConnectivity.status == .available else {
                return
            }
            forecastWasInterruptedByOffline = false
            await model.searchNearbyPlaces(
                around: city,
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

    // MARK: - Forecast Recovery

    private func retryForecast() {
        guard let city else { return }
        Task {
            await model.weatherStore.refresh(city: city)
        }
    }

    // MARK: - Place Actions

    private var placeActionsMenu: some View {
        PlaceDetailActionsMenu(
            isSaved: savedPlace != nil,
            canUsePlace: city != nil,
            viewOnMap: viewOnMap,
            savePlace: savePlace,
            removePlace: deleteSavedPlace,
            customizeDetailView: {
                presentedSheet = .customize
            }
        )
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
                message: localizedPlacesErrorDescription(error, locale: locale)
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
                message: localizedPlacesErrorDescription(error, locale: locale)
            )
        }
    }

    private func viewOnMap() {
        guard let city else { return }
        if savedPlace != nil {
            router.showMap(placeID: placeID)
        } else {
            router.showMap(previewing: city)
        }
    }

}

// MARK: - Place Detail Menu

private enum PlaceDetailSheet: String, Identifiable {
    case customize

    var id: String { rawValue }
}

/// Secondary city-specific actions live with the large city title so the
/// navigation bar remains dedicated to forecast navigation.
private struct PlaceDetailActionsMenu: View {
    let isSaved: Bool
    let canUsePlace: Bool
    let viewOnMap: () -> Void
    let savePlace: () -> Void
    let removePlace: () -> Void
    let customizeDetailView: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            Button("View on Map", systemImage: "map", action: viewOnMap)
                .disabled(!canUsePlace)

            if isSaved {
                Button(role: .destructive, action: removePlace) {
                    // Native menus can tint the destructive title without
                    // tinting its template icon, so style both explicitly.
                    Label(
                        "Remove from Saved Places",
                        systemImage: "bookmark.slash"
                    )
                    .foregroundStyle(theme.colors.destructive)
                }
                .tint(theme.colors.destructive)
            } else {
                Button("Save Place", systemImage: "bookmark", action: savePlace)
                    .disabled(!canUsePlace)
            }

            Divider()

            Button(
                "Customize Detail View",
                systemImage: "arrow.up.arrow.down",
                action: customizeDetailView
            )
        } label: {
            Label("Place Actions", systemImage: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 28, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mutation Alert Payload

/// Item-driven native error presentation for persistence mutations.
private struct PlaceDetailMutationError: Identifiable {
    let id = UUID()
    let message: String
}

/// Shared large heading treatment used by forecast reports and planning views.
struct DetailStyleReportTitle: View {
    let title: String
    let horizontalPadding: CGFloat

    @Environment(\.appTheme) private var theme
    @ScaledMetric(relativeTo: .largeTitle)
    private var titleMinimumHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .largeTitle)
    private var titleToContentGap: CGFloat = 8

    init(title: String, horizontalPadding: CGFloat = 34) {
        self.title = title
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        Text(title)
            .font(.system(.largeTitle, design: .serif).weight(.bold))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, titleToContentGap)
            .frame(minHeight: titleMinimumHeight)
    }
}

// MARK: - Report Header

/// Large in-content heading shared by every forecast report.
struct LocationReportHeader<HeaderAccessory: View>: View {
    // MARK: - Inputs and Scaled Layout

    let locationName: String
    let weather: CityWeather?
    let forecast: DailyForecast?
    /// The landscape left column supplies its available header space so the
    /// condition summary can sit independently of the title and timeline.
    let landscapeHeight: CGFloat?
    let landscapeConditionVerticalOffset: CGFloat
    private let headerAccessory: HeaderAccessory

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
    @ScaledMetric(relativeTo: .body)
    private var sunStatusHeight: CGFloat = 20

    init(
        locationName: String,
        weather: CityWeather?,
        forecast: DailyForecast?,
        landscapeHeight: CGFloat?,
        landscapeConditionVerticalOffset: CGFloat,
        @ViewBuilder headerAccessory: () -> HeaderAccessory
    ) {
        self.locationName = locationName
        self.weather = weather
        self.forecast = forecast
        self.landscapeHeight = landscapeHeight
        self.landscapeConditionVerticalOffset =
            landscapeConditionVerticalOffset
        self.headerAccessory = headerAccessory()
    }

    // MARK: - Sunny-Hours Status

    /// Retain the live sun-status vocabulary for today's forecast. Only the
    /// “Sunny for …” result (a non-today total) takes the shared Map
    /// card treatment below.
    private var sunStatus: SunnyHoursCalculation.DailySunStatus? {
        guard let weather,
              let forecast else {
            return nil
        }
        let data = SunnyHoursCalculation.sunnyHoursData(
            for: forecast,
            timeZone: weather.timeZone
        )
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
            return sunOutInText(to: date)
        case .noSunToday:
            if let sunlessForecastHorizonText = sunlessForecastHorizonText(
                "No sun in the next %lld days."
            ) {
                return sunlessForecastHorizonText
            }
            if let nextSunnyRelativeDateText {
                return String(
                    format: localizedString(
                        "No sun today. Sun coming out %@.",
                        locale: locale
                    ),
                    locale: locale,
                    nextSunnyRelativeDateText
                )
            }
            return localizedString("No Sun Today", locale: locale)
        case .noMoreSunToday:
            if let sunlessForecastHorizonText = sunlessForecastHorizonText(
                "No more sun in the next %lld days."
            ) {
                return sunlessForecastHorizonText
            }
            if let nextSunnyRelativeDateText {
                return String(
                    format: localizedString(
                        "No more sun today. Sun coming out %@.",
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

    /// A forecast-wide sunless message is only safe when every later forecast
    /// day is present, assessable, and has no sunny interval. The current day
    /// is included in the displayed horizon, so this reads naturally as “the
    /// next 10 days” for a ten-day forecast beginning today.
    private func sunlessForecastHorizonText(
        _ key: String.LocalizationValue
    ) -> String? {
        guard let weather,
              let forecast,
              let followingDayCount = SunnyHoursCalculation
                .followingSunlessForecastDayCount(
                    after: forecast,
                    in: weather.dailyForecasts,
                    timeZone: weather.timeZone,
                    selectionCalendar: calendar
                ), followingDayCount > 0 else {
            return nil
        }

        let horizonDayCount = followingDayCount + 1
        return String(
            format: localizedString(key, locale: locale),
            locale: locale,
            Int64(horizonDayCount)
        )
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

    /// Treats the duration as a localized placeholder rather than appending it
    /// to an English-order prefix. This also supplies the unstyled version used
    /// by fallback status presentation.
    private func sunOutInText(to date: Date) -> String {
        let duration = countdownText(to: date)
        var resource: LocalizedStringResource = "Sun out in \(duration)"
        resource.locale = locale
        return String(localized: resource)
    }

    /// The same complete sentence as `sunOutInText(to:)`, with only the
    /// duration emphasized. Attributed-string interpolation preserves that run
    /// if a translation moves the placeholder before the surrounding copy.
    private func attributedSunOutInText(to date: Date) -> AttributedString {
        var emphasizedDuration = AttributedString(countdownText(to: date))
        emphasizedDuration.font = .body.weight(.semibold)
        emphasizedDuration.foregroundColor = theme.colors.dotSun

        var resource: LocalizedStringResource = "Sun out in \(emphasizedDuration)"
        resource.locale = locale
        return AttributedString(localized: resource)
    }

    // MARK: - Displayed Condition

    /// The Detail header is the one report element that represents the live
    /// observation when the selected forecast is the city's local Today. Do
    /// not substitute the daily summary if a legacy cache lacks the observation.
    private var displayedCondition: (
        symbolName: String,
        tone: WeatherIconTone
    )? {
        guard let forecast else { return nil }

        if let weather,
           let displayedCondition = weather.displayedCondition(for: forecast) {
            return (
                displayedCondition.symbolName,
                displayedCondition.condition?.iconTone ?? .cloudy
            )
        }

        if weather != nil { return nil }

        guard !forecast.symbolName.isEmpty else { return nil }
        return (forecast.symbolName, forecast.condition?.iconTone ?? .cloudy)
    }

    // MARK: - Presentation

    var body: some View {
        if let landscapeHeight {
            ZStack(alignment: .top) {
                conditionAndStatus
                    .frame(maxHeight: .infinity, alignment: .center)
                    .offset(y: landscapeConditionVerticalOffset)

                locationTitle
            }
            .frame(maxWidth: .infinity)
            .frame(height: landscapeHeight)
            .padding(.top, 4)
            .padding(.bottom, 4)
        } else {
            VStack(spacing: 9) {
                locationTitle
                conditionAndStatus
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }

    private var locationTitle: some View {
        HStack(alignment: .top, spacing: 2) {
            DetailStyleReportTitle(
                title: locationName,
                horizontalPadding: 0
            )
            headerAccessory
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity)
    }

    private var conditionAndStatus: some View {
        VStack(spacing: 9) {
            if let displayedCondition {
                // Today's header uses the exact live WeatherKit observation;
                // other selected days use their exact daily forecast symbol.
                let icon = displayedCondition.symbolName
                Image(systemName: icon)
                    .weatherIconStyle(
                        for: displayedCondition.tone,
                        symbolName: icon
                    )
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

                            Text(attributedSunOutInText(to: date))
                                .font(.body)
                                .foregroundStyle(theme.colors.secondaryText)
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
        }
    }

    // MARK: - Countdown Formatting

    private func countdownText(to date: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        formatter.calendar = localizedCalendar
        return formatter.string(
            from: max(0, date.timeIntervalSinceNow)
        ) ?? localizedString("less than one minute", locale: locale)
    }

}
