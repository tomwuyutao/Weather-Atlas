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
import OSLog
import SwiftUI
import WeatherKit
import WidgetKit

private let widgetForecastLogger = Logger(
    subsystem: "Yutao-Wu.Weather.WeatherWidgets",
    category: "ForecastProvider"
)

// MARK: - Widget Locale Lookup

/// Looks up widget copy that the localized main app published into the app group.
/// The widget target may be launched independently, so it reads the app-selected
/// language from shared storage instead of assuming its process has that context.
func widgetLocalizedString(_ key: String) -> String {
    WidgetDataStore.localizedText(for: key)
}

/// Uses the same untinted cloudy/no-sun fill as the app's daily and ten-day
/// timelines. Increase Contrast changes only this color, preserving the normal
/// gray recipe and darkening it by the app's deliberately small amount.
private func widgetNoSunTimelineColor(
    colorScheme: ColorScheme,
    contrast: ColorSchemeContrast
) -> Color {
    switch (colorScheme, contrast) {
    case (.dark, .increased):
        ThemeColors.increasedContrastDark.noSunTimelineFill
    case (.dark, _):
        ThemeColors.dark.noSunTimelineFill
    case (_, .increased):
        ThemeColors.increasedContrastLight.noSunTimelineFill
    default:
        ThemeColors.light.noSunTimelineFill
    }
}

/// Applies the app's Small...Large typography contract inside WidgetKit.
/// Follow System remains live in the extension process; a fixed app choice
/// remains exact. Both paths use the same upper and lower bounds as the app.
private struct WidgetTextSizePolicyModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize

    private var resolvedSize: DynamicTypeSize {
        let catalog = WidgetDataStore.catalog()
        if catalog?.resolvedFollowsSystemTextSize == true {
            return min(
                max(systemDynamicTypeSize, .small),
                .xLarge
            )
        }
        return catalog?.resolvedTextSize.dynamicTypeSize ?? .large
    }

    func body(content: Content) -> some View {
        content.dynamicTypeSize(resolvedSize)
    }
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
    /// Optional configuration-only context used to distinguish same-name cities.
    let subtitle: String?

    init(id: String, cityName: String, subtitle: String? = nil) {
        self.id = id
        self.cityName = cityName
        self.subtitle = subtitle
    }

    /// Entity type label used by WidgetKit configuration UI.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Location"
    /// Query used by App Intents to resolve city entities.
    static var defaultQuery = WidgetCityQuery()

    /// User-facing city representation in configuration UI.
    /// The string-literal resource preserves a runtime city name rather than
    /// treating it as a localization key that must exist in the extension's
    /// String Catalog.
    var displayRepresentation: DisplayRepresentation {
        if let subtitle,
           !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: cityName),
                subtitle: LocalizedStringResource(stringLiteral: subtitle)
            )
        } else {
            DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: cityName)
            )
        }
    }
}

/// Searchable location resolver shared by every widget family.
/// WidgetKit invokes these methods while a person configures a widget,
/// potentially when the main app is closed.
struct WidgetCityQuery: EntityStringQuery {
    /// Resolves only entities whose stable identifiers still exist. App Intents
    /// permits missing identifiers to be omitted; returning a different fallback
    /// ID here would misrepresent the person's persisted widget configuration.
    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        let catalog = WidgetDataStore.catalog()
        let defaultLocation = WidgetCityEntity.defaultLocation(in: catalog)
        let cities = catalog?.cities ?? []
        return identifiers.compactMap { id in
            if id == WidgetDataStore.currentLocationIdentifier {
                return defaultLocation
            }
            guard let city = cities.first(where: {
                $0.matchesWidgetIdentifier(id)
            }),
                  city.hasResolvableWidgetLocation else {
                // App Intents rehydrates persisted entities through this query.
                // Returning a tombstone preserves a deleted selection's exact ID
                // so the provider shows unavailable instead of substituting its
                // default Current/Home Location.
                return WidgetCityEntity(
                    id: id,
                    cityName: WidgetDataStore.localizedText(for: "Saved Place")
                )
            }
            // App Intents requires the rehydrated entity to retain the exact
            // identifier WidgetKit persisted. The provider later resolves this
            // legacy alias to the catalog's canonical Saved Place UUID.
            return WidgetCityEntity(city, identifier: id)
        }
    }

    /// The app's Current/Home Location is always first, followed by Saved Places.
    func suggestedEntities() async throws -> [WidgetCityEntity] {
        let catalog = WidgetDataStore.catalog()
        return [WidgetCityEntity.defaultLocation(in: catalog)]
            + (catalog?.cities ?? [])
                .filter(\.hasResolvableWidgetLocation)
                .map(WidgetCityEntity.init)
    }

    /// Every new widget starts with the app's Current/Home Location. A person
    /// can then choose any resolved Saved Place in the configuration sheet.
    func defaultResult() async -> WidgetCityEntity? {
        .defaultLocation(in: WidgetDataStore.catalog())
    }

    /// Filters scoped cities by localized case-insensitive name.
    /// The protocol is async because App Intents allows remote lookups, even
    /// though this source currently reads the local shared catalog synchronously.
    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
                || ($0.subtitle?.localizedCaseInsensitiveContains(string) == true)
        }
    }

}

private extension WidgetCityEntity {
    /// Stable intent entity representing the app-published default coordinate.
    /// Its ID remains unchanged for existing widgets while its label follows
    /// the location choice confirmed in the main app.
    static func defaultLocation(
        in catalog: WidgetDataCatalog?
    ) -> WidgetCityEntity {
        let key = catalog?.resolvedDefaultLocationKind.displayNameKey
            ?? WidgetDefaultLocationKind.currentLocation.displayNameKey
        return WidgetCityEntity(
            id: WidgetDataStore.currentLocationIdentifier,
            cityName: catalog?.localizedStrings[key]
                ?? WidgetDataStore.localizedText(for: key)
        )
    }

    /// Converts a shared Codable city into an App Intent entity.
    init(_ city: WidgetDataCity) {
        id = city.id
        cityName = city.cityName
        subtitle = city.configurationSubtitle
    }

    /// Rehydrates a persisted legacy App Intent entity while taking its current
    /// display metadata from the UUID-backed catalog record.
    init(_ city: WidgetDataCity, identifier: String) {
        id = identifier
        cityName = city.cityName
        subtitle = city.configurationSubtitle
    }
}

// MARK: - Widget Configuration Intent

/// Location configuration shared by all Weather Atlas widgets.
/// WidgetKit persists the selected `WidgetCityEntity` and passes it back to
/// every provider callback.
struct SunnyHoursLockScreenConfigurationIntent: WidgetConfigurationIntent {
    /// Configuration title shown by WidgetKit.
    static var title: LocalizedStringResource = "Sunny Hours"
    /// Configuration explanation shown by WidgetKit.
    static var description = IntentDescription(
        "Show Current Location or choose a Saved Place."
    )

    /// Searchable selected-location parameter.
    /// The `@Parameter` macro tells the system configuration UI to show the App
    /// Entity picker above.
    @Parameter(title: "Location") var city: WidgetCityEntity?

    /// Required empty initializer for App Intent configuration.
    init() {}
}

// MARK: - Home-Screen Widgets

/// Home Screen widget showing compact daily or ten-day sunny hours by family.
struct BestSunnyPlacesWidget: Widget {
    /// Stable kind for the unified Home Screen widget.
    static let kind = WidgetDataStore.kind

    /// Registers all three Home Screen sizes under one configuration so
    /// WidgetKit can expose every choice in the widget gallery.
    var body: some WidgetConfiguration {
        // AppIntentConfiguration connects a stable widget kind, a configurable
        // city intent, one timeline provider, and the SwiftUI view used to draw
        // every entry. WidgetKit owns calling the provider later.
        AppIntentConfiguration(kind: Self.kind, intent: SunnyHoursLockScreenConfigurationIntent.self, provider: SunnyHoursLockScreenProvider()) { entry in
            SunnyHoursHomeScreenWidgetView(entry: entry)
                // Inject the main app's published locale once so nested widget
                // views use the same date and text formatting policy.
                .environment(\.locale, WidgetDataStore.appLocale)
                .modifier(WidgetTextSizePolicyModifier())
                // Home widgets can also appear on iPad Lock Screen and iPhone
                // StandBy. Respect the person's system privacy/redaction choice
                // on every surface that can expose a city and forecast.
                .privacySensitive()
                .containerBackground(for: .widget) {
                    WidgetPaletteBackground()
                }
        }
        .configurationDisplayName(WidgetDataStore.localizedText(for: "Sunny Hours"))
        .description(WidgetDataStore.localizedText(for: "Track sunny hours for a chosen city."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
        if family == .systemSmall {
            SunnyStatusWidgetView(entry: entry)
        } else if family == .systemLarge {
            SunnyWindowLargeWidgetView(entry: entry)
        } else {
            SunnyHoursHomeWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Sun-Status Presentation

/// Compact status presentation for the Small Home Screen widget.
private struct SunnyStatusWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            VStack(alignment: .leading, spacing: 8) {
                if issue == nil,
                   let weather = widgetWeatherPresentation(
                       for: city,
                       at: entry.date
                   ) {
                    WidgetConditionIcon(weather: weather, size: 34)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(renderedSecondary)

                }
                Text(status ?? widgetLocalizedString("Weather unavailable."))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(renderedSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                Text(city.cityName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .padding(.bottom, 12)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .foregroundStyle(renderedPrimary)
            .widgetURL(widgetPlaceURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }

    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    private var renderedPrimary: Color {
        usesSystemColors ? .primary : widgetPalette.titleText
    }

    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : widgetPalette.secondaryText
    }
}

// MARK: - Large Sunny-Window Presentation

/// Header, ten-day chart, legend, and missing-data state for the large widget.
private struct SunnyWindowLargeWidgetView: View {
    /// Locale published by the main app.
    @Environment(\.locale) private var locale
    /// Widget appearance used by the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds available chart content or a visible unavailable placeholder.
    var body: some View {
        if let city = entry.city {
            let currentIssue = city.widgetCurrentIssue
            let windowIssue = city.widgetSunnyWindowIssue
            let summaryText = widgetSunnyHoursTotalText(for: city, locale: locale)
            VStack(alignment: .leading, spacing: 9) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    weather: currentIssue == nil
                        ? widgetWeatherPresentation(for: city, at: entry.date)
                        : nil,
                    summaryText: summaryText,
                    font: .headline.weight(.semibold),
                    usesWeatherColors: true
                )

                // Validation is intentionally checked before layout. A short
                // forecast is valid and renders all of its available rows; an
                // unavailable state is reserved for missing forecast structure
                // or an unsafe city identity.
                if windowIssue != nil {
                    WidgetDataUnavailablePlaceholder()
                } else if let timeZone = city.widgetTimeZone,
                          let chartBounds = SunnyHoursChartBounds.merged(
                              city.widgetSunnyWindowDays.map(\.widgetDaylightBounds)
                          ) {
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
            .foregroundStyle(
                widgetRenderingMode == .fullColor
                    ? AppPalette.values(
                        for: colorScheme,
                        contrast: colorSchemeContrast
                    ).titleText
                    : Color.primary
            )
            // `widgetURL` makes the entire noninteractive widget a deep link;
            // WidgetKit does not support arbitrary in-widget navigation here.
            .widgetURL(widgetPlaceURL(for: city, issue: windowIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }
}

/// Height-adaptive ten-day widget timeline using real daylight bounds.
/// The chart is custom SwiftUI layout rather than Swift Charts because every
/// row needs the same solar-time x-axis while WidgetKit supplies tight sizes.
private struct SunnyWindowLargeChart: View {
    /// Available current/future day rows extracted from WeatherKit.
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

    /// Rows already capped at the large widget's ten-row presentation limit.
    private var visibleDays: [WidgetSunnyWindowDay] {
        days
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

    /// Builds date labels and contiguous hourly-weather capsules.
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
                        .minimumScaleFactor(0.7)
                        .frame(width: labelWidth, alignment: .leading)

                    SunnyHoursContinuousCapsuleTrack(
                        hours: day.chartHourlyConditions.compactMap {
                            guard let weather = $0.weather else { return nil }
                            return SunnyHoursChartHour(
                                date: $0.date,
                                hour: $0.hour,
                                condition: weather.condition
                            )
                        },
                        bounds: chartBounds,
                        colors: sharedChartColors,
                        height: capsuleHeight
                    )
                    // Give each shared capsule track a stable 16-point lane.
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
                renderedSecondary.opacity(0.08),
                lineWidth: 1
            )
            .frame(width: timelineWidth, height: rowsHeight)
        }
        .frame(height: rowsHeight)
    }

    // `@ViewBuilder` lets this helper intentionally emit no view when today is
    // absent. Off-window times clamp to the chart's leading or trailing edge.
    @ViewBuilder
    /// Draws selected-city local time on today's row, clamped to daylight.
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
                            // Keep the complete two-point marker visible when
                            // an off-window time clamps to either chart edge.
                            .offset(
                                x: min(
                                    max(markerX - 1, 0),
                                    max(timelineWidth - 2, 0)
                                )
                            )
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

    /// Returns the shared timeline color for one API-derived tint family.
    /// This changes only the track color; current-condition symbols always use
    /// the original WeatherKit `symbolName`.
    private func segmentColor(for tone: WeatherIconTone) -> Color {
        if usesSystemColors {
            return monochromeColor(for: tone)
        }
        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return chartColor(for: tone, colors: colors)
        }
        return chartColor(for: tone, colors: palette)
    }

    /// Adapter-only colour policy for the shared app/widget capsule renderer.
    private var sharedChartColors: SunnyHoursChartColors {
        SunnyHoursChartColors(
            primary: renderedPrimary,
            secondary: renderedSecondary,
            sun: segmentColor(for: .clear),
            partlySunny: segmentColor(for: .partlySunny),
            rain: segmentColor(for: .rain),
            drizzle: segmentColor(for: .drizzle),
            noSun: segmentColor(for: .cloudy)
        )
    }

    /// Retains clear, precipitation, and neutral no-sun weights when WidgetKit
    /// enforces a monochrome or tinted rendering mode.
    private func monochromeColor(for tone: WeatherIconTone) -> Color {
        switch tone {
        case .clear:
            .primary.opacity(1)
        case .partlySunny:
            .primary.opacity(0.92)
        case .rain:
            .primary.opacity(0.82)
        case .drizzle:
            .primary.opacity(0.38)
        case .cloudy:
            .primary.opacity(0.14)
        }
    }

    /// Maps only tint families to the timeline palette.
    private func chartColor(
        for tone: WeatherIconTone,
        colors: AppPalette.Values
    ) -> Color {
        switch tone {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
        case .cloudy:
            widgetNoSunTimelineColor(
                colorScheme: colorScheme,
                contrast: colorSchemeContrast
            )
        }
    }

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
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
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds configured city content or remains empty before catalog publication.
    var body: some View {
        if let city = entry.city {
            // The city payload is validated within content, while the outer view
            // owns the shared full-widget deep-link destination.
            content(city)
                .widgetURL(widgetPlaceURL(for: city, issue: city.widgetCurrentIssue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    /// Builds header, current-day timeline, legend, or missing-data state.
    private func content(_ city: WidgetDataCity) -> some View {
        let issue = city.widgetCurrentIssue
        let summaryText = widgetSunnyHoursTotalText(for: city, locale: locale)
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
            SunnyHoursHeader(
                cityName: city.cityName,
                weather: issue == nil
                    ? widgetWeatherPresentation(for: city, at: entry.date)
                    : nil,
                summaryText: summaryText,
                font: .headline.weight(.semibold),
                usesWeatherColors: true
            )

            if issue != nil {
                WidgetDataUnavailablePlaceholder()
            } else {
                WidgetDailySunnyHoursTimeline(
                    city: city,
                    currentDate: entry.date
                )
                    .padding(.top, 12)
                    .frame(maxHeight: .infinity)

                SunnyHoursLegend()
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(
            widgetRenderingMode == .fullColor
                ? AppPalette.values(
                    for: colorScheme,
                    contrast: colorSchemeContrast
                ).titleText
                : Color.primary
        )
    }
}

// MARK: - Shared Widget Background

/// Shared full-color widget background drawn from the app palette.
private struct WidgetPaletteBackground: View {
    /// Widget appearance selecting light or dark background.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Fills the widget container with the semantic canvas.
    var body: some View {
        // `containerBackground(for: .widget)` above inserts this semantic color
        // only in families where WidgetKit allows the extension to own it.
        AppPalette.values(
            for: colorScheme,
            contrast: colorSchemeContrast
        ).background
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
    /// Deterministic sample used by placeholders, the gallery, and Xcode previews.
    static let preview = SunnyHoursLockScreenEntry(
        date: .now,
        city: .preview
    )
}

/// Immutable identity captured before an asynchronous refresh begins. The app
/// can republish the catalog, move Current Location, or advance Reset App while
/// WeatherKit is suspended, so every completed response is checked against this
/// exact selection before it can be rendered or persisted.
private struct WidgetSelectionIdentity: Hashable, Sendable {
    let cityID: String
    let cityName: String
    let latitude: Double?
    let longitude: Double?
    let timeZoneIdentifier: String?
    let appLanguageIdentifier: String
    let defaultLocationKind: WidgetDefaultLocationKind?
    let resetEpoch: String?

    init(
        city: WidgetDataCity,
        appLanguageIdentifier: String,
        defaultLocationKind: WidgetDefaultLocationKind?,
        resetEpoch: String?
    ) {
        cityID = city.id
        cityName = city.cityName
        latitude = city.latitude
        longitude = city.longitude
        timeZoneIdentifier = city.timeZoneIdentifier
        self.appLanguageIdentifier = appLanguageIdentifier
        self.defaultLocationKind = defaultLocationKind
        self.resetEpoch = resetEpoch
    }
}

/// Primitive, process-local key for sharing identical extension requests. It
/// includes reset generation and full forecast identity so neither a moved
/// Current Location nor a reset can inherit an older in-flight response.
private struct WidgetForecastRequestKey: Hashable, Sendable {
    let cityID: String
    let cityName: String
    let cityNameLocaleIdentifier: String
    let latitude: Double
    let longitude: Double
    let timeZoneIdentifier: String
    /// City-local day requested from WeatherKit. Including it prevents a
    /// pre-midnight in-flight or just-completed task from being reused after
    /// that city crosses midnight.
    let forecastLocalDate: Date
    let locationTimestamp: Date?
    let locationSource: WidgetForecastLocationSource
    let resetEpoch: String?
}

/// WeatherKit's aggregate tuple is wrapped so an unstructured timeout race can
/// safely hand the immutable response back to the provider. WeatherKit owns the
/// contained value types; this extension only reads them after completion.
private struct WidgetWeatherKitResponse: @unchecked Sendable {
    /// Exact current presentation when available, otherwise the nearest
    /// WeatherKit hourly record. The latter lets the widget retain useful
    /// direct forecast data when only the current product is temporarily
    /// unavailable from WeatherKit.
    let currentWeather: WidgetWeatherPresentation
    let dailyForecast: Forecast<DayWeather>
    let hourlyForecast: Forecast<HourWeather>
}

/// `WidgetWeatherSnapshot` is an immutable value once produced. This wrapper
/// makes that ownership explicit at the request-coalescing boundary without
/// changing the shared Codable model in another source file.
private struct WidgetWeatherSnapshotBox: @unchecked Sendable {
    let snapshot: WidgetWeatherSnapshot
}

private enum WidgetWeatherFetchError: Error {
    case timedOut
    case invalidTimeZone
    case missingHourlyFallback
    case missingCurrentHourlyCoverage
}

private enum WidgetWeatherRequestMode: Hashable, Sendable {
    case complete
    case forecastFallback
}

/// Process-local identity for one expensive WeatherKit operation. It excludes
/// presentation-only city metadata so simultaneous widget families querying
/// the same coordinate and forecast interval share one system request.
private struct WidgetWeatherOperationKey: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
    let forecastStartDate: Date
    let forecastEndDate: Date
    let mode: WidgetWeatherRequestMode
}

/// Makes one WeatherKit wait cancellation- and deadline-responsive without
/// cancelling the shared system request. WeatherKit can continue work after a
/// cancelled Swift task; leaving ownership with the operation coordinator lets
/// later widget callbacks join that work instead of launching a duplicate.
private actor WidgetWeatherResponseWaiter {
    private var continuation: CheckedContinuation<WidgetWeatherKitResponse, Error>?
    private var observerTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var cancellationRequested = false

    func value(
        of task: Task<WidgetWeatherKitResponse, Error>,
        timeout: Duration
    ) async throws -> WidgetWeatherKitResponse {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetWeatherFetchError.timedOut
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(
                    continuation,
                    task: task,
                    timeout: timeout
                )
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func install(
        _ continuation: CheckedContinuation<WidgetWeatherKitResponse, Error>,
        task: Task<WidgetWeatherKitResponse, Error>,
        timeout: Duration
    ) {
        guard !cancellationRequested else {
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        observerTask = Task.detached(priority: .utility) { [self] in
            do {
                await finish(.success(try await task.value))
            } catch {
                await finish(.failure(error))
            }
        }
        timeoutTask = Task.detached(priority: .utility) { [self] in
            do {
                try await Task.sleep(for: timeout)
                try Task.checkCancellation()
                await finish(.failure(WidgetWeatherFetchError.timedOut))
            } catch {
                // Cancellation means the WeatherKit task already won, or the
                // caller no longer needs this race. Neither case is an error.
            }
        }
    }

    private func finish(
        _ result: Result<WidgetWeatherKitResponse, Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        observerTask?.cancel()
        timeoutTask?.cancel()
        observerTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }

    private func cancel() {
        cancellationRequested = true
        finish(.failure(CancellationError()))
    }
}

/// Owns actual WeatherKit work independently from any one WidgetKit callback.
/// A callback may time out at its provider deadline while the system request
/// ignores cancellation. Retaining that operation briefly lets subsequent
/// Home and Lock Screen callbacks join it instead of stacking another full
/// 10-day WeatherKit request on top of the first one.
private actor WidgetWeatherOperationCoordinator {
    static let shared = WidgetWeatherOperationCoordinator()

    private struct InFlightOperation {
        let id: UUID
        let task: Task<WidgetWeatherKitResponse, Error>
        let expiryTask: Task<Void, Never>
    }

    private struct CompletedResponse {
        let response: WidgetWeatherKitResponse
        let completedAt: ContinuousClock.Instant
    }

    private var inFlight: [WidgetWeatherOperationKey: InFlightOperation] = [:]
    private var recentlyCompleted: [WidgetWeatherOperationKey: CompletedResponse] = [:]
    private let completedReuseInterval: Duration = .seconds(30)
    /// Do not retain a genuinely stuck system request forever. This interval is
    /// twice the provider budget, long enough to absorb late completion and a
    /// sequential family batch while allowing a later WidgetKit retry to start
    /// cleanly if WeatherKit never returns.
    private let maximumOperationLifetime: Duration = .seconds(48)

    func response(
        latitude: Double,
        longitude: Double,
        forecastStartDate: Date,
        forecastEndDate: Date,
        timeout: Duration,
        mode: WidgetWeatherRequestMode = .complete
    ) async throws -> WidgetWeatherKitResponse {
        try Task.checkCancellation()
        guard timeout > .zero else {
            throw WidgetWeatherFetchError.timedOut
        }

        let key = WidgetWeatherOperationKey(
            latitude: latitude,
            longitude: longitude,
            forecastStartDate: forecastStartDate,
            forecastEndDate: forecastEndDate,
            mode: mode
        )
        let now = ContinuousClock.now
        recentlyCompleted = recentlyCompleted.filter {
            let age = $0.value.completedAt.duration(to: now)
            return age >= .zero && age < completedReuseInterval
        }
        if let completed = recentlyCompleted[key] {
            try Task.checkCancellation()
            return completed.response
        }

        let operation: InFlightOperation
        if let existing = inFlight[key] {
            operation = existing
        } else {
            let id = UUID()
            let task = Task<WidgetWeatherKitResponse, Error>.detached(
                priority: .utility
            ) {
                try await Self.performRequest(
                    latitude: latitude,
                    longitude: longitude,
                    forecastStartDate: forecastStartDate,
                    forecastEndDate: forecastEndDate,
                    mode: mode
                )
            }
            let expiryTask = Task.detached(priority: .utility) { [self] in
                do {
                    try await Task.sleep(for: maximumOperationLifetime)
                    try Task.checkCancellation()
                    await expire(key: key, operationID: id)
                } catch {
                    // Normal completion cancels this housekeeping task.
                }
            }
            operation = InFlightOperation(
                id: id,
                task: task,
                expiryTask: expiryTask
            )
            inFlight[key] = operation

            Task.detached(priority: .utility) { [self] in
                let result: Result<WidgetWeatherKitResponse, Error>
                do {
                    result = .success(try await task.value)
                } catch {
                    result = .failure(error)
                }
                await complete(
                    key: key,
                    operationID: id,
                    result: result
                )
            }
        }

        let response = try await WidgetWeatherResponseWaiter().value(
            of: operation.task,
            timeout: timeout
        )
        try Task.checkCancellation()
        return response
    }

    private func complete(
        key: WidgetWeatherOperationKey,
        operationID: UUID,
        result: Result<WidgetWeatherKitResponse, Error>
    ) {
        guard let operation = inFlight[key],
              operation.id == operationID else {
            return
        }
        operation.expiryTask.cancel()
        inFlight[key] = nil
        if case let .success(response) = result {
            recentlyCompleted[key] = CompletedResponse(
                response: response,
                completedAt: ContinuousClock.now
            )
        }
    }

    private func expire(
        key: WidgetWeatherOperationKey,
        operationID: UUID
    ) {
        guard let operation = inFlight[key],
              operation.id == operationID else {
            return
        }
        operation.task.cancel()
        inFlight[key] = nil
    }

    nonisolated private static func performRequest(
        latitude: Double,
        longitude: Double,
        forecastStartDate: Date,
        forecastEndDate: Date,
        mode: WidgetWeatherRequestMode
    ) async throws -> WidgetWeatherKitResponse {
        let location = CLLocation(
            latitude: latitude,
            longitude: longitude
        )
        switch mode {
        case .complete:
            let (current, daily, hourly) = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .current,
                .daily(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                ),
                .hourly(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                )
            )
            return WidgetWeatherKitResponse(
                currentWeather: WidgetWeatherPresentation(
                    condition: AppWeatherCondition(
                        weatherKit: current.condition
                    ),
                    symbolName: current.symbolName
                ),
                dailyForecast: daily,
                hourlyForecast: hourly
            )
        case .forecastFallback:
            let (daily, hourly) = try await WeatherKit.WeatherService.shared.weather(
                for: location,
                including: .daily(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                ),
                .hourly(
                    startDate: forecastStartDate,
                    endDate: forecastEndDate
                )
            )
            guard let nearestHour = hourly.forecast.min(by: {
                abs($0.date.timeIntervalSinceNow)
                    < abs($1.date.timeIntervalSinceNow)
            }) else {
                throw WidgetWeatherFetchError.missingHourlyFallback
            }
            return WidgetWeatherKitResponse(
                currentWeather: WidgetWeatherPresentation(
                    condition: AppWeatherCondition(
                        weatherKit: nearestHour.condition
                    ),
                    symbolName: nearestHour.symbolName
                ),
                dailyForecast: daily,
                hourlyForecast: hourly
            )
        }
    }
}

/// Makes one caller's wait on a shared snapshot request cancellation-responsive.
/// Awaiting an unstructured task's value directly does not necessarily resume
/// when only the waiter is cancelled, which can consume WidgetKit's full
/// execution allowance after it has already abandoned that callback.
private actor WidgetForecastTaskWaiter {
    private var continuation: CheckedContinuation<WidgetWeatherSnapshotBox, Error>?
    private var observerTask: Task<Void, Never>?
    private var cancellationRequested = false

    func value(
        of task: Task<WidgetWeatherSnapshotBox, Error>
    ) async throws -> WidgetWeatherSnapshotBox {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                install(continuation, task: task)
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func install(
        _ continuation: CheckedContinuation<WidgetWeatherSnapshotBox, Error>,
        task: Task<WidgetWeatherSnapshotBox, Error>
    ) {
        guard !cancellationRequested else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        observerTask = Task.detached(priority: .utility) { [self] in
            do {
                await finish(.success(try await task.value))
            } catch {
                await finish(.failure(error))
            }
        }
    }

    private func finish(
        _ result: Result<WidgetWeatherSnapshotBox, Error>
    ) {
        guard let continuation else { return }
        self.continuation = nil
        observerTask?.cancel()
        observerTask = nil
        continuation.resume(with: result)
    }

    private func cancel() {
        cancellationRequested = true
        finish(.failure(CancellationError()))
    }
}

/// Coalesces simultaneous snapshot/timeline callbacks for the same identity.
/// A very short completed-result window closes the reentrancy gap between one
/// waiter finishing and another callback observing the newly persisted cache.
private actor WidgetForecastRequestCoordinator {
    static let shared = WidgetForecastRequestCoordinator()

    private struct InFlightRequest {
        let id: UUID
        let task: Task<WidgetWeatherSnapshotBox, Error>
        var waiterIDs: Set<UUID>
    }

    private struct CompletedResult {
        let box: WidgetWeatherSnapshotBox
        let completedAt: ContinuousClock.Instant
    }

    private var inFlight: [WidgetForecastRequestKey: InFlightRequest] = [:]
    private var recentlyCompleted: [WidgetForecastRequestKey: CompletedResult] = [:]
    private let completedReuseInterval: Duration = .seconds(5)

    func snapshot(
        for key: WidgetForecastRequestKey,
        operation: @escaping @Sendable () async throws -> WidgetWeatherSnapshotBox
    ) async throws -> WidgetWeatherSnapshotBox {
        let now = ContinuousClock.now
        recentlyCompleted = recentlyCompleted.filter {
            let age = $0.value.completedAt.duration(to: now)
            return age >= .zero && age < completedReuseInterval
        }
        if let completed = recentlyCompleted[key] {
            try Task.checkCancellation()
            return completed.box
        }

        let waiterID = UUID()
        let request: InFlightRequest
        if var existing = inFlight[key] {
            existing.waiterIDs.insert(waiterID)
            inFlight[key] = existing
            request = existing
        } else {
            let task = Task<WidgetWeatherSnapshotBox, Error>.detached(
                priority: .utility
            ) {
                try await operation()
            }
            request = InFlightRequest(
                id: UUID(),
                task: task,
                waiterIDs: [waiterID]
            )
            inFlight[key] = request
        }

        return try await withTaskCancellationHandler {
            do {
                let box = try await WidgetForecastTaskWaiter().value(
                    of: request.task
                )
                try Task.checkCancellation()
                complete(
                    key: key,
                    requestID: request.id,
                    box: box
                )
                return box
            } catch is CancellationError {
                removeWaiter(
                    waiterID,
                    key: key,
                    requestID: request.id,
                    cancelWhenEmpty: true
                )
                throw CancellationError()
            } catch {
                removeWaiter(
                    waiterID,
                    key: key,
                    requestID: request.id,
                    cancelWhenEmpty: false
                )
                throw error
            }
        } onCancel: {
            Task {
                await self.removeWaiter(
                    waiterID,
                    key: key,
                    requestID: request.id,
                    cancelWhenEmpty: true
                )
            }
        }
    }

    private func complete(
        key: WidgetForecastRequestKey,
        requestID: UUID,
        box: WidgetWeatherSnapshotBox
    ) {
        guard inFlight[key]?.id == requestID else { return }
        recentlyCompleted[key] = CompletedResult(
            box: box,
            completedAt: ContinuousClock.now
        )
        inFlight[key] = nil
    }

    private func removeWaiter(
        _ waiterID: UUID,
        key: WidgetForecastRequestKey,
        requestID: UUID,
        cancelWhenEmpty: Bool
    ) {
        guard var request = inFlight[key],
              request.id == requestID else {
            return
        }
        request.waiterIDs.remove(waiterID)
        if request.waiterIDs.isEmpty {
            if cancelWhenEmpty {
                request.task.cancel()
            }
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }
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
    /// Entries stop presenting any response after the cache's hard retention.
    private let maximumDisplayInterval: TimeInterval = 24 * 60 * 60
    /// Current-time markers advance between network refresh opportunities.
    private let markerUpdateInterval: TimeInterval = 30 * 60
    /// One provider callback must leave time for WidgetKit to archive and render
    /// its timeline before the system's extension execution allowance expires.
    private let providerExecutionBudget: Duration = .seconds(24)

    /// A catalog city paired with the exact private snapshot applied to it.
    /// Keeping both lets timeline planning respect fetch and expiry metadata.
    private struct AppliedSnapshot {
        let city: WidgetDataCity
        let snapshot: WidgetWeatherSnapshot
    }

    /// Scheduling class for a provider result. Persistent failures still retry
    /// independently, but avoid the aggressive cadence reserved for temporary
    /// network, cancellation, and location outages.
    private enum ReloadPolicy {
        case normal
        case transientFailure
        case persistentFailure
    }

    /// Refresh output plus the appropriate independent retry behavior.
    /// This small private type separates rendered data from scheduling policy.
    private struct RefreshResult {
        /// Configured city after cache or WeatherKit application.
        let city: WidgetDataCity?
        /// Exact response applied to `city`, if one is currently displayable.
        let snapshot: WidgetWeatherSnapshot?
        /// Provider scheduling class for this exact result.
        let reloadPolicy: ReloadPolicy
    }

    /// Device-location identity paired with the timestamp Core Location
    /// supplied for the exact coordinate.
    private struct ResolvedDeviceLocationCity {
        let city: WidgetDataCity
        let locationTimestamp: Date
        /// True only when this exact Core Location request also produced a
        /// nonempty reverse-geocoded locality in the app-selected language.
        let hasFreshResolvedCityName: Bool
    }

    // MARK: - WidgetKit Lifecycle Callbacks

    /// Supplies immediate gallery content from cache or deterministic preview data.
    /// Placeholder must return synchronously and cheaply; it must not wait for
    /// WeatherKit, because WidgetKit uses it while loading the gallery UI.
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry {
        SunnyHoursLockScreenEntry.preview
    }

    /// Supplies gallery snapshot or performs a direct WeatherKit refresh.
    func snapshot(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> SunnyHoursLockScreenEntry {
        // Previews should never make a live network request. They use a cached
        // payload when available, otherwise the deterministic fixture below.
        if context.isPreview {
            return SunnyHoursLockScreenEntry.preview
        }
        // Use the same direct WeatherKit path as the timeline so a newly added
        // widget does not wait for WidgetKit's next scheduled refresh.
        let result = await refreshedCity(for: configuration)
        return SunnyHoursLockScreenEntry(
            date: .now,
            city: result.city
        )
    }

    /// Produces future entries for status changes and current-time-marker
    /// movement, then requests normal or short-retry network timing.
    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let result = await refreshedCity(for: configuration)
        return plannedTimeline(for: result, now: .now)
    }

    // MARK: - City and Cache Resolution

    /// Resolves the shared Current/Home default or the exact chosen Saved Place.
    /// A deleted/invalid configured place retains its persisted ID and name in
    /// an unavailable state instead of silently becoming a different location.
    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetDataCity? {
        selectedCity(
            for: configuration,
            catalog: WidgetDataStore.catalog()
        )
    }

    /// Resolves a selection from one captured catalog value so its city, mode,
    /// and language cannot come from different app publications.
    private func selectedCity(
        for configuration: SunnyHoursLockScreenConfigurationIntent,
        catalog: WidgetDataCatalog?
    ) -> WidgetDataCity? {
        guard let catalog else {
            let selectedEntity = configuration.city
                ?? .defaultLocation(in: nil)
            return unavailableConfiguredCity(
                selectedEntity,
                issue: .unresolvedPlace("widget location catalog")
            )
        }
        WidgetForecastStore.prune(
            keeping: Set(
                [WidgetDataStore.currentLocationIdentifier]
                    + catalog.cities.flatMap(\.allWidgetIdentifiers)
            )
        )
        let defaultEntity = WidgetCityEntity.defaultLocation(in: catalog)
        let selectedEntity = configuration.city ?? defaultEntity
        let defaultCity = catalog.currentLocation
            ?? unavailableConfiguredCity(
                defaultEntity,
                issue: .unresolvedPlace("default location")
            )
        if selectedEntity.id == WidgetDataStore.currentLocationIdentifier {
            return defaultCity
        }
        guard let savedCity = catalog.cities.first(where: {
            $0.matchesWidgetIdentifier(selectedEntity.id)
        }), savedCity.hasResolvableWidgetLocation else {
            return unavailableConfiguredCity(
                selectedEntity,
                issue: .unresolvedPlace("saved widget location")
            )
        }
        return savedCity
    }

    /// Whether the stable default widget slot currently represents the
    /// device's live location rather than the person's fixed Home Location.
    /// The extension resolves this coordinate itself on every provider refresh;
    /// the catalog coordinate is only a transient fallback if Core Location
    /// cannot answer promptly.
    private func usesDeviceCurrentLocation(
        _ configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> Bool {
        usesDeviceCurrentLocation(
            configuration,
            catalog: WidgetDataStore.catalog()
        )
    }

    /// Catalog-captured variant used by asynchronous refresh identity.
    private func usesDeviceCurrentLocation(
        _ configuration: SunnyHoursLockScreenConfigurationIntent,
        catalog: WidgetDataCatalog?
    ) -> Bool {
        let selectedEntity = configuration.city
            ?? .defaultLocation(in: catalog)
        return selectedEntity.id == WidgetDataStore.currentLocationIdentifier
            && (catalog?.resolvedDefaultLocationKind ?? .currentLocation)
                == .currentLocation
    }

    /// Mode participating in cache identity only for the stable default slot.
    private func defaultLocationKind(
        for city: WidgetDataCity,
        catalog: WidgetDataCatalog?
    ) -> WidgetDefaultLocationKind? {
        guard city.id == WidgetDataStore.currentLocationIdentifier else {
            return nil
        }
        return catalog?.resolvedDefaultLocationKind ?? .currentLocation
    }

    /// Captures one explicit locale identifier without rereading the app group
    /// after reverse geocoding begins.
    private func appLanguageIdentifier(
        in catalog: WidgetDataCatalog?
    ) -> String {
        guard let identifier = catalog?.appLanguageIdentifier,
              !identifier.isEmpty else {
            return Locale.autoupdatingCurrent.identifier
        }
        return identifier
    }

    /// Retains a configured entity's exact stable identity when its catalog
    /// record or fetchable coordinates are unavailable.
    private func unavailableConfiguredCity(
        _ city: WidgetCityEntity,
        issue: WeatherDataIssue
    ) -> WidgetDataCity {
        return WidgetDataCity(
            id: city.id,
            cityName: city.cityName,
            configurationSubtitle: city.subtitle,
            timeZoneIdentifier: nil,
            latitude: nil,
            longitude: nil,
            dataIssue: issue
        )
    }

    /// Applies only a fresh, widget-owned snapshot for the destination's
    /// current local day. Placeholder/gallery rendering must not briefly
    /// present yesterday's weather as current while a later direct refresh is
    /// still pending.
    private func cityUsingCachedSnapshot(
        for configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> WidgetDataCity? {
        let catalog = WidgetDataStore.catalog()
        guard let city = selectedCity(
            for: configuration,
            catalog: catalog
        ) else { return nil }
        if let issue = city.widgetCurrentIssue {
            return city.markingUnavailable(issue)
        }
        return freshAppliedSnapshot(
            for: city,
            defaultLocationKind: defaultLocationKind(
                for: city,
                catalog: catalog
            )
        )?.city
            ?? city.markingUnavailable(.missingForecastData(at: .now))
    }

    /// Returns the extension's private snapshot only while it is inside the
    /// normal freshness window and still matches the catalog identity.
    private func freshAppliedSnapshot(
        for city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?,
        preservesResolvedCityName: Bool = false
    ) -> AppliedSnapshot? {
        guard city.widgetCurrentIssue == nil else { return nil }
        guard let snapshot = WidgetForecastStore.freshSnapshot(
            forAny: city.allWidgetIdentifiers,
            matching: {
                snapshotMatchesCity(
                    $0,
                    city: city,
                    defaultLocationKind: defaultLocationKind
                ) && snapshotRepresentsLocalDay($0, at: .now)
            }
        ) else {
            return nil
        }
        return AppliedSnapshot(
            city: city.applying(
                snapshot,
                preservesResolvedCityName: preservesResolvedCityName
            ),
            snapshot: snapshot
        )
    }

    /// Returns a current-local-day, last-known-good extension snapshot after a
    /// direct request fails. This recovery path is intentionally unavailable to
    /// the host app and never uses the App Group catalog as weather storage.
    private func cityUsingFallbackWidgetSnapshot(
        for city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?,
        preservesResolvedCityName: Bool = false
    ) -> AppliedSnapshot? {
        guard let snapshot = WidgetForecastStore.fallbackSnapshot(
            forAny: city.allWidgetIdentifiers,
            matching: {
                snapshotMatchesCity(
                    $0,
                    city: city,
                    defaultLocationKind: defaultLocationKind
                ) && snapshotRepresentsLocalDay($0, at: .now)
            }
        ) else {
            return nil
        }
        let cachedCity = city.applying(
            snapshot,
            preservesResolvedCityName: preservesResolvedCityName
        )
        guard cachedCity.widgetCurrentIssue == nil else { return nil }
        return AppliedSnapshot(city: cachedCity, snapshot: snapshot)
    }

    /// Uses a valid fresh extension cache before making a bounded direct
    /// WeatherKit request. Every response is tied to the selection and reset
    /// generation captured before suspension.
    private func refreshedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) async -> RefreshResult {
        let executionDeadline = ContinuousClock.now.advanced(
            by: providerExecutionBudget
        )
        let capturedCatalog = WidgetDataStore.catalog()
        guard let selectedCatalogCity = selectedCity(
            for: configuration,
            catalog: capturedCatalog
        ) else {
            return RefreshResult(
                city: nil,
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }

        let resetEpoch = WidgetResetEpoch.current
        let capturedLanguageIdentifier = appLanguageIdentifier(
            in: capturedCatalog
        )
        let capturedDefaultLocationKind = defaultLocationKind(
            for: selectedCatalogCity,
            catalog: capturedCatalog
        )
        let selectionIdentity = WidgetSelectionIdentity(
            city: selectedCatalogCity,
            appLanguageIdentifier: capturedLanguageIdentifier,
            defaultLocationKind: capturedDefaultLocationKind,
            resetEpoch: resetEpoch
        )
        let resolvesDeviceLocation = usesDeviceCurrentLocation(
            configuration,
            catalog: capturedCatalog
        )
        guard selectionStillMatches(
            selectionIdentity,
            configuration: configuration,
            resolvesDeviceLocation: resolvesDeviceLocation
        ) else {
            return resultForCurrentSelection(configuration)
        }

        let city: WidgetDataCity
        let locationTimestamp: Date?
        let preservesResolvedCityName: Bool
        if resolvesDeviceLocation {
            do {
                let resolved = try await resolvedDeviceLocationCity(
                    replacing: selectedCatalogCity,
                    languageIdentifier: capturedLanguageIdentifier
                )
                city = resolved.city
                locationTimestamp = resolved.locationTimestamp
                preservesResolvedCityName = resolved.hasFreshResolvedCityName
                try Task.checkCancellation()
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ) else {
                    return resultForCurrentSelection(configuration)
                }
            } catch is CancellationError {
                return transientCurrentLocationFallback(
                    for: selectedCatalogCity
                )
            } catch let error as WidgetCurrentLocationError {
                switch error {
                case .widgetUpdatesNotAuthorized,
                     .locationServicesDisabled:
                    // Once location use is disallowed, never keep presenting or
                    // refetching the last app-published device coordinate.
                    WidgetForecastStore.removeSnapshot(
                        for: WidgetDataStore.currentLocationIdentifier
                    )
                    return RefreshResult(
                        city: selectedCatalogCity.markingUnavailable(
                            .unresolvedPlace("widget current location permission")
                        ),
                        snapshot: nil,
                        reloadPolicy: .persistentFailure
                    )
                case .locationUnavailable,
                     .timeZoneUnavailable,
                     .timedOut:
                    // A short-lived location outage may reuse only the
                    // extension's same-day response. It must not launch a new
                    // WeatherKit request for an unverified old coordinate.
                    return transientCurrentLocationFallback(
                        for: selectedCatalogCity
                    )
                }
            } catch {
                return transientCurrentLocationFallback(
                    for: selectedCatalogCity
                )
            }
        } else {
            city = await cityResolvingTimeZoneIfNeeded(selectedCatalogCity)
            locationTimestamp = nil
            preservesResolvedCityName = false
            // Time-zone repair is asynchronous. A Saved Place can be deleted,
            // replaced, or edited while it is suspended, so do not apply a
            // cache or begin WeatherKit work for the captured stale record.
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: false
            ) else {
                return resultForCurrentSelection(configuration)
            }
        }

        if let issue = city.widgetCurrentIssue {
            return RefreshResult(
                city: city.markingUnavailable(issue),
                snapshot: nil,
                reloadPolicy: reloadPolicy(for: issue)
            )
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude else {
            return RefreshResult(
                city: city.markingUnavailable(.unresolvedPlace("coordinates")),
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }
        guard let timeZoneIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: timeZoneIdentifier) != nil else {
            return RefreshResult(
                city: city.markingUnavailable(.missingTimeZone),
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }

        if resolvesDeviceLocation {
            let remainsAuthorized = await WidgetCurrentLocationResolver
                .widgetUpdatesAuthorized()
            guard remainsAuthorized else {
                WidgetForecastStore.removeSnapshot(
                    for: WidgetDataStore.currentLocationIdentifier
                )
                return RefreshResult(
                    city: city.markingUnavailable(
                        .unresolvedPlace("widget current location permission")
                    ),
                    snapshot: nil,
                    reloadPolicy: .persistentFailure
                )
            }
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: true
            ) else {
                return resultForCurrentSelection(configuration)
            }
        }

        // A normal WidgetKit callback often arrives while the last extension
        // response is still fresh. Reusing it preserves WeatherKit budget and
        // makes the widget independent from main-app launches.
        if let applied = freshAppliedSnapshot(
            for: city,
            defaultLocationKind: capturedDefaultLocationKind,
            preservesResolvedCityName: preservesResolvedCityName
        ) {
            return RefreshResult(
                city: applied.city,
                snapshot: applied.snapshot,
                reloadPolicy: .normal
            )
        }

        let requestKey = WidgetForecastRequestKey(
            cityID: city.id,
            cityName: city.cityName,
            cityNameLocaleIdentifier: capturedLanguageIdentifier,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: timeZoneIdentifier,
            forecastLocalDate: {
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
                return calendar.startOfDay(for: .now)
            }(),
            locationTimestamp: locationTimestamp,
            locationSource: resolvesDeviceLocation
                ? .deviceCurrentLocation
                : .fixedLocation,
            resetEpoch: resetEpoch
        )

        do {
            let box = try await WidgetForecastRequestCoordinator.shared.snapshot(
                for: requestKey
            ) {
                let response = try await Self.weatherResponseWithRetry(
                    for: requestKey,
                    deadline: executionDeadline
                )
                guard let timeZone = TimeZone(
                    identifier: requestKey.timeZoneIdentifier
                ) else {
                    throw WidgetWeatherFetchError.invalidTimeZone
                }
                return WidgetWeatherSnapshotBox(
                    snapshot: try Self.makeWeatherSnapshot(
                        currentWeather: response.currentWeather,
                        dailyForecast: response.dailyForecast,
                        hourlyForecast: response.hourlyForecast,
                        request: requestKey,
                        timeZone: timeZone
                    )
                )
            }
            try Task.checkCancellation()

            // WeatherKit and Core Location can both suspend across midnight.
            // Never persist or display a response whose destination-local day
            // ceased to be Today while the request was in flight.
            guard snapshotRepresentsLocalDay(box.snapshot, at: .now) else {
                throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
            }

            // Do not save or display a response if Reset App, widget selection,
            // city coordinates, timezone, or localized city identity changed
            // while either WeatherKit attempt was suspended.
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ), box.snapshot.resetEpoch == WidgetResetEpoch.current else {
                return resultForCurrentSelection(configuration)
            }
            if resolvesDeviceLocation {
                let remainsAuthorized = await WidgetCurrentLocationResolver
                    .widgetUpdatesAuthorized()
                guard remainsAuthorized else {
                    WidgetForecastStore.removeSnapshot(
                        for: WidgetDataStore.currentLocationIdentifier
                    )
                    return RefreshResult(
                        city: city.markingUnavailable(
                            .unresolvedPlace("widget current location permission")
                        ),
                        snapshot: nil,
                        reloadPolicy: .persistentFailure
                    )
                }
                // The authorization query itself suspends. Revalidate the app
                // publication once more before persisting its response.
                guard selectionStillMatches(
                    selectionIdentity,
                    configuration: configuration,
                    resolvesDeviceLocation: true
                ), box.snapshot.resetEpoch == WidgetResetEpoch.current else {
                    return resultForCurrentSelection(configuration)
                }
            }

            WidgetForecastStore.save(box.snapshot, for: city.id)
            return RefreshResult(
                city: city.applying(
                    box.snapshot,
                    preservesResolvedCityName: preservesResolvedCityName
                ),
                snapshot: box.snapshot,
                reloadPolicy: .normal
            )
        } catch is CancellationError {
            widgetForecastLogger.error(
                "Widget forecast refresh was cancelled for \(city.id, privacy: .public)"
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            if let fallback = cityUsingFallbackWidgetSnapshot(
                for: city,
                defaultLocationKind: capturedDefaultLocationKind,
                preservesResolvedCityName: preservesResolvedCityName
            ) {
                return RefreshResult(
                    city: fallback.city,
                    snapshot: fallback.snapshot,
                    reloadPolicy: .transientFailure
                )
            }
            return RefreshResult(
                city: city.markingUnavailable(.missingForecastData(at: .now)),
                snapshot: nil,
                reloadPolicy: .transientFailure
            )
        } catch {
            widgetForecastLogger.error(
                "Widget forecast refresh failed for \(city.id, privacy: .public): \(String(reflecting: error), privacy: .public)"
            )
            guard selectionStillMatches(
                selectionIdentity,
                configuration: configuration,
                resolvesDeviceLocation: resolvesDeviceLocation
            ) else {
                return resultForCurrentSelection(configuration)
            }
            if let fallback = cityUsingFallbackWidgetSnapshot(
                for: city,
                defaultLocationKind: capturedDefaultLocationKind,
                preservesResolvedCityName: preservesResolvedCityName
            ) {
                return RefreshResult(
                    city: fallback.city,
                    snapshot: fallback.snapshot,
                    reloadPolicy: Self.isTransientWeatherRequestError(error)
                        ? .transientFailure
                        : .persistentFailure
                )
            }
            return RefreshResult(
                city: city.markingUnavailable(
                    .weatherRequestFailed(String(reflecting: type(of: error)))
                ),
                snapshot: nil,
                reloadPolicy: Self.isTransientWeatherRequestError(error)
                    ? .transientFailure
                    : .persistentFailure
            )
        }
    }

    /// Repairs legacy fixed places whose catalog predates persisted time-zone
    /// metadata. The lookup is local to the extension, so the widget remains
    /// self-sufficient without waiting for the containing app to reopen.
    private func cityResolvingTimeZoneIfNeeded(
        _ city: WidgetDataCity
    ) async -> WidgetDataCity {
        if let identifier = city.timeZoneIdentifier,
           TimeZone(identifier: identifier) != nil {
            return city
        }
        guard let latitude = city.latitude,
              let longitude = city.longitude,
              let timeZone = await WidgetTimeZoneResolver.shared.timeZone(
                  latitude: latitude,
                  longitude: longitude
              ) else {
            return city
        }
        return city.replacingTimeZone(with: timeZone.identifier)
    }

    /// Re-resolves the configuration after suspension so catalog/reset changes
    /// cannot be hidden by the provider's earlier value-type copy.
    private func selectionStillMatches(
        _ identity: WidgetSelectionIdentity,
        configuration: SunnyHoursLockScreenConfigurationIntent,
        resolvesDeviceLocation: Bool
    ) -> Bool {
        let catalog = WidgetDataStore.catalog()
        guard WidgetResetEpoch.current == identity.resetEpoch,
              let currentCity = selectedCity(
                  for: configuration,
                  catalog: catalog
              ) else {
            return false
        }
        let currentLanguageIdentifier = appLanguageIdentifier(in: catalog)
        let currentDefaultLocationKind = defaultLocationKind(
            for: currentCity,
            catalog: catalog
        )

        // Device Current Location is intentionally independent from the
        // app-published coordinate and label. While an async request is in
        // flight, only its stable configured slot, default-location mode, and
        // reset generation must remain unchanged. The request key separately
        // binds the resulting forecast to the extension-resolved coordinate.
        if resolvesDeviceLocation {
            return currentCity.id == WidgetDataStore.currentLocationIdentifier
                && usesDeviceCurrentLocation(
                    configuration,
                    catalog: catalog
                )
                && identity.defaultLocationKind == .currentLocation
                && currentDefaultLocationKind == identity.defaultLocationKind
                && currentLanguageIdentifier
                    == identity.appLanguageIdentifier
        }
        return WidgetSelectionIdentity(
            city: currentCity,
            appLanguageIdentifier: currentLanguageIdentifier,
            defaultLocationKind: currentDefaultLocationKind,
            resetEpoch: WidgetResetEpoch.current
        ) == identity
    }

    /// Produces a truthful fetch identity from a widget-owned Core Location
    /// request. Reverse-geocoded metadata updates the label and timezone after
    /// travel. If metadata briefly fails without meaningful movement, the last
    /// published identity remains safe; after a move, neutral Current Location
    /// copy and the bundled coordinate time-zone database avoid labelling the
    /// new coordinate as the old city or using the device's former timezone.
    private func resolvedDeviceLocationCity(
        replacing publishedCity: WidgetDataCity,
        languageIdentifier: String
    ) async throws -> ResolvedDeviceLocationCity {
        let context = try await WidgetCurrentLocationRequestCoordinator.shared
            .currentContext(
            locationTimeout: .seconds(5),
            metadataTimeout: .seconds(3),
            locale: Locale(identifier: languageIdentifier)
        )
        let newLocation = CLLocation(
            latitude: context.latitude,
            longitude: context.longitude
        )
        let publishedLocation = publishedCity.latitude.flatMap { latitude in
            publishedCity.longitude.map { longitude in
                CLLocation(latitude: latitude, longitude: longitude)
            }
        }
        let movedMeaningfully = publishedLocation.map {
            $0.distance(from: newLocation) > 2_000
        } ?? true

        let resolvedName = context.cityName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let freshResolvedName = resolvedName.flatMap { $0.isEmpty ? nil : $0 }
        let cityName = freshResolvedName
            ?? (movedMeaningfully
                ? widgetLocalizedString("Current Location")
                : publishedCity.cityName)

        let geocodedTimeZone = context.timeZoneIdentifier.flatMap {
            TimeZone(identifier: $0)?.identifier
        }
        let coordinateTimeZone = await WidgetTimeZoneResolver.shared.timeZone(
            latitude: context.latitude,
            longitude: context.longitude
        )?.identifier
        let retainedTimeZone = movedMeaningfully
            ? nil
            : publishedCity.timeZoneIdentifier.flatMap {
                TimeZone(identifier: $0)?.identifier
            }
        guard let timeZoneIdentifier = geocodedTimeZone
            ?? coordinateTimeZone
            ?? retainedTimeZone else {
            throw WidgetCurrentLocationError.timeZoneUnavailable
        }

        return ResolvedDeviceLocationCity(
            city: WidgetDataCity(
                id: WidgetDataStore.currentLocationIdentifier,
                cityName: cityName,
                timeZoneIdentifier: timeZoneIdentifier,
                latitude: context.latitude,
                longitude: context.longitude
            ),
            locationTimestamp: context.locationTimestamp,
            hasFreshResolvedCityName: freshResolvedName != nil
        )
    }

    /// Recovers from a transient Core Location failure without using an old
    /// coordinate for a new network request. Fresh and retained snapshots are
    /// extension-owned and constrained to the same local day and location
    /// identity by the shared cache validators.
    private func transientCurrentLocationFallback(
        for publishedCity: WidgetDataCity
    ) -> RefreshResult {
        // Without a fresh coordinate this UI cannot honestly distinguish a
        // last-known forecast from current weather. Keep the private cache for
        // the next successful coordinate match, but do not display or refetch
        // it under the app's older published identity.
        return RefreshResult(
            city: publishedCity.markingUnavailable(
                .unresolvedPlace("widget current location")
            ),
            snapshot: nil,
            reloadPolicy: .transientFailure
        )
    }

    /// Produces a safe result for the selection that exists after a stale
    /// request completes. It never starts a second request within the same
    /// callback; WidgetKit's short retry will fetch the replacement identity.
    private func resultForCurrentSelection(
        _ configuration: SunnyHoursLockScreenConfigurationIntent
    ) -> RefreshResult {
        let catalog = WidgetDataStore.catalog()
        guard let city = selectedCity(
            for: configuration,
            catalog: catalog
        ) else {
            return RefreshResult(
                city: nil,
                snapshot: nil,
                reloadPolicy: .persistentFailure
            )
        }
        if let issue = city.widgetCurrentIssue {
            return RefreshResult(
                city: city.markingUnavailable(issue),
                snapshot: nil,
                reloadPolicy: reloadPolicy(for: issue)
            )
        }
        if usesDeviceCurrentLocation(configuration, catalog: catalog) {
            // This synchronous stale-request path cannot safely resolve a new
            // device coordinate. Ask WidgetKit to retry rather than displaying
            // a cache tied only to the app's older Current Location identity.
            return RefreshResult(
                city: city.markingUnavailable(
                    .missingForecastData(at: .now)
                ),
                snapshot: nil,
                reloadPolicy: .transientFailure
            )
        }
        if let applied = freshAppliedSnapshot(
            for: city,
            defaultLocationKind: defaultLocationKind(
                for: city,
                catalog: catalog
            )
        ) {
            return RefreshResult(
                city: applied.city,
                snapshot: applied.snapshot,
                reloadPolicy: .normal
            )
        }
        return RefreshResult(
            city: city.markingUnavailable(.missingForecastData(at: .now)),
            snapshot: nil,
            reloadPolicy: .transientFailure
        )
    }

    /// Classifies catalog and cached validation issues separately from direct
    /// request errors, which retain their concrete transient/terminal type.
    private func reloadPolicy(for issue: WeatherDataIssue) -> ReloadPolicy {
        switch issue.kind {
        case .weatherRequestFailed,
             .missingForecastData:
            return .transientFailure
        case .unresolvedPlace,
             .missingTimeZone:
            return .persistentFailure
        default:
            return .persistentFailure
        }
    }

    /// Tries WeatherKit's complete product first, then its independently useful
    /// daily/hourly products. Every attempt shares one absolute provider
    /// deadline, leaving WidgetKit time to archive and render the timeline.
    private static func weatherResponseWithRetry(
        for request: WidgetForecastRequestKey,
        deadline: ContinuousClock.Instant
    ) async throws -> WidgetWeatherKitResponse {
        guard let timeZone = TimeZone(
            identifier: request.timeZoneIdentifier
        ) else {
            throw WidgetWeatherFetchError.invalidTimeZone
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let forecastStartDate = request.forecastLocalDate
        guard let forecastEndDate = calendar.date(
            byAdding: .day,
            value: 10,
            to: forecastStartDate
        ) else {
            throw WidgetWeatherFetchError.invalidTimeZone
        }

        // Prefer the exact current product and give this one aggregate request
        // the provider's remaining budget. Starting a forecast-only duplicate
        // merely because the aggregate call reached a short local timeout can
        // overlap expensive WeatherKit work that ignored task cancellation.
        // A forecast-only recovery is therefore used only after the aggregate
        // request actually returns a nonterminal error.
        do {
            let timeout = try weatherRequestTimeout(
                preferred: .seconds(24),
                deadline: deadline
            )
            return try await WidgetWeatherOperationCoordinator.shared.response(
                latitude: request.latitude,
                longitude: request.longitude,
                forecastStartDate: forecastStartDate,
                forecastEndDate: forecastEndDate,
                timeout: timeout,
                mode: .complete
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Self.isTerminalWeatherRequestError(error)
                || Self.isWeatherRequestTimeout(error) {
                throw error
            }
            // Continue into the forecast-only recovery below. This is useful
            // for partial WeatherKit outages as well as network/cache states in
            // which the current product expires before the forecast products.
        }

        var finalError: Error = WidgetWeatherFetchError.timedOut
        for attempt in 0..<2 {
            try Task.checkCancellation()
            do {
                let timeout = try weatherRequestTimeout(
                    preferred: .seconds(24),
                    deadline: deadline
                )
                return try await WidgetWeatherOperationCoordinator.shared.response(
                    latitude: request.latitude,
                    longitude: request.longitude,
                    forecastStartDate: forecastStartDate,
                    forecastEndDate: forecastEndDate,
                    timeout: timeout,
                    mode: .forecastFallback
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                finalError = error
                guard attempt == 0,
                      Self.isTransientWeatherRequestError(error),
                      !Self.isWeatherRequestTimeout(error) else {
                    throw error
                }
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining >= .seconds(1) else {
                    throw finalError
                }
                try await Task.sleep(
                    for: min(.milliseconds(750), remaining)
                )
            }
        }
        throw finalError
    }

    /// Gives each WeatherKit operation only the portion of the provider budget
    /// that still remains. Tiny fragments cannot produce a useful response and
    /// are rejected before another system request is launched.
    private static func weatherRequestTimeout(
        preferred: Duration,
        deadline: ContinuousClock.Instant
    ) throws -> Duration {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining >= .milliseconds(250) else {
            throw WidgetWeatherFetchError.timedOut
        }
        return min(preferred, remaining)
    }

    private static func isWeatherRequestTimeout(_ error: Error) -> Bool {
        guard let fetchError = error as? WidgetWeatherFetchError else {
            return false
        }
        if case .timedOut = fetchError {
            return true
        }
        return false
    }

    private static func isTerminalWeatherRequestError(_ error: Error) -> Bool {
        guard let weatherError = error as? WeatherKit.WeatherError else {
            return false
        }
        switch weatherError {
        case .permissionDenied:
            return true
        case .unknown:
            return false
        @unknown default:
            return false
        }
    }

    private static func isTransientWeatherRequestError(_ error: Error) -> Bool {
        if let fetchError = error as? WidgetWeatherFetchError {
            switch fetchError {
            case .timedOut:
                return true
            case .missingCurrentHourlyCoverage:
                return true
            case .invalidTimeZone,
                 .missingHourlyFallback:
                return false
            }
        }
        if let weatherError = error as? WeatherKit.WeatherError {
            switch weatherError {
            case .unknown:
                return true
            case .permissionDenied:
                return false
            @unknown default:
                return true
            }
        }
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

    /// Rejects snapshots created for a superseded or corrupt timezone identity.
    private func snapshotMatchesCity(
        _ snapshot: WidgetWeatherSnapshot,
        city: WidgetDataCity,
        defaultLocationKind: WidgetDefaultLocationKind?
    ) -> Bool {
        let expectedSource: WidgetForecastLocationSource =
            city.id == WidgetDataStore.currentLocationIdentifier
                && defaultLocationKind == .currentLocation
            ? .deviceCurrentLocation
            : .fixedLocation
        guard let cityIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: cityIdentifier) != nil,
              snapshot.timeZoneIdentifier == cityIdentifier,
              snapshot.locationSource == expectedSource,
              let snapshotLatitude = snapshot.latitude,
              let snapshotLongitude = snapshot.longitude,
              let cityLatitude = city.latitude,
              let cityLongitude = city.longitude else {
            return false
        }
        // Device Current Location tolerates ordinary GPS jitter. Home and Saved
        // locations are fixed identities, so a much tighter bound prevents two
        // nearby Home coordinates sharing the stable default App Intent ID.
        let snapshotLocation = CLLocation(
            latitude: snapshotLatitude,
            longitude: snapshotLongitude
        )
        let cityLocation = CLLocation(
            latitude: cityLatitude,
            longitude: cityLongitude
        )
        let maximumDistance: CLLocationDistance = expectedSource
            == .deviceCurrentLocation
            ? 2_000
            : 50
        return snapshotLocation.distance(from: cityLocation) <= maximumDistance
    }

    /// Independently verifies the represented day at each use site. The store
    /// currently enforces this too, but keeping the display boundary local to
    /// the provider prevents a future cache-policy change from reviving an old
    /// day's current status.
    private func snapshotRepresentsLocalDay(
        _ snapshot: WidgetWeatherSnapshot,
        at date: Date
    ) -> Bool {
        guard let identifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: identifier),
              let representedDate = snapshot.representedLocalDate else {
            return false
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar.isDate(representedDate, inSameDayAs: date)
    }

    // MARK: - Timeline Planning

    /// Creates a useful offline timeline from one immutable forecast. Forecast
    /// interval boundaries update sun status, while half-hour checkpoints move
    /// the time marker and countdown even if WidgetKit defers the network reload.
    private func plannedTimeline(
        for result: RefreshResult,
        now: Date
    ) -> Timeline<SunnyHoursLockScreenEntry> {
        var preferredReloadDate: Date
        switch result.reloadPolicy {
        case .normal:
            preferredReloadDate = now.addingTimeInterval(normalRefreshInterval)
            if let snapshot = result.snapshot {
                // Refresh a fresh response when it reaches the normal age, not
                // 30 minutes after a cache-serving provider callback.
                preferredReloadDate = max(
                    now.addingTimeInterval(5 * 60),
                    snapshot.fetchedAt.addingTimeInterval(normalRefreshInterval)
                )
            }
        case .transientFailure:
            preferredReloadDate = now.addingTimeInterval(failureRetryInterval)
        case .persistentFailure:
            preferredReloadDate = now.addingTimeInterval(normalRefreshInterval)
        }

        guard let city = result.city,
              let snapshot = result.snapshot,
              let displayExpiry = snapshotDisplayExpiry(
                snapshot,
                relativeTo: now
              ),
              displayExpiry > now else {
            // A result can carry an applied city alongside a snapshot that
            // became invalid at midnight. Clear its weather-bearing fields so
            // yesterday's status is never rendered during the retry interval.
            let city = result.snapshot == nil
                ? result.city
                : result.city?.markingUnavailable(
                    .missingForecastData(at: now)
                )
            let entry = SunnyHoursLockScreenEntry(date: now, city: city)
            return Timeline(
                entries: [entry],
                policy: .after(preferredReloadDate)
            )
        }

        var futureDates = Set<Date>()
        let firstMarker = Date(
            timeIntervalSinceReferenceDate: ceil(
                now.timeIntervalSinceReferenceDate / markerUpdateInterval
            ) * markerUpdateInterval
        )
        var markerDate = firstMarker
        while markerDate < displayExpiry {
            if markerDate > now {
                futureDates.insert(markerDate)
            }
            markerDate = markerDate.addingTimeInterval(markerUpdateInterval)
        }

        // Each stored hour represents [date, date + 1 hour). Add both ends so
        // "Sun Out Now", countdown, and "No More Sun Today" change on time.
        for condition in snapshot.hourlyWeatherConditions ?? [] {
            for boundary in [
                condition.date,
                condition.date.addingTimeInterval(60 * 60)
            ] where boundary > now && boundary < displayExpiry {
                futureDates.insert(boundary)
            }
        }
        for boundary in [snapshot.sunrise, snapshot.sunset].compactMap({ $0 })
        where boundary > now && boundary < displayExpiry {
            futureDates.insert(boundary)
        }

        var entries = [SunnyHoursLockScreenEntry(date: now, city: city)]
        entries.append(
            contentsOf: futureDates.sorted().map {
                SunnyHoursLockScreenEntry(date: $0, city: city)
            }
        )

        // A terminal entry guarantees a deferred refresh cannot call yesterday
        // "today" or retain a response beyond the cache's display lifetime.
        entries.append(
            SunnyHoursLockScreenEntry(
                date: displayExpiry,
                city: city.markingUnavailable(
                    .missingForecastData(at: displayExpiry)
                )
            )
        )

        // `.after` is an earliest preferred refresh, not a background-task
        // schedule WidgetKit guarantees to honor.
        return Timeline(
            entries: entries,
            policy: .after(min(preferredReloadDate, displayExpiry))
        )
    }

    /// The represented local day and the cache retention are independent hard
    /// boundaries. Whichever arrives first ends forecast presentation.
    private func snapshotDisplayExpiry(
        _ snapshot: WidgetWeatherSnapshot,
        relativeTo now: Date
    ) -> Date? {
        guard snapshotRepresentsLocalDay(snapshot, at: now),
              let identifier = snapshot.timeZoneIdentifier,
              let timeZone = TimeZone(identifier: identifier),
              let representedDate = snapshot.representedLocalDate else {
            return nil
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        guard let nextLocalMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: representedDate)
        ) else {
            return nil
        }
        return min(
            nextLocalMidnight,
            snapshot.fetchedAt.addingTimeInterval(maximumDisplayInterval)
        )
    }

    // MARK: - WeatherKit Snapshot Construction

    /// Converts WeatherKit data into a compact rendering payload. Widgets use
    /// WeatherKit's daylight flag directly and derive their chart domains from
    /// the returned hours, without interpreting solar-event edge cases. Current
    /// and hourly data remain usable even when no daily row is available for the
    /// large-widget timeline.
    private static func makeWeatherSnapshot(
        currentWeather: WidgetWeatherPresentation,
        dailyForecast: Forecast<DayWeather>,
        hourlyForecast: Forecast<HourWeather>,
        request: WidgetForecastRequestKey,
        timeZone: TimeZone
    ) throws -> WidgetWeatherSnapshot {
        let now = Date()
        // WeatherKit Dates are absolute instants. Interpret both `now` and each
        // forecast date in the configured city's timezone before choosing today.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentLocalDay = request.forecastLocalDate
        guard calendar.isDate(currentLocalDay, inSameDayAs: now) else {
            throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
        }
        let forecastDays = Array(
            dailyForecast.forecast
                .filter { calendar.startOfDay(for: $0.date) >= currentLocalDay }
                .prefix(10)
        )
        // Group WeatherKit's available daylight records once. Both the current
        // card and every large-widget row then reuse the same local-day data.
        let allHourlyForecasts = Array(hourlyForecast.forecast)
            .sorted { $0.date < $1.date }
        widgetForecastLogger.debug(
            "Building widget snapshot with \(allHourlyForecasts.count) hourly and \(dailyForecast.forecast.count) daily records; first=\(String(describing: allHourlyForecasts.first?.date), privacy: .public), last=\(String(describing: allHourlyForecasts.last?.date), privacy: .public), now=\(String(describing: now), privacy: .public)"
        )
        let completeHoursByDay = completeHourlyForecastsByDay(
            allHourlyForecasts,
            currentLocalDay: currentLocalDay,
            now: now,
            calendar: calendar
        )
        guard let currentDayHours = completeHoursByDay[currentLocalDay] else {
            throw WidgetWeatherFetchError.missingCurrentHourlyCoverage
        }
        let daylightHoursByDay = Dictionary(
            grouping: allHourlyForecasts.filter { forecast in
                guard completeHoursByDay[
                    calendar.startOfDay(for: forecast.date)
                ] != nil else {
                    return false
                }
                return forecast.isDaylight
            }
        ) {
            calendar.startOfDay(for: $0.date)
        }
        // Retain each daylight record's source condition and symbol unchanged.
        let currentHourlyConditions = widgetForecastHourlyConditions(
            hours: daylightHoursByDay[currentLocalDay] ?? [],
            calendar: calendar
        )
        let currentDayWeatherConditions = widgetForecastHourlyConditions(
            hours: currentDayHours,
            calendar: calendar
        )
        let currentDayForecast = forecastDays.first {
            calendar.startOfDay(for: $0.date) == currentLocalDay
        }

        // The large widget shows each available current/future WeatherKit day,
        // up to its ten-row capacity. Each row uses only WeatherKit's available
        // daylight-marked hourly records.
        let sunnyWindowDays: [WidgetSunnyWindowDay] = forecastDays.compactMap {
            day -> WidgetSunnyWindowDay? in
            let localDay = calendar.startOfDay(for: day.date)
            // Omit a day the hourly product did not cover. An empty daylight
            // group remains valid when that covered day is a polar night.
            guard completeHoursByDay[localDay] != nil else { return nil }
            let hourlyConditions = widgetForecastHourlyConditions(
                hours: daylightHoursByDay[localDay] ?? [],
                calendar: calendar
            )
            return WidgetSunnyWindowDay(
                date: localDay,
                hourlyConditions: hourlyConditions
            )
        }

        return WidgetWeatherSnapshot(
            resetEpoch: request.resetEpoch,
            fetchedAt: now,
            representedLocalDate: calendar.startOfDay(for: now),
            timeZoneIdentifier: timeZone.identifier,
            latitude: request.latitude,
            longitude: request.longitude,
            resolvedCityName: request.cityName,
            cityNameLocaleIdentifier: request.cityNameLocaleIdentifier,
            locationTimestamp: request.locationTimestamp,
            locationSource: request.locationSource,
            currentWeather: currentWeather,
            hourlyConditions: currentHourlyConditions,
            hourlyWeatherConditions: currentDayWeatherConditions,
            sunrise: currentDayForecast?.sun.sunrise,
            sunset: currentDayForecast?.sun.sunset,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
    }

    /// Returns only local days whose hourly product continuously covers the
    /// portion WeatherKit was asked to provide. Future rows must span their
    /// complete 23/24/25-hour civil day; Today's row may begin at its current
    /// hour because WeatherKit does not promise historical hourly conditions.
    /// This keeps a partial response from being painted as neutral "No Sun".
    private static func completeHourlyForecastsByDay(
        _ forecasts: [HourWeather],
        currentLocalDay: Date,
        now: Date,
        calendar: Calendar
    ) -> [Date: [HourWeather]] {
        let grouped = Dictionary(grouping: forecasts) {
            calendar.startOfDay(for: $0.date)
        }
        let tolerance: TimeInterval = 5 * 60
        return grouped.reduce(into: [:]) { result, pair in
            let day = pair.key
            guard let dayEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                return
            }
            let sorted = Dictionary(
                grouping: pair.value,
                by: \.date
            ).compactMap { $0.value.first }.sorted { $0.date < $1.date }
            guard let first = sorted.first,
                  let last = sorted.last else {
                return
            }
            let expectedStart: Date
            if calendar.isDate(day, inSameDayAs: currentLocalDay) {
                expectedStart = calendar.dateInterval(of: .hour, for: now)?.start
                    ?? now
            } else {
                expectedStart = day
            }
            let coversExpectedStart = sorted.contains { forecast in
                forecast.date <= expectedStart.addingTimeInterval(tolerance)
                    && forecast.date.addingTimeInterval(60 * 60)
                        > expectedStart.addingTimeInterval(-tolerance)
            }
            guard first.date <= expectedStart.addingTimeInterval(tolerance),
                  coversExpectedStart,
                  last.date.addingTimeInterval(60 * 60)
                    >= dayEnd.addingTimeInterval(-tolerance),
                  zip(sorted, sorted.dropFirst()).allSatisfy({ pair in
                      let gap = pair.1.date.timeIntervalSince(pair.0.date)
                      return gap > 0 && gap <= 60 * 60 + tolerance
                  }) else {
                return
            }
            result[day] = sorted
        }
    }

}

// MARK: - Widget Forecast Classification

/// Reduces WeatherKit records to the persistent widget payload without
/// translating their condition or replacing their source symbol.
private func widgetForecastHourlyConditions(
    hours: [HourWeather],
    calendar: Calendar
) -> [WidgetHourlyCondition] {
    hours.map { forecast in
        let weather = WidgetWeatherPresentation(
            condition: AppWeatherCondition(weatherKit: forecast.condition),
            symbolName: forecast.symbolName
        )
        let hour = calendar.component(.hour, from: forecast.date)
        return WidgetHourlyCondition(
            date: forecast.date,
            hour: hour,
            weather: weather
        )
    }
}

/// Uses the actual represented hours where possible; a full-day domain is a
/// safe visual fallback when WeatherKit gives no daylight records to narrow it.
private func widgetFallbackChartBounds(for hours: [Int]) -> SunnyHoursChartBounds {
    guard let firstHour = hours.min(), let lastHour = hours.max() else {
        return .fullDay
    }
    return SunnyHoursChartBounds(startHour: firstHour, endHour: lastHour + 1)
}

private extension WidgetSunnyWindowDay {
    var widgetDaylightBounds: SunnyHoursChartBounds {
        widgetFallbackChartBounds(for: chartHourlyConditions.map(\.hour))
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
                .modifier(WidgetTextSizePolicyModifier())
                // Let the person's Lock Screen data-access setting redact city
                // and forecast details while the device is locked.
                .privacySensitive()
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(WidgetDataStore.localizedText(for: "Sunny Hours"))
        .description(WidgetDataStore.localizedText(for: "Track sunny daytime hours for a chosen city."))
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Height-specific rectangular Lock Screen presentation. The accessory family
/// is much shorter than a Small Home widget, so its information is arranged in
/// one compact row instead of inheriting the taller icon/status/city stack.
private struct SunnyHoursLockScreenWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @Environment(\.locale) private var locale
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Keeps city and condition/status visible without clipping at the system's
    /// fixed accessory-rectangular height.
    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            HStack(alignment: .center, spacing: 8) {
                if issue == nil,
                   let weather = widgetWeatherPresentation(
                       for: city,
                       at: entry.date
                   ) {
                    WidgetConditionIcon(weather: weather, size: 24)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(renderedSecondary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(city.cityName)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(status ?? widgetLocalizedString("Weather unavailable."))
                        .font(.caption2)
                        .foregroundStyle(renderedSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .leading
            )
            .foregroundStyle(renderedPrimary)
            .widgetURL(widgetPlaceURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }

    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    private var renderedPrimary: Color {
        usesSystemColors ? .primary : widgetPalette.titleText
    }

    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : widgetPalette.secondaryText
    }
}

// MARK: - Shared Widget Presentation

/// Shared city-name and current-condition header for every widget family.
/// It can show either a condition icon or a text sunny-window summary, keeping
/// family-specific choice at the call site and the visual alignment in one place.
private struct SunnyHoursHeader: View {
    /// Widget appearance selecting the weather icon palette.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode determining full-color versus monochrome symbols.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Localized configured city name.
    let cityName: String
    /// Optional current WeatherKit condition and source symbol.
    let weather: WidgetWeatherPresentation?
    /// Optional day-total text replacing the condition icon on Home Screen widgets.
    var summaryText: String? = nil
    /// Family-specific header font.
    let font: Font
    /// Whether full-color weather icon rendering is permitted.
    let usesWeatherColors: Bool

    /// Builds city title and its WeatherKit-provided condition icon. If weather
    /// data is absent, the header leaves that secondary slot empty while
    /// retaining the available weather timeline.
    var body: some View {
        HStack(spacing: 6) {
            Text(cityName)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 6)
            // Home Screen cards prefer a compact daily total. Lock Screen cards
            // omit it and show the current condition symbol instead.
            if let summaryText {
                Text(summaryText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        widgetRenderingMode == .fullColor
                            ? widgetPalette.secondaryText
                            : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else if let weather {
                // WidgetKit can request monochrome/tinted rendering regardless
                // of the device color scheme. In Full Color, match each weather
                // symbol to the same semantic color as its Map-dot condition.
                if usesWeatherColors,
                   widgetRenderingMode == .fullColor {
                    Image(systemName: weather.symbolName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            widgetConditionIconColor(
                                for: weather,
                                colors: widgetPalette
                            )
                        )
                } else {
                    Image(systemName: weather.symbolName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .font(font)
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }
}

/// Reusable weather symbol for compact widgets. Home Screen widgets retain the
/// app's semantic condition tint; WidgetKit-controlled Lock Screen rendering
/// remains system monochrome or tinted as required.
private struct WidgetConditionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let weather: WidgetWeatherPresentation
    let size: CGFloat

    var body: some View {
        Image(systemName: weather.symbolName)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        guard widgetRenderingMode == .fullColor else { return .primary }
        return widgetConditionIconColor(
            for: weather,
            colors: AppPalette.values(
                for: colorScheme,
                contrast: colorSchemeContrast
            )
        )
    }
}

/// Formats the full current-day favorable total for widget headers.
private func widgetSunnyHoursTotalText(
    for city: WidgetDataCity,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil else { return nil }
    // Count source forecast records rather than distinct clock labels. A local
    // hour repeats when daylight saving time ends, and both real hours belong
    // in the day's total.
    let favorableHourCount = (city.hourlyConditions ?? []).count { hour in
        hour.weather?.condition.countsAsSunnyHour == true
    }
    guard favorableHourCount > 0 else {
        return widgetLocalizedString("No Sun")
    }
    return SunnyHoursFormatting.hourCountLabel(
        Double(favorableHourCount),
        locale: locale
    )
}

/// Chooses the hourly condition that covers a timeline entry. WidgetKit can
/// render these entries long after the extension was suspended, so compact
/// icons must advance from persisted hourly data rather than freezing the
/// fetch-time current observation.
private func widgetWeatherPresentation(
    for city: WidgetDataCity,
    at date: Date
) -> WidgetWeatherPresentation? {
    if let currentWeather = city.currentWeather,
       let fetchedAt = city.weatherFetchedAt,
       let timeZone = city.widgetTimeZone {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        if calendar.isDate(date, equalTo: fetchedAt, toGranularity: .hour) {
            return currentWeather
        }
    }
    if let weather = city.hourlyWeatherConditions?.first(where: {
        $0.date <= date && date < $0.date.addingTimeInterval(60 * 60)
    })?.weather {
        return weather
    }
    return city.currentWeather
}

/// Uses the same current-day sun-status wording as the Detail hero. Widgets
/// only display today, so the non-today "Sunny for … hours" branch is not
/// needed here.
private func widgetSunStatusText(
    for city: WidgetDataCity,
    at referenceDate: Date,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil,
          let timeZone = city.widgetTimeZone else {
        return nil
    }

    guard let conditions = city.hourlyConditions else { return nil }
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let representedConditions = conditions
        .filter { calendar.isDate($0.date, inSameDayAs: referenceDate) }
        .sorted { $0.date < $1.date }
    let sunnyConditions = representedConditions.filter {
        $0.weather?.condition.countsAsSunnyHour == true
    }

    // Solar events refine live copy at their exact instant. HourWeather's
    // daylight flag remains the sole source for chart totals and colors.
    if let sunset = city.sunset, referenceDate >= sunset {
        return sunnyConditions.isEmpty
            ? widgetLocalizedString("No Sun Today")
            : widgetLocalizedString("No More Sun Today")
    }
    if let sunrise = city.sunrise, sunrise > referenceDate,
       sunnyConditions.contains(where: {
           $0.date <= sunrise
               && sunrise < $0.date.addingTimeInterval(60 * 60)
       }) {
        return String(
            format: widgetLocalizedString("Sun Out in %@"),
            locale: locale,
            widgetCountdownText(
                to: sunrise,
                from: referenceDate,
                locale: locale
            )
        )
    }

    // An empty daylight array is valid during polar night. The snapshot still
    // has a current condition and daily forecast, so this means zero daylight
    // rather than a failed WeatherKit request.
    guard !sunnyConditions.isEmpty else {
        return widgetLocalizedString("No Sun Today")
    }

    if let current = representedConditions.last(where: {
        $0.date <= referenceDate
            && referenceDate < $0.date.addingTimeInterval(60 * 60)
    }), current.weather?.condition.countsAsSunnyHour == true {
        return widgetLocalizedString("Sun Out Now")
    }
    if let next = sunnyConditions.first(where: { $0.date > referenceDate }) {
        let nextSunnyInstant: Date
        if let sunrise = city.sunrise,
           sunrise > next.date,
           sunrise < next.date.addingTimeInterval(60 * 60) {
            nextSunnyInstant = sunrise
        } else {
            nextSunnyInstant = next.date
        }
        return String(
            format: widgetLocalizedString("Sun Out in %@"),
            locale: locale,
            widgetCountdownText(
                to: nextSunnyInstant,
                from: referenceDate,
                locale: locale
            )
        )
    }
    return widgetLocalizedString("No More Sun Today")
}

/// Formats the Detail-compatible duration without depending on the app process.
private func widgetCountdownText(
    to date: Date,
    from referenceDate: Date,
    locale: Locale
) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    var calendar = Calendar.autoupdatingCurrent
    calendar.locale = locale
    formatter.calendar = calendar
    return formatter.string(
        from: max(0, date.timeIntervalSince(referenceDate))
    ) ?? widgetLocalizedString("less than one minute")
}

/// Widget-only adapter for the current-day chart. The actual capsule rendering
/// is shared with the app's Daily Sunny Hours card.
private struct WidgetDailySunnyHoursTimeline: View {
    // MARK: - Rendering Environment and Inputs

    /// Contrast preference selecting the app's higher-contrast colors.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode controlling system monochrome/tinted colors.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Configured city with current-day chart data.
    let city: WidgetDataCity
    /// Entry time used by the city-local current-time marker.
    let currentDate: Date
    // MARK: - Shared Timeline

    var body: some View {
        SunnyHoursDiscreteCapsuleTimeline(
            hours: chartHours,
            bounds: city.widgetCurrentDaylightBounds,
            currentDate: currentDate,
            timeZone: city.widgetTimeZone ?? .autoupdatingCurrent,
            showsCurrentTimeMarker: true,
            configuration: .appAndHome,
            colors: sharedChartColors
        )
    }

    // MARK: - Timeline Rendering

    /// Resolves the widget's colour policy before passing it to the shared
    /// renderer. WidgetKit can enforce monochrome or accented colours.
    private func timelineColor(for tone: WeatherIconTone) -> Color {
        if usesSystemColors {
            return monochromeColor(for: tone)
        }

        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return chartColor(for: tone, colors: colors)
        }

        return chartColor(for: tone, colors: palette)
    }

    private var sharedChartColors: SunnyHoursChartColors {
        SunnyHoursChartColors(
            primary: renderedPrimary,
            secondary: renderedSecondary,
            sun: timelineColor(for: .clear),
            partlySunny: timelineColor(for: .partlySunny),
            rain: timelineColor(for: .rain),
            drizzle: timelineColor(for: .drizzle),
            noSun: timelineColor(for: .cloudy)
        )
    }

    /// Adapts exact persisted API conditions to the presentation-only shared
    /// track. No missing source value is replaced by a fabricated condition.
    private var chartHours: [SunnyHoursChartHour] {
        let daylightHours = city.hourlyConditions ?? []
        if !daylightHours.isEmpty {
            return daylightHours.compactMap { source in
                guard let weather = source.weather else { return nil }
                return SunnyHoursChartHour(
                    date: source.date,
                    hour: source.hour,
                    condition: weather.condition
                )
            }
        }

        // A fully covered polar-night response legitimately contains no
        // daylight records. Draw its available hours as neutral no-sun cells
        // instead of leaving the medium widget's timeline blank.
        let noSun = AppWeatherCondition(
            weatherKit: WeatherKit.WeatherCondition.cloudy
        )
        return (city.hourlyWeatherConditions ?? []).map { source in
            SunnyHoursChartHour(
                date: source.date,
                hour: source.hour,
                condition: noSun
            )
        }
    }

    /// Neutral no-sun color shared by non-sunny chart slots.
    private var noSunColor: Color {
        if usesSystemColors {
            return .primary.opacity(0.14)
        }
        return widgetNoSunTimelineColor(
            colorScheme: colorScheme,
            contrast: colorSchemeContrast
        )
    }

    /// WidgetKit may enforce monochrome/tinted rendering, where custom colors
    /// are unavailable. Preserve condition differences with distinct weights.
    private func monochromeColor(for tone: WeatherIconTone) -> Color {
        switch tone {
        case .clear:
            .primary.opacity(1)
        case .partlySunny:
            .primary.opacity(0.92)
        case .rain:
            .primary.opacity(0.82)
        case .drizzle:
            .primary.opacity(0.38)
        case .cloudy:
            noSunColor
        }
    }

    /// Uses the widget's full-color timeline mapping: clear, rain, drizzle,
    /// and the neutral no-sun treatment.
    private func chartColor(
        for tone: WeatherIconTone,
        colors: AppPalette.Values
    ) -> Color {
        switch tone {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
        case .cloudy:
            widgetNoSunTimelineColor(
                colorScheme: colorScheme,
                contrast: colorSchemeContrast
            )
        }
    }

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
    }

    /// Whether WidgetKit requires semantic system foregrounds.
    private var usesSystemColors: Bool {
        widgetRenderingMode != .fullColor
    }

    /// Effective primary foreground.
    private var renderedPrimary: Color {
        usesSystemColors ? .primary : palette.titleText
    }

    /// Effective secondary foreground.
    private var renderedSecondary: Color {
        usesSystemColors ? .secondary : palette.secondaryText
    }

}

/// Centered five-state key shared by medium and large Home Screen timelines.
/// It mirrors the timeline's rendering mode, so the explanatory key remains
/// consistent with the chart.
private struct SunnyHoursLegend: View {
    // MARK: - Rendering Environment

    /// Contrast preference selecting stronger semantic colors.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode selecting system or full-color foregrounds.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Legend Layout

    /// Builds the timeline's clear, partly sunny, neutral, rain, and drizzle
    /// categories.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                legendItems
            }

            VStack(spacing: 5) {
                HStack(spacing: 14) {
                    item(
                        color: color(for: .clear),
                        title: widgetLocalizedString("Sunny")
                    )
                    item(
                        color: color(for: .partlySunny),
                        title: widgetLocalizedString("Partly Sunny")
                    )
                }
                HStack(spacing: 14) {
                    item(
                        color: color(for: .cloudy),
                        title: widgetLocalizedString("No Sun")
                    )
                    item(
                        color: color(for: .rain),
                        title: widgetLocalizedString("Rain")
                    )
                    item(
                        color: color(for: .drizzle),
                        title: widgetLocalizedString("Drizzle")
                    )
                }
            }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(renderedSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    /// Complete one-line legend, used whenever the widget family can fit it.
    private var legendItems: some View {
        Group {
            item(
                color: color(for: .clear),
                title: widgetLocalizedString("Sunny")
            )
            item(
                color: color(for: .partlySunny),
                title: widgetLocalizedString("Partly Sunny")
            )
            item(
                color: color(for: .cloudy),
                title: widgetLocalizedString("No Sun")
            )
            item(
                color: color(for: .rain),
                title: widgetLocalizedString("Rain")
            )
            item(
                color: color(for: .drizzle),
                title: widgetLocalizedString("Drizzle")
            )
        }
    }

    /// Matches the four timeline color categories used by the widget. In
    /// system-controlled widget rendering modes, use distinct monochrome
    /// weights because WidgetKit does not permit custom tint colors.
    private func color(for tone: WeatherIconTone) -> Color {
        if usesSystemColors {
            switch tone {
            case .clear:
                return .primary.opacity(1)
            case .partlySunny:
                return .primary.opacity(0.92)
            case .rain:
                return .primary.opacity(0.82)
            case .drizzle:
                return .primary.opacity(0.38)
            case .cloudy:
                return .primary.opacity(0.14)
            }
        }

        let colors = colorSchemeContrast == .increased
            ? AppPalette.increasedContrastValues(for: colorScheme)
            : palette
        switch tone {
        case .clear:
            return colors.dotSun
        case .partlySunny:
            return colors.dotPartlyCloudy
        case .rain:
            return colors.dotRain
        case .drizzle:
            return colors.dotDrizzle
        case .cloudy:
            return widgetNoSunTimelineColor(
                colorScheme: colorScheme,
                contrast: colorSchemeContrast
            )
        }
    }

    /// Builds one color-dot legend item.
    private func item(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
        }
    }

    /// Standard primitive palette for widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
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

    /// Presents a concise status while WidgetKit schedules its own retry.
    var body: some View {
        // Widget families have sharply different text budgets, so retain one
        // self-contained status rather than directing people to the app.
        let message = widgetLocalizedString("Weather unavailable.")

        Label(message, systemImage: "exclamationmark.icloud")
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

    }
}

/// Returns the exact semantic Map-dot color for a widget condition icon.
///
/// Full-color widgets use one color for every layer of a condition symbol, just
/// like the main app. WidgetKit's tinted and monochrome modes retain their
/// platform-controlled rendering outside this helper.
private func widgetConditionIconColor(
    for weather: WidgetWeatherPresentation,
    colors: AppPalette.Values
) -> Color {
    if weather.symbolName.localizedCaseInsensitiveContains("moon") {
        return colors.moonIcon
    }
    switch weather.condition.iconTone {
    case .clear:
        return colors.dotSun
    case .partlySunny:
        return colors.dotPartlyCloudy
    case .cloudy:
        return colors.dotCloudy
    case .rain:
        return colors.dotRain
    case .drizzle:
        return colors.dotDrizzle
    }
}

// MARK: - Deep Links

/// Builds a city-specific deep link carrying exact missing-data diagnostics when
/// needed. WidgetKit opens a Saved Place directly in Detail, while the special
/// Current Location selection opens its matching app report. URLComponents
/// safely percent-encodes the stable identifier and user-visible name.
private func widgetPlaceURL(for city: WidgetDataCity, issue: WeatherDataIssue?) -> URL? {
    var components = URLComponents()
    components.scheme = "weatheratlas"
    components.host = "place"
    var queryItems = [
        // Widget city IDs are cross-process coordinate identities, which the
        // app resolves back to the current Saved Place UUID before routing.
        URLQueryItem(name: "cityID", value: city.id),
        URLQueryItem(name: "city", value: city.cityName)
    ]
    if let issue {
        // Healthy widgets need only identity. Unavailable widgets append their
        // precise, user-safe issue so the app can retry before showing an alert.
        queryItems += [
            URLQueryItem(name: "missingKind", value: issue.kind.rawValue),
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
    }
    components.queryItems = queryItems
    return components.url
}

// MARK: - Widget Presentation Models

/// Builds deterministic source-shaped WeatherKit data for Xcode previews.
private func widgetPreviewWeather(
    _ condition: WeatherCondition,
    symbolName: String
) -> WidgetWeatherPresentation {
    WidgetWeatherPresentation(
        condition: AppWeatherCondition(weatherKit: condition),
        symbolName: symbolName
    )
}

private extension WidgetSunnyWindowDay {
    /// Full source conditions for a five-color row. Pre-source-payload snapshots
    /// are refreshed instead of fabricating a weather condition or symbol.
    var chartHourlyConditions: [WidgetHourlyCondition] {
        (hourlyConditions ?? []).filter { $0.weather != nil }
    }
}

private extension WidgetDataCity {
    // MARK: - Preview Fixture

    /// Deterministic multi-day city fixture used by WidgetKit previews.
    static var preview: WidgetDataCity {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var city = WidgetDataCity(
            id: "barcelona",
            cityName: "Barcelona",
            timeZoneIdentifier: "Europe/Madrid",
            latitude: 41.3874,
            longitude: 2.1686
        )
        city.hourlyConditions = (6...21).compactMap { hour in
            guard let date = calendar.date(
                bySettingHour: hour,
                minute: 0,
                second: 0,
                of: .now
            ) else {
                return nil
            }
            let weather: WidgetWeatherPresentation
            switch hour {
            case 8...16:
                weather = widgetPreviewWeather(.clear, symbolName: "sun.max.fill")
            case 17:
                weather = widgetPreviewWeather(.mostlyClear, symbolName: "cloud.sun.fill")
            case 7, 20:
                weather = widgetPreviewWeather(.partlyCloudy, symbolName: "cloud.sun.fill")
            case 18:
                weather = widgetPreviewWeather(.rain, symbolName: "cloud.rain.fill")
            case 19:
                weather = widgetPreviewWeather(.drizzle, symbolName: "cloud.drizzle.fill")
            default:
                weather = widgetPreviewWeather(.cloudy, symbolName: "cloud.fill")
            }
            return WidgetHourlyCondition(
                date: date,
                hour: hour,
                weather: weather
            )
        }
        city.currentWeather = widgetPreviewWeather(
            .mostlyClear,
            symbolName: "cloud.sun.fill"
        )
        city.weatherFetchedAt = .now
        city.hourlyWeatherConditions = city.hourlyConditions
        city.sunrise = calendar.date(
            bySettingHour: 6,
            minute: 30,
            second: 0,
            of: .now
        )
        city.sunset = calendar.date(
            bySettingHour: 21,
            minute: 0,
            second: 0,
            of: .now
        )
        // Vary hours by day so previews exercise differing spans and source
        // symbols without requiring a live WeatherKit request.
        city.sunnyWindowDays = (0..<10).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: .now) else { return nil }
            let sunnyStart = 7 + (offset % 4)
            let sunnyEnd = 15 + (offset % 5)
            return WidgetSunnyWindowDay(
                date: calendar.startOfDay(for: date),
                hourlyConditions: (6...21).compactMap { hour in
                    guard let hourDate = calendar.date(
                        bySettingHour: hour,
                        minute: 0,
                        second: 0,
                        of: date
                    ) else {
                        return nil
                    }
                    let weather: WidgetWeatherPresentation
                    if (sunnyStart..<sunnyEnd).contains(hour) {
                        weather = widgetPreviewWeather(.clear, symbolName: "sun.max.fill")
                    } else if hour == sunnyEnd {
                        weather = widgetPreviewWeather(
                            .mostlyClear,
                            symbolName: "cloud.sun.fill"
                        )
                    } else if hour == 6 || hour == sunnyEnd + 1 {
                        weather = widgetPreviewWeather(.partlyCloudy, symbolName: "cloud.sun.fill")
                    } else if hour == 18, offset.isMultiple(of: 3) {
                        weather = widgetPreviewWeather(.rain, symbolName: "cloud.rain.fill")
                    } else if hour == 19, offset.isMultiple(of: 3) {
                        weather = widgetPreviewWeather(.drizzle, symbolName: "cloud.drizzle.fill")
                    } else {
                        weather = widgetPreviewWeather(.cloudy, symbolName: "cloud.fill")
                    }
                    return WidgetHourlyCondition(
                        date: hourDate,
                        hour: hour,
                        weather: weather
                    )
                }
            )
        }
        return city
    }

    // MARK: - Derived Presentation

    /// The large chart has room for at most ten rows, but it does not validate
    /// or require a complete ten-day horizon. It presents WeatherKit's available
    /// current/future rows in their received order.
    var widgetSunnyWindowDays: [WidgetSunnyWindowDay] {
        Array((sunnyWindowDays ?? []).prefix(10))
    }

    /// Valid timezone represented by the published identifier.
    /// `flatMap` both unwraps the optional identifier and discards invalid
    /// timezone strings.
    var widgetTimeZone: TimeZone? {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
    }

    /// Uses the current API condition only to tint no-sun chart slots.
    var widgetScreenTone: WeatherIconTone? {
        currentWeather?.condition.iconTone
    }

    /// A rendering-safe current-day domain derived from WeatherKit's available
    /// daylight-marked hourly records. A full-day domain is used only when that
    /// source list is empty.
    var widgetCurrentDaylightBounds: SunnyHoursChartBounds {
        let sourceHours = hourlyConditions?.map(\.hour) ?? []
        return widgetFallbackChartBounds(for: sourceHours)
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

    /// Whether a catalog location has stable identity and coordinates for a
    /// direct request. Time zone is intentionally excluded because the widget
    /// extension can repair legacy fixed places from its bundled lookup data.
    var hasResolvableWidgetLocation: Bool {
        widgetIdentityIssue == nil
    }

    /// Exact issue preventing current-day widget content. Source-level solar,
    /// hourly, condition, and metric gaps are presentation fallbacks, not an
    /// unavailable state; only a failed request, explicit no-forecast state,
    /// unsafe identity, or missing timezone blocks the widget.
    var widgetCurrentIssue: WeatherDataIssue? {
        if let dataIssue = widgetBlockingDataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        return nil
    }

    /// Exact issue preventing the large multi-day chart.
    /// Its requirements differ from the daily widget only because it needs at
    /// least one available forecast row to draw.
    var widgetSunnyWindowIssue: WeatherDataIssue? {
        if let dataIssue = widgetBlockingDataIssue { return dataIssue }
        if let identityIssue = widgetIdentityIssue { return identityIssue }
        guard widgetTimeZone != nil else { return .missingTimeZone }
        guard !widgetSunnyWindowDays.isEmpty else { return .missingForecastData }
        return nil
    }

    /// Returns only issues that mean the snapshot cannot safely identify or
    /// represent a place at all. Legacy field-level issues remain decodable but
    /// no longer hide otherwise usable WeatherKit data.
    var widgetBlockingDataIssue: WeatherDataIssue? {
        guard let dataIssue else { return nil }
        switch dataIssue.kind {
        case .weatherRequestFailed,
             .unresolvedPlace,
             .missingForecastData,
             .missingTimeZone:
            return dataIssue
        default:
            return nil
        }
    }

    // MARK: - Combining Catalog and Snapshot Data

    /// Replaces weather-bearing catalog fields with a fetched cached snapshot.
    /// This returns a new struct because Swift value types are copied on change;
    /// the catalog value itself remains app-owned and unmodified.
    func applying(
        _ snapshot: WidgetWeatherSnapshot,
        preservesResolvedCityName: Bool = false
    ) -> WidgetDataCity {
        let snapshotName: String? = {
            guard !preservesResolvedCityName,
                  id == WidgetDataStore.currentLocationIdentifier,
                  snapshot.locationSource == .deviceCurrentLocation,
                  WidgetDataStore.catalog()?.resolvedDefaultLocationKind
                    == .currentLocation,
                  snapshot.cityNameLocaleIdentifier
                    == WidgetDataStore.appLocale.identifier else {
                return nil
            }
            return snapshot.resolvedCityName
        }()
        return WidgetDataCity(
            id: id,
            legacyIdentifiers: legacyIdentifiers,
            cityName: snapshotName ?? cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            latitude: snapshot.latitude ?? latitude,
            longitude: snapshot.longitude ?? longitude,
            hourlyConditions: snapshot.hourlyConditions,
            hourlyWeatherConditions: snapshot.hourlyWeatherConditions,
            currentWeather: snapshot.currentWeather,
            weatherFetchedAt: snapshot.fetchedAt,
            sunrise: snapshot.sunrise,
            sunset: snapshot.sunset,
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
            legacyIdentifiers: legacyIdentifiers,
            cityName: cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            hourlyConditions: nil,
            hourlyWeatherConditions: nil,
            currentWeather: nil,
            weatherFetchedAt: nil,
            sunrise: nil,
            sunset: nil,
            sunnyWindowDays: [],
            dataIssue: issue
        )
    }

    /// Returns the same catalog/snapshot value with one locally resolved zone.
    func replacingTimeZone(with identifier: String) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            legacyIdentifiers: legacyIdentifiers,
            cityName: cityName,
            configurationSubtitle: configurationSubtitle,
            timeZoneIdentifier: identifier,
            latitude: latitude,
            longitude: longitude,
            hourlyConditions: hourlyConditions,
            hourlyWeatherConditions: hourlyWeatherConditions,
            currentWeather: currentWeather,
            weatherFetchedAt: weatherFetchedAt,
            sunrise: sunrise,
            sunset: sunset,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: dataIssue
        )
    }
}

// MARK: - Widget Bundle

/// Widget extension entry point registering all supported widget families.
/// `@main` is the executable entry point for the extension target, not the main
/// Weather Atlas app. WidgetKit discovers each widget returned from this body.
@main
struct WeatherWidgetsBundle: WidgetBundle {
    /// Declares the small/medium/large Home Screen and rectangular Lock Screen widgets.
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
    }
}

// MARK: - Previews

// SwiftUI previews use the deterministic entry above, never a live app-group
// catalog or WeatherKit call, so they remain available in Xcode offline.

#if DEBUG
#Preview("Sun Status - Small", as: .systemSmall) {
    BestSunnyPlacesWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}

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

#Preview("Sun Status - Lock Screen", as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
#endif
