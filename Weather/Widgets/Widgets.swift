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
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Location"
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

/// Searchable location resolver shared by every widget family.
/// WidgetKit invokes these methods while a person configures a widget,
/// potentially when the main app is closed.
struct WidgetCityQuery: EntityStringQuery {
    /// Resolves the stable default-location selection plus Saved Places. A
    /// deleted or no-longer-fetchable Saved Place becomes the app's default so
    /// the system editor and the provider share the same fallback contract.
    func entities(for identifiers: [String]) async throws -> [WidgetCityEntity] {
        let catalog = WidgetDataStore.catalog()
        let defaultLocation = WidgetCityEntity.defaultLocation(in: catalog)
        let cities = catalog?.cities ?? []
        return identifiers.map { id in
            if id == WidgetDataStore.currentLocationIdentifier {
                return defaultLocation
            }
            guard let city = cities.first(where: { $0.id == id }),
                  city.hasResolvableWidgetLocation else {
                return defaultLocation
            }
            return WidgetCityEntity(city)
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

/// The compact status presentation shared by the Small Home Screen and
/// Rectangular Lock Screen widgets. Keeping this one view as the source of
/// truth prevents those two glanceable surfaces from drifting in either
/// information or visual hierarchy.
private struct SunnyStatusWidgetView: View {
    /// The Home Screen gets a slightly tighter leading inset. The Lock Screen
    /// retains its original system-friendly spacing even though it reuses the
    /// same information hierarchy.
    enum Surface {
        case homeSmall
        case lockScreen
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry
    var surface: Surface = .homeSmall

    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            VStack(alignment: .leading, spacing: 8) {
                if issue == nil,
                   let weather = city.currentWeather {
                    WidgetConditionIcon(weather: weather, size: 34)
                } else {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(widgetPalette.secondaryText)

                }
                Text(status ?? widgetLocalizedString("Weather unavailable."))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(widgetPalette.secondaryText)
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
            .padding(.leading, surface == .homeSmall ? 8 : 12)
            .padding(.trailing, 12)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .foregroundStyle(widgetPalette.titleText)
            .widgetURL(widgetPlaceURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
        }
    }

    private var widgetPalette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
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
                        ? city.currentWeather
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
                        chartBounds: chartBounds,
                        screenTone: city.widgetScreenTone
                    )
                    .padding(.top, 7)
                    .frame(maxHeight: .infinity, alignment: .top)

                    SunnyHoursLegend(screenTone: city.widgetScreenTone)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(
                AppPalette.values(
                    for: colorScheme,
                    contrast: colorSchemeContrast
                ).titleText
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
    /// Current destination tone used by Detail for its no-sun chart fill.
    let screenTone: WeatherIconTone?

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
            noSunColor(in: colors)
        }
    }

    /// Reproduces Detail's subdued condition-aware no-sun fill. Increased
    /// contrast keeps the strengthened cloudy mark opaque against the canvas.
    private func noSunColor(in colors: AppPalette.Values) -> Color {
        if colorSchemeContrast == .increased {
            return colors.dotCloudy
        }
        guard let screenTone else { return colors.settingsRow }
        return weatherColor(for: screenTone, colors: colors).interpolated(
            with: colors.background,
            by: 0.86
        )
    }

    /// Matches `ThemeColors.weatherIconColor(for:)` using the widget palette.
    private func weatherColor(
        for tone: WeatherIconTone,
        colors: AppPalette.Values
    ) -> Color {
        switch tone {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .cloudy:
            colors.dotCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
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
                    ? city.currentWeather
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

                SunnyHoursLegend(screenTone: city.widgetScreenTone)
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 12)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(
            AppPalette.values(
                for: colorScheme,
                contrast: colorSchemeContrast
            ).titleText
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

    /// Resolves the shared Current/Home default or a chosen Saved Place.
    /// Deleted or invalid Saved Places silently inherit that default location;
    /// the widget extension can then continue fetching without the app running.
    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetDataCity? {
        guard let catalog = WidgetDataStore.catalog() else {
            let selectedEntity = configuration.city
                ?? .defaultLocation(in: nil)
            return unavailableConfiguredCity(
                selectedEntity,
                issue: .unresolvedPlace("widget location catalog")
            )
        }
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
            $0.id == selectedEntity.id
        }), savedCity.hasResolvableWidgetLocation else {
            return defaultCity
        }
        return savedCity
    }

    /// Builds an unavailable default only before the app has ever published a
    /// confirmed coordinate. Stale Saved Places never use this path; they first
    /// fall back to the persisted default location above.
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
        guard let city = selectedCity(for: configuration) else { return nil }
        return cityUsingFreshWidgetSnapshot(for: city)
    }

    /// Applies the extension's private snapshot only while it is still inside
    /// the normal freshness window.
    private func cityUsingFreshWidgetSnapshot(
        for city: WidgetDataCity
    ) -> WidgetDataCity {
        if let issue = city.widgetCurrentIssue {
            return city.markingUnavailable(issue)
        }
        guard let snapshot = WidgetForecastStore.freshSnapshot(for: city.id) else {
            return city.markingUnavailable(.missingForecastData(at: .now))
        }
        guard snapshotMatchesCity(snapshot, city: city) else {
            return city.markingUnavailable(.missingTimeZone)
        }
        return city.applying(snapshot)
    }

    /// Returns a current-local-day, last-known-good extension snapshot after a
    /// direct request fails. This recovery path is intentionally unavailable to
    /// the host app and never uses the App Group catalog as weather storage.
    private func cityUsingFallbackWidgetSnapshot(
        for city: WidgetDataCity
    ) -> WidgetDataCity? {
        guard let snapshot = WidgetForecastStore.fallbackSnapshot(for: city.id),
              snapshotMatchesCity(snapshot, city: city) else {
            return nil
        }
        let cachedCity = city.applying(snapshot)
        guard cachedCity.widgetCurrentIssue == nil else { return nil }
        return cachedCity
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
        if let issue = city.widgetCurrentIssue {
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
        guard let timeZone = city.widgetTimeZone else {
            return RefreshResult(
                city: city.markingUnavailable(.missingTimeZone),
                needsShortRetry: true
            )
        }

        // `snapshot` and `timeline` own an actual extension-side WeatherKit
        // refresh. The private cache is reserved for synchronous placeholders
        // and recovery after a direct request fails, never as app-provided data.
        // Request only the datasets these widgets render; the aggregate request
        // also asks WeatherKit for alerts, air quality, and next-hour data.
        var finalRequestError: Error?
        for attempt in 0..<2 {
            do {
                let (currentWeather, dailyForecast, hourlyForecast) = try await WeatherKit.WeatherService.shared.weather(
                    for: CLLocation(latitude: latitude, longitude: longitude),
                    including: .current,
                    .daily,
                    .hourly
                )
                let snapshot = makeWeatherSnapshot(
                    currentWeather: currentWeather,
                    dailyForecast: dailyForecast,
                    hourlyForecast: hourlyForecast,
                    city: city,
                    timeZone: timeZone
                )
                WidgetForecastStore.save(snapshot, for: city.id)
                return RefreshResult(
                    city: city.applying(snapshot),
                    needsShortRetry: false
                )
            } catch is CancellationError {
                return RefreshResult(
                    city: cityUsingFallbackWidgetSnapshot(for: city)
                        ?? city.markingUnavailable(.missingForecastData(at: .now)),
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

        let errorDetail = finalRequestError.map {
            String(reflecting: type(of: $0))
        }
        return RefreshResult(
            city: cityUsingFallbackWidgetSnapshot(for: city)
                ?? city.markingUnavailable(.weatherRequestFailed(errorDetail)),
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

    /// Rejects snapshots created for a superseded or corrupt timezone identity.
    private func snapshotMatchesCity(
        _ snapshot: WidgetWeatherSnapshot,
        city: WidgetDataCity
    ) -> Bool {
        guard let cityIdentifier = city.timeZoneIdentifier,
              TimeZone(identifier: cityIdentifier) != nil,
              snapshot.timeZoneIdentifier == cityIdentifier,
              let snapshotLatitude = snapshot.latitude,
              let snapshotLongitude = snapshot.longitude,
              let cityLatitude = city.latitude,
              let cityLongitude = city.longitude else {
            return false
        }
        // Current Location can move by ordinary GPS jitter between catalog and
        // timeline updates. A small real-world distance tolerates that drift
        // without reviving a forecast after the person has meaningfully moved.
        let snapshotLocation = CLLocation(
            latitude: snapshotLatitude,
            longitude: snapshotLongitude
        )
        let cityLocation = CLLocation(
            latitude: cityLatitude,
            longitude: cityLongitude
        )
        return snapshotLocation.distance(from: cityLocation) <= 2_000
    }

    // MARK: - WeatherKit Snapshot Construction

    /// Converts WeatherKit data into a compact rendering payload. Widgets use
    /// WeatherKit's daylight flag directly and derive their chart domains from
    /// the returned hours, without interpreting solar-event edge cases. Current
    /// and hourly data remain usable even when no daily row is available for the
    /// large-widget timeline.
    private func makeWeatherSnapshot(
        currentWeather: CurrentWeather,
        dailyForecast: Forecast<DayWeather>,
        hourlyForecast: Forecast<HourWeather>,
        city: WidgetDataCity,
        timeZone: TimeZone
    ) -> WidgetWeatherSnapshot {
        let now = Date()
        // WeatherKit Dates are absolute instants. Interpret both `now` and each
        // forecast date in the configured city's timezone before choosing today.
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let currentLocalDay = calendar.startOfDay(for: now)
        let forecastDays = Array(
            dailyForecast.forecast
                .filter { calendar.startOfDay(for: $0.date) >= currentLocalDay }
                .prefix(10)
        )
        // The header uses the exact current WeatherKit condition and symbol,
        // rather than substituting a daily value or app-selected icon.
        let currentWeatherPresentation = WidgetWeatherPresentation(
            condition: AppWeatherCondition(weatherKit: currentWeather.condition),
            symbolName: currentWeather.symbolName
        )

        // Group WeatherKit's available daylight records once. Both the current
        // card and every large-widget row then reuse the same local-day data.
        let daylightHoursByDay = Dictionary(
            grouping: Array(hourlyForecast.forecast)
                .filter(\.isDaylight)
                .sorted { $0.date < $1.date }
        ) {
            calendar.startOfDay(for: $0.date)
        }
        // Retain each daylight record's source condition and symbol unchanged.
        let currentHourlyConditions = widgetForecastHourlyConditions(
            hours: daylightHoursByDay[currentLocalDay] ?? [],
            calendar: calendar
        )

        // The large widget shows each available current/future WeatherKit day,
        // up to its ten-row capacity. Each row uses only WeatherKit's available
        // daylight-marked hourly records.
        let sunnyWindowDays = forecastDays.map { day in
            let localDay = calendar.startOfDay(for: day.date)
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
            resetEpoch: WidgetResetEpoch.current,
            fetchedAt: now,
            representedLocalDate: calendar.startOfDay(for: now),
            timeZoneIdentifier: timeZone.identifier,
            latitude: city.latitude,
            longitude: city.longitude,
            currentWeather: currentWeatherPresentation,
            hourlyConditions: currentHourlyConditions,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
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
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName(WidgetDataStore.localizedText(for: "Sunny Hours"))
        .description(WidgetDataStore.localizedText(for: "Track sunny daytime hours for a chosen city."))
        .supportedFamilies([.accessoryRectangular])
    }
}

/// The rectangular Lock Screen widget deliberately reuses the exact Small
/// Home Screen status presentation: city, current condition, then sun status.
/// WidgetKit supplies the different canvas; the information architecture stays
/// identical across both quick-glance surfaces.
private struct SunnyHoursLockScreenWidgetView: View {
    /// Timeline entry supplied by the shared provider.
    let entry: SunnyHoursLockScreenEntry

    /// Builds configured accessory content or remains empty before configuration.
    var body: some View {
        SunnyStatusWidgetView(entry: entry, surface: .lockScreen)
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
    // Match the previous persisted buckets by counting each favorable local
    // clock hour once, including both clear and mostly-clear conditions.
    let favorableHours = Set((city.hourlyConditions ?? []).compactMap { hour in
        hour.weather?.condition.countsAsSunnyHour == true ? hour.hour : nil
    })
    guard !favorableHours.isEmpty else {
        return widgetLocalizedString("No Sun")
    }
    return SunnyHoursFormatting.hourCountLabel(
        Double(favorableHours.count),
        locale: locale
    )
}

/// Uses the same current-day sun-status wording as the Detail hero. Widgets
/// only display today, so the non-today "Sunny for … hours" branch is not
/// needed here.
private func widgetSunStatusText(
    for city: WidgetDataCity,
    at referenceDate: Date,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil else {
        return nil
    }

    if let conditions = city.hourlyConditions,
       !conditions.isEmpty {
        let sunnyConditions = conditions.filter {
            $0.weather?.condition.countsAsSunnyHour == true
        }
        guard !sunnyConditions.isEmpty else {
            return widgetLocalizedString("No Sun Today")
        }
        if let current = conditions.last(where: { $0.date <= referenceDate }),
           current.weather?.condition.countsAsSunnyHour == true {
            return widgetLocalizedString("Sun Out Now")
        }
        if let next = sunnyConditions.first(where: { $0.date > referenceDate }) {
            return String(
                format: widgetLocalizedString("Sun Out in %@"),
                locale: locale,
                widgetCountdownText(
                    to: next.date,
                    from: referenceDate,
                    locale: locale
                )
            )
        }
        return widgetLocalizedString("No More Sun Today")
    }

    return nil
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
    // MARK: - Surface Style

    /// Layout and rendering density for each widget family.
    enum Style {
        case home
        case lockScreen
    }

    // MARK: - Rendering Environment and Inputs

    /// Contrast preference strengthening tracks and outlines.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Rendering mode controlling system monochrome/tinted colors.
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    /// Widget appearance selecting the shared palette.
    @Environment(\.colorScheme) private var colorScheme
    /// Configured city with current-day chart data.
    let city: WidgetDataCity
    /// Entry time used by the city-local current-time marker.
    let currentDate: Date
    /// Family-specific style.
    var style: Style = .home

    // MARK: - Shared Timeline

    var body: some View {
        SunnyHoursDiscreteCapsuleTimeline(
            hours: chartHours,
            bounds: city.widgetCurrentDaylightBounds,
            currentDate: currentDate,
            timeZone: city.widgetTimeZone ?? .autoupdatingCurrent,
            showsCurrentTimeMarker: true,
            configuration: style == .home ? .appAndHome : .lockScreen,
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
        displayedHours.compactMap { hour in
            guard let source = city.hourlyConditions?.first(where: {
                $0.hour == hour
            }),
                  let weather = source.weather else {
                return nil
            }
            return SunnyHoursChartHour(
                date: source.date,
                hour: hour,
                condition: weather.condition
            )
        }
    }

    /// Neutral no-sun color shared by non-sunny chart slots.
    private var noSunColor: Color {
        if usesSystemColors {
            return .primary.opacity(0.14)
        }
        let colors = colorSchemeContrast == .increased
            ? AppPalette.increasedContrastValues(for: colorScheme)
            : palette
        return conditionAwareNoSunColor(in: colors)
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
            conditionAwareNoSunColor(in: colors)
        }
    }

    /// Matches Detail's subtle condition-derived no-sun fill in full color.
    /// Increased contrast uses the opaque strengthened cloudy palette value.
    private func conditionAwareNoSunColor(in colors: AppPalette.Values) -> Color {
        if colorSchemeContrast == .increased {
            return colors.dotCloudy
        }
        guard let tone = city.widgetScreenTone else { return colors.settingsRow }
        return weatherColor(for: tone, colors: colors).interpolated(
            with: colors.background,
            by: 0.86
        )
    }

    /// Widget equivalent of `ThemeColors.weatherIconColor(for:)`.
    private func weatherColor(
        for tone: WeatherIconTone,
        colors: AppPalette.Values
    ) -> Color {
        switch tone {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .cloudy:
            colors.dotCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
        }
    }

    /// Shared primitive palette for the widget appearance.
    private var palette: AppPalette.Values {
        AppPalette.values(for: colorScheme, contrast: colorSchemeContrast)
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

    /// Available daylight hours, downsampled only for Lock Screen space.
    /// A full-day fallback keeps an empty current-day source renderable.
    private var displayedHours: [Int] {
        // A half-open range turns inclusive start/exclusive end chart bounds
        // into every actual hour-cell the current-day timeline represents.
        let daylightBounds = city.widgetCurrentDaylightBounds
        let sourceHours = Array(daylightBounds.startHour..<daylightBounds.endHour)
        let finalSourceHour = daylightBounds.endHour - 1
        guard style == .lockScreen, sourceHours.count > 1 else {
            return sourceHours
        }

        // Retain every other slot in tight Lock Screen space. `compactMap`
        // returns only even-indexed elements while still preserving order.
        var twoHourlySlots = sourceHours.enumerated().compactMap { index, hour in
            index.isMultiple(of: 2) ? hour : nil
        }
        if twoHourlySlots.last != finalSourceHour {
            twoHourlySlots.append(finalSourceHour)
        }
        return twoHourlySlots
    }

}

/// Centered five-state key shared by medium and large Home Screen timelines.
/// It mirrors the timeline's rendering mode, so the explanatory key remains
/// consistent with the chart.
private struct SunnyHoursLegend: View {
    /// Current destination tone used by Detail's no-sun chart category.
    let screenTone: WeatherIconTone?

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
            return noSunColor(in: colors)
        }
    }

    /// Reproduces the condition-aware no-sun swatch from the Detail legend.
    /// Increased contrast uses the opaque strengthened cloudy palette value.
    private func noSunColor(in colors: AppPalette.Values) -> Color {
        if colorSchemeContrast == .increased {
            return colors.dotCloudy
        }
        guard let screenTone else { return colors.settingsRow }
        return weatherColor(for: screenTone, colors: colors).interpolated(
            with: colors.background,
            by: 0.86
        )
    }

    /// Matches `ThemeColors.weatherIconColor(for:)` using widget palette data.
    private func weatherColor(
        for tone: WeatherIconTone,
        colors: AppPalette.Values
    ) -> Color {
        switch tone {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .cloudy:
            colors.dotCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
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

    /// Whether a catalog location has all identity required for a direct
    /// WeatherKit request. Forecast arrays are intentionally excluded because
    /// the widget extension refreshes those itself.
    var hasResolvableWidgetLocation: Bool {
        widgetIdentityIssue == nil && widgetTimeZone != nil
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
    func applying(_ snapshot: WidgetWeatherSnapshot) -> WidgetDataCity {
        WidgetDataCity(
            id: id,
            cityName: cityName,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            latitude: latitude,
            longitude: longitude,
            hourlyConditions: snapshot.hourlyConditions,
            currentWeather: snapshot.currentWeather,
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
            hourlyConditions: nil,
            currentWeather: nil,
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
