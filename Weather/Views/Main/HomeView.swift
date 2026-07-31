//
//  HomeView.swift
//  Weather
//
//  Purpose: Defines the Home dashboard: static map preview, sunny-date
//  calendar, and ranked sunny-city list.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Home Destination

extension ContentView {
    /// Builds the root dashboard with native bottom toolbar and route overlays.
    var homeView: some View {
        homeContent(previewActive: false)
            // Home keeps its custom in-content title while iPad exposes the
            // native navigation bar for NavigationSplitView's own sidebar control.
            .navigationTitle("")
            .toolbar(isIPad ? .visible : .hidden, for: .navigationBar)
            .tint(theme.colors.primaryText)
            .onAppear {
                isMapCardPresented = false
            }
    }
}

// MARK: - Static Home Map

/// Noninteractive map snapshot summarizing cities on the Home dashboard.
struct HomeStaticMapPreview: View {
    /// Loaded city weather used to color available markers.
    let cities: [CityWeather]
    /// Source coordinates used by generated-list previews before weather exists.
    let previewCities: [City]
    /// Coordinates used to fit the initial map region.
    let fitCities: [City]
    /// Literal date determining each loaded city's marker condition.
    let selectedForecastDate: Date
    /// Neutral marker color for unfetched generated-list cities.
    let previewDot: Color
    /// Theme color revealed while MapKit has no drawable content.
    let fallbackBackground: Color
    /// Saturation applied to MapKit tiles.
    let mapSaturation: Double
    /// Active palette used by high-contrast marker alternatives.
    @Environment(\.appTheme) private var theme
    /// Contrast preference used to outline markers over map tiles.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Internal camera fitted whenever source city/date inputs change.
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: 12),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 38)
    ))

    /// Keep the Home map excerpt in step with the larger iPad map markers.
    private var markerScale: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 1.25 : 1
    }

    /// Builds the clipped, noninteractive map preview.
    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                appleMapPreview
            } else {
                fallbackBackground
            }
        }
        .background(fallbackBackground)
    }

    /// Renders loaded and preview annotations in MapKit.
    private var appleMapPreview: some View {
        Map(position: $cameraPosition, interactionModes: []) {
            ForEach(cities) { cityWeather in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: cityWeather.city.latitude,
                        longitude: cityWeather.city.longitude
                    ),
                    anchor: .center
                ) {
                    if let markerColor = markerColor(for: cityWeather) {
                        staticMapMarker(color: markerColor)
                    }
                }
            }

            ForEach(previewCities) { city in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: city.latitude,
                        longitude: city.longitude
                    ),
                    anchor: .center
                ) {
                    staticMapMarker(color: previewDot)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .saturation(mapSaturation)
        .allowsHitTesting(false)
        .background(fallbackBackground)
        .onAppear {
            fitAllCities()
        }
        .onChange(of: fitCities.map(\.id)) { _, _ in
            fitAllCities()
        }
        .onChange(of: selectedForecastDate) { _, _ in
            fitAllCities()
        }
    }

    /// Returns the selected date's semantic condition color when data is valid.
    private func markerColor(for cityWeather: CityWeather) -> Color? {
        cityWeather.forecastIfAvailable(on: selectedForecastDate).flatMap {
            SunninessScoring.condition(for: $0.symbolName)?.dotColor(for: theme.colors)
        }
    }

    @ViewBuilder
    /// Builds a noninteractive dot with an increased-contrast alternative.
    private func staticMapMarker(color: Color) -> some View {
        Group {
            if colorSchemeContrast == .increased {
                // An opaque backing and high-contrast outline keep the
                // weather color perceivable over every possible MapKit tile.
                ZStack {
                    Circle()
                        .fill(theme.colors.glassFill)
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle().stroke(theme.colors.primaryText, lineWidth: 2)
                        }

                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.42), radius: 5, y: 1)
            }
        }
        // The compact Home map uses the same iPad-only visual scaling as the
        // full map, while phone markers retain their established size.
        .scaleEffect(markerScale)
        // Counteract tile desaturation so semantic marker colors remain unchanged.
        .saturation(mapSaturation == 0 ? 1 : 1 / mapSaturation)
    }

    /// Fits loaded or preview coordinates without responding to user gestures.
    private func fitAllCities() {
        let citiesForFitting: [City]
        if cities.isEmpty {
            // List previews do not have weather yet, so continue fitting their
            // configured coordinates. A real weather map fits visible dots only.
            citiesForFitting = fitCities.isEmpty ? previewCities : fitCities
        } else {
            citiesForFitting = cities.compactMap { cityWeather in
                markerColor(for: cityWeather) == nil ? nil : cityWeather.city
            }
        }
        guard !citiesForFitting.isEmpty else { return }
        let points = citiesForFitting.map {
            MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
        }
        let cityRect = points.reduce(MKMapRect.null) { rect, point in
            rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }

        // A geographic degree span does not translate directly to the visible map area.
        // Fit MapKit's projected coordinates instead, with extra breathing room for lists
        // that span several regions (for example, Africa plus Australia).
        let widestRelativeSpan = max(
            cityRect.width / MKMapSize.world.width,
            cityRect.height / MKMapSize.world.height
        )
        // Widely scattered cities need increasingly more room than a local list.
        // There is deliberately no upper cap here; MapKit itself limits the view
        // to the world map when the fitted rectangle reaches that extent.
        let paddingMultiplier: Double = widestRelativeSpan > 0.22
            ? max(0.85, widestRelativeSpan * 2.4)
            : 0.34
        let minimumPadding = widestRelativeSpan > 0.22 ? 2_000_000.0 : 650_000.0
        let fittedRect = cityRect.insetBy(
            dx: -max(cityRect.width * paddingMultiplier, minimumPadding),
            dy: -max(cityRect.height * paddingMultiplier, minimumPadding)
        )
        cameraPosition = .rect(fittedRect)
    }

}

// MARK: - Home Card Components

/// Shared icon-and-title heading for Home dashboard cards.
struct SunnyPlacesSectionHeader: View {
    /// SF Symbol displayed before the heading.
    let icon: String
    /// Localized section title.
    let title: String

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Builds the aligned icon and title row.
    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Minimal ranked city-name row used by generated-list previews.
struct CityNameListRow: View {
    /// One-based position.
    let rank: Int
    /// Canonical city name supplied by the preview source.
    let cityName: String

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Builds rank and city-name columns matching weather candidate rows.
    var body: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            CityRankLabel(rank: rank)

            Text(cityName)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Home Sunny-Day Models

/// Per-date city availability and sunny-count inputs for Home's heatmap.
struct HomeSunnyDayRecommendation: Identifiable {
    /// Literal selection date and SwiftUI identity.
    let id: Date
    /// Number of available cities classified as sunny.
    let sunnyCityCount: Double
    /// Number of cities with valid condition inputs on this date.
    let availableCityCount: Int
}

/// One calendar cell, including inactive dates between returned forecasts.
private struct HomeSunnyCalendarDate: Identifiable {
    /// Stable literal date identity.
    let id: Date
    /// Date rendered by the cell.
    let date: Date
    /// Recommendation when the API returned this date.
    let recommendation: HomeSunnyDayRecommendation?

    /// Whether the cell represents selectable forecast data.
    var isForecastDate: Bool {
        recommendation != nil
    }
}

// MARK: - Home Screen

extension ContentView {
    // MARK: - Sunny-Day Recommendations

    /// Sunny-date recommendations for the active map city collection.
    var homeSunnyDayRecommendations: [HomeSunnyDayRecommendation] {
        homeSunnyDayRecommendations(for: mapCities)
    }

    /// Counts valid and sunny cities for every returned literal date.
    func homeSunnyDayRecommendations(for cities: [CityWeather]) -> [HomeSunnyDayRecommendation] {
        guard !cities.isEmpty else { return [] }

        return availableForecastDates(for: cities).compactMap { selectedDate in
            let forecasts = cities.compactMap { cityWeather in
                cityWeather.forecastIfAvailable(on: selectedDate)
            }
            guard !forecasts.isEmpty else { return nil }

            let conditions = forecasts.compactMap {
                SunninessScoring.condition(for: $0.symbolName)
            }
            guard !conditions.isEmpty else { return nil }
            let sunnyCityCount = conditions.reduce(0.0) { count, condition in
                switch condition {
                case .clear:
                    return count + 1
                case .partlySunny:
                    return count + 0.5
                default:
                    return count
                }
            }

            return HomeSunnyDayRecommendation(
                id: selectedDate,
                sunnyCityCount: sunnyCityCount,
                availableCityCount: conditions.count
            )
        }
    }

    // MARK: - Screen Composition

    /// Normal dashboard content using current generated-preview state.
    var homeContent: some View {
        homeContent(previewActive: isListPreviewActive)
    }

    /// Builds responsive dashboard cards for loaded or generated-preview state.
    func homeContent(previewActive: Bool) -> some View {
        GeometryReader { geometry in
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            // Match List View's readable iPad column and its centered side margins.
            let maxContentWidth = usesIPadLandscapeLayout(for: geometry.size) ? 680.0 : 760.0
            let availableContentWidth = min(
                max(geometry.size.width - 32, 0),
                maxContentWidth
            )
            let calendarContentWidth = max(availableContentWidth - 36, 0)
            // The map sits inside a card with a 6pt inset on each side.
            let mapContentWidth = max(availableContentWidth - 12, 0)
            let showsEmptyList = !previewActive
                && weatherService.cityListCoordinates().isEmpty
            let showsSunnyDaysCard = !previewActive
                && !homeSunnyCalendarDates(for: weatherService.cityWeatherData).isEmpty
            // Keep the established device-specific map proportions within the
            // shared single-column layout.
            let snapshotHeight: CGFloat = {
                let preferredHeight = isIPad
                    ? min(max(geometry.size.height * 0.36, 240), 390)
                    : min(max(geometry.size.height * 0.32, 190), 310)
                // A very wide dashboard map must remain tall enough to read;
                // preserve at least a 2:1 width-to-height proportion using
                // the map's rendered card width, not the full window width.
                let minimumHeight = mapContentWidth / 2
                return max(preferredHeight, minimumHeight)
            }()

            ScrollView {
                VStack(spacing: 20) {
                    // Preview the staged generated-list name without changing the active list.
                    topToolbar(
                        titleOverride: previewActive
                            ? listPreviewState.name.map {
                                "\($0) - \(localizedString("Preview", locale: locale))"
                            }
                            : nil
                    ) {
                        EmptyView()
                    }

                    if showsEmptyList {
                        homeCard {
                            emptyListContent
                                .padding(.vertical, 24)
                        }
                    } else {
                        homeCard(contentPadding: 6) {
                            homeMapSnapshot(height: snapshotHeight, previewActive: previewActive)
                        }
                        if showsSunnyDaysCard {
                            homeCard {
                                homeSunnyDaysSection(
                                    previewActive: previewActive,
                                    calendarContentWidth: calendarContentWidth
                                )
                            }
                        }
                        homeCard {
                            homeSunnySection(previewActive: previewActive)
                        }
                    }
                }
                // Use exactly List View's single centered content width on iPad.
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
        }
        .onAppear {
            filterSunny = false
        }
    }

    /// Wraps dashboard content in the shared rounded translucent card.
    private func homeCard<Content: View>(
        contentPadding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 24))
    }

    @ViewBuilder
    /// Makes the map tappable only when it represents loaded app data.
    private func homeMapSnapshot(height: CGFloat, previewActive: Bool) -> some View {
        if previewActive {
            homeMapSnapshotVisual(height: height, previewActive: true)
        } else {
            Button {
                selectedMapCity = nil
                isMapCardPresented = false
                citySearchState.temporaryMapCity = nil
                pushRoute(.map)
            } label: {
                homeMapSnapshotVisual(height: height, previewActive: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// Builds the static map from loaded or generated-list coordinates.
    private func homeMapSnapshotVisual(height: CGFloat, previewActive: Bool) -> some View {
        HomeStaticMapPreview(
            cities: previewActive ? [] : mapCities,
            previewCities: previewActive ? listPreviewCities : [],
            // Fit generated previews to staged cities and Home to the saved list.
            fitCities: previewActive ? listPreviewCities : weatherService.cityListCoordinates(),
            selectedForecastDate: selectedForecastDate,
            previewDot: theme.colors.primaryText,
            fallbackBackground: theme.colors.background,
            mapSaturation: 0.72
        )
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.colors.primaryText.opacity(0.12), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Builds ranked sunny places or the generated preview's city names.
    func homeSunnySection(previewActive: Bool) -> some View {
        let sectionIcon = previewActive ? "list.bullet" : "mappin.and.ellipse"
        let sectionTitle = previewActive
            ? localizedString("List of Cities", locale: locale)
            : localizedString("Best Sunny Places", locale: locale)

        return VStack(alignment: .leading, spacing: 12) {
            SunnyPlacesSectionHeader(icon: sectionIcon, title: sectionTitle)

            homeCandidateList(previewActive: previewActive)

            if !previewActive {
                Button {
                    pushRoute(.list)
                } label: {
                    HStack(spacing: 8) {
                        Text(localizedString("Show All Cities", locale: locale))
                            .font(.callout.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }

        }
    }

    /// Builds the selectable multiweek sunny-date heatmap card.
    private func homeSunnyDaysSection(
        previewActive: Bool,
        calendarContentWidth: CGFloat
    ) -> some View {
        let cities = previewActive ? [] : weatherService.cityWeatherData
        let days = homeSunnyCalendarDates(for: cities)
        // When an iPad has enough room to preserve a 44-point target for every
        // date, use a single row instead of making the existing two-row cells
        // taller. Smaller windows retain the familiar seven-day calendar grid.
        let usesSingleRowCalendar = UIDevice.current.userInterfaceIdiom == .pad
            && !days.isEmpty
            && calendarContentWidth / CGFloat(days.count) >= 44
        let calendarColumnCount = usesSingleRowCalendar ? days.count : 7
        let calendarColumnSpacing: CGFloat = usesSingleRowCalendar ? 0 : 7
        let weekdayLabels = homeSunnyCalendarWeekdayLabels(
            for: days,
            includesEveryDate: usesSingleRowCalendar
        )

        return VStack(alignment: .leading, spacing: 14) {
            SunnyPlacesSectionHeader(
                icon: "calendar",
                title: localizedString("Best Sunny Dates", locale: locale)
            )

            if days.isEmpty {
                Text(localizedString("No strong sunny days", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 7) {
                    LazyVGrid(
                        // Keep weekday labels on the same equal-width grid as dates.
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: calendarColumnSpacing),
                            count: calendarColumnCount
                        ),
                        spacing: 0
                    ) {
                        ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: calendarColumnSpacing),
                            count: calendarColumnCount
                        ),
                        spacing: 7
                    ) {
                        ForEach(days) { day in
                            homeSunnyHeatmapDayView(day, maxSunnyCityCount: cities.count)
                        }
                    }
                }
            }
        }
    }

    /// Builds localized weekday headings aligned with heatmap columns.
    private func homeSunnyCalendarWeekdayLabels(
        for days: [HomeSunnyCalendarDate],
        includesEveryDate: Bool
    ) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = .autoupdatingCurrent
        let symbols = calendar.shortStandaloneWeekdaySymbols
        guard includesEveryDate else {
            let mondayIndex = 1
            return Array(symbols[mondayIndex...]) + Array(symbols[..<mondayIndex])
        }

        return days.map { day in
            symbols[calendar.component(.weekday, from: day.date) - 1]
        }
    }

    /// Expands returned forecast dates into complete calendar rows with gaps.
    private func homeSunnyCalendarDates(for cities: [CityWeather]) -> [HomeSunnyCalendarDate] {
        let recommendations = homeSunnyDayRecommendations(for: cities)
        guard let firstForecastDate = recommendations.first?.id,
              let lastForecastDate = recommendations.last?.id else {
            return []
        }
        let recommendationsByDate = Dictionary(uniqueKeysWithValues: recommendations.map { ($0.id, $0) })
        // Count Monday-aligned placeholders before the first forecast date.
        let sundayBasedWeekday = Calendar.current.component(.weekday, from: firstForecastDate) - 1
        let leadingCount = (sundayBasedWeekday - 1 + 7) % 7
        let totalBeforeTrailing = leadingCount + recommendations.count
        let trailingCount = (7 - (totalBeforeTrailing % 7)) % 7
        let leadingDates = (0..<leadingCount).compactMap { index in
            Calendar.current.date(byAdding: .day, value: index - leadingCount, to: firstForecastDate)
        }
        let trailingDates = (1...max(trailingCount, 1)).compactMap { index -> Date? in
            guard trailingCount > 0 else { return nil }
            return Calendar.current.date(byAdding: .day, value: index, to: lastForecastDate)
        }

        return (leadingDates + recommendations.map(\.id) + trailingDates).map { date in
            HomeSunnyCalendarDate(
                id: date,
                date: date,
                recommendation: recommendationsByDate[date]
            )
        }
    }

    @ViewBuilder
    /// Makes returned dates selectable and leaves gap dates inert.
    private func homeSunnyHeatmapDayView(_ day: HomeSunnyCalendarDate, maxSunnyCityCount: Int) -> some View {
        if let recommendation = day.recommendation {
            let isSelected = Calendar.current.isDate(recommendation.id, inSameDayAs: selectedForecastDate)
            Button {
                withAnimation(.smooth(duration: 0.2)) {
                    selectedForecastDate = recommendation.id
                }
            } label: {
                homeSunnyHeatmapDayCell(
                    day,
                    maxSunnyCityCount: maxSunnyCityCount,
                    isSelected: isSelected
                )
            }
            .buttonStyle(.plain)
        } else {
            homeSunnyHeatmapDayCell(
                day,
                maxSunnyCityCount: maxSunnyCityCount,
                isSelected: false
            )
        }
    }

    // MARK: - Sunny Calendar Rendering

    /// Builds one date cell with selection, intensity, and legible text treatment.
    private func homeSunnyHeatmapDayCell(
        _ day: HomeSunnyCalendarDate,
        maxSunnyCityCount: Int,
        isSelected: Bool
    ) -> some View {
        let fill = homeSunnyHeatmapFill(
            sunnyCityCount: day.recommendation?.sunnyCityCount ?? 0,
            maxSunnyCityCount: day.recommendation?.availableCityCount ?? maxSunnyCityCount,
            isForecastDate: day.isForecastDate
        )
        let cornerRadius: CGFloat = 12

        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)

            VStack(spacing: 0) {
                // Use localized calendar numbering and strengthen only the selected date.
                Text("\(Calendar.current.component(.day, from: day.date))")
                    .font(.system(
                        size: 16,
                        weight: !day.isForecastDate ? .medium : (isSelected ? .semibold : .medium),
                        design: .default
                    ).monospacedDigit())

                if (differentiateWithoutColor || colorSchemeContrast == .increased),
                   let recommendation = day.recommendation,
                   recommendation.availableCityCount > 0 {
                    // Expose heatmap intensity numerically when color
                    // alone must not carry meaning or Increase Contrast is enabled.
                    Text("\(Int((recommendation.sunnyCityCount / Double(recommendation.availableCityCount) * 100).rounded()))%")
                        .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(
                homeSunnyHeatmapTextColor(
                    sunnyCityCount: day.recommendation?.sunnyCityCount ?? 0,
                    isForecastDate: day.isForecastDate,
                    isSelected: isSelected
                )
            )
            .lineLimit(1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                // In Increase Contrast, every heatmap cell receives
                // a measured outline in addition to its numeric intensity label.
                .stroke(
                    isSelected
                        ? theme.colors.accent
                        : theme.colors.primaryText.opacity(colorSchemeContrast == .increased ? 1 : 0.16),
                    lineWidth: isSelected ? 1.65 : (colorSchemeContrast == .increased ? 1.25 : 0.7)
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(2)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Maps relative sunny-city count into the calendar cell fill.
    private func homeSunnyHeatmapFill(sunnyCityCount: Double, maxSunnyCityCount: Int, isForecastDate: Bool) -> Color {
        guard isForecastDate else {
            return theme.colors.secondaryText.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }

        guard sunnyCityCount > 0, maxSunnyCityCount > 0 else {
            if colorScheme == .dark {
                return theme.colors.secondaryText.opacity(0.16)
            }
            return theme.colors.glassFill.opacity(0.56)
        }

        if colorSchemeContrast == .increased {
            // The numeric percentage carries intensity in Increase
            // Contrast, so sunny cells use one solid, measured-contrast fill.
            return theme.colors.dotSun
        }

        let fraction = max(0, min(1, sunnyCityCount / Double(maxSunnyCityCount)))
        let curvedFraction = pow(fraction, 1.55)
        return theme.colors.dotSun.opacity(0.16 + 0.79 * curvedFraction)
    }

    /// Chooses readable number color for the cell's fill and contrast mode.
    private func homeSunnyHeatmapTextColor(
        sunnyCityCount: Double,
        isForecastDate: Bool,
        isSelected: Bool
    ) -> Color {
        if !isForecastDate {
            return theme.colors.secondaryText
        }

        if colorSchemeContrast == .increased,
           colorScheme == .dark,
           sunnyCityCount > 0 {
            // Bright increased-contrast yellow needs a dark foreground.
            return theme.colors.background
        }

        return isSelected ? theme.colors.accent : theme.colors.primaryText
    }

    // MARK: - Candidate List

    /// Selects loaded ranked rows or generated-preview city-name rows.
    private func homeCandidateList(previewActive: Bool) -> some View {
        if previewActive {
            return AnyView(homePreviewCityList())
        }

        let rankedCandidates = sunnyCandidates(for: weatherService.cityWeatherData)
            .filter { $0.condition.isSunnyOrPartlySunny }
        return AnyView(VStack(spacing: 0) {
            if rankedCandidates.isEmpty {
                Text(localizedString("No sunny places for this date.", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(theme.colors.glassFill.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                listCandidateRows(
                    rankedCandidates,
                    showsDividers: true,
                    // Match List View's sunniness ranking: rank and city name
                    // share its typography, while cloud cover is the only value.
                    listMetricMode: .sunny,
                    selectionAction: { candidate in
                        selectCandidate(candidate, focusMap: false)
                    }
                )
            }
        })
    }

    /// Builds the leading generated-list city names before weather is fetched.
    private func homePreviewCityList() -> some View {
        VStack(spacing: 0) {
            ForEach(Array(listPreviewCities.enumerated()), id: \.element.id) { index, city in
                CityNameListRow(
                    rank: index + 1,
                    cityName: localizedCityName(for: city)
                )

                if index < listPreviewCities.count - 1 {
                    Divider()
                        .background(theme.colors.secondaryText.opacity(0.18))
                        .padding(.leading, CityListLayout.cityNameLeadingInset)
                }
            }
        }
    }

}

// MARK: - Previews

#Preview("Home View") {
    ContentView()
}
