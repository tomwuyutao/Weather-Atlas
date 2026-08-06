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

// MARK: - Widget Locale Lookup

/// Looks up widget copy that the localized main app published into the app group.
func widgetLocalizedString(_ key: String) -> String {
    WidgetDataStore.localizedText(for: key)
}

// MARK: - Widget Place Scope Selection

/// App Intent entity representing the Saved Places library.
struct WidgetPlaceScopeEntity: AppEntity, Identifiable {
    /// Stable scope identifier.
    let id: String
    /// Localized scope name.
    let displayName: String

    /// Entity type label used by WidgetKit configuration UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Places"
    /// Query used by App Intents to resolve place scopes.
    static var defaultQuery = WidgetPlaceScopeQuery()

    /// User-facing scope representation in configuration UI.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }
}

/// Searchable resolver for published widget place scopes.
struct WidgetPlaceScopeQuery: EntityStringQuery {
    /// Resolves stable identifiers against the latest app-group catalog.
    func entities(for identifiers: [String]) async throws -> [WidgetPlaceScopeEntity] {
        let scopes = WidgetDataStore.catalog()?.placeScopes ?? []
        return identifiers.compactMap { id in
            scopes.first(where: { $0.id == id }).map(WidgetPlaceScopeEntity.init)
        }
    }

    /// Returns all published scopes in app-defined order.
    func suggestedEntities() async throws -> [WidgetPlaceScopeEntity] {
        (WidgetDataStore.catalog()?.placeScopes ?? []).map(WidgetPlaceScopeEntity.init)
    }

    /// Uses Saved Places as initial configuration.
    func defaultResult() async -> WidgetPlaceScopeEntity? {
        WidgetDataStore.catalog()?.placeScopes.first.map(WidgetPlaceScopeEntity.init)
    }

    /// Filters scopes by localized case-insensitive name matching.
    func entities(matching string: String) async throws -> [WidgetPlaceScopeEntity] {
        try await suggestedEntities().filter {
            $0.displayName.localizedCaseInsensitiveContains(string)
        }
    }
}

// MARK: - Inline Place Scope Selection

/// Finite place-scope options used by the widget editing interface.
struct WidgetPlaceScopeOptionsProvider: DynamicOptionsProvider {
    /// Returns all published place scopes.
    func results() async throws -> [WidgetPlaceScopeEntity] {
        (WidgetDataStore.catalog()?.placeScopes ?? []).map(WidgetPlaceScopeEntity.init)
    }

    /// Uses Saved Places when no configuration has been saved.
    func defaultResult() async -> WidgetPlaceScopeEntity? {
        WidgetDataStore.catalog()?.placeScopes.first.map(WidgetPlaceScopeEntity.init)
    }
}

private extension WidgetPlaceScopeEntity {
    /// Converts the shared Codable scope into an App Intent entity.
    init(_ scope: WidgetPlaceScope) {
        id = scope.id
        displayName = scope.displayName
    }
}

// MARK: - Widget City Selection

/// App Intent entity representing one city within a selected place scope.
struct WidgetCityEntity: AppEntity, Identifiable {
    /// Stable cross-process city identifier.
    let id: String
    /// Localized city display name.
    let cityName: String

    /// Entity type label used by WidgetKit configuration UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "City"
    /// Query used by App Intents to resolve city entities.
    static var defaultQuery = WidgetCityQuery()

    /// User-facing city representation in configuration UI.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: cityName))
    }
}

/// Searchable city resolver scoped to the intent's selected places.
struct WidgetCityQuery: EntityStringQuery {
    /// Dependency exposing the selected scope while resolving city options.
    @IntentParameterDependency<SunnyHoursLockScreenConfigurationIntent>(\.$placeScope) var intent

    /// Resolves identifiers only within the selected scope.
    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        let cities = citiesForSelectedScope()
        return identifiers.compactMap { id in
            cities.first(where: { $0.id == id }).map(WidgetCityEntity.init)
        }
    }

    /// Returns all cities published for the selected scope.
    func suggestedEntities() async throws -> [WidgetCityEntity] {
        citiesForSelectedScope().map(WidgetCityEntity.init)
    }

    /// Uses the selected scope's first city as initial configuration.
    func defaultResult() async -> WidgetCityEntity? {
        citiesForSelectedScope().first.map(WidgetCityEntity.init)
    }

    /// Filters scoped cities by localized case-insensitive name.
    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
        }
    }

    /// Reads cities from the selected scope. Saved Places is used only when the
    /// user has not configured a scope; an unavailable explicit scope stays empty.
    private func citiesForSelectedScope() -> [WidgetDataCity] {
        guard let catalog = WidgetDataStore.catalog() else { return [] }
        let scope: WidgetPlaceScope?
        if let selectedScope = intent?.placeScope {
            scope = catalog.placeScopes.first(where: { $0.id == selectedScope.id })
        } else {
            scope = catalog.placeScopes.first
        }
        return scope?.cities ?? []
    }
}

private extension WidgetCityEntity {
    /// Converts a shared Codable city into an App Intent entity.
    init(_ city: WidgetDataCity) {
        id = city.id
        cityName = city.cityName
    }
}

// MARK: - Widget Configuration Intent

/// Shared place-scope and city configuration used by all Weather Atlas widgets.
struct SunnyHoursLockScreenConfigurationIntent: WidgetConfigurationIntent {
    /// Configuration title shown by WidgetKit.
    static var title: LocalizedStringResource = "Sunny Hours"
    /// Configuration explanation shown by WidgetKit.
    static var description = IntentDescription("Choose a city to track its sunny daytime hours.")

    /// Inline selected-place-scope parameter.
    @Parameter(title: "Places", optionsProvider: WidgetPlaceScopeOptionsProvider()) var placeScope: WidgetPlaceScopeEntity?
    /// Searchable selected-city parameter filtered by the chosen scope.
    @Parameter(title: "City") var city: WidgetCityEntity?

    /// Required empty initializer for App Intent configuration.
    init() {}
}

// MARK: - Home-Screen Widgets

/// Home Screen widget showing daily or ten-day sunny hours by family.
struct BestSunnyPlacesWidget: Widget {
    /// Stable kind for the unified Home Screen widget.
    static let kind = WidgetDataStore.kind

    /// Registers both Home Screen sizes under one configuration so WidgetKit
    /// can expose both choices from the app icon as well as the widget gallery.
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursHomeScreenWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .containerBackground(for: .widget) {
                    WidgetPaletteBackground()
                }
        }
        .configurationDisplayName(WidgetDataStore.localizedText(for: "Sunny Hours"))
        .description(WidgetDataStore.localizedText(for: "Track sunny hours for a chosen city."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Chooses the existing size-specific presentation inside the shared widget kind.
private struct SunnyHoursHomeScreenWidgetView: View {
    /// WidgetKit's currently rendered Home Screen family.
    @Environment(\.widgetFamily) private var family
    /// Timeline entry shared by the medium and large presentations.
    let entry: SunnyHoursLockScreenEntry

    @ViewBuilder
    var body: some View {
        if family == .systemLarge {
            SunnyWindowLargeWidgetView(entry: entry)
        } else {
            SunnyHoursHomeWidgetView(entry: entry)
        }
    }
}

// MARK: - Large Sunny-Window Presentation

/// Header, ten-day chart, legend, and missing-data state for the large widget.
private struct SunnyWindowLargeWidgetView: View {
    /// Locale published by the main app.
    @Environment(\.locale) private var locale
    /// Widget appearance used by the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds available chart content or a visible unavailable placeholder.
    var body: some View {
        if let city = entry.city {
            VStack(alignment: .leading, spacing: 9) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    conditionSymbolName: city.currentConditionSymbolName,
                    summaryText: widgetSunnyRangeText(for: city, locale: locale),
                    font: .headline.weight(.semibold),
                    usesWeatherColors: true
                )

                if city.widgetSunnyWindowIssue != nil {
                    WidgetDataUnavailablePlaceholder()
                } else if let timeZone = city.widgetTimeZone,
                          // Merge the visible daylight domains only when every day has real bounds.
                          let chartBounds: SunnyHoursChartBounds = {
                              let days = city.widgetSunnyWindowDays
                              let bounds = days.compactMap(\.daylightBounds)
                              return bounds.count == days.count
                                  ? SunnyHoursChartBounds.merged(bounds)
                                  : nil
                          }() {
                    SunnyWindowLargeChart(
                        days: city.widgetSunnyWindowDays,
                        currentDate: entry.date,
                        locale: locale,
                        timeZone: timeZone,
                        chartBounds: chartBounds
                    )
                    .padding(.top, 7)
                    .frame(maxHeight: .infinity, alignment: .top)

                    SunnyHoursLegend()
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(AppPalette.values(for: colorScheme).titleText)
            .widgetURL(widgetPlacesURL(for: city, issue: city.widgetSunnyWindowIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }
}

/// Height-adaptive ten-day widget timeline using real daylight bounds.
private struct SunnyWindowLargeChart: View {
    /// Available day rows after source-data validation.
    let days: [WidgetSunnyWindowDay]
    /// Timeline entry date used for the current-time marker.
    let currentDate: Date
    /// Main-app locale used by date labels.
    let locale: Locale
    /// Selected city timezone.
    let timeZone: TimeZone
    /// Merged real daylight domain across visible rows.
    let chartBounds: SunnyHoursChartBounds

    // Match the detail chart's redundant solid/dashed outlines
    // when the user asks the interface not to communicate with color alone.
    /// Preference adding patterned distinctions to sunny segment types.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// Contrast preference strengthening chart guides and tracks.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode used to replace colors in tinted/vibrant widgets.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme

    /// Width reserved for compact day labels.
    private let labelWidth: CGFloat = 52
    /// Height reserved for hour-axis labels.
    private let axisHeight: CGFloat = 18
    /// Visible track and segment thickness.
    private let capsuleHeight: CGFloat = 10

    /// Maximum ten rows represented by the large widget.
    private var visibleDays: [WidgetSunnyWindowDay] {
        Array(days.prefix(10))
    }

    /// Integer tick hours chosen for the daylight domain.
    private var axisHours: [Int] {
        chartBounds.axisHours(maximumTickCount: 8)
    }

    /// Divides actual WidgetKit height among rows so the legend never overlaps.
    var body: some View {
        GeometryReader { geometry in
            let timelineWidth = max(geometry.size.width - labelWidth, 1)
            // Reserve two points between the axis and the first forecast row.
            let availableRowsHeight = max(
                geometry.size.height - axisHeight - 2,
                0
            )
            // WidgetKit can give the same family different usable heights on
            // iPhone and iPad. Divide the actual proposal exactly so the chart
            // never grows into the legend below it.
            let rowHeight = visibleDays.isEmpty
                ? 0
                : availableRowsHeight / CGFloat(visibleDays.count)
            let rowsHeight = CGFloat(visibleDays.count) * rowHeight

            VStack(spacing: 2) {
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

    /// Positions hour labels over the shared timeline width.
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

    /// Builds date labels and contiguous sunny/partly-sunny capsules.
    private func rowsView(
        _ visibleDays: [WidgetSunnyWindowDay],
        timelineWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(visibleDays) { day in
                let isCurrentDay = isToday(day.date)
                HStack(spacing: 0) {
                    // Format Today or a compact localized month/day label.
                    Text({
                        if isCurrentDay {
                            return widgetLocalizedString("Today")
                        }
                        var format = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(locale)
                        format.timeZone = timeZone
                        return day.date.formatted(format)
                    }())
                        .font(.caption2.weight(isCurrentDay ? .bold : .medium))
                        .foregroundStyle(isCurrentDay ? renderedPrimary : renderedSecondary)
                        .lineLimit(1)
                        .frame(width: labelWidth, alignment: .leading)

                    ZStack(alignment: .leading) {
                        Capsule()
                            // Adapt the empty daylight track to rendering and contrast modes.
                            .fill(
                                usesSystemRenderingColors
                                    ? .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
                                    : palette.settingsRow
                            )
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
                    // Give each capsule a stable 16-point visual lane.
                    .frame(width: timelineWidth, height: 16)
                }
                .frame(height: rowHeight)
            }
        }
    }

    /// Draws vertical hour guides across the visible row region.
    private func gridLines(
        rowCount: Int,
        timelineWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let rowsHeight = CGFloat(rowCount) * rowHeight
        let verticalInset = (16 - capsuleHeight) / 2
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
            // Keep vertical guides subordinate in every rendering mode.
            .stroke(
                renderedSecondary.opacity(colorSchemeContrast == .increased ? 0.18 : 0.08),
                lineWidth: 1
            )
            .frame(width: timelineWidth, height: rowsHeight)
        }
        .frame(height: rowsHeight)
    }

    @ViewBuilder
    /// Draws selected-city local time only on today's row inside daylight.
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

    /// Returns semantic or system-rendered color for one segment kind.
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

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    /// Whether WidgetKit requires monochrome/tinted semantic foregrounds.
    private var usesSystemRenderingColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground in full-color or system-rendered mode.
    private var renderedPrimary: Color {
        usesSystemRenderingColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground in full-color or system-rendered mode.
    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }

    /// Whether a literal row date matches the city's current local day.
    private func isToday(_ date: Date) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: currentDate)
    }

}

// MARK: - Medium Daily Presentation

/// Medium Home Screen widget content for one city's current local day.
private struct SunnyHoursHomeWidgetView: View {
    /// Active widget family used for compact spacing decisions.
    @Environment(\.widgetFamily) private var family
    /// Main-app locale used by the sunny-window summary.
    @Environment(\.locale) private var locale
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds configured city content or remains empty before catalog publication.
    var body: some View {
        if let city = entry.city {
            content(city)
                .widgetURL(widgetPlacesURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    /// Builds header, current-day timeline, legend, or missing-data state.
    private func content(_ city: WidgetDataCity) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            SunnyHoursHeader(
                cityName: city.cityName,
                conditionSymbolName: city.currentConditionSymbolName,
                summaryText: widgetSunnyRangeText(for: city, locale: locale),
                font: .headline.weight(.semibold),
                usesWeatherColors: true
            )

            if city.widgetCurrentIssue != nil {
                WidgetDataUnavailablePlaceholder()
            } else {
                SunnyHoursTimeline(city: city, currentDate: entry.date)
                    .padding(.top, 12)
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

/// Shared full-color widget background drawn from the app palette.
private struct WidgetPaletteBackground: View {
    /// Widget appearance selecting light or dark background.
    @Environment(\.colorScheme) private var colorScheme

    /// Fills the widget container with the semantic canvas.
    var body: some View {
        AppPalette.values(for: colorScheme).background
    }
}

// MARK: - Timeline Entry and Provider

/// The historical type name is retained because it participates in existing
/// AppIntent/widget configurations; the entry is shared by every widget size.
private struct SunnyHoursLockScreenEntry: TimelineEntry {
    /// Entry generation time used by current-time markers and refresh policy.
    let date: Date
    /// Configured city with applied snapshot, or `nil` before configuration.
    let city: WidgetDataCity?

    /// Deterministic sample entry used by WidgetKit previews.
    static let preview = SunnyHoursLockScreenEntry(date: .now, city: .preview)
}

/// Shared by the medium, large, and lock-screen widgets so all three use the
/// same WeatherKit request, cache, and refresh policy.
private struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    /// Normal WeatherKit refresh cadence requested from WidgetKit.
    private let normalRefreshInterval: TimeInterval = 30 * 60
    /// Failure cadence; WidgetKit treats this as an earliest preferred retry.
    private let failureRetryInterval: TimeInterval = 15 * 60

    /// Refresh output plus whether WidgetKit should retry unusually soon.
    private struct RefreshResult {
        /// Configured city after cache or WeatherKit application.
        let city: WidgetDataCity?
        /// Whether missing/stale data warrants an earlier retry.
        let needsShortRetry: Bool
    }

    /// Supplies immediate gallery content from cache or deterministic preview data.
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry {
        let configuration = SunnyHoursLockScreenConfigurationIntent()
        return SunnyHoursLockScreenEntry(
            date: .now,
            city: cityUsingCachedSnapshot(for: configuration) ?? .preview
        )
    }

    /// Supplies gallery snapshot or performs a direct WeatherKit refresh.
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

    /// Produces one entry and requests normal or short-retry refresh timing.
    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let result = await refreshedCity(for: configuration)
        let entry = SunnyHoursLockScreenEntry(date: .now, city: result.city)
        let retryDelay = result.needsShortRetry ? failureRetryInterval : normalRefreshInterval
        // WidgetKit treats this as a preferred refresh time, rather than a precise schedule.
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(retryDelay)))
    }

    /// Resolves configured scope and city while validating membership.
    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetDataCity? {
        guard let catalog = WidgetDataStore.catalog() else { return nil }
        let scope: WidgetPlaceScope?
        if let selectedScope = configuration.placeScope {
            scope = catalog.placeScopes.first(where: { $0.id == selectedScope.id })
        } else {
            scope = catalog.placeScopes.first
        }

        guard let scope else { return nil }
        if let selectedCity = configuration.city {
            return scope.cities.first(where: { $0.id == selectedCity.id })
        }
        return scope.cities.first
    }

    /// Applies the latest usable widget-owned cache, even when it is stale.
    private func cityUsingCachedSnapshot(
        for configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> WidgetDataCity? {
        guard let city = selectedCity(for: configuration) else { return nil }
        guard let snapshot = WidgetDataStore.latestWeatherSnapshot(for: city.id),
              isUsable(snapshot, for: city) else {
            return city.markingUnavailable(.missingForecastData)
        }
        return city.applying(snapshot)
    }

    /// Uses fresh cache or makes a bounded direct WeatherKit request.
    ///
    /// Failed refreshes never overwrite the last-known-good snapshot. A stale
    /// snapshot remains visible while WidgetKit schedules the next retry.
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
           isUsable(snapshot, for: city) {
            return RefreshResult(
                city: city.applying(snapshot),
                needsShortRetry: false
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
                if isUsable(snapshot, for: city) {
                    WidgetDataStore.saveWeatherSnapshot(snapshot, for: city.id)
                    return RefreshResult(
                        city: city.applying(snapshot),
                        needsShortRetry: false
                    )
                }
                return fallbackResult(for: city, unavailableSnapshot: snapshot)
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(750))
                }
            }
        }

        return fallbackResult(for: city)
    }

    /// Returns stale last-known-good weather before exposing an unavailable state.
    private func fallbackResult(
        for city: WidgetDataCity,
        unavailableSnapshot: WidgetWeatherSnapshot? = nil
    ) -> RefreshResult {
        if let snapshot = WidgetDataStore.latestWeatherSnapshot(for: city.id),
           isUsable(snapshot, for: city) {
            return RefreshResult(
                city: city.applying(snapshot),
                needsShortRetry: true
            )
        }

        return RefreshResult(
            city: unavailableSnapshot.map(city.applying)
                ?? city.markingUnavailable(.missingForecastData),
            needsShortRetry: true
        )
    }

    /// Validates that one snapshot can render every supported widget family.
    private func isUsable(_ snapshot: WidgetWeatherSnapshot, for city: WidgetDataCity) -> Bool {
        let resolvedCity = city.applying(snapshot)
        return resolvedCity.widgetCurrentIssue == nil
            && resolvedCity.widgetSunnyWindowIssue == nil
    }

    /// Converts WeatherKit data while preserving every missing/unknown source issue.
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

    /// Creates an empty weather payload carrying an exact failure reason.
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

    /// Selects hourly intervals intersecting real sunrise-to-sunset daylight.
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

    /// Delegates interval/daylight overlap using the selected city timezone.
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

/// Minimal widget-only classification for sunny-hour grouping.
private enum WidgetCondition {
    case sunny
    case partlySunny
    case other

    /// Resolves a WeatherKit symbol, failing rather than assigning a default.
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

/// Classified integer hours or the exact unknown-symbol issue encountered.
private struct WidgetForecastHourBreakdown {
    /// Every validated daylight hour.
    let daytimeHours: [Int]
    /// Hours classified as fully sunny.
    let sunnyHours: [Int]
    /// Hours classified as partly sunny.
    let partlySunnyHours: [Int]
    /// Source issue preventing a trustworthy breakdown.
    let dataIssue: WeatherDataIssue?

    /// Classifies WeatherKit hours using the selected city calendar.
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
    /// Extracts the typed failure while leaving successful values untouched.
    var failure: WeatherDataIssue? {
        guard case .failure(let issue) = self else { return nil }
        return issue
    }
}

// MARK: - Lock-Screen Widget

/// Rectangular Lock Screen widget showing one city's current-day timeline.
struct SunnyHoursLockScreenWidget: Widget {
    /// Stable WidgetKit registration kind.
    static let kind = "SunnyHoursLockScreenWidget"

    /// Registers the accessory widget with the shared configuration/provider.
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursLockScreenWidgetView(entry: entry)
                .environment(\.locale, WidgetDataStore.appLocale)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(WidgetDataStore.localizedText(for: "Sunny Hours"))
        .description(WidgetDataStore.localizedText(for: "Track sunny daytime hours for a chosen city."))
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Compact Lock Screen header, timeline, and missing-data presentation.
private struct SunnyHoursLockScreenWidgetView: View {
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds configured accessory content or remains empty before configuration.
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
            .widgetURL(widgetPlacesURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }
}

// MARK: - Shared Widget Presentation

/// Shared city-name and current-condition header for every widget family.
private struct SunnyHoursHeader: View {
    /// Widget appearance selecting the weather icon palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Rendering mode determining full-color versus monochrome symbols.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Localized configured city name.
    let cityName: String
    /// Optional recognized current-condition source symbol.
    let conditionSymbolName: String?
    /// Optional sunny-window text replacing the condition icon on Home Screen widgets.
    var summaryText: String? = nil
    /// Family-specific header font.
    let font: Font
    /// Whether full-color weather icon rendering is permitted.
    let usesWeatherColors: Bool

    /// Builds city title and condition icon without symbol fallback.
    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            if let summaryText {
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        widgetRenderingMode == .fullColor
                            ? AppPalette.values(for: colorScheme).secondaryText
                            : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else if let conditionSymbolName {
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

/// Formats the longest current-day sunny or partly-sunny run for widget headers.
private func widgetSunnyRangeText(for city: WidgetDataCity, locale: Locale) -> String {
    guard city.widgetCurrentIssue == nil else { return "—" }
    let ranges = SunnyHoursFormatting.contiguousRanges(
        in: city.sunnyHours + city.partlySunnyHours
    )
    guard let range = ranges.max(by: {
        $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound
    }) else {
        return widgetLocalizedString("No Sun")
    }

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = DateFormatter.dateFormat(
        fromTemplate: "j",
        options: 0,
        locale: locale
    )
    func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = ((hour % 24) + 24) % 24
        return components.date.map(formatter.string(from:))
            ?? SunnyHoursFormatting.chartHourLabel(hour)
    }
    return "\(hourLabel(range.lowerBound)) – \(hourLabel(range.upperBound + 1))"
}

/// Current-day capsule timeline shared by medium and Lock Screen widgets.
private struct SunnyHoursTimeline: View {
    /// Layout and rendering density for each widget family.
    enum Style {
        case home
        case lockScreen
    }

    /// Stable axis identity is the unique represented clock hour.
    private struct AxisMarker: Identifiable {
        let hour: Int
        let capsuleIndex: Int

        var id: Int { hour }
    }

    /// Adds outlines as a redundant cue when colors alone are insufficient.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// Contrast preference strengthening tracks and outlines.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode controlling system monochrome/tinted colors.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Main-app locale used by time labels.
    @Environment(\.locale) private var locale
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Configured city with current-day chart data.
    let city: WidgetDataCity
    /// Entry time used by the city-local current-time marker.
    let currentDate: Date
    /// Family-specific style.
    var style: Style = .home

    /// Builds capsule hours, current-time marker, and family-specific axis.
    var body: some View {
        let hours = displayedHours
        if let startHour = hours.first, let endHour = hours.last {
            VStack(spacing: style == .home ? 4 : 3) {
                GeometryReader { proxy in
                    let capsuleHeight = proxy.size.height
                    let capsuleSpacing: CGFloat = style == .home ? 7 : 8
                    let capsuleWidth = (
                        proxy.size.width - capsuleSpacing * CGFloat(hours.count - 1)
                    ) / CGFloat(hours.count)
                    ZStack(alignment: .leading) {
                        HStack(spacing: capsuleSpacing) {
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
                                    // Place the marker in the gap nearest the city's current hour.
                                    x: CGFloat(boundaryIndex) * capsuleWidth
                                        + (CGFloat(boundaryIndex) - 0.5) * capsuleSpacing,
                                    y: capsuleHeight / 2
                                )
                        }
                    }
                    .frame(height: capsuleHeight, alignment: .top)
                }
                // Preserve usable Home Screen capsule thickness.
                .frame(minHeight: style == .home ? 44 : 18)

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
                        let capsuleSpacing: CGFloat = style == .home ? 7 : 8
                        let capsuleWidth = (
                            proxy.size.width - capsuleSpacing * CGFloat(hours.count - 1)
                        ) / CGFloat(hours.count)
                        ZStack(alignment: .leading) {
                            ForEach(axisMarkers) { marker in
                                Text(SunnyHoursFormatting.chartHourLabel(marker.hour))
                                    .position(
                                        // Align each clock label with its nearest capsule center.
                                        x: CGFloat(marker.capsuleIndex) * (capsuleWidth + capsuleSpacing)
                                            + capsuleWidth / 2,
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
    /// Adds solid/dashed outlines to distinguish sunny segment types.
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

    /// Returns sunny, partly-sunny, or track color for one displayed hour.
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
            return colors.settingsRow
        }

        if city.sunnyHours.contains(hour) {
            return palette.dotSun
        }
        if city.partlySunnyHours.contains(hour) {
            return palette.dotPartlyCloudy
        }
        return palette.settingsRow
    }

    /// Thin marker placed at the nearest current-hour boundary.
    private var currentTimeMarker: some View {
        Rectangle()
            .fill(renderedPrimary.opacity(0.9))
            .frame(width: 2)
    }

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    /// Whether family/rendering mode requires semantic system foregrounds.
    private var usesSystemRenderingColors: Bool {
        style == .lockScreen || widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground.
    private var renderedPrimary: Color {
        usesSystemRenderingColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground.
    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }

    /// Finds the capsule boundary nearest the city's current local hour.
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

    /// Real daylight hours, downsampled only for Lock Screen space constraints.
    private var displayedHours: [Int] {
        let sourceHours: [Int]
        if let daylightBounds = city.daylightBounds {
            sourceHours = Array(daylightBounds.startHour..<daylightBounds.endHour)
        } else {
            // Published daytime hours provide a complete fallback domain.
            let daytime = city.daytimeHours.sorted()
            sourceHours = daytime.isEmpty
                ? Array(Set(city.sunnyHours + city.partlySunnyHours)).sorted()
                : daytime
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

    /// Maps four evenly spaced desired hours to the nearest actual capsule centers.
    private func timelineAxisMarkers(
        for hours: [Int],
        from startHour: Int,
        through endHour: Int
    ) -> [AxisMarker] {
        guard !hours.isEmpty else { return [] }
        let span = max(endHour - startHour, 0)
        let axisHours = (0...3).reduce(into: [Int]()) { hours, index in
            let hour = startHour
                + Int((Double(span) * Double(index) / 3).rounded())
            if hours.last != hour {
                hours.append(hour)
            }
        }

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
            return AxisMarker(hour: hour, capsuleIndex: capsuleIndex)
        }
    }

}

/// Centered three-state key shared by medium and large Home Screen timelines.
private struct SunnyHoursLegend: View {
    /// Locale published by the main app.
    @Environment(\.locale) private var locale
    /// Replaces color dots with condition symbols when requested.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// Contrast preference selecting stronger semantic colors.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode selecting system or full-color foregrounds.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme

    /// Builds the same three centered legend items used by Detail View.
    var body: some View {
        HStack(spacing: 14) {
            item(
                // Effective fully sunny swatch color.
                color: usesSystemRenderingColors
                    ? .primary.opacity(1)
                    : colorSchemeContrast == .increased
                        ? AppPalette.increasedContrastValues(for: colorScheme).dotSun
                        : palette.dotSun,
                title: widgetLocalizedString("Sunny"),
                symbol: WeatherIconSymbol.clear
            )
            item(
                // Effective partly sunny swatch color.
                color: usesSystemRenderingColors
                    ? .primary.opacity(0.48)
                    : colorSchemeContrast == .increased
                        ? AppPalette.increasedContrastValues(for: colorScheme).dotPartlyCloudy
                        : palette.dotPartlyCloudy,
                title: widgetLocalizedString("Partly Sunny"),
                symbol: WeatherIconSymbol.partlyCloudy
            )
            item(
                color: usesSystemRenderingColors
                    ? .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
                    : colorSchemeContrast == .increased
                        ? AppPalette.increasedContrastValues(for: colorScheme).settingsRow
                        : palette.settingsRow,
                title: widgetLocalizedString("No Sun"),
                symbol: WeatherIconSymbol.cloudy
            )
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(renderedSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    /// Builds one color-dot or redundant-symbol legend item.
    private func item(color: Color, title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            if differentiateWithoutColor {
                let iconPalette = widgetConditionIconPalette(for: symbol, colors: palette)
                Image(systemName: widgetConditionDisplaySymbolName(for: symbol))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconPalette.primary, iconPalette.secondary)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
            }
            Text(title)
        }
    }

    /// Standard primitive palette for widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme)
    }

    /// Whether WidgetKit requires monochrome/tinted semantic colors.
    private var usesSystemRenderingColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective secondary foreground for labels and divider.
    private var renderedSecondary: Color {
        usesSystemRenderingColors ? .secondary : palette.secondaryText
    }
}

// MARK: - Widget Missing-Data Presentation

/// Compact visible and accessible fallback for missing widget configuration or
/// unavailable WeatherKit data.
private struct WidgetDataUnavailablePlaceholder: View {
    /// Widget family used to keep Lock Screen copy to one line.
    @Environment(\.widgetFamily) private var family

    /// Presents a concise recovery action in every supported family.
    var body: some View {
        let message = widgetLocalizedString("Open Weather Atlas to refresh.")

        Label(message, systemImage: "icloud.slash")
            .font(.caption2.weight(.medium))
            .lineLimit(family == .accessoryRectangular ? 1 : 2)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
    }
}

/// Maps a recognized WeatherKit symbol to the app's canonical display symbol.
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

/// Returns the semantic two-color palette for a widget condition icon.
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

/// Builds a Places deep link carrying exact missing-data diagnostics when needed.
private func widgetPlacesURL(for city: WidgetDataCity, issue: WeatherDataIssue?) -> URL? {
    guard let separator = city.id.firstIndex(of: "|"),
          separator > city.id.startIndex else {
        return nil
    }
    let scopeID = String(city.id[..<separator])
    var components = URLComponents()
    components.scheme = "weatheratlas"
    components.host = "places"
    components.path = "/\(scopeID)"
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

private extension WidgetPlaceScope {
    /// Deterministic scope fixture used by widget previews and placeholders.
    static let preview = WidgetPlaceScope(
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
    /// Deterministic multi-day city fixture used by WidgetKit previews.
    static var preview: WidgetDataCity {
        var city = WidgetPlaceScope.preview.cities[0]
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

    /// Available large-widget rows, omitting only incomplete source days.
    var widgetSunnyWindowDays: [WidgetSunnyWindowDay] {
        (sunnyWindowDays ?? []).filter {
            $0.dataIssue == nil && $0.daylightBounds != nil
        }
    }

    /// Valid timezone represented by the published identifier.
    var widgetTimeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// Exact issue preventing current-day widget content.
    var widgetCurrentIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        guard daylightBounds != nil else { return .missingSunriseOrSunset }
        guard !daytimeHours.isEmpty else { return .missingHourlyData }
        return nil
    }

    /// Exact issue preventing the large multi-day chart.
    var widgetSunnyWindowIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        let days = widgetSunnyWindowDays
        guard !days.isEmpty else { return .missingForecastData }
        return nil
    }

    /// Missing or unknown current-condition symbol issue.
    var widgetCurrentConditionIssue: WeatherDataIssue? {
        guard let currentConditionSymbolName else { return .missingForecastData }
        guard WeatherSymbolClassification.resolve(currentConditionSymbolName) != nil else {
            return .unknownWeatherSymbol(currentConditionSymbolName)
        }
        return nil
    }

    /// Replaces weather-bearing catalog fields with a fetched cached snapshot.
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

    /// Clears weather-bearing content while retaining identity and exact issue.
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

/// Widget extension entry point registering all supported widget families.
@main
struct WeatherWidgetsBundle: WidgetBundle {
    /// Declares medium, large, and rectangular Lock Screen widgets.
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
    }
}

// MARK: - Previews

#Preview("Sunny Hours (Daily) - Medium", as: .systemMedium) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

#Preview("Sunny Hours — Large", as: .systemLarge) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

#Preview("Sunny Hours - Lock Screen", as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
