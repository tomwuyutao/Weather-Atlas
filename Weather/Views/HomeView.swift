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
    var homeView: some View {
        homeContent(previewActive: false)
            .navigationTitle(toolbarTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
            }
    }
}

// MARK: - Static Home Map

struct HomeStaticMapPreview: View {
    let cities: [CityWeather]
    let previewCities: [City]
    let fitCities: [City]
    let selectedForecastDate: Date
    let previewDot: Color
    let water: Color
    let mapSaturation: Double
    @Environment(\.appTheme) private var theme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48, longitude: 12),
        span: MKCoordinateSpan(latitudeDelta: 28, longitudeDelta: 38)
    ))

    private var markerSaturationCompensation: Double {
        mapSaturation == 0 ? 1 : 1 / mapSaturation
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                appleMapPreview
            } else {
                water
            }
        }
        .background(water)
    }

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
        .background(water)
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

    private func markerColor(for cityWeather: CityWeather) -> Color? {
        cityWeather.forecastIfAvailable(on: selectedForecastDate).flatMap {
            SunninessScoring.condition(for: $0.symbolName)?.dotColor(for: theme.colors)
        }
    }

    @ViewBuilder
    private func staticMapMarker(color: Color) -> some View {
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
            .saturation(markerSaturationCompensation)
        } else {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.42), radius: 5, y: 1)
                .saturation(markerSaturationCompensation)
        }
    }

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

struct SunnyPlacesSectionHeader: View {
    let icon: String
    let title: String

    @Environment(\.appTheme) private var theme
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

struct CityNameListRow: View {
    let rank: Int
    let cityName: String

    @Environment(\.appTheme) private var theme
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

struct HomeSunnyDayRecommendation: Identifiable {
    let id: Date
    let sunnyCityCount: Double
    let availableCityCount: Int
}

private struct HomeSunnyCalendarDate: Identifiable {
    let id: Date
    let date: Date
    let recommendation: HomeSunnyDayRecommendation?

    var isForecastDate: Bool {
        recommendation != nil
    }
}

// MARK: - Home Screen

extension ContentView {
    // MARK: - Sunny-Day Recommendations

    var homeSunnyDayRecommendations: [HomeSunnyDayRecommendation] {
        homeSunnyDayRecommendations(for: mapCities)
    }

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

    var homeContent: some View {
        homeContent(previewActive: isListPreviewActive)
    }

    func homeContent(previewActive: Bool) -> some View {
        GeometryReader { geometry in
            let availableContentWidth = min(max(geometry.size.width - 32, 0), 1_160)
            // The app's text-size setting currently caps at xxLarge, so treat that
            // maximum as the readable single-column breakpoint as well as the
            // largest system categories.
            let usesReadableSingleColumn = dynamicTypeSize >= .xxLarge
            let usesWideLayout = availableContentWidth >= 900 && !usesReadableSingleColumn
            let isIPad = UIDevice.current.userInterfaceIdiom == .pad
            let columnSpacing: CGFloat = 20
            let primaryColumnWidth = (availableContentWidth - columnSpacing) * 0.58
            let calendarContentWidth = max(
                (usesWideLayout ? primaryColumnWidth : availableContentWidth) - 36,
                0
            )
            let droppedCityCount = previewActive
                ? 0
                : rankingOmissionCount(in: weatherService.cityWeatherData)
            let showsSunnyDaysCard = !previewActive
                && !homeSunnyCalendarDates(for: weatherService.cityWeatherData).isEmpty
            // Preserve the existing height calculation in narrow windows. On a
            // wide window, derive the map height from its column so it retains a
            // useful landscape proportion instead of stretching with the screen.
            // iPad has enough room to give the map more geographic context; the
            // phone proportions remain exactly as before.
            let snapshotHeight: CGFloat = {
                if usesWideLayout {
                    return isIPad
                        ? min(max(primaryColumnWidth * 0.55, 300), 390)
                        : min(max(primaryColumnWidth * 0.48, 240), 310)
                }
                return isIPad
                    ? min(max(geometry.size.height * 0.36, 240), 390)
                    : min(max(geometry.size.height * 0.32, 190), 310)
            }()

            ScrollView {
                VStack(spacing: 20) {
                    homePageHeader(previewActive: previewActive)

                    if usesWideLayout {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            VStack(spacing: 20) {
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
                            }
                            .frame(width: primaryColumnWidth, alignment: .top)

                            homeCard {
                                homeSunnySection(previewActive: previewActive)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
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

                    if droppedCityCount > 0 {
                        forecastAvailabilityNote(droppedCityCount: droppedCityCount)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // Keep the page comfortably readable in full-screen and large
                // Stage Manager windows while leaving compact layouts unchanged.
                .frame(maxWidth: usesReadableSingleColumn ? 760 : 1_160)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                // The omission notice is the final independent card. Leave
                // enough room to scroll it fully above the floating toolbar.
                .padding(.bottom, droppedCityCount > 0 ? 88 : 16)
            }
            .scrollIndicators(.hidden)
            .background(theme.colors.background.ignoresSafeArea())
        }
        .onAppear {
            filterSunny = false
        }
    }

    private func homeCard<Content: View>(
        contentPadding: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 24))
    }

    private func homePageHeader(previewActive: Bool) -> some View {
        topToolbar(titleOverride: homeTitleOverride(previewActive: previewActive)) {
            EmptyView()
        }
    }

    private func homeTitleOverride(previewActive: Bool) -> String? {
        guard previewActive, let previewName = listPreviewState.name else { return nil }
        return "\(previewName) - \(localizedString("Preview", locale: locale))"
    }

    @ViewBuilder
    private func homeMapSnapshot(height: CGFloat, previewActive: Bool) -> some View {
        if previewActive {
            homeMapSnapshotVisual(height: height, previewActive: true)
        } else {
            Button {
                selectedMapCity = nil
                showingMapExpandedCard = false
                citySearchState.temporaryMapCity = nil
                pushRoute(.map)
            } label: {
                homeMapSnapshotVisual(height: height, previewActive: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func homeMapSnapshotVisual(height: CGFloat, previewActive: Bool) -> some View {
        HomeStaticMapPreview(
            cities: previewActive ? [] : mapCities,
            previewCities: previewActive ? listPreviewCities : [],
            fitCities: previewActive ? listPreviewCities : mapFitCities,
            selectedForecastDate: selectedForecastDate,
            previewDot: theme.colors.primaryText,
            water: theme.colors.mapOcean,
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

    func homeSunnySection(previewActive: Bool) -> some View {
        let sectionIcon = previewActive ? "list.bullet" : "sun.max.fill"
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

    func forecastAvailabilityNote(droppedCityCount: Int) -> some View {
        ForecastOmissionNotice(droppedCityCount: droppedCityCount)
    }

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
                icon: "sparkles",
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
                        columns: homeSunnyCalendarColumns(
                            count: calendarColumnCount,
                            spacing: calendarColumnSpacing
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
                        columns: homeSunnyCalendarColumns(
                            count: calendarColumnCount,
                            spacing: calendarColumnSpacing
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

    private func homeSunnyCalendarColumns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }

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

    private func homeSunnyCalendarDates(for cities: [CityWeather]) -> [HomeSunnyCalendarDate] {
        let recommendations = homeSunnyDayRecommendations(for: cities)
        guard let firstForecastDate = recommendations.first?.id,
              let lastForecastDate = recommendations.last?.id else {
            return []
        }
        let recommendationsByDate = Dictionary(uniqueKeysWithValues: recommendations.map { ($0.id, $0) })
        let leadingCount = homeSunnyCalendarLeadingInactiveCount(firstForecastDate: firstForecastDate)
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

    private func homeSunnyCalendarLeadingInactiveCount(firstForecastDate: Date) -> Int {
        let sundayBasedWeekday = Calendar.current.component(.weekday, from: firstForecastDate) - 1
        let mondayIndex = 1
        return (sundayBasedWeekday - mondayIndex + 7) % 7
    }

    @ViewBuilder
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
                Text(homeSunnyCalendarDayNumber(date: day.date))
                    .font(.system(size: 16, weight: homeSunnyCalendarDayWeight(day, isSelected: isSelected), design: .default).monospacedDigit())

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

    private func homeSunnyCalendarDayWeight(_ day: HomeSunnyCalendarDate, isSelected: Bool) -> Font.Weight {
        if !day.isForecastDate {
            return .medium
        }
        return isSelected ? .semibold : .medium
    }

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

    private func homeSunnyCalendarDayNumber(date: Date) -> String {
        return "\(Calendar.current.component(.day, from: date))"
    }

    // MARK: - Candidate List

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
                    showsTemperature: true,
                    selectionAction: { candidate in
                        selectCandidate(candidate, focusMap: false)
                    }
                )
            }
        })
    }

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
