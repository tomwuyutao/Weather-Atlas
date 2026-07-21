//
//  WeatherWidgets.swift
//  WeatherWidgets
//
//  Purpose: Displays configurable home and lock-screen weather widgets.
//

import AppIntents
import CoreLocation
import SwiftUI
import WeatherKit
import WidgetKit

// MARK: - Widget List Selection

struct WidgetListEntity: AppEntity, Identifiable {
    let id: String
    let displayName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static var defaultQuery = WidgetListQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }
}

struct WidgetListQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetListEntity] {
        let lists = WidgetDataStore.catalog()?.lists ?? []
        return identifiers.compactMap { id in
            lists.first(where: { $0.id == id }).map(WidgetListEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetListEntity] {
        (WidgetDataStore.catalog()?.lists ?? []).map(WidgetListEntity.init)
    }

    func defaultResult() async -> WidgetListEntity? {
        WidgetDataStore.catalog()?.lists.first.map(WidgetListEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetListEntity] {
        try await suggestedEntities().filter {
            $0.displayName.localizedCaseInsensitiveContains(string)
        }
    }
}

// MARK: - Inline List Selection

struct WidgetListOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [WidgetListEntity] {
        (WidgetDataStore.catalog()?.lists ?? []).map(WidgetListEntity.init)
    }

    func defaultResult() async -> WidgetListEntity? {
        WidgetDataStore.catalog()?.lists.first.map(WidgetListEntity.init)
    }
}

private extension WidgetListEntity {
    init(_ list: WidgetDataList) {
        id = list.id
        displayName = list.displayName
    }
}

// MARK: - Widget City Selection

struct WidgetCityEntity: AppEntity, Identifiable {
    let id: String
    let cityName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    static var defaultQuery = WidgetCityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: cityName))
    }
}

struct WidgetCityQuery: EntityStringQuery {
    @IntentParameterDependency<SunnyHoursLockScreenConfigurationIntent>(\.$list) var intent

    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        let cities = citiesForSelectedList()
        return identifiers.compactMap { id in
            cities.first(where: { $0.id == id }).map(WidgetCityEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetCityEntity] {
        citiesForSelectedList().map(WidgetCityEntity.init)
    }

    func defaultResult() async -> WidgetCityEntity? {
        citiesForSelectedList().first.map(WidgetCityEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
        }
    }

    private func citiesForSelectedList() -> [WidgetDataCity] {
        guard let catalog = WidgetDataStore.catalog() else { return [] }
        let selectedListID = intent?.list.id
        let list = selectedListID.flatMap { listID in
            catalog.lists.first(where: { $0.id == listID })
        } ?? catalog.lists.first
        return list?.cities ?? []
    }
}

private extension WidgetCityEntity {
    init(_ city: WidgetDataCity) {
        id = city.id
        cityName = city.cityName
    }
}

// MARK: - Widget Configuration Intent

struct SunnyHoursLockScreenConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Sunny Hours"
    static var description = IntentDescription("Choose a city to track its sunny daytime hours.")

    @Parameter(title: "List", optionsProvider: WidgetListOptionsProvider()) var list: WidgetListEntity?
    @Parameter(title: "City") var city: WidgetCityEntity?

    init() {}
}

// MARK: - Home-Screen Widgets

struct BestSunnyPlacesWidget: Widget {
    static let kind = WidgetDataStore.kind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursHomeWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .containerBackground(for: .widget) {
                    WidgetPaletteBackground()
                }
        }
        .configurationDisplayName("Sunny Hours (Daily)")
        .description("Track sunny hours for a chosen city.")
        .supportedFamilies([.systemMedium])
    }
}

struct SunnyWindowWidget: Widget {
    static let kind = "SunnyWindowWidget"

    var body: some WidgetConfiguration {
        // The large widget intentionally shares the medium widget's intent and
        // provider. Both sizes therefore use the same defaults, WeatherKit fetch,
        // refresh policy, and per-city multi-day cache.
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyWindowLargeWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .containerBackground(for: .widget) {
                    WidgetPaletteBackground()
                }
        }
        .configurationDisplayName("Sunny Hours (10 Days)")
        .description("Track sunny hours for a chosen city.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Large Sunny-Window Presentation

private struct SunnyWindowLargeWidgetView: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            VStack(alignment: .leading, spacing: 9) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    conditionSymbolName: city.currentConditionSymbolName,
                    font: .headline.weight(.semibold),
                    usesWeatherColors: true
                )

                if city.widgetSunnyWindowIssue != nil {
                    WidgetDataUnavailablePlaceholder()
                } else if let timeZone = city.widgetTimeZone,
                          let chartBounds = city.widgetSunnyWindowChartBounds {
                    SunnyWindowLargeChart(
                        days: city.widgetSunnyWindowDays,
                        currentDate: entry.date,
                        locale: locale,
                        timeZone: timeZone,
                        chartBounds: chartBounds
                    )
                    .frame(maxHeight: .infinity, alignment: .top)

                    SunnyHoursLegend()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(AppPalette.values(for: colorScheme).titleText)
            .widgetURL(widgetListURL(for: city, issue: city.widgetSunnyWindowIssue))
        } else {
            EmptyView()
        }
    }
}

private struct SunnyWindowLargeChart: View {
    let days: [WidgetSunnyWindowDay]
    let currentDate: Date
    let locale: Locale
    let timeZone: TimeZone
    let chartBounds: SunnyHoursChartBounds

    // Match the detail chart's redundant solid/dashed outlines
    // when the user asks the interface not to communicate with color alone.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.colorScheme) private var colorScheme

    private let labelWidth: CGFloat = 52
    private let axisHeight: CGFloat = 18
    private let minimumRowHeight: CGFloat = 22
    private let axisToRowsSpacing: CGFloat = 2
    private let timelineLaneHeight: CGFloat = 16
    private let capsuleHeight: CGFloat = 10

    private var visibleDays: [WidgetSunnyWindowDay] {
        Array(days.prefix(10))
    }

    private var axisHours: [Int] {
        chartBounds.axisHours(maximumTickCount: 8)
    }

    var body: some View {
        GeometryReader { geometry in
            let timelineWidth = max(geometry.size.width - labelWidth, 1)
            let availableRowsHeight = max(
                geometry.size.height - axisHeight - axisToRowsSpacing,
                0
            )
            let rowHeight = visibleDays.isEmpty
                ? minimumRowHeight
                : max(availableRowsHeight / CGFloat(visibleDays.count), minimumRowHeight)
            let rowsHeight = CGFloat(visibleDays.count) * rowHeight

            VStack(spacing: axisToRowsSpacing) {
                axisRow(timelineWidth: timelineWidth)
                ZStack {
                    rowsView(
                        visibleDays,
                        timelineWidth: timelineWidth,
                        rowHeight: rowHeight
                    )
                    gridLines(
                        rowCount: visibleDays.count,
                        timelineWidth: timelineWidth,
                        rowHeight: rowHeight
                    )
                        .allowsHitTesting(false)
                    currentTimeMarker(
                        rowCount: visibleDays.count,
                        timelineWidth: timelineWidth,
                        rowHeight: rowHeight
                    )
                    .allowsHitTesting(false)
                }
                .frame(height: rowsHeight)
                .clipped()
            }
        }
    }

    private func axisRow(timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)
            ZStack(alignment: .leading) {
                ForEach(axisHours, id: \.self) { hour in
                    Text(SunnyHoursFormatting.chartHourLabel(hour))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(renderedSecondary)
                        .position(
                            x: chartBounds.xPosition(for: Double(hour), width: timelineWidth),
                            y: axisHeight / 2
                        )
                }
            }
            .frame(width: timelineWidth, height: axisHeight)
        }
    }

    private func rowsView(
        _ visibleDays: [WidgetSunnyWindowDay],
        timelineWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(visibleDays) { day in
                HStack(spacing: 0) {
                    Text(dayLabel(for: day.date))
                        .font(.caption2.weight(isToday(day.date) ? .bold : .medium))
                        .foregroundStyle(isToday(day.date) ? renderedPrimary : renderedSecondary)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(trackColor)
                            .frame(height: capsuleHeight)

                        ForEach(
                            SunnyHoursTimelineLayout.spans(
                                sunnyHours: day.sunnyHours,
                                partlySunnyHours: day.partlySunnyHours,
                                boundedBy: chartBounds
                            )
                        ) { span in
                            let spanStartX = chartBounds.xPosition(
                                for: Double(span.range.lowerBound),
                                width: timelineWidth
                            )

                            ZStack(alignment: .leading) {
                                ForEach(span.segments) { segment in
                                    Rectangle()
                                        .fill(segmentColor(isPartlySunny: segment.isPartlySunny))
                                        .frame(
                                            width: chartBounds.width(
                                                for: segment.range,
                                                timelineWidth: timelineWidth,
                                                minimumWidth: 6
                                            ),
                                            height: capsuleHeight
                                        )
                                        .overlay {
                                            if differentiateWithoutColor {
                                                Rectangle()
                                                    .stroke(
                                                        renderedPrimary.opacity(0.82),
                                                        style: StrokeStyle(
                                                            lineWidth: 1,
                                                            dash: segment.isPartlySunny ? [2, 2] : []
                                                        )
                                                    )
                                            }
                                        }
                                        .offset(
                                            x: chartBounds.xPosition(
                                                for: Double(segment.range.lowerBound),
                                                width: timelineWidth
                                            ) - spanStartX
                                        )
                                }
                            }
                            .frame(
                                width: chartBounds.width(
                                    for: span.range,
                                    timelineWidth: timelineWidth,
                                    minimumWidth: 6
                                ),
                                height: capsuleHeight,
                                alignment: .leading
                            )
                            .clipShape(Capsule())
                            .offset(x: spanStartX)
                        }
                    }
                    .frame(width: timelineWidth, height: timelineLaneHeight)
                }
                .frame(height: rowHeight)
            }
        }
    }

    private func gridLines(
        rowCount: Int,
        timelineWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let rowsHeight = CGFloat(rowCount) * rowHeight
        let verticalInset = (timelineLaneHeight - capsuleHeight) / 2
        let gridHeight = max(rowsHeight - verticalInset * 2, 0)

        return HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)
            Path { path in
                for hour in axisHours {
                    let x = chartBounds.xPosition(for: Double(hour), width: timelineWidth)
                    path.move(to: CGPoint(x: x, y: verticalInset))
                    path.addLine(to: CGPoint(x: x, y: verticalInset + gridHeight))
                }
            }
            .stroke(gridColor, lineWidth: 1)
            .frame(width: timelineWidth, height: rowsHeight)
        }
        .frame(height: rowsHeight)
    }

    @ViewBuilder
    private func currentTimeMarker(
        rowCount: Int,
        timelineWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let rowsHeight = CGFloat(rowCount) * rowHeight
        if let todayRowIndex = visibleDays.firstIndex(where: { isToday($0.date) }),
           let markerX = chartBounds.currentTimeXPosition(
               at: currentDate,
               timeZone: timeZone,
               width: timelineWidth
           ) {
            HStack(spacing: 0) {
                Color.clear.frame(width: labelWidth)
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(renderedPrimary.opacity(0.82))
                            .frame(width: 2, height: capsuleHeight)
                            .offset(x: markerX - 1)
                    }
                    .frame(
                        width: timelineWidth,
                        height: capsuleHeight,
                        alignment: .leading
                    )
                    .clipShape(Capsule())
                    .offset(
                        y: CGFloat(todayRowIndex) * rowHeight
                            + (rowHeight - capsuleHeight) / 2
                    )
                }
                .frame(width: timelineWidth, height: rowsHeight, alignment: .topLeading)
            }
            .frame(height: rowsHeight)
        }
    }

    private func segmentColor(isPartlySunny: Bool) -> Color {
        if usesSystemRenderingColors {
            return .primary.opacity(isPartlySunny ? 0.48 : 1)
        }
        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return isPartlySunny
                ? colors.dotPartlyCloudy
                : colors.dotSun
        }
        return isPartlySunny ? palette.dotPartlyCloudy : palette.dotSun
    }

    private var trackColor: Color {
        if usesSystemRenderingColors {
            return .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
        }
        return colorSchemeContrast == .increased
            ? renderedPrimary.opacity(0.52)
            : renderedSecondary.opacity(0.16)
    }

    private var gridColor: Color {
        renderedSecondary.opacity(colorSchemeContrast == .increased ? 0.18 : 0.08)
    }

    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    private var usesSystemRenderingColors: Bool {
        widgetRenderingMode != .fullColor
    }

    private var renderedPrimary: Color {
        usesSystemRenderingColors ? .primary : palette.titleText
    }

    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }

    private func dayLabel(for date: Date) -> String {
        if isToday(date) {
            return widgetLocalizedString("Today", locale: locale)
        }
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
        format.timeZone = timeZone
        return date.formatted(format)
    }

    private func isToday(_ date: Date) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: currentDate)
    }

}

// MARK: - Medium Daily Presentation

private struct SunnyHoursHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            content(city)
                .widgetURL(widgetListURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            EmptyView()
        }
    }

    private func content(_ city: WidgetDataCity) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            SunnyHoursHeader(
                cityName: city.cityName,
                conditionSymbolName: city.currentConditionSymbolName,
                font: .headline.weight(.semibold),
                usesWeatherColors: true
            )

            if city.widgetCurrentIssue != nil {
                WidgetDataUnavailablePlaceholder()
            } else {
                SunnyHoursTimeline(city: city, currentDate: entry.date)
                    .padding(.top, 5)
                    .frame(maxHeight: .infinity)

                SunnyHoursLegend()
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(AppPalette.values(for: colorScheme).titleText)
    }
}

// MARK: - Shared Widget Background

private struct WidgetPaletteBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        AppPalette.values(for: colorScheme).background
    }
}

// MARK: - Timeline Entry and Provider

/// The historical type name is retained because it participates in existing
/// AppIntent/widget configurations; the entry is shared by every widget size.
private struct SunnyHoursLockScreenEntry: TimelineEntry {
    let date: Date
    let city: WidgetDataCity?

    static let preview = SunnyHoursLockScreenEntry(date: .now, city: .preview)
}

/// Shared by the medium, large, and lock-screen widgets so all three use the
/// same WeatherKit request, cache, and refresh policy.
private struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    private struct RefreshResult {
        let city: WidgetDataCity?
        let needsShortRetry: Bool
    }

    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry {
        let configuration = SunnyHoursLockScreenConfigurationIntent()
        return SunnyHoursLockScreenEntry(
            date: .now,
            city: cityUsingCachedSnapshot(for: configuration) ?? .preview
        )
    }

    func snapshot(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> SunnyHoursLockScreenEntry {
        if context.isPreview {
            return SunnyHoursLockScreenEntry(
                date: .now,
                city: cityUsingCachedSnapshot(for: configuration) ?? .preview
            )
        }
        // Use the same direct WeatherKit path as the timeline so a newly added
        // widget does not wait for WidgetKit's next scheduled refresh.
        let result = await refreshedCity(for: configuration)
        return SunnyHoursLockScreenEntry(date: .now, city: result.city)
    }

    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let result = await refreshedCity(for: configuration)
        let entry = SunnyHoursLockScreenEntry(date: .now, city: result.city)
        let retryDelay: TimeInterval = result.needsShortRetry ? 60 : 30 * 60
        // WidgetKit treats this as a preferred refresh time, rather than a precise schedule.
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(retryDelay)))
    }

    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetDataCity? {
        guard let catalog = WidgetDataStore.catalog() else { return nil }
        let list = configuration.list.flatMap { selectedList in
            catalog.lists.first(where: { $0.id == selectedList.id })
        } ?? catalog.lists.first

        guard let list else { return nil }
        return configuration.city.flatMap { selectedCity in
            list.cities.first(where: { $0.id == selectedCity.id })
        } ?? list.cities.first
    }

    private func cityUsingCachedSnapshot(
        for configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> WidgetDataCity? {
        guard let city = selectedCity(for: configuration) else { return nil }
        return WidgetDataStore.weatherSnapshot(for: city.id)
            .map(city.applying)
            ?? city.markingUnavailable(.missingForecastData)
    }

    private func refreshedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) async -> RefreshResult {
        guard let city = selectedCity(for: configuration) else {
            return RefreshResult(city: nil, needsShortRetry: true)
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude else {
            return RefreshResult(
                city: city.markingUnavailable(.missingForecastData),
                needsShortRetry: true
            )
        }

        if let snapshot = WidgetDataStore.weatherSnapshot(for: city.id),
           let currentConditionSymbolName = snapshot.currentConditionSymbolName,
           WeatherSymbolClassification.resolve(currentConditionSymbolName) != nil {
            return RefreshResult(
                city: city.applying(snapshot),
                needsShortRetry: snapshot.dataIssue != nil
            )
        }

        // A widget can be asked for its first timeline while WeatherKit is still
        // establishing the extension's service session. Retry that initial miss
        // once before returning an empty entry.
        for attempt in 0..<2 {
            do {
                let weather = try await WeatherService.shared.weather(
                    for: CLLocation(latitude: latitude, longitude: longitude)
                )
                let snapshot = makeWeatherSnapshot(weather: weather, city: city)
                WidgetDataStore.saveWeatherSnapshot(snapshot, for: city.id)
                return RefreshResult(
                    city: city.applying(snapshot),
                    needsShortRetry: snapshot.dataIssue != nil
                )
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(750))
                }
            }
        }

        return RefreshResult(
            city: city.markingUnavailable(.missingForecastData),
            needsShortRetry: true
        )
    }

    private func makeWeatherSnapshot(weather: Weather, city: WidgetDataCity) -> WidgetWeatherSnapshot {
        let now = Date()
        guard let timeZone = city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: city.timeZoneIdentifier,
                issue: .missingTimeZone
            )
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard let today = weather.dailyForecast.forecast.first(where: {
            calendar.isDate($0.date, inSameDayAs: now)
        }) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                issue: .missingForecastData
            )
        }
        let daytimeConditionSymbolName = today.symbolName
        guard WeatherSymbolClassification.resolve(daytimeConditionSymbolName) != nil else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                issue: .unknownWeatherSymbol(daytimeConditionSymbolName)
            )
        }

        let hourlyForecasts = Array(weather.hourlyForecast.forecast)
        let currentDaylightHours = daylightHours(
            on: now,
            sunrise: today.sun.sunrise,
            sunset: today.sun.sunset,
            from: hourlyForecasts,
            calendar: calendar
        )
        guard case .success(let resolvedCurrentHours) = currentDaylightHours else {
            let issue = currentDaylightHours.failure ?? .missingHourlyData
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: daytimeConditionSymbolName,
                issue: issue
            )
        }

        let currentHours = WidgetForecastHourBreakdown(
            hours: resolvedCurrentHours,
            calendar: calendar
        )
        if let issue = currentHours.dataIssue {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: daytimeConditionSymbolName,
                issue: issue
            )
        }
        if let issue = WeatherDataIssue.missingSunEvent(
            sunrise: today.sun.sunrise,
            sunset: today.sun.sunset
        ) {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                issue: issue
            )
        }
        guard let daylightBounds = SunnyHoursChartBounds.daylight(
            sunrise: today.sun.sunrise,
            sunset: today.sun.sunset,
            timeZone: timeZone
        ) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: daytimeConditionSymbolName,
                issue: .missingSunriseOrSunset
            )
        }

        let sunnyWindowDays = weather.dailyForecast.forecast.prefix(10).map { day in
            let daylightResult = daylightHours(
                on: day.date,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset,
                from: hourlyForecasts,
                calendar: calendar
            )
            guard case .success(let resolvedHours) = daylightResult,
                  let dayBounds = SunnyHoursChartBounds.daylight(
                    sunrise: day.sun.sunrise,
                    sunset: day.sun.sunset,
                    timeZone: timeZone
                  ) else {
                return WidgetSunnyWindowDay(
                    date: calendar.startOfDay(for: day.date),
                    sunnyHours: [],
                    partlySunnyHours: [],
                    daylightBounds: nil,
                    dataIssue: daylightResult.failure ?? .missingSunriseOrSunset
                )
            }
            let hours = WidgetForecastHourBreakdown(hours: resolvedHours, calendar: calendar)
            return WidgetSunnyWindowDay(
                date: calendar.startOfDay(for: day.date),
                sunnyHours: hours.sunnyHours,
                partlySunnyHours: hours.partlySunnyHours,
                daylightBounds: dayBounds,
                dataIssue: hours.dataIssue
            )
        }

        return WidgetWeatherSnapshot(
            fetchedAt: now,
            timeZoneIdentifier: timeZone.identifier,
            currentConditionSymbolName: daytimeConditionSymbolName,
            daytimeHours: currentHours.daytimeHours,
            sunnyHours: currentHours.sunnyHours,
            partlySunnyHours: currentHours.partlySunnyHours,
            daylightBounds: daylightBounds,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
    }

    private func unavailableSnapshot(
        fetchedAt: Date,
        timeZoneIdentifier: String?,
        currentConditionSymbolName: String? = nil,
        issue: WeatherDataIssue
    ) -> WidgetWeatherSnapshot {
        WidgetWeatherSnapshot(
            fetchedAt: fetchedAt,
            timeZoneIdentifier: timeZoneIdentifier,
            currentConditionSymbolName: currentConditionSymbolName,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            daylightBounds: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }

    private func daylightHours(
        on date: Date,
        sunrise: Date?,
        sunset: Date?,
        from forecasts: [HourWeather],
        calendar: Calendar
    ) -> Result<[HourWeather], WeatherDataIssue> {
        if let issue = WeatherDataIssue.missingSunEvent(sunrise: sunrise, sunset: sunset) {
            return .failure(issue)
        }
        guard let sunrise, let sunset else { return .failure(.missingSunriseOrSunset) }
        let matchingHours = forecasts.filter {
            calendar.isDate($0.date, inSameDayAs: date)
        }
        guard !matchingHours.isEmpty else {
            return .failure(.missingHourlyData)
        }
        let daylightHours = matchingHours.filter { hour in
            hourlyInterval(
                at: hour.date,
                overlapsDaylightFrom: sunrise,
                to: sunset,
                calendar: calendar
            )
        }
        guard !daylightHours.isEmpty else {
            return .failure(.missingHourlyData)
        }
        return .success(daylightHours)
    }

    private func hourlyInterval(
        at hourStart: Date,
        overlapsDaylightFrom sunrise: Date,
        to sunset: Date,
        calendar: Calendar
    ) -> Bool {
        SunnyHoursChartBounds.hourlyIntervalOverlapsDaylight(
            at: hourStart,
            sunrise: sunrise,
            sunset: sunset,
            timeZone: calendar.timeZone
        )
    }

}

// MARK: - Widget Forecast Classification

private enum WidgetCondition {
    case sunny
    case partlySunny
    case other

    init?(symbolName: String) {
        guard let classification = WeatherSymbolClassification.resolve(symbolName) else {
            return nil
        }
        switch classification {
        case .clear:
            self = .sunny
        case .partlySunny:
            self = .partlySunny
        default:
            self = .other
        }
    }
}

private struct WidgetForecastHourBreakdown {
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    let dataIssue: WeatherDataIssue?

    init(hours: [HourWeather], calendar: Calendar) {
        var daytimeHours: [Int] = []
        var sunnyHours: [Int] = []
        var partlySunnyHours: [Int] = []
        var dataIssue: WeatherDataIssue?

        for forecast in hours {
            guard let condition = WidgetCondition(symbolName: forecast.symbolName) else {
                dataIssue = .unknownWeatherSymbol(forecast.symbolName)
                break
            }
            let hour = calendar.component(.hour, from: forecast.date)
            daytimeHours.append(hour)

            switch condition {
            case .sunny:
                sunnyHours.append(hour)
            case .partlySunny:
                partlySunnyHours.append(hour)
            case .other:
                break
            }
        }

        self.daytimeHours = daytimeHours
        self.sunnyHours = sunnyHours
        self.partlySunnyHours = partlySunnyHours
        self.dataIssue = dataIssue
    }
}

private extension Result where Failure == WeatherDataIssue {
    var failure: WeatherDataIssue? {
        guard case .failure(let issue) = self else { return nil }
        return issue
    }
}

// MARK: - Lock-Screen Widget

struct SunnyHoursLockScreenWidget: Widget {
    static let kind = "SunnyHoursLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursLockScreenWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Sunny Hours")
        .description("Track sunny daytime hours for a chosen city.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct SunnyHoursLockScreenWidgetView: View {
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            VStack(alignment: .leading, spacing: 4) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    conditionSymbolName: city.currentConditionSymbolName,
                    font: .caption.weight(.semibold),
                    usesWeatherColors: false
                )
                    .padding(.horizontal, 10)
                    .padding(.trailing, -4)

                if city.widgetCurrentIssue != nil {
                    WidgetDataUnavailablePlaceholder()
                    .padding(.horizontal, 10)
                } else {
                    SunnyHoursTimeline(city: city, currentDate: entry.date, style: .lockScreen)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .offset(y: 2)
                }
            }
            .widgetURL(widgetListURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            EmptyView()
        }
    }
}

// MARK: - Shared Widget Presentation

private struct SunnyHoursHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let cityName: String
    let conditionSymbolName: String?
    let font: Font
    let usesWeatherColors: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            if let conditionSymbolName {
                let displaySymbolName = widgetConditionDisplaySymbolName(for: conditionSymbolName)
                if usesWeatherColors && widgetRenderingMode == .fullColor {
                    let palette = widgetConditionIconPalette(
                        for: conditionSymbolName,
                        colors: AppPalette.values(for: colorScheme)
                    )
                    Image(systemName: displaySymbolName)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(palette.primary, palette.secondary)
                } else {
                    Image(systemName: displaySymbolName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .font(font)
    }
}

private struct SunnyHoursTimeline: View {
    enum Style {
        case home
        case lockScreen
    }

    // Add shapes as a redundant cue when colors alone are insufficient.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    let city: WidgetDataCity
    let currentDate: Date
    var style: Style = .home

    private let minimumCapsuleLaneHeight: CGFloat = 44

    var body: some View {
        let hours = displayedHours
        if let startHour = hours.first, let endHour = hours.last {
            VStack(spacing: style == .home ? 4 : 3) {
                GeometryReader { proxy in
                    let capsuleHeight = proxy.size.height
                    ZStack(alignment: .leading) {
                        HStack(spacing: style == .home ? 7 : 8) {
                            ForEach(hours, id: \.self) { hour in
                                Capsule()
                                    .fill(segmentColor(for: hour))
                                    .overlay {
                                        segmentDifferentiator(for: hour)
                                    }
                            }
                        }

                        if let boundaryIndex = currentTimeBoundaryIndex(in: hours) {
                            currentTimeMarker
                                .frame(height: capsuleHeight)
                                .position(
                                    x: boundaryPosition(
                                        for: boundaryIndex,
                                        capsuleCount: hours.count,
                                        availableWidth: proxy.size.width
                                    ),
                                    y: capsuleHeight / 2
                                )
                        }
                    }
                    .frame(height: capsuleHeight, alignment: .top)
                }
                .frame(minHeight: style == .home ? minimumCapsuleLaneHeight : 18)

                if style == .lockScreen {
                    HStack {
                        Text(SunnyHoursFormatting.chartHourLabel(startHour))
                        Spacer(minLength: 0)
                        Text(SunnyHoursFormatting.chartHourLabel(endHour))
                    }
                    .frame(height: 14)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(renderedSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
                } else {
                    let axisMarkers = timelineAxisMarkers(
                        for: hours,
                        from: startHour,
                        through: endHour
                    )
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            ForEach(Array(axisMarkers.enumerated()), id: \.offset) { _, marker in
                                Text(SunnyHoursFormatting.chartHourLabel(marker.hour))
                                    .position(
                                        x: capsuleCenterPosition(
                                            for: marker.capsuleIndex,
                                            capsuleCount: hours.count,
                                            availableWidth: proxy.size.width
                                        ),
                                        y: proxy.size.height / 2
                                    )
                            }
                        }
                    }
                    .frame(height: 14)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(renderedSecondary)
                    .lineLimit(1)
                }
            }
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    @ViewBuilder
    private func segmentDifferentiator(for hour: Int) -> some View {
        if differentiateWithoutColor {
            if city.sunnyHours.contains(hour) {
                Capsule()
                    .strokeBorder(renderedPrimary.opacity(0.9), lineWidth: 1.2)
            } else if city.partlySunnyHours.contains(hour) {
                Capsule()
                    .strokeBorder(
                        renderedPrimary.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])
                    )
            }
        }
    }

    // MARK: - Timeline Rendering

    private func segmentColor(for hour: Int) -> Color {
        if usesSystemRenderingColors {
            // Lock-screen widgets sit on a translucent system surface. Keep a wide
            // luminance separation over any wallpaper. iOS also uses accented mode
            // for clear and tinted Home Screen widgets, preserving these opacities
            // while converting their colors to white.
            if city.sunnyHours.contains(hour) { return .primary.opacity(1) }
            if city.partlySunnyHours.contains(hour) { return .primary.opacity(0.48) }
            return .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
        }

        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            if city.sunnyHours.contains(hour) { return colors.dotSun }
            if city.partlySunnyHours.contains(hour) { return colors.dotPartlyCloudy }
            return colors.titleText.opacity(0.52)
        }

        if city.sunnyHours.contains(hour) {
            return palette.dotSun
        }
        if city.partlySunnyHours.contains(hour) {
            return palette.dotPartlyCloudy
        }
        return palette.secondaryText.opacity(0.16)
    }

    private var currentTimeMarker: some View {
        Rectangle()
            .fill(renderedPrimary.opacity(0.9))
            .frame(width: 2)
    }

    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    private var usesSystemRenderingColors: Bool {
        style == .lockScreen || widgetRenderingMode != .fullColor
    }

    private var renderedPrimary: Color {
        usesSystemRenderingColors ? .primary : palette.titleText
    }

    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }

    private func currentTimeBoundaryIndex(in hours: [Int]) -> Int? {
        guard let timeZone = city.widgetTimeZone,
              let firstHour = hours.first,
              let lastHour = hours.last else {
            return nil
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentHour = calendar.component(.hour, from: currentDate)
        guard hours.count > 1,
              currentHour >= firstHour,
              currentHour <= lastHour,
              let currentIndex = hours.enumerated().min(by: {
                abs($0.element - currentHour) < abs($1.element - currentHour)
              })?.offset else {
            return nil
        }
        return min(currentIndex + 1, hours.count - 1)
    }

    private func boundaryPosition(for boundaryIndex: Int, capsuleCount: Int, availableWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = style == .home ? 7 : 8
        let capsuleWidth = (availableWidth - spacing * CGFloat(capsuleCount - 1)) / CGFloat(capsuleCount)
        return CGFloat(boundaryIndex) * capsuleWidth + (CGFloat(boundaryIndex) - 0.5) * spacing
    }

    private func capsuleCenterPosition(for index: Int, capsuleCount: Int, availableWidth: CGFloat) -> CGFloat {
        let spacing: CGFloat = style == .home ? 7 : 8
        let capsuleWidth = (availableWidth - spacing * CGFloat(capsuleCount - 1)) / CGFloat(capsuleCount)
        return CGFloat(index) * (capsuleWidth + spacing) + capsuleWidth / 2
    }

    private var displayedHours: [Int] {
        let sourceHours: [Int]
        if let daylightBounds = city.daylightBounds {
            sourceHours = Array(daylightBounds.startHour..<daylightBounds.endHour)
        } else {
            sourceHours = city.widgetTimelineHours
        }
        let hours = sourceHours.last.map { sourceHours + [$0 + 1] } ?? sourceHours
        guard style == .lockScreen, hours.count > 1 else { return hours }

        var twoHourlySlots = hours.enumerated().compactMap { index, hour in
            index.isMultiple(of: 2) ? hour : nil
        }
        if let finalHour = hours.last, twoHourlySlots.last != finalHour {
            twoHourlySlots.append(finalHour)
        }
        return twoHourlySlots
    }

    private func timelineAxisHours(from startHour: Int, through endHour: Int) -> [Int] {
        let span = max(endHour - startHour, 0)
        return (0...3).map { index in
            startHour + Int((Double(span) * Double(index) / 3).rounded())
        }
    }

    private func timelineAxisMarkers(
        for hours: [Int],
        from startHour: Int,
        through endHour: Int
    ) -> [(hour: Int, capsuleIndex: Int)] {
        guard !hours.isEmpty else { return [] }
        let axisHours = timelineAxisHours(from: startHour, through: endHour)

        return axisHours.enumerated().map { axisIndex, hour in
            let capsuleIndex: Int
            if axisIndex == 0 {
                capsuleIndex = 0
            } else if axisIndex == axisHours.count - 1 {
                capsuleIndex = hours.count - 1
            } else {
                capsuleIndex = hours.enumerated().min {
                    abs($0.element - hour) < abs($1.element - hour)
                }?.offset ?? 0
            }
            return (hour, capsuleIndex)
        }
    }

}

private struct SunnyHoursLegend: View {
    // Replace color dots with condition symbols when requested by the system.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            item(
                color: sunnyLegendColor,
                title: "Sunny",
                symbol: WeatherIconSymbol.clear
            )
            item(
                color: partlySunnyLegendColor,
                title: "Partly Sunny",
                symbol: WeatherIconSymbol.partlyCloudy
            )
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(renderedSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(renderedSecondary.opacity(0.18))
                .frame(height: 1)
        }
    }

    private var sunnyLegendColor: Color {
        if usesSystemRenderingColors { return .primary.opacity(1) }
        return colorSchemeContrast == .increased
            ? increasedContrastPalette.dotSun
            : palette.dotSun
    }

    private var partlySunnyLegendColor: Color {
        if usesSystemRenderingColors { return .primary.opacity(0.48) }
        return colorSchemeContrast == .increased
            ? increasedContrastPalette.dotPartlyCloudy
            : palette.dotPartlyCloudy
    }

    private func item(color: Color, title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            if differentiateWithoutColor {
                let iconPalette = widgetConditionIconPalette(for: symbol, colors: palette)
                Image(systemName: widgetConditionDisplaySymbolName(for: symbol))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconPalette.primary, iconPalette.secondary)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(title)
        }
    }

    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    private var increasedContrastPalette: AppPalette.Values {
        AppPalette.increasedContrastValues(for: colorScheme)
    }

    private var usesSystemRenderingColors: Bool {
        widgetRenderingMode != .fullColor
    }

    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }
}

// MARK: - Widget Missing-Data Suppression

private struct WidgetDataUnavailablePlaceholder: View {
    var body: some View {
        // Missing-data text is intentionally suppressed inside the widget; the
        // app deep link carries the issue and presents its native alert instead.
        EmptyView()
    }
}

private func widgetConditionDisplaySymbolName(for symbolName: String) -> String {
    switch WeatherSymbolClassification.resolve(symbolName) {
    case .clear:
        return WeatherIconSymbol.clear
    case .partlySunny, .partlyCloudy:
        return WeatherIconSymbol.partlyCloudy
    case .cloudy:
        return WeatherIconSymbol.cloudy
    case .rain:
        return WeatherIconSymbol.rain
    case .drizzle:
        return WeatherIconSymbol.drizzle
    case .snow:
        return WeatherIconSymbol.snow
    case .fog:
        return WeatherIconSymbol.fog
    case .wind:
        return WeatherIconSymbol.wind
    case nil:
        return symbolName
    }
}

private func widgetConditionIconPalette(
    for symbolName: String,
    colors: AppPalette.Values
) -> (primary: Color, secondary: Color) {
    switch WeatherSymbolClassification.resolve(symbolName) {
    case .clear:
        return (colors.dotSun, colors.dotSun)
    case .partlySunny, .partlyCloudy:
        return (colors.titleText, colors.dotSun)
    case .rain, .drizzle:
        return (colors.titleText, colors.dotRain)
    case .cloudy, .snow, .fog, .wind, nil:
        return (colors.titleText, colors.titleText)
    }
}

// MARK: - Deep Links

private func widgetListURL(for city: WidgetDataCity, issue: WeatherDataIssue?) -> URL? {
    guard let separator = city.id.firstIndex(of: "|"),
          separator > city.id.startIndex else {
        return nil
    }
    let listID = String(city.id[..<separator])
    var components = URLComponents()
    components.scheme = "weatheratlas"
    components.host = "list"
    components.path = "/\(listID)"
    if let issue {
        var queryItems = [
            URLQueryItem(name: "missingKind", value: issue.kind.rawValue),
            URLQueryItem(name: "city", value: city.cityName)
        ]
        if let detail = issue.detail {
            queryItems.append(URLQueryItem(name: "missingDetail", value: detail))
        }
        components.queryItems = queryItems
    }
    return components.url
}

// MARK: - Widget Presentation Models

private extension WidgetDataList {
    static let preview = WidgetDataList(
        id: "europe",
        displayName: "Europe",
        cities: [
            WidgetDataCity(id: "barcelona", cityName: "Barcelona", timeZoneIdentifier: "Europe/Madrid", latitude: 41.3874, longitude: 2.1686, daytimeHours: Array(6...21), sunnyHours: Array(8...19), partlySunnyHours: [7, 20]),
            WidgetDataCity(id: "rome", cityName: "Rome", timeZoneIdentifier: "Europe/Rome", latitude: 41.9028, longitude: 12.4964, daytimeHours: Array(6...21), sunnyHours: Array(9...18), partlySunnyHours: [7, 8, 19]),
            WidgetDataCity(id: "athens", cityName: "Athens", timeZoneIdentifier: "Europe/Athens", latitude: 37.9838, longitude: 23.7275, daytimeHours: Array(6...21), sunnyHours: Array(8...20), partlySunnyHours: [7])
        ]
    )
}

private extension WidgetDataCity {
    static var preview: WidgetDataCity {
        var city = WidgetDataList.preview.cities[0]
        city.currentConditionSymbolName = WeatherIconSymbol.clear
        let calendar = Calendar.current
        city.sunnyWindowDays = (0..<10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let sunnyStart = 7 + (offset % 4)
            let sunnyEnd = 15 + (offset % 5)
            return WidgetSunnyWindowDay(
                date: calendar.startOfDay(for: date),
                sunnyHours: Array(sunnyStart...sunnyEnd),
                partlySunnyHours: offset.isMultiple(of: 2) ? [6, sunnyEnd + 1] : [sunnyEnd + 1]
            )
        }
        return city
    }

    var widgetSunnyHours: [Int] {
        Array(Set(sunnyHours + partlySunnyHours)).sorted()
    }

    var widgetSunnyWindowDays: [WidgetSunnyWindowDay] {
        sunnyWindowDays ?? []
    }

    var widgetTimelineHours: [Int] {
        let daytime = daytimeHours.sorted()
        guard !daytime.isEmpty else { return widgetSunnyHours }
        return daytime
    }

    var widgetTimeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    var widgetCurrentIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        guard daylightBounds != nil else { return .missingSunriseOrSunset }
        guard !daytimeHours.isEmpty else { return .missingHourlyData }
        return nil
    }

    var widgetSunnyWindowIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        let days = widgetSunnyWindowDays
        guard !days.isEmpty else { return .missingForecastData }
        if let issue = days.compactMap(\.dataIssue).first {
            return issue
        }
        guard days.allSatisfy({ $0.daylightBounds != nil }) else {
            return .missingSunriseOrSunset
        }
        return nil
    }

    var widgetCurrentConditionIssue: WeatherDataIssue? {
        guard let currentConditionSymbolName else { return .missingForecastData }
        guard WeatherSymbolClassification.resolve(currentConditionSymbolName) != nil else {
            return .unknownWeatherSymbol(currentConditionSymbolName)
        }
        return nil
    }

    var widgetSunnyWindowChartBounds: SunnyHoursChartBounds? {
        let days = widgetSunnyWindowDays
        let bounds = days.compactMap(\.daylightBounds)
        guard bounds.count == days.count else { return nil }
        return SunnyHoursChartBounds.merged(bounds)
    }

    func applying(_ snapshot: WidgetWeatherSnapshot) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            cityName: cityName,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            daytimeHours: snapshot.daytimeHours,
            sunnyHours: snapshot.sunnyHours,
            partlySunnyHours: snapshot.partlySunnyHours,
            currentConditionSymbolName: snapshot.currentConditionSymbolName,
            daylightBounds: snapshot.daylightBounds,
            sunnyWindowDays: snapshot.sunnyWindowDays,
            dataIssue: snapshot.dataIssue
        )
    }

    func markingUnavailable(_ issue: WeatherDataIssue) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            currentConditionSymbolName: currentConditionSymbolName,
            daylightBounds: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }
}

// MARK: - Widget Bundle

@main
struct WeatherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyWindowWidget()
        SunnyHoursLockScreenWidget()
    }
}

// MARK: - Previews

#Preview("Sunny Hours (Daily) - Medium", as: .systemMedium) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

#Preview("Sunny Hours (10 Days) - Large", as: .systemLarge) {
    SunnyWindowWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

#Preview("Sunny Hours - Lock Screen", as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
