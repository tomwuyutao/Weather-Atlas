//
//  Widgets.swift
//  WeatherWidgets
//
//  Purpose: Displays configurable home and lock-screen weather widgets.
//

import AppIntents
import CoreLocation
import SwiftUI
import WeatherKit
import WidgetKit

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

    func entities(matching string: String) async throws -> [WidgetListEntity] {
        try await suggestedEntities().filter {
            $0.displayName.localizedCaseInsensitiveContains(string)
        }
    }
}

private extension WidgetListEntity {
    init(_ list: WidgetDataList) {
        id = list.id
        displayName = list.displayName
    }
}

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
    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        let cities = WidgetDataStore.catalog()?.lists.flatMap(\.cities) ?? []
        return identifiers.compactMap { id in
            cities.first(where: { $0.id == id }).map(WidgetCityEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetCityEntity] {
        (WidgetDataStore.catalog()?.lists.flatMap(\.cities) ?? []).map(WidgetCityEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
        }
    }
}

private extension WidgetCityEntity {
    init(_ city: WidgetDataCity) {
        id = city.id
        cityName = city.cityName
    }
}

struct SunnyHoursLockScreenConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Sunny Hours"
    static var description = IntentDescription("Choose a city to track its sunny daytime hours.")

    @Parameter(title: "List") var list: WidgetListEntity?
    @Parameter(title: "City", optionsProvider: WidgetCityOptionsProvider()) var city: WidgetCityEntity?

    init() {}
}

struct WidgetCityOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<SunnyHoursLockScreenConfigurationIntent>(\.$list) var intent

    func results() async throws -> [WidgetCityEntity] {
        guard let listID = intent?.list.id,
              let list = WidgetDataStore.catalog()?.lists.first(where: { $0.id == listID }) else {
            return []
        }
        return list.cities.map(WidgetCityEntity.init)
    }
}

struct BestSunnyPlacesWidget: Widget {
    static let kind = "BestSunnyPlacesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Sunny Hours")
        .description("Track sunny daytime hours for a chosen city.")
        .supportedFamilies([.systemMedium])
    }
}

private struct SunnyHoursHomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city, !city.daytimeHours.isEmpty {
            content(city)
        } else {
            WidgetEmptyState(title: "Sunny Hours", symbol: "sun.max.fill")
        }
    }

    private func content(_ city: WidgetDataCity) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            SunnyHoursHeader(cityName: city.cityName, font: .headline.weight(.semibold), usesAccentColor: true)

            SunnyHoursTimeline(city: city, currentDate: entry.date)
                .padding(.top, 5)
                .frame(maxHeight: .infinity)

            SunnyHoursLegend()
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Accessibility: A widget is a single launch target, so provide its complete
        // weather result in one focus stop instead of exposing decorative chart pieces.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: "Sunny Hours")), \(city.cityName)")
        .accessibilityValue(widgetSunnyHoursAccessibilitySummary(for: city, locale: locale))
    }
}

private struct SunnyHoursLockScreenEntry: TimelineEntry {
    let date: Date
    let city: WidgetDataCity?

    static let preview = SunnyHoursLockScreenEntry(date: .now, city: .preview)
}

private struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry { .preview }

    func snapshot(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> SunnyHoursLockScreenEntry {
        SunnyHoursLockScreenEntry(date: .now, city: selectedCity(for: configuration))
    }

    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let entry = SunnyHoursLockScreenEntry(date: .now, city: await refreshedCity(for: configuration))
        // WidgetKit treats this as a preferred refresh time, rather than a precise schedule.
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(30 * 60)))
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

    private func refreshedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) async -> WidgetDataCity? {
        guard let city = selectedCity(for: configuration),
              let latitude = city.latitude,
              let longitude = city.longitude else {
            return selectedCity(for: configuration)
        }

        if let snapshot = WidgetDataStore.weatherSnapshot(for: city.id) {
            return city.applying(snapshot)
        }

        do {
            let weather = try await WeatherService.shared.weather(
                for: CLLocation(latitude: latitude, longitude: longitude)
            )
            let snapshot = makeWeatherSnapshot(weather: weather, city: city)
            WidgetDataStore.saveWeatherSnapshot(snapshot, for: city.id)
            return city.applying(snapshot)
        } catch {
            // Preserve the app's last forecast if the widget refresh is offline or throttled.
            return city
        }
    }

    private func makeWeatherSnapshot(weather: Weather, city: WidgetDataCity) -> WidgetWeatherSnapshot {
        let timeZone = city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let now = Date()
        let today = weather.dailyForecast.forecast.first { calendar.isDate($0.date, inSameDayAs: now) }
        let sunrise = today?.sun.sunrise
        let sunset = today?.sun.sunset

        let hours = weather.hourlyForecast.forecast.filter { hour in
            guard calendar.isDate(hour.date, inSameDayAs: now) else { return false }
            guard let sunrise, let sunset else {
                let hourNumber = calendar.component(.hour, from: hour.date)
                return (6...21).contains(hourNumber)
            }
            return hour.date >= sunrise && hour.date < sunset
        }

        let daytimeHours = hours.map { calendar.component(.hour, from: $0.date) }
        let sunnyHours = hours
            .filter { widgetCondition(for: $0.symbolName) == .sunny }
            .map { calendar.component(.hour, from: $0.date) }
        let partlySunnyHours = hours
            .filter { widgetCondition(for: $0.symbolName) == .partlySunny }
            .map { calendar.component(.hour, from: $0.date) }

        return WidgetWeatherSnapshot(
            fetchedAt: now,
            timeZoneIdentifier: timeZone.identifier,
            daytimeHours: daytimeHours,
            sunnyHours: sunnyHours,
            partlySunnyHours: partlySunnyHours
        )
    }

    private func widgetCondition(for symbolName: String) -> WidgetCondition {
        let symbol = symbolName.lowercased()
        if symbol.contains("cloud") && symbol.contains("sun") { return .partlySunny }
        if symbol.contains("sun.max") || symbol == "sun" || symbol == "sun.fill" { return .sunny }
        return .other
    }
}

private enum WidgetCondition {
    case sunny
    case partlySunny
    case other
}

struct SunnyHoursLockScreenWidget: Widget {
    static let kind = "SunnyHoursLockScreenWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursLockScreenWidgetView(entry: entry)
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
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city, !city.daytimeHours.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SunnyHoursHeader(cityName: city.cityName, font: .caption.weight(.semibold), usesAccentColor: false)
                    .padding(.horizontal, 10)
                    .padding(.trailing, -4)

                SunnyHoursTimeline(city: city, currentDate: entry.date, style: .lockScreen)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .offset(y: 2)
            }
            // Accessibility: Keep the compact lock-screen widget to one meaningful
            // launch target with the same information as its visual timeline.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(String(localized: "Sunny Hours")), \(city.cityName)")
            .accessibilityValue(widgetSunnyHoursAccessibilitySummary(for: city, locale: locale))
        } else {
            WidgetEmptyState(title: "Sunny Hours", symbol: "sun.max.fill")
        }
    }
}

private struct SunnyHoursHeader: View {
    let cityName: String
    let font: Font
    let usesAccentColor: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            Image(systemName: "sun.max.fill")
                .foregroundStyle(usesAccentColor ? WidgetColors.sunny : Color.primary)
                .accessibilityHidden(true)
        }
        .font(font)
    }
}

private struct SunnyHoursTimeline: View {
    enum Style {
        case home
        case lockScreen
    }

    // Accessibility: Adds shapes as a redundant cue when colors alone are insufficient.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let city: WidgetDataCity
    let currentDate: Date
    var style: Style = .home

    private let minimumCapsuleLaneHeight: CGFloat = 44

    var body: some View {
        let hours = displayedHours
        let startHour = hours.first ?? 6
        let endHour = hours.last ?? 21

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
                    Text(formattedHour(startHour))
                    Spacer(minLength: 0)
                    Text(formattedHour(endHour))
                }
                .frame(height: 14)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
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
                            Text(formattedHour(marker.hour))
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
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        // Accessibility: The timeline's visual segments and axis become one concise summary.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sunny Hours")
        .accessibilityValue(accessibilityTimelineValue)
    }

    // MARK: - Accessibility - Timeline Descriptions

    @ViewBuilder
    private func segmentDifferentiator(for hour: Int) -> some View {
        if differentiateWithoutColor {
            if city.sunnyHours.contains(hour) {
                Capsule()
                    .strokeBorder(.primary.opacity(0.9), lineWidth: 1.2)
            } else if city.partlySunnyHours.contains(hour) {
                Capsule()
                    .strokeBorder(
                        .primary.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])
                    )
            }
        }
    }

    private var accessibilityTimelineValue: String {
        var parts: [String] = []
        let sunnyRanges = formattedHourRanges(city.sunnyHours)
        if !sunnyRanges.isEmpty {
            parts.append("\(String(localized: "Sunny")): \(sunnyRanges)")
        }
        let partlySunnyRanges = formattedHourRanges(city.partlySunnyHours)
        if !partlySunnyRanges.isEmpty {
            parts.append("\(String(localized: "Partly Sunny")): \(partlySunnyRanges)")
        }
        if parts.isEmpty {
            let hours = displayedHours
            return "\(formattedHour(hours.first ?? 6))–\(formattedHour(hours.last ?? 21))"
        }
        return parts.joined(separator: "; ")
    }

    private func formattedHourRanges(_ sourceHours: [Int]) -> String {
        let hours = Array(Set(sourceHours)).sorted()
        guard let firstHour = hours.first else { return "" }

        var ranges: [(start: Int, end: Int)] = []
        var rangeStart = firstHour
        var previousHour = firstHour
        for hour in hours.dropFirst() {
            if hour == previousHour + 1 {
                previousHour = hour
            } else {
                ranges.append((rangeStart, previousHour + 1))
                rangeStart = hour
                previousHour = hour
            }
        }
        ranges.append((rangeStart, previousHour + 1))

        return ranges
            .map { "\(formattedHour($0.start))–\(formattedHour($0.end))" }
            .joined(separator: ", ")
    }

    // MARK: - Timeline Rendering

    private func segmentColor(for hour: Int) -> Color {
        if style == .lockScreen {
            if city.sunnyHours.contains(hour) { return .primary.opacity(0.92) }
            if city.partlySunnyHours.contains(hour) { return .primary.opacity(0.62) }
            // Accessibility: Strengthen inactive lock-screen segments only when
            // Increase Contrast is enabled so they remain visually meaningful.
            return .primary.opacity(colorSchemeContrast == .increased ? 0.52 : 0.28)
        }

        if colorSchemeContrast == .increased {
            // Accessibility: Adaptive primary fills keep every timeline state above
            // the non-text contrast threshold on light and dark widget backgrounds.
            if city.sunnyHours.contains(hour) { return .primary }
            if city.partlySunnyHours.contains(hour) { return .primary.opacity(0.70) }
            return .primary.opacity(0.52)
        }

        if city.sunnyHours.contains(hour) {
            return WidgetColors.sunny
        }
        if city.partlySunnyHours.contains(hour) {
            return WidgetColors.partlySunny
        }
        return .secondary.opacity(0.16)
    }

    private var currentTimeMarker: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.9))
            .frame(width: 2)
    }

    private func currentTimeBoundaryIndex(in hours: [Int]) -> Int? {
        var calendar = Calendar.current
        calendar.timeZone = city.widgetTimeZone
        let currentHour = calendar.component(.hour, from: currentDate)
        guard hours.count > 1,
              currentHour >= (hours.first ?? currentHour),
              currentHour <= (hours.last ?? currentHour) else {
            return nil
        }
        let currentIndex = hours.enumerated().min {
            abs($0.element - currentHour) < abs($1.element - currentHour)
        }?.offset ?? 0
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
        let sourceHours = city.widgetTimelineHours
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

    private func formattedHour(_ hour: Int) -> String {
        String(format: "%02d", hour % 24)
    }

}

private struct SunnyHoursLegend: View {
    // Accessibility: Replaces color dots with condition symbols when requested by the system.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: 9) {
            item(
                color: colorSchemeContrast == .increased ? .primary : WidgetColors.sunny,
                title: "Sunny",
                symbol: "sun.max.fill"
            )
            item(
                color: colorSchemeContrast == .increased ? .primary.opacity(0.70) : WidgetColors.partlySunny,
                title: "Partly Sunny",
                symbol: "cloud.sun.fill"
            )
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 9)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.secondary.opacity(0.18))
                .frame(height: 1)
        }
    }

    private func item(color: Color, title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            if differentiateWithoutColor {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(title)
        }
    }
}

private struct WidgetEmptyState: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                // Accessibility: A semantic foreground remains legible in both
                // light and dark widget appearances.
                .foregroundStyle(.primary)
            Spacer()
            Text("Open Weather Atlas to update this widget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Accessibility: Treat the empty-state title and instruction as one useful element.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("Open Weather Atlas to update this widget.")
    }
}

// MARK: - Accessibility - Widget Summaries

private func widgetSunnyHoursAccessibilitySummary(for city: WidgetDataCity, locale: Locale) -> String {
    var parts: [String] = []
    let sunnyRanges = widgetFormattedHourRanges(city.sunnyHours, locale: locale)
    if !sunnyRanges.isEmpty {
        parts.append("\(String(localized: "Sunny")): \(sunnyRanges)")
    }

    let partlySunnyRanges = widgetFormattedHourRanges(city.partlySunnyHours, locale: locale)
    if !partlySunnyRanges.isEmpty {
        parts.append("\(String(localized: "Partly Sunny")): \(partlySunnyRanges)")
    }

    if parts.isEmpty {
        return String(localized: "No Sun")
    }
    return parts.joined(separator: "; ")
}

private func widgetFormattedHourRanges(_ sourceHours: [Int], locale: Locale) -> String {
    let hours = Array(Set(sourceHours)).sorted()
    guard let firstHour = hours.first else { return "" }

    var ranges: [(start: Int, end: Int)] = []
    var rangeStart = firstHour
    var previousHour = firstHour
    for hour in hours.dropFirst() {
        if hour == previousHour + 1 {
            previousHour = hour
        } else {
            ranges.append((rangeStart, previousHour + 1))
            rangeStart = hour
            previousHour = hour
        }
    }
    ranges.append((rangeStart, previousHour + 1))

    // Accessibility: Respect the user's 12/24-hour convention in spoken summaries.
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale)

    func formattedHour(_ hour: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = hour % 24
        components.minute = 0
        guard let date = components.date else { return String(format: "%02d", hour % 24) }
        return formatter.string(from: date)
    }

    return ranges
        .map { "\(formattedHour($0.start))–\(formattedHour($0.end))" }
        .joined(separator: ", ")
}

private enum WidgetColors {
    static let navy = Color(red: 0.12, green: 0.28, blue: 0.55)
    static let sunny = Color(red: 1, green: 0.72, blue: 0.30)
    static let partlySunny = Color(red: 1, green: 0.80, blue: 0.46)
}

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
    static let preview = WidgetDataList.preview.cities[0]

    var widgetSunnyHours: [Int] {
        Array(Set(sunnyHours + partlySunnyHours)).sorted()
    }

    var widgetTimelineHours: [Int] {
        let daytime = daytimeHours.sorted()
        guard !daytime.isEmpty else { return widgetSunnyHours }
        return daytime
    }

    var widgetTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .autoupdatingCurrent
    }

    func applying(_ snapshot: WidgetWeatherSnapshot) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            cityName: cityName,
            timeZoneIdentifier: snapshot.timeZoneIdentifier ?? timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            daytimeHours: snapshot.daytimeHours,
            sunnyHours: snapshot.sunnyHours,
            partlySunnyHours: snapshot.partlySunnyHours
        )
    }
}

@main
struct WeatherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
    }
}

#Preview("Sunny Hours - Medium", as: .systemMedium) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

#Preview("Sunny Hours - Lock Screen", as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
