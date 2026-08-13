//
//  Widgets.swift
//  WeatherWidgets
//
//  Purpose: Displays configurable home and lock-screen weather widgets.
//
//  Reading guide: WidgetKit asks this extension for small, pre-rendered timeline
//  entries rather than running the main app's screens. This file has four layers:
//  configuration via App Intents, a shared timeline provider, SwiftUI views for
//  each supported size, and safe translation of WeatherKit/cache data into those
//  views.
//

import AppIntents
import CoreLocation
import SwiftUI
import WeatherKit
import WidgetKit

// MARK: - Widget Locale Lookup

/// Looks up widget copy that the localized main app published into the app group.
/// The widget target may be launched independently, so it reads the app-selected
/// language from shared storage instead of assuming its process has that context.
func widgetLocalizedString(_ key: String) -> String {
    WidgetDataStore.localizedText(for: key)
}

// MARK: - Widget City Selection

/// App Intent entity representing one saved city.
/// App Intents expose this lightweight value to the system configuration sheet;
/// it is not a live model object shared with the main app.
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
    /// The string-literal resource preserves a runtime city name rather than
    /// treating it as a localization key that must exist in the extension's
    /// String Catalog.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: cityName))
    }
}

/// Searchable city resolver for Saved Places.
/// WidgetKit invokes these methods while a person configures a widget,
/// potentially when the main app is closed.
struct WidgetCityQuery: EntityStringQuery {
    /// Resolves identifiers against the latest Saved Places catalog.
    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        // Intent configuration stores only IDs. Re-resolve them against the
        // latest shared catalog in case Saved Places changed since configuration.
        let cities = WidgetDataStore.catalog()?.cities ?? []
        // `compactMap` deliberately drops deleted cities rather than returning
        // a malformed App Intent entity for an ID the catalog no longer knows.
        return identifiers.compactMap { id in
            cities.first(where: { $0.id == id }).map(WidgetCityEntity.init)
        }
    }

    /// Returns all cities published from Saved Places.
    /// WidgetKit uses this list as its initial suggestion list.
    func suggestedEntities() async throws -> [WidgetCityEntity] {
        (WidgetDataStore.catalog()?.cities ?? []).map(WidgetCityEntity.init)
    }

    /// Uses the first Saved Place as initial configuration.
    /// The user can still select another one; this only avoids an empty
    /// configuration by default.
    func defaultResult() async -> WidgetCityEntity? {
        WidgetDataStore.catalog()?.cities.first.map(WidgetCityEntity.init)
    }

    /// Filters scoped cities by localized case-insensitive name.
    /// The protocol is async because App Intents allows remote lookups, even
    /// though this source currently reads the local shared catalog synchronously.
    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
        }
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

/// City configuration used by all Weather Atlas widgets.
/// WidgetKit persists the selected `WidgetCityEntity` and passes it back to
/// every provider callback.
struct SunnyHoursLockScreenConfigurationIntent: WidgetConfigurationIntent {
    /// Configuration title shown by WidgetKit.
    static var title: LocalizedStringResource = "Sunny Hours"
    /// Configuration explanation shown by WidgetKit.
    static var description = IntentDescription("Choose a city to track its sunny daytime hours.")

    /// Searchable selected-city parameter.
    /// The `@Parameter` macro tells the system configuration UI to show the App
    /// Entity picker above.
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
        // AppIntentConfiguration connects a stable widget kind, a configurable
        // city intent, one timeline provider, and the SwiftUI view used to draw
        // every entry. WidgetKit owns calling the provider later.
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursHomeScreenWidgetView(entry: entry)
                // Inject the main app's published locale once so nested widget
                // views use the same date and text formatting policy.
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
/// `@ViewBuilder` permits the `if` branches to produce different concrete SwiftUI
/// view types while still satisfying the single `some View` body requirement.
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
            let currentIssue = city.widgetCurrentIssue
            let windowIssue = city.widgetSunnyWindowIssue
            let summaryText = widgetSunnyRangeText(for: city, locale: locale)
            VStack(alignment: .leading, spacing: 9) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    conditionSymbolName: currentIssue == nil
                        ? city.currentConditionSymbolName
                        : nil,
                    summaryText: summaryText,
                    font: .headline.weight(.semibold),
                    usesWeatherColors: true
                )

                // Validation is intentionally checked before layout. A widget
                // must show an honest unavailable state rather than a partial
                // chart whose missing daylight data could look trustworthy.
                if windowIssue != nil {
                    WidgetDataUnavailablePlaceholder()
                } else if let timeZone = city.widgetTimeZone,
                          // Merge the visible daylight domains only when every day has real bounds.
                          // The immediately invoked closure keeps this temporary
                          // validation local to the `else if` condition. Merge
                          // visible daylight domains only when every day has
                          // real bounds, so every row shares an honest x-axis.
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
            // A Home Screen widget is one deep-link destination. Present a
            // concise city-and-sunny-hours summary rather than exposing every
            // decorative chart segment and grid label to VoiceOver.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                widgetAccessibilitySummary(
                    cityName: city.cityName,
                    summaryText: summaryText,
                    hasIssue: currentIssue != nil || windowIssue != nil,
                    locale: locale
                )
            )
            // `widgetURL` makes the entire noninteractive widget a deep link;
            // WidgetKit does not support arbitrary in-widget navigation here.
            .widgetURL(widgetPlacesURL(for: city, issue: windowIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }
}

/// Height-adaptive ten-day widget timeline using real daylight bounds.
/// The chart is custom SwiftUI layout rather than Swift Charts because every
/// row needs the same solar-time x-axis while WidgetKit supplies tight sizes.
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

    // MARK: - Rendering Environment

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

    // MARK: - Fixed Layout Constants

    /// Width reserved for compact day labels.
    private let labelWidth: CGFloat = 52
    /// Height reserved for hour-axis labels.
    private let axisHeight: CGFloat = 18
    /// Visible track and segment thickness.
    private let capsuleHeight: CGFloat = 10

    // MARK: - Derived Chart Inputs

    /// Maximum ten rows represented by the large widget.
    private var visibleDays: [WidgetSunnyWindowDay] {
        Array(days.prefix(10))
    }

    /// Integer tick hours chosen for the daylight domain.
    private var axisHours: [Int] {
        chartBounds.axisHours(maximumTickCount: 8)
    }

    // MARK: - Adaptive Chart Layout

    /// Divides actual WidgetKit height among rows so the legend never overlaps.
    var body: some View {
        // GeometryReader exposes the size proposed by WidgetKit at render time.
        // It is appropriate here because row allocation genuinely depends on
        // the container's final height rather than a fixed device dimension.
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
                // Overlay independent layers on the same chart coordinate space:
                // content capsules first, then noninteractive guides and marker.
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
                        // Decorative overlays must never absorb the widget tap
                        // used by the widgetURL deep link.
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

    // MARK: - Chart Layers

    /// Positions hour labels over the shared timeline width.
    private func axisRow(timelineWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: labelWidth)
            ZStack(alignment: .leading) {
                // Hours are unique integers, so `\.self` is a stable identity
                // for SwiftUI's lightweight axis-label ForEach.
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
                // `let` declarations inside a ViewBuilder are recomputed from
                // immutable entry data on each render; they are not stored state.
                let isCurrentDay = isToday(day.date)
                HStack(spacing: 0) {
                    // Format Today or a compact localized month/day label.
                    Text({
                        if isCurrentDay {
                            return widgetLocalizedString("Today")
                        }
                        // Format dates in the selected city's timezone. A Date
                        // is absolute, so device-local formatting could label a
                        // forecast row as the previous/next calendar day.
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
                                usesSystemColors
                                    ? .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
                                    : palette.settingsRow
                            )
                            .frame(height: capsuleHeight)

                        // SunnyHoursTimelineLayout creates outer connected spans
                        // plus their inner sunny/partly-sunny pieces. The span
                        // IDs are deterministic, so SwiftUI can diff redraws.
                        ForEach(
                            SunnyHoursTimelineLayout.spans(
                                sunnyHours: day.sunnyHours,
                                partlySunnyHours: day.partlySunnyHours,
                                boundedBy: chartBounds
                            )
                        ) { span in
                            // Place the outer capsule once, then offset inner
                            // rectangles relative to its leading edge so their
                            // absolute solar-time alignment stays exact.
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
                                            // A dashed outline makes partly sunny
                                            // distinguishable when color alone is
                                            // not an accessible cue.
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
            // Build one vector path instead of a view per guide. Path coordinates
            // are local to this timeline rectangle and therefore share the axis.
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

    // `@ViewBuilder` lets this helper intentionally emit no view when today is
    // absent or the current time lies outside the chart's real daylight bounds.
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
            // Offset the marker into today's row while keeping its x coordinate
            // relative to the day-label-free timeline area.
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

    // MARK: - Rendering Colors and Local Time

    /// Returns semantic or system-rendered color for one segment kind.
    private func segmentColor(isPartlySunny: Bool) -> Color {
        if usesSystemColors {
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
    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground in full-color or system-rendered mode.
    private var renderedPrimary: Color {
        usesSystemColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground in full-color or system-rendered mode.
    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : palette.secondaryText
    }

    /// Whether a literal row date matches the city's current local day.
    private func isToday(_ date: Date) -> Bool {
        // Use the city zone rather than device zone for both dates. This keeps
        // the marker on the row the city itself calls "today".
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(date, inSameDayAs: currentDate)
    }

}

// MARK: - Medium Daily Presentation

/// Medium Home Screen widget content for one city's current local day.
/// The medium view reuses the same entry/provider as the large widget but draws
/// the compact single-day timeline instead of independently fetching weather.
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
            // The city payload is validated within content, while the outer view
            // owns the shared full-widget deep-link destination.
            content(city)
                .widgetURL(widgetPlacesURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    /// Builds header, current-day timeline, legend, or missing-data state.
    private func content(_ city: WidgetDataCity) -> some View {
        let issue = city.widgetCurrentIssue
        let summaryText = widgetSunnyRangeText(for: city, locale: locale)
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            SunnyHoursHeader(
                cityName: city.cityName,
                conditionSymbolName: issue == nil
                    ? city.currentConditionSymbolName
                    : nil,
                summaryText: summaryText,
                font: .headline.weight(.semibold),
                usesWeatherColors: true
            )

            if issue != nil {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            widgetAccessibilitySummary(
                cityName: city.cityName,
                summaryText: summaryText,
                hasIssue: issue != nil,
                locale: locale
            )
        )
    }
}

// MARK: - Shared Widget Background

/// Shared full-color widget background drawn from the app palette.
private struct WidgetPaletteBackground: View {
    /// Widget appearance selecting light or dark background.
    @Environment(\.colorScheme) private var colorScheme

    /// Fills the widget container with the semantic canvas.
    var body: some View {
        // `containerBackground(for: .widget)` above inserts this semantic color
        // only in families where WidgetKit allows the extension to own it.
        AppPalette.values(for: colorScheme).background
    }
}

// MARK: - Timeline Entry and Provider

/// The historical type name is retained because it participates in existing
/// AppIntent/widget configurations; the entry is shared by every widget size.
/// A TimelineEntry is an immutable snapshot: WidgetKit later renders it without
/// rerunning the provider or reading live WeatherKit state from a view body.
private struct SunnyHoursLockScreenEntry: TimelineEntry {
    /// Entry generation time used by current-time markers and refresh policy.
    let date: Date
    /// Configured city with applied snapshot, or `nil` before configuration.
    let city: WidgetDataCity?
    /// Deterministic sample entry used by WidgetKit previews.
    static let preview = SunnyHoursLockScreenEntry(
        date: .now,
        city: .preview
    )
}

/// Shared by the medium, large, and lock-screen widgets so all three use the
/// same WeatherKit request, cache, and refresh policy.
/// AppIntentTimelineProvider is WidgetKit's lifecycle protocol. WidgetKit calls
/// its placeholder, gallery snapshot, and scheduled timeline methods outside
/// the main app's process and decides the actual execution timing.
private struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    // MARK: - Refresh Policy

    /// Normal WeatherKit refresh cadence requested from WidgetKit.
    private let normalRefreshInterval: TimeInterval = 30 * 60
    /// Failure cadence; WidgetKit treats this as an earliest preferred retry.
    private let failureRetryInterval: TimeInterval = 15 * 60

    /// Refresh output plus whether WidgetKit should retry unusually soon.
    /// This small private type separates rendered data from retry scheduling
    /// policy.
    private struct RefreshResult {
        /// Configured city after cache or WeatherKit application.
        let city: WidgetDataCity?
        /// Whether missing/stale data warrants an earlier retry.
        let needsShortRetry: Bool
    }

    // MARK: - WidgetKit Lifecycle Callbacks

    /// Supplies immediate gallery content from cache or deterministic preview data.
    /// Placeholder must return synchronously and cheaply; it must not wait for
    /// WeatherKit, because WidgetKit uses it while loading the gallery UI.
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry {
        let configuration = SunnyHoursLockScreenConfigurationIntent()
        return SunnyHoursLockScreenEntry(
            date: .now,
            city: cityUsingCachedSnapshot(for: configuration) ?? .preview
        )
    }

    /// Supplies gallery snapshot or performs a direct WeatherKit refresh.
    func snapshot(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> SunnyHoursLockScreenEntry {
        // Previews should never make a live network request. They use a cached
        // payload when available, otherwise the deterministic fixture below.
        if context.isPreview {
            return SunnyHoursLockScreenEntry(
                date: .now,
                city: cityUsingCachedSnapshot(for: configuration) ?? .preview
            )
        }
        // Use the same direct WeatherKit path as the timeline so a newly added
        // widget does not wait for WidgetKit's next scheduled refresh.
        let result = await refreshedCity(for: configuration)
        return SunnyHoursLockScreenEntry(
            date: .now,
            city: result.city
        )
    }

    /// Produces one entry and requests normal or short-retry refresh timing.
    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let result = await refreshedCity(for: configuration)
        let entry = SunnyHoursLockScreenEntry(
            date: .now,
            city: result.city
        )
        let retryDelay = result.needsShortRetry ? failureRetryInterval : normalRefreshInterval
        // WidgetKit treats this as a preferred refresh time, rather than a precise schedule.
        // `.after` is an earliest preferred refresh, not a background-task
        // schedule the system guarantees to honor.
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(retryDelay)))
    }

    // MARK: - City and Cache Resolution

    /// Resolves the configured city against the latest Saved Places catalog.
    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetDataCity? {
        // Configuration may reference a deleted city. Preserve that configured
        // identity as an unavailable value so the widget can deep-link the exact
        // place-data issue instead of silently switching to another Saved Place.
        guard let catalog = WidgetDataStore.catalog() else {
            guard let selectedCity = configuration.city else { return nil }
            return unavailableConfiguredCity(
                selectedCity,
                issue: .unresolvedPlace("saved place catalog")
            )
        }
        if let selectedCity = configuration.city {
            return catalog.cities.first(where: { $0.id == selectedCity.id })
                ?? unavailableConfiguredCity(
                    selectedCity,
                    issue: .unresolvedPlace("saved place")
                )
        }
        return catalog.cities.first
    }

    /// Retains an App Intent's configured identity when its Saved Place record
    /// cannot be resolved, allowing the unavailable widget to route the exact
    /// issue without substituting a different city.
    private func unavailableConfiguredCity(
        _ city: WidgetCityEntity,
        issue: WeatherDataIssue
    ) -> WidgetDataCity {
        WidgetDataCity(
            id: city.id,
            cityName: city.cityName,
            timeZoneIdentifier: nil,
            latitude: nil,
            longitude: nil,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            dataIssue: issue
        )
    }

    /// Applies only a fresh snapshot for the destination's current local day.
    /// Placeholder/gallery rendering must not briefly present yesterday's
    /// weather as current while a later timeline refresh is still pending.
    private func cityUsingCachedSnapshot(
        for configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> WidgetDataCity? {
        guard let city = selectedCity(for: configuration) else { return nil }
        if let issue = city.widgetIdentityIssue {
            return city.markingUnavailable(issue)
        }
        guard let snapshot = WidgetDataStore.weatherSnapshot(for: city.id) else {
            return city.markingUnavailable(.missingForecastData(at: .now))
        }
        guard snapshotMatchesCity(snapshot, city: city) else {
            return city.markingUnavailable(.missingTimeZone)
        }
        // A partial snapshot must never become a fresh-looking widget while a
        // later timeline tries to repair it. Placeholder rendering cannot start
        // network work, so leave it blank and preserve its exact issue instead.
        guard isUsable(snapshot, for: city) else {
            return city.markingUnavailable(
                unavailableIssue(for: snapshot, city: city)
            )
        }
        return city.applying(snapshot)
    }

    /// Uses fresh cache or makes a bounded direct WeatherKit request.
    ///
    /// Failed refreshes produce an unavailable entry. WidgetKit schedules the
    /// next retry, but an expired snapshot is never presented as current.
    private func refreshedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) async -> RefreshResult {
        // A missing selection is recoverable: return an empty entry and request
        // a short retry in case the main app has not published its catalog yet.
        guard let city = selectedCity(for: configuration) else {
            return RefreshResult(city: nil, needsShortRetry: true)
        }
        if let issue = city.widgetIdentityIssue {
            return RefreshResult(
                city: city.markingUnavailable(issue),
                needsShortRetry: true
            )
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude else {
            return RefreshResult(
                city: city.markingUnavailable(.unresolvedPlace("coordinates")),
                needsShortRetry: true
            )
        }

        // A fresh validated snapshot avoids a network request and is the normal
        // fast path when WidgetKit wakes the extension between app launches.
        if let snapshot = WidgetDataStore.weatherSnapshot(for: city.id),
           snapshotMatchesCity(snapshot, city: city),
           isUsable(snapshot, for: city) {
            return RefreshResult(
                city: city.applying(snapshot),
                needsShortRetry: false
            )
        }

        // The cache is no longer a valid presentation source. Remove it before
        // starting the refresh so a later callback cannot revive it after a
        // network or validation failure.
        WidgetDataStore.removeWeatherSnapshot(for: city.id)

        // A widget can be asked for its first timeline while WeatherKit is still
        // establishing the extension's service session. An unavailable request
        // or an incomplete *successful* snapshot each receive one immediate
        // re-fetch before WidgetKit gets an unavailable entry. This is a bounded
        // two-attempt policy, not an unbounded background loop; WidgetKit owns
        // any later retry through the timeline policy.
        var finalRequestError: Error?
        for attempt in 0..<2 {
            do {
                // WeatherKit returns an aggregate containing daily and hourly
                // forecasts for this coordinate; makeWeatherSnapshot validates
                // and reduces it to the widget's Codable data contract.
                let weather = try await WeatherService.shared.weather(
                    for: CLLocation(latitude: latitude, longitude: longitude)
                )
                let snapshot = makeWeatherSnapshot(weather: weather, city: city)
                if isUsable(snapshot, for: city) {
                    // Persist only a fully usable response. An incomplete result
                    // is a transient repair candidate, never a stale fallback for
                    // the next gallery/placeholder render.
                    WidgetDataStore.saveWeatherSnapshot(snapshot, for: city.id)
                    return RefreshResult(
                        city: city.applying(snapshot),
                        needsShortRetry: false
                    )
                }

                // A real WeatherKit response omitted a required value. Throw
                // away this first partial snapshot and immediately try once more.
                // The second partial response is retained only as an exact issue
                // on a blank widget, never as partially rendered weather.
                WidgetDataStore.removeWeatherSnapshot(for: city.id)
                if attempt == 0 {
                    continue
                }
                return RefreshResult(
                    city: city.markingUnavailable(
                        unavailableIssue(for: snapshot, city: city)
                    ),
                    needsShortRetry: true
                )
            } catch {
                finalRequestError = error
                if attempt == 0, isTransientWeatherRequestError(error) {
                    // Cooperative async sleep yields the extension task rather
                    // than blocking a thread while WeatherKit initializes.
                    try? await Task.sleep(for: .milliseconds(750))
                } else {
                    break
                }
            }
        }

        WidgetDataStore.removeWeatherSnapshot(for: city.id)
        let errorDetail = finalRequestError.map {
            String(reflecting: type(of: $0))
        }
        return RefreshResult(
            city: city.markingUnavailable(.weatherRequestFailed(errorDetail)),
            needsShortRetry: true
        )
    }

    private func isTransientWeatherRequestError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    /// Validates that one snapshot can render every supported widget family.
    /// Apply first so validation uses the snapshot's timezone and weather fields,
    /// while retaining catalog identity and deep-link coordinates from `city`.
    private func isUsable(_ snapshot: WidgetWeatherSnapshot, for city: WidgetDataCity) -> Bool {
        let resolvedCity = city.applying(snapshot)
        return resolvedCity.widgetCurrentIssue == nil
            && resolvedCity.widgetSunnyWindowIssue == nil
    }

    /// Extracts the same precise issue that the widget's blank state will expose
    /// through its deep link. The source snapshot itself is never returned after
    /// a failed second attempt, which prevents missing data from looking current.
    private func unavailableIssue(
        for snapshot: WidgetWeatherSnapshot,
        city: WidgetDataCity
    ) -> WeatherDataIssue {
        let resolvedCity = city.applying(snapshot)
        return resolvedCity.widgetCurrentIssue
            ?? resolvedCity.widgetSunnyWindowIssue
            ?? .missingForecastData(at: .now)
    }

    /// Rejects snapshots created for a superseded or corrupt timezone identity.
    private func snapshotMatchesCity(
        _ snapshot: WidgetWeatherSnapshot,
        city: WidgetDataCity
    ) -> Bool {
        guard let cityIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: cityIdentifier) != nil else {
            return false
        }
        return snapshot.timeZoneIdentifier == cityIdentifier
    }

    // MARK: - WeatherKit Snapshot Construction

    /// Converts WeatherKit data while preserving every missing/unknown source issue.
    /// The method is intentionally strict: a widget should show an unavailable
    /// state rather than interpolate missing sunrise, hourly, or symbol values.
    private func makeWeatherSnapshot(weather: Weather, city: WidgetDataCity) -> WidgetWeatherSnapshot {
        let now = Date()
        guard let timeZone = city.timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: city.timeZoneIdentifier,
                issue: .missingTimeZone
            )
        }
        // WeatherKit Dates are absolute instants. Interpret both `now` and each
        // forecast date in the configured city's timezone before choosing today.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard let today = weather.dailyForecast.forecast.first(where: {
            calendar.isDate($0.date, inSameDayAs: now)
        }) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                issue: .missingForecastData(
                    at: calendar.startOfDay(for: now)
                )
            )
        }
        // The header describes current weather, so use WeatherKit's current
        // record rather than substituting the daily condition. An unrecognized
        // future symbol becomes an explicit issue and leaves the icon blank.
        let currentConditionSymbolName = weather.currentWeather.symbolName
        guard WeatherSymbolClassification.resolve(currentConditionSymbolName) != nil else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                issue: .unknownWeatherSymbol(
                    currentConditionSymbolName,
                    at: calendar.startOfDay(for: now)
                )
            )
        }

        // Convert WeatherKit's sequence once because it is used for current day
        // and every large-widget row below.
        let hourlyForecasts = Array(weather.hourlyForecast.forecast)
        let currentDaylight = daylightResolution(
            on: now,
            sunrise: today.sun.sunrise,
            sunset: today.sun.sunset,
            from: hourlyForecasts,
            calendar: calendar,
            referenceDate: now
        )
        let resolvedCurrentDaylight: WidgetDaylightResolution
        switch currentDaylight {
        case .success(let resolution):
            resolvedCurrentDaylight = resolution
        case .failure(let issue):
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: currentConditionSymbolName,
                issue: issue
            )
        }
        guard let currentRegime = WidgetDaylightRegime(
            resolvedCurrentDaylight.regime
        ),
        let daylightBounds = SunnyHoursChartBounds.daylight(
            regime: resolvedCurrentDaylight.regime,
            timeZone: timeZone
        ) else {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: currentConditionSymbolName,
                issue: .invalidValue(
                    "daylight bounds",
                    at: calendar.startOfDay(for: now)
                )
            )
        }

        // Reduce real daylight HourWeather objects to integer chart hours plus
        // the exact symbol problem, if an hourly symbol cannot be classified.
        let currentHoursResult = widgetForecastHourBreakdown(
            hours: resolvedCurrentDaylight.hours,
            calendar: calendar
        )
        let currentHours: SunnyHoursSourceBreakdown
        switch currentHoursResult {
        case .success(let breakdown):
            currentHours = breakdown
        case .failure(let issue):
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: currentConditionSymbolName,
                issue: issue
            )
        }

        let forecastDays = Array(weather.dailyForecast.forecast.prefix(10))
        if let missingDate = firstMissingForecastDate(
            in: forecastDays,
            startingAt: now,
            calendar: calendar
        ) {
            return unavailableSnapshot(
                fetchedAt: now,
                timeZoneIdentifier: timeZone.identifier,
                currentConditionSymbolName: currentConditionSymbolName,
                issue: .missingForecastData(at: missingDate)
            )
        }

        // The large widget presents exactly ten WeatherKit daily entries. Preserve
        // incomplete rows as data-bearing failures so their absence is never
        // silently reinterpreted as a cloudy/no-sun day.
        let sunnyWindowDays = forecastDays.map { day in
            let daylightResult = daylightResolution(
                on: day.date,
                sunrise: day.sun.sunrise,
                sunset: day.sun.sunset,
                from: hourlyForecasts,
                calendar: calendar,
                referenceDate: now
            )
            switch daylightResult {
            case .failure(let issue):
                return WidgetSunnyWindowDay(
                    date: calendar.startOfDay(for: day.date),
                    sunnyHours: [],
                    partlySunnyHours: [],
                    daylightBounds: nil,
                    daylightRegime: nil,
                    dataIssue: issue
                )
            case .success(let resolvedDaylight):
                guard let regime = WidgetDaylightRegime(resolvedDaylight.regime),
                      let dayBounds = SunnyHoursChartBounds.daylight(
                        regime: resolvedDaylight.regime,
                        timeZone: timeZone
                      ) else {
                    return WidgetSunnyWindowDay(
                        date: calendar.startOfDay(for: day.date),
                        sunnyHours: [],
                        partlySunnyHours: [],
                        daylightBounds: nil,
                        daylightRegime: nil,
                        dataIssue: .invalidValue(
                            "daylight bounds",
                            at: calendar.startOfDay(for: day.date)
                        )
                    )
                }
                let hoursResult = widgetForecastHourBreakdown(
                    hours: resolvedDaylight.hours,
                    calendar: calendar
                )
                switch hoursResult {
                case .success(let hours):
                    return WidgetSunnyWindowDay(
                        date: calendar.startOfDay(for: day.date),
                        sunnyHours: hours.sunnyHours,
                        partlySunnyHours: hours.partlySunnyHours,
                        daylightBounds: dayBounds,
                        daylightRegime: regime,
                        dataIssue: nil
                    )
                case .failure(let issue):
                    return WidgetSunnyWindowDay(
                        date: calendar.startOfDay(for: day.date),
                        sunnyHours: [],
                        partlySunnyHours: [],
                        daylightBounds: dayBounds,
                        daylightRegime: regime,
                        dataIssue: issue
                    )
                }
            }
        }

        return WidgetWeatherSnapshot(
            fetchedAt: now,
            representedLocalDate: calendar.startOfDay(for: now),
            timeZoneIdentifier: timeZone.identifier,
            currentConditionSymbolName: currentConditionSymbolName,
            daytimeHours: currentHours.daytimeHours,
            sunnyHours: currentHours.sunnyHours,
            partlySunnyHours: currentHours.partlySunnyHours,
            daylightBounds: daylightBounds,
            daylightRegime: currentRegime,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
    }

    /// Creates an empty weather payload carrying an exact failure reason.
    /// The catalog city identity survives, allowing the card to deep link back
    /// to its place even while the widget cannot show forecast-derived content.
    private func unavailableSnapshot(
        fetchedAt: Date,
        timeZoneIdentifier: String?,
        currentConditionSymbolName: String? = nil,
        issue: WeatherDataIssue
    ) -> WidgetWeatherSnapshot {
        let representedLocalDate: Date?
        if let identifier = timeZoneIdentifier,
           let timeZone = TimeZone(identifier: identifier) {
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            representedLocalDate = calendar.startOfDay(for: fetchedAt)
        } else {
            representedLocalDate = nil
        }

        return WidgetWeatherSnapshot(
            fetchedAt: fetchedAt,
            representedLocalDate: representedLocalDate,
            timeZoneIdentifier: timeZoneIdentifier,
            currentConditionSymbolName: currentConditionSymbolName,
            daytimeHours: [],
            sunnyHours: [],
            partlySunnyHours: [],
            daylightBounds: nil,
            daylightRegime: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }

    /// Resolves normal, polar-day, or polar-night daylight from real events and
    /// WeatherKit's available hourly `isDaylight` flags. Partial hourly feeds are
    /// valid input; only an entirely empty local day or contradictory solar facts
    /// prevent the widget from producing a timeline.
    private func daylightResolution(
        on date: Date,
        sunrise: Date?,
        sunset: Date?,
        from forecasts: [HourWeather],
        calendar: Calendar,
        referenceDate: Date = .now
    ) -> Result<WidgetDaylightResolution, WeatherDataIssue> {
        let sourceResult = SunnyHoursSourceAnalysis.availableDaylightHours(
            on: date,
            sunrise: sunrise,
            sunset: sunset,
            from: forecasts,
            calendar: calendar,
            referenceDate: referenceDate,
            dateOf: \HourWeather.date,
            isDaylight: \HourWeather.isDaylight
        )
        switch sourceResult {
        case .success(let resolution):
            return .success(resolution)
        case .failure(let issue):
            return .failure(
                issue.widgetWeatherDataIssue(
                    at: calendar.startOfDay(for: date)
                )
            )
        }
    }

    /// Verifies that the ten-day source begins on the destination's current day
    /// and contains every following local date exactly where expected.
    private func firstMissingForecastDate(
        in forecasts: [DayWeather],
        startingAt date: Date,
        calendar: Calendar
    ) -> Date? {
        let firstExpectedDate = calendar.startOfDay(for: date)
        for offset in 0..<10 {
            guard let expectedDate = calendar.date(
                byAdding: .day,
                value: offset,
                to: firstExpectedDate
            ) else {
                return firstExpectedDate
            }
            guard forecasts.indices.contains(offset),
                  calendar.isDate(
                    forecasts[offset].date,
                    inSameDayAs: expectedDate
                  ) else {
                return expectedDate
            }
        }
        return nil
    }

}

// MARK: - Widget Forecast Classification

/// Local alias keeps the WeatherKit adapter signatures short while the actual
/// filtering/result model remains shared with the main app.
private typealias WidgetDaylightResolution = AvailableDaylightHours<HourWeather>

private extension WidgetDaylightRegime {
    /// Converts only regimes the widget can prove from the supplied source facts.
    init?(_ regime: DaylightRegime) {
        switch regime {
        case .normal:
            self = .normal
        case .sunriseOnly:
            self = .sunriseOnly
        case .sunsetOnly:
            self = .sunsetOnly
        case .polarDay:
            self = .polarDay
        case .polarNight:
            self = .polarNight
        }
    }
}

/// Classifies widget WeatherKit records through the same symbol policy used by
/// shared sunny-hour timelines, then adds the app's structured issue wrapper.
private func widgetForecastHourBreakdown(
    hours: [HourWeather],
    calendar: Calendar
) -> Result<SunnyHoursSourceBreakdown, WeatherDataIssue> {
    let result = SunnyHoursSourceAnalysis.sourceBreakdown(
        for: hours,
        calendar: calendar,
        dateOf: \HourWeather.date,
        symbolName: \HourWeather.symbolName
    )
    switch result {
    case .success(let breakdown):
        return .success(breakdown)
    case .failure(let issue):
        return .failure(
            .unknownWeatherSymbol(issue.symbolName, at: issue.date)
        )
    }
}

private extension SunnyHoursSourceIssue {
    /// Attaches the widget's represented local date to a shared source failure.
    func widgetWeatherDataIssue(at date: Date) -> WeatherDataIssue {
        switch self {
        case .missingHourlyData:
            return .missingHourlyData(at: date)
        case .missingSunriseData:
            return WeatherDataIssue(kind: .missingSunriseData, forecastDate: date)
        case .missingSunsetData:
            return WeatherDataIssue(kind: .missingSunsetData, forecastDate: date)
        case .missingSunriseOrSunset:
            return WeatherDataIssue(
                kind: .missingSunriseOrSunset,
                forecastDate: date
            )
        }
    }
}

// MARK: - Lock-Screen Widget

/// Rectangular Lock Screen widget showing one city's current-day timeline.
/// Lock Screen families use system-controlled rendering, so this configuration
/// shares data/provider behavior but intentionally chooses a transparent canvas.
struct SunnyHoursLockScreenWidget: Widget {
    /// Stable WidgetKit registration kind.
    static let kind = "SunnyHoursLockScreenWidget"

    /// Registers the accessory widget with the shared configuration/provider.
    var body: some WidgetConfiguration {
        // The same intent/provider guarantees a selected city shows consistent
        // forecast data across Home and Lock Screen widget families.
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
    @Environment(\.locale) private var locale

    /// Builds configured accessory content or remains empty before configuration.
    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let summaryText = widgetSunnyRangeText(for: city, locale: locale)
            // Lock Screen layout has a fixed narrow height, so it uses the same
            // components as Home Screen with a compact style rather than a
            // separate weather/data path.
            VStack(alignment: .leading, spacing: 4) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    conditionSymbolName: issue == nil
                        ? city.currentConditionSymbolName
                        : nil,
                    font: .caption.weight(.semibold),
                    usesWeatherColors: false
                )
                    .padding(.horizontal, 10)
                    .padding(.trailing, -4)

                if issue != nil {
                    WidgetDataUnavailablePlaceholder()
                    .padding(.horizontal, 10)
                } else {
                    SunnyHoursTimeline(city: city, currentDate: entry.date, style: .lockScreen)
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .offset(y: 2)
                }
            }
            // A configured accessory widget sends its single tap to Places.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                widgetAccessibilitySummary(
                    cityName: city.cityName,
                    summaryText: summaryText,
                    hasIssue: issue != nil,
                    locale: locale
                )
            )
            .widgetURL(widgetPlacesURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }
}

// MARK: - Shared Widget Presentation

/// Shared city-name and current-condition header for every widget family.
/// It can show either a condition icon or a text sunny-window summary, keeping
/// family-specific choice at the call site and the visual alignment in one place.
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
    /// If a symbol is absent, the header intentionally leaves that secondary
    /// slot empty; validation elsewhere supplies the unavailable message for
    /// bad data.
    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            // Home Screen cards prefer a compact range summary. Lock Screen
            // cards omit it and show the current condition symbol instead.
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
            } else if let conditionSymbolName,
                      let displaySymbolName = widgetConditionDisplaySymbolName(
                        for: conditionSymbolName
                      ) {
                // Normalize raw WeatherKit names once, so all widget families
                // share the same canonical SF Symbol mapping as the main app.
                // WidgetKit can request monochrome/tinted rendering regardless
                // of the device color scheme. In Full Color, match each weather
                // symbol to the same semantic color as its Map-dot condition.
                if usesWeatherColors,
                   widgetRenderingMode == .fullColor,
                   let color = widgetConditionIconColor(
                        for: conditionSymbolName,
                        colors: AppPalette.values(for: colorScheme)
                   ) {
                    Image(systemName: displaySymbolName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(color)
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

/// Formats the longest current-day favorable run for widget headers.
private func widgetSunnyRangeText(
    for city: WidgetDataCity,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil else { return nil }
    let ranges = SunnyHoursFormatting.contiguousRanges(
        in: city.sunnyHours + city.partlySunnyHours
    )
    guard let range = ranges.max(by: {
        $0.upperBound - $0.lowerBound < $1.upperBound - $1.lowerBound
    }) else {
        return widgetLocalizedString("No Sun")
    }

    // DateFormatter's "j" template follows the locale's 12/24-hour convention.
    // Building synthetic dates solely for formatting keeps these integer hours
    // independent of today's date and daylight-saving transitions.
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = DateFormatter.dateFormat(
        fromTemplate: "j",
        options: 0,
        locale: locale
    )
    // Local nested helpers can use the surrounding formatter without expanding
    // the file's public/global API surface.
    func hourLabel(_ hour: Int) -> String? {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.hour = ((hour % 24) + 24) % 24
        return components.date.map(formatter.string(from:))
    }
    guard let lowerLabel = hourLabel(range.lowerBound),
          let upperLabel = hourLabel(range.upperBound + 1) else {
        return nil
    }
    return "\(lowerLabel) – \(upperLabel)"
}

/// Widgets are one deep-link target, not a collection of independently
/// interactive chart marks. This compact summary gives VoiceOver the same
/// forecast context the visual timeline communicates without serializing every
/// axis label, segment, and guide line.
private func widgetAccessibilitySummary(
    cityName: String,
    summaryText: String?,
    hasIssue: Bool,
    locale: Locale
) -> String {
    let summary = hasIssue
        ? widgetLocalizedString("Open Weather Atlas to refresh.")
        : summaryText ?? widgetLocalizedString("No Sun")
    return String(
        format: widgetLocalizedString("Sunny Hours for %@: %@"),
        locale: locale,
        cityName,
        summary
    )
}

/// Current-day capsule timeline shared by medium and Lock Screen widgets.
/// It uses a discrete capsule per clock hour, unlike the large widget's
/// continuous solar-time chart, to remain legible in narrow widget families.
private struct SunnyHoursTimeline: View {
    // MARK: - Style and Identity Types

    /// Layout and rendering density for each widget family.
    enum Style {
        case home
        case lockScreen
    }

    /// Stable axis identity is the unique represented clock hour.
    /// The separate capsule index records where that label belongs after
    /// downsampling.
    private struct AxisMarker: Identifiable {
        let hour: Int
        let capsuleIndex: Int

        var id: Int { hour }
    }

    // MARK: - Rendering Environment and Inputs

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

    // MARK: - Timeline Layout

    /// Builds capsule hours, current-time marker, and family-specific axis.
    var body: some View {
        // All downstream geometry derives from the same normalized hour array,
        // so capsules, current marker, and labels cannot drift out of alignment.
        let hours = displayedHours
        if let startHour = hours.first, let endHour = hours.last {
            VStack(spacing: style == .home ? 4 : 3) {
                GeometryReader { proxy in
                    let capsuleHeight = proxy.size.height
                    let capsuleSpacing: CGFloat = style == .home ? 7 : 8
                    // Divide the offered width after reserving gaps. The widget
                    // family may be resized by the system, so no fixed width is
                    // assumed here.
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

                        // An optional marker is emitted only when the city-local
                        // current hour is inside this daylight/capsule domain.
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
                    // The medium widget can afford four labels. Map them back to
                    // actual capsule centers so a requested evenly spaced hour
                    // never floats between nonuniform displayed hours.
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

    // The helper must be able to render nothing when redundant color cues are
    // not requested, so `@ViewBuilder` is used instead of returning one View.
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
        if usesSystemColors {
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
    private var usesSystemColors: Bool {
        style == .lockScreen || widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground.
    private var renderedPrimary: Color {
        usesSystemColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground.
    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : palette.secondaryText
    }

    /// Finds the capsule boundary nearest the city's current local hour.
    private func currentTimeBoundaryIndex(in hours: [Int]) -> Int? {
        guard let timeZone = city.widgetTimeZone,
              let firstHour = hours.first,
              let lastHour = hours.last else {
            return nil
        }
        // Current time must be evaluated in the selected city, not device zone.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentHour = calendar.component(.hour, from: currentDate)
        // `enumerated().min` returns the nearest represented clock hour after
        // any Lock Screen downsampling, then the marker advances to its boundary.
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
        guard let daylightBounds = city.daylightBounds else { return [] }
        // A half-open range turns inclusive start/exclusive end chart bounds
        // into every actual hour-cell the current-day timeline represents.
        let sourceHours = Array(daylightBounds.startHour..<daylightBounds.endHour)
        // Add a terminal boundary cell so an evening range has a visible ending
        // edge and its final axis/marker position is meaningful.
        guard let finalSourceHour = sourceHours.last else { return [] }
        let hours = sourceHours + [finalSourceHour + 1]
        guard style == .lockScreen, hours.count > 1 else { return hours }

        // Retain every other slot in tight Lock Screen space. `compactMap`
        // returns only even-indexed elements while still preserving order.
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
        // `reduce(into:)` builds four desired labels while avoiding duplicates
        // in very short daylight spans where rounding lands on the same hour.
        let axisHours = (0...3).reduce(into: [Int]()) { hours, index in
            let hour = startHour
                + Int((Double(span) * Double(index) / 3).rounded())
            if hours.last != hour {
                hours.append(hour)
            }
        }

        var markers: [AxisMarker] = []
        for (axisIndex, hour) in axisHours.enumerated() {
            let capsuleIndex: Int
            if axisIndex == 0 {
                capsuleIndex = 0
            } else if axisIndex == axisHours.count - 1 {
                capsuleIndex = hours.count - 1
            } else {
                guard let closestIndex = hours.enumerated().min(by: {
                    abs($0.element - hour) < abs($1.element - hour)
                })?.offset else {
                    return []
                }
                capsuleIndex = closestIndex
            }
            markers.append(AxisMarker(hour: hour, capsuleIndex: capsuleIndex))
        }
        return markers
    }

}

/// Centered three-state key shared by medium and large Home Screen timelines.
/// It mirrors the timeline's rendering-mode and accessibility policy, so the
/// explanatory key never relies on a color distinction the timeline removed.
private struct SunnyHoursLegend: View {
    // MARK: - Rendering Environment

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

    // MARK: - Legend Layout

    /// Builds the same three centered legend items used by Detail View.
    var body: some View {
        HStack(spacing: 14) {
            item(
                // Effective fully sunny swatch color.
                color: usesSystemColors
                    ? .primary.opacity(1)
                    : colorSchemeContrast == .increased
                        ? AppPalette.increasedContrastValues(for: colorScheme).dotSun
                        : palette.dotSun,
                title: widgetLocalizedString("Sunny"),
                symbol: WeatherIconSymbol.clear
            )
            item(
                // Effective partly sunny swatch color.
                color: usesSystemColors
                    ? .primary.opacity(0.48)
                    : colorSchemeContrast == .increased
                        ? AppPalette.increasedContrastValues(for: colorScheme).dotPartlyCloudy
                        : palette.dotPartlyCloudy,
                title: widgetLocalizedString("Partly Sunny"),
                symbol: WeatherIconSymbol.partlyCloudy
            )
            item(
                color: usesSystemColors
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
    /// Accessibility mode uses the condition symbol as a second non-color cue,
    /// matching chart fills.
    private func item(color: Color, title: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            if differentiateWithoutColor {
                if let displaySymbolName = widgetConditionDisplaySymbolName(for: symbol),
                   let iconColor = widgetConditionIconColor(for: symbol, colors: palette) {
                    Image(systemName: displaySymbolName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(iconColor)
                }
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
    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective secondary foreground for labels and divider.
    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : palette.secondaryText
    }
}

// MARK: - Widget Missing-Data Presentation

/// Compact visible fallback for missing widget configuration or unavailable
/// WeatherKit data.
/// This is intentionally one reusable state, so every family communicates that
/// no forecast was invented instead of showing an empty card.
private struct WidgetDataUnavailablePlaceholder: View {
    /// Widget family used to keep Lock Screen copy to one line.
    @Environment(\.widgetFamily) private var family

    /// Presents a concise recovery action in every supported family.
    var body: some View {
        // Widget families have sharply different text budgets; use the same
        // localized recovery action but cap Lock Screen content to one line.
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
            .accessibilityElement(children: .combine)
    }
}

/// Maps a recognized WeatherKit symbol to the app's canonical display symbol.
/// Unknown source symbols return nil so the icon slot remains blank.
private func widgetConditionDisplaySymbolName(for symbolName: String) -> String? {
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
        return nil
    }
}

/// Returns the exact semantic Map-dot color for a widget condition icon.
///
/// Full-color widgets use one color for every layer of a condition symbol, just
/// like the main app. WidgetKit's tinted and monochrome modes retain their
/// platform-controlled rendering outside this helper.
private func widgetConditionIconColor(
    for symbolName: String,
    colors: AppPalette.Values
) -> Color? {
    switch WeatherSymbolClassification.resolve(symbolName) {
    case .clear:
        return colors.dotSun
    case .partlySunny:
        return colors.dotPartlyCloudy
    case .partlyCloudy, .cloudy, .snow, .fog, .wind:
        return colors.dotCloudy
    case .rain:
        return colors.dotRain
    case .drizzle:
        return colors.dotDrizzle
    case nil:
        return nil
    }
}

// MARK: - Deep Links

/// Builds a Places deep link carrying exact missing-data diagnostics when needed.
/// WidgetKit opens this URL in the main app; URLComponents safely percent-encodes
/// city names and diagnostic detail instead of manually concatenating a URL.
private func widgetPlacesURL(for city: WidgetDataCity, issue: WeatherDataIssue?) -> URL? {
    var components = URLComponents()
    components.scheme = "weatheratlas"
    components.host = "places"
    if let issue {
        // Include diagnostics only for unavailable states. A healthy widget has
        // a clean Places destination without stale forecast-specific parameters.
        var queryItems = [
            URLQueryItem(name: "missingKind", value: issue.kind.rawValue),
            URLQueryItem(name: "city", value: city.cityName),
            // The display label can be renamed or localized. Carry the stable
            // catalog identity so the main app can re-fetch the exact saved
            // place before it decides whether this diagnostic still warrants
            // an alert.
            URLQueryItem(name: "cityID", value: city.id)
        ]
        if let detail = issue.detail {
            queryItems.append(URLQueryItem(name: "missingDetail", value: detail))
        }
        if let forecastDate = issue.forecastDate {
            queryItems.append(
                URLQueryItem(
                    name: "missingDate",
                    value: forecastDate.ISO8601Format()
                )
            )
        }
        components.queryItems = queryItems
    }
    return components.url
}

// MARK: - Widget Presentation Models

private extension WidgetDataCity {
    // MARK: - Preview Fixture

    /// Deterministic multi-day city fixture used by WidgetKit previews.
    static var preview: WidgetDataCity {
        var city = WidgetDataCity(
            id: "barcelona",
            cityName: "Barcelona",
            timeZoneIdentifier: "Europe/Madrid",
            latitude: 41.3874,
            longitude: 2.1686,
            daytimeHours: Array(6...21),
            sunnyHours: Array(8...19),
            partlySunnyHours: [7, 20]
        )
        city.currentConditionSymbolName = WeatherIconSymbol.clear
        city.daylightBounds = SunnyHoursChartBounds(startHour: 6, endHour: 22)
        city.daylightRegime = .normal
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        // Vary hours by day so previews exercise differing span widths and both
        // sunny/partly-sunny treatments without requiring WeatherKit access.
        city.sunnyWindowDays = (0..<10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let sunnyStart = 7 + (offset % 4)
            let sunnyEnd = 15 + (offset % 5)
            return WidgetSunnyWindowDay(
                date: calendar.startOfDay(for: date),
                sunnyHours: Array(sunnyStart...sunnyEnd),
                partlySunnyHours: offset.isMultiple(of: 2) ? [6, sunnyEnd + 1] : [sunnyEnd + 1],
                daylightBounds: SunnyHoursChartBounds(startHour: 6, endHour: 22),
                daylightRegime: .normal
            )
        }
        return city
    }

    // MARK: - Derived Validation

    /// Every source day remains represented. Validation below rejects a chart
    /// containing an incomplete row, so a missing date can never silently
    /// disappear between two apparently contiguous forecasts.
    var widgetSunnyWindowDays: [WidgetSunnyWindowDay] {
        sunnyWindowDays ?? []
    }

    /// Valid timezone represented by the published identifier.
    /// `flatMap` both unwraps the optional identifier and discards invalid
    /// timezone strings.
    var widgetTimeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// Exact place-identity issue preventing a trustworthy fetch or deep link.
    var widgetIdentityIssue: WeatherDataIssue? {
        guard !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unresolvedPlace("city name")
        }
        guard let latitude,
              latitude.isFinite,
              (-90...90).contains(latitude),
              let longitude,
              longitude.isFinite,
              (-180...180).contains(longitude) else {
            return .unresolvedPlace("coordinates")
        }
        return nil
    }

    /// Exact issue preventing current-day widget content.
    /// The snapshot producer has already run the shared rolling-hour analysis and
    /// records any failure in `dataIssue`. Trusting that result is important after
    /// sunset, when an empty available-daylight array is valid rather than missing.
    var widgetCurrentIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        guard daylightBounds != nil else { return .missingSunriseOrSunset }
        guard let daylightRegime else { return .missingSunriseOrSunset }
        if daylightRegime == .polarNight {
            guard daytimeHours.isEmpty,
                  sunnyHours.isEmpty,
                  partlySunnyHours.isEmpty else {
                return .invalidValue("polar night contains daylight hours")
            }
        }
        return nil
    }

    /// Exact issue preventing the large multi-day chart.
    /// Its requirements differ from the daily widget because it needs at least
    /// one validated multi-day row.
    var widgetSunnyWindowIssue: WeatherDataIssue? {
        if let dataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        if let conditionIssue = widgetCurrentConditionIssue { return conditionIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        let days = widgetSunnyWindowDays
        guard days.count == 10 else { return .missingForecastData }
        if let sequenceIssue = widgetSunnyWindowSequenceIssue {
            return sequenceIssue
        }
        if let rowIssue = days.compactMap(\.dataIssue).first {
            return rowIssue
        }
        guard days.allSatisfy({ $0.daylightBounds != nil }) else {
            return .missingSunriseOrSunset
        }
        guard days.allSatisfy({ $0.daylightRegime != nil }) else {
            return .missingSunriseOrSunset
        }
        return nil
    }

    /// Detects duplicate or skipped local dates in a cached ten-day payload.
    var widgetSunnyWindowSequenceIssue: WeatherDataIssue? {
        guard let timeZone = widgetTimeZone else { return .missingTimeZone }
        let days = widgetSunnyWindowDays
        guard days.count == 10, let firstDate = days.first?.date else {
            return .missingForecastData
        }

        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let firstDay = calendar.startOfDay(for: firstDate)
        for offset in days.indices {
            guard let expectedDate = calendar.date(
                byAdding: .day,
                value: offset,
                to: firstDay
            ),
            calendar.isDate(days[offset].date, inSameDayAs: expectedDate) else {
                let issueDate = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: firstDay
                )
                return .missingForecastData(at: issueDate)
            }
        }
        return nil
    }

    /// Missing or unknown current-condition symbol issue.
    /// Unknown symbols are deliberately not coerced into a generic cloudy icon
    /// for ranking/display.
    var widgetCurrentConditionIssue: WeatherDataIssue? {
        guard let currentConditionSymbolName else {
            return WeatherDataIssue(kind: .missingConditionData)
        }
        guard WeatherSymbolClassification.resolve(currentConditionSymbolName) != nil else {
            return .unknownWeatherSymbol(currentConditionSymbolName)
        }
        return nil
    }

    // MARK: - Combining Catalog and Snapshot Data

    /// Replaces weather-bearing catalog fields with a fetched cached snapshot.
    /// This returns a new struct because Swift value types are copied on change;
    /// the catalog value itself remains app-owned and unmodified.
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
            daylightRegime: snapshot.daylightRegime,
            sunnyWindowDays: snapshot.sunnyWindowDays,
            dataIssue: snapshot.dataIssue
        )
    }

    /// Clears weather-bearing content while retaining identity and exact issue.
    /// The resulting value is still routable and configurable, but cannot be
    /// mistaken for a valid all-cloudy/zero-sun forecast.
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
            currentConditionSymbolName: nil,
            daylightBounds: nil,
            daylightRegime: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }
}

// MARK: - Widget Bundle

/// Widget extension entry point registering all supported widget families.
/// `@main` is the executable entry point for the extension target, not the main
/// Weather Atlas app. WidgetKit discovers each widget returned from this body.
@main
struct WeatherWidgetsBundle: WidgetBundle {
    /// Declares medium, large, and rectangular Lock Screen widgets.
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
    }
}

// MARK: - Previews

// SwiftUI previews use the deterministic entry above, never a live app-group
// catalog or WeatherKit call, so they remain available in Xcode offline.

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
