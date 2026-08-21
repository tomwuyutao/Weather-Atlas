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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city {
            let issue = city.widgetCurrentIssue
            let status = issue == nil
                ? widgetSunStatusText(for: city, at: entry.date, locale: locale)
                : nil

            VStack(spacing: 6) {
                Text(city.cityName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                if issue == nil,
                   let condition = city.currentCondition {
                    WidgetConditionIcon(condition: condition, size: 34)
                } else {
                    Image(systemName: "cloud.slash")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AppPalette.values(for: colorScheme).secondaryText)

                }

                Spacer(minLength: 0)

                Text(status ?? widgetLocalizedString("Weather unavailable."))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppPalette.values(for: colorScheme).secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .foregroundStyle(AppPalette.values(for: colorScheme).titleText)


            .widgetURL(widgetPlaceURL(for: city, issue: issue))
        } else {
            WidgetDataUnavailablePlaceholder()
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
            let summaryText = widgetSunnyHoursTotalText(for: city, locale: locale)
            VStack(alignment: .leading, spacing: 9) {
                SunnyHoursHeader(
                    cityName: city.cityName,
                    condition: currentIssue == nil
                        ? city.currentCondition
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
            .foregroundStyle(AppPalette.values(for: colorScheme).titleText)
            // A Home Screen widget is one deep-link destination. Present a
            // concise city-and-sunny-hours summary rather than exposing every
            // decorative chart segment and grid label.


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
                                    : noSunColor(in: palette)
                            )
                            .frame(height: capsuleHeight)

                        // Draw every source hour directly, matching the Detail
                        // chart's five-condition renderer instead of reducing
                        // precipitation to an undifferentiated no-sun track.
                        ForEach(day.chartHourlyConditions) { hour in
                            Rectangle()
                                .fill(segmentColor(for: hour.condition))
                                .frame(
                                    width: chartBounds.width(
                                        for: hour.hour...hour.hour,
                                        timelineWidth: timelineWidth,
                                        minimumWidth: 1
                                    ),
                                    height: capsuleHeight
                                )
                                .offset(
                                    x: chartBounds.xPosition(
                                        for: Double(hour.hour),
                                        width: timelineWidth
                                    )
                                )
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

    /// Returns the shared five-condition chart color for one source hour.
    private func segmentColor(for condition: AppWeatherCondition) -> Color {
        if usesSystemColors {
            return monochromeColor(for: condition)
        }
        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return chartColor(for: condition, colors: colors)
        }
        return chartColor(for: condition, colors: palette)
    }

    /// Retains five distinguishable weights when WidgetKit enforces a
    /// monochrome or tinted rendering mode and custom chart colors are not
    /// permitted by the system.
    private func monochromeColor(for condition: AppWeatherCondition) -> Color {
        switch condition {
        case .clear:
            .primary.opacity(1)
        case .partlySunny:
            .primary.opacity(0.62)
        case .rain:
            .primary.opacity(0.82)
        case .drizzle:
            .primary.opacity(0.38)
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            .primary.opacity(colorSchemeContrast == .increased ? 0.24 : 0.14)
        }
    }

    /// Maps normalized conditions to the same semantic palette values used by
    /// Detail's daily and ten-day charts.
    private func chartColor(
        for condition: AppWeatherCondition,
        colors: AppPalette.Values
    ) -> Color {
        switch condition {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            noSunColor(in: colors)
        }
    }

    /// Reproduces Detail's subdued condition-aware no-sun fill.
    private func noSunColor(in colors: AppPalette.Values) -> Color {
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
                condition: issue == nil
                    ? city.currentCondition
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

                SunnyHoursLegend(screenTone: city.widgetScreenTone)
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
        if let issue = city.widgetCurrentIssue {
            return city.markingUnavailable(issue)
        }
        guard let snapshot = WidgetDataStore.weatherSnapshot(for: city.id) else {
            return city.markingUnavailable(.missingForecastData(at: .now))
        }
        guard snapshotMatchesCity(snapshot, city: city) else {
            return city.markingUnavailable(.missingTimeZone)
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

        // Timeline and gallery requests always fetch through the extension so
        // widgets remain self-refreshing. Cached data is used only by the
        // synchronous placeholder path, where WidgetKit cannot await WeatherKit.
        // Remove it before the request so a failed refresh cannot revive a
        // previous coordinate or forecast through a later callback.
        WidgetDataStore.removeWeatherSnapshot(for: city.id)

        // A widget can be asked for its first timeline while WeatherKit is still
        // establishing the extension's service session. Retry one transient
        // request failure, but accept every returned WeatherKit response: a
        // partial daily or hourly horizon is still useful widget data.
        var finalRequestError: Error?
        for attempt in 0..<2 {
            do {
                // WeatherKit returns an aggregate containing daily and hourly
                // forecasts for this coordinate; reduce it directly to the
                // widget's Codable rendering payload.
                let weather = try await WeatherService.shared.weather(
                    for: CLLocation(latitude: latitude, longitude: longitude)
                )
                let snapshot = makeWeatherSnapshot(
                    weather: weather,
                    city: city,
                    timeZone: timeZone
                )
                WidgetDataStore.saveWeatherSnapshot(snapshot, for: city.id)
                return RefreshResult(
                    city: city.applying(snapshot),
                    needsShortRetry: false
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
        // Catalog coordinates are rounded/persisted values. A tiny tolerance
        // accepts their stable representation while rejecting a moved Current
        // Location before its old forecast can be drawn.
        return abs(snapshotLatitude - cityLatitude) < 0.0001
            && abs(snapshotLongitude - cityLongitude) < 0.0001
    }

    // MARK: - WeatherKit Snapshot Construction

    /// Converts WeatherKit data into a compact rendering payload. Widgets use
    /// WeatherKit's daylight flag directly and derive their chart domains from
    /// the returned hours, without interpreting solar-event edge cases. Current
    /// and hourly data remain usable even when no daily row is available for the
    /// large-widget timeline.
    private func makeWeatherSnapshot(
        weather: Weather,
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
            weather.dailyForecast.forecast
                .filter { calendar.startOfDay(for: $0.date) >= currentLocalDay }
                .prefix(10)
        )
        // The header describes current weather, so use WeatherKit's current
        // record rather than substituting the daily condition.
        let currentWeather = weather.currentWeather
        let currentCondition = AppWeatherCondition.resolve(
            weatherKit: currentWeather.condition,
            isDaylight: currentWeather.isDaylight,
            symbolName: currentWeather.symbolName
        ) ?? .cloudy

        // Group WeatherKit's available daylight records once. Both the current
        // card and every large-widget row then reuse the same local-day data.
        let daylightHoursByDay = Dictionary(
            grouping: Array(weather.hourlyForecast.forecast)
                .filter(\.isDaylight)
                .sorted { $0.date < $1.date }
        ) {
            calendar.startOfDay(for: $0.date)
        }
        // Reduce available daylight HourWeather objects to integer chart hours.
        // Unrecognized source conditions use a neutral presentation rather than
        // discarding an otherwise useful widget snapshot.
        let currentHours = widgetForecastHourBreakdown(
            hours: daylightHoursByDay[currentLocalDay] ?? [],
            calendar: calendar
        )

        // The large widget shows each available current/future WeatherKit day,
        // up to its ten-row capacity. Each row uses only WeatherKit's available
        // daylight-marked hourly records.
        let sunnyWindowDays = forecastDays.map { day in
            let localDay = calendar.startOfDay(for: day.date)
            let hours = widgetForecastHourBreakdown(
                hours: daylightHoursByDay[localDay] ?? [],
                calendar: calendar
            )
            return WidgetSunnyWindowDay(
                date: localDay,
                sunnyHours: hours.sunnyHours,
                partlySunnyHours: hours.partlySunnyHours,
                hourlyConditions: hours.hourlyConditions
            )
        }

        return WidgetWeatherSnapshot(
            fetchedAt: now,
            representedLocalDate: calendar.startOfDay(for: now),
            timeZoneIdentifier: timeZone.identifier,
            latitude: city.latitude,
            longitude: city.longitude,
            currentCondition: currentCondition,
            daytimeHours: currentHours.daytimeHours,
            sunnyHours: currentHours.sunnyHours,
            partlySunnyHours: currentHours.partlySunnyHours,
            hourlyConditions: currentHours.hourlyConditions,
            sunnyWindowDays: sunnyWindowDays,
            dataIssue: nil
        )
    }

}

// MARK: - Widget Forecast Classification

/// Widget-specific output adds full normalized conditions to the shared sunny
/// and partly-sunny buckets. The buckets remain for range summaries and older
/// cache compatibility; the conditions let charts render all five categories.
private struct WidgetForecastHourBreakdown {
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
    let hourlyConditions: [WidgetHourlyCondition]
}

/// Resolves widget WeatherKit records with the app's semantic-first condition
/// adapter, then derives every persisted chart bucket from that one result.
/// A future WeatherKit condition that is outside the app's finite display
/// vocabulary gets the neutral cloudy treatment instead of invalidating the
/// entire forecast.
private func widgetForecastHourBreakdown(
    hours: [HourWeather],
    calendar: Calendar
) -> WidgetForecastHourBreakdown {
    var daytimeHours: [Int] = []
    var sunnyHours: [Int] = []
    var partlySunnyHours: [Int] = []
    var hourlyConditions: [WidgetHourlyCondition] = []

    for forecast in hours {
        let condition = AppWeatherCondition.resolve(
            weatherKit: forecast.condition,
            isDaylight: forecast.isDaylight,
            symbolName: forecast.symbolName
        ) ?? .cloudy

        let hour = calendar.component(.hour, from: forecast.date)
        daytimeHours.append(hour)
        if condition == .clear {
            sunnyHours.append(hour)
        } else if condition == .partlySunny {
            partlySunnyHours.append(hour)
        }
        hourlyConditions.append(
            WidgetHourlyCondition(
                date: forecast.date,
                hour: hour,
                condition: condition
            )
        )
    }

    return WidgetForecastHourBreakdown(
        daytimeHours: daytimeHours,
        sunnyHours: sunnyHours,
        partlySunnyHours: partlySunnyHours,
        hourlyConditions: hourlyConditions
    )
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
        SunnyStatusWidgetView(entry: entry)
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
    /// Optional current condition normalized by the shared app/widget model.
    let condition: AppWeatherCondition?
    /// Optional day-total text replacing the condition icon on Home Screen widgets.
    var summaryText: String? = nil
    /// Family-specific header font.
    let font: Font
    /// Whether full-color weather icon rendering is permitted.
    let usesWeatherColors: Bool

    /// Builds city title and its already-normalized condition icon. If a
    /// condition is absent, the header leaves that secondary slot empty while
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
                            ? AppPalette.values(for: colorScheme).secondaryText
                            : Color.secondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else if let condition {
                // WidgetKit can request monochrome/tinted rendering regardless
                // of the device color scheme. In Full Color, match each weather
                // symbol to the same semantic color as its Map-dot condition.
                if usesWeatherColors,
                   widgetRenderingMode == .fullColor {
                    Image(systemName: condition.displayIcon)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            widgetConditionIconColor(
                                for: condition,
                                colors: AppPalette.values(for: colorScheme)
                            )
                        )
                } else {
                    Image(systemName: condition.displayIcon)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .font(font)
    }
}

/// Reusable weather symbol for compact widgets. Home Screen widgets retain the
/// app's semantic condition tint; WidgetKit-controlled Lock Screen rendering
/// remains system monochrome or tinted as required.
private struct WidgetConditionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    let condition: AppWeatherCondition
    let size: CGFloat

    var body: some View {
        Image(systemName: condition.displayIcon)
            .font(.system(size: size, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(iconColor)
    }

    private var iconColor: Color {
        guard widgetRenderingMode == .fullColor else { return .primary }
        return widgetConditionIconColor(
            for: condition,
            colors: AppPalette.values(for: colorScheme)
        )
    }
}

/// Formats the full current-day favorable total for widget headers.
private func widgetSunnyHoursTotalText(
    for city: WidgetDataCity,
    locale: Locale
) -> String? {
    guard city.widgetCurrentIssue == nil else { return nil }
    let favorableHours = Set(city.sunnyHours + city.partlySunnyHours)
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
    guard city.widgetCurrentIssue == nil,
          let timeZone = city.widgetTimeZone else {
        return nil
    }

    if let conditions = city.hourlyConditions,
       !conditions.isEmpty {
        let sunnyConditions = conditions.filter {
            $0.condition.isSunnyOrPartlySunny
        }
        guard !sunnyConditions.isEmpty else {
            return widgetLocalizedString("No Sun Today")
        }
        if let current = conditions.last(where: { $0.date <= referenceDate }),
           current.condition.isSunnyOrPartlySunny {
            return widgetLocalizedString("Sun Out Now")
        }
        if let next = sunnyConditions.first(where: { $0.date > referenceDate }) {
            return String(
                format: widgetLocalizedString("Sun Out in %@"),
                locale: locale,
                widgetCountdownText(to: next.date, from: referenceDate)
            )
        }
        return widgetLocalizedString("No More Sun Today")
    }

    // Older cached snapshots carry hour buckets rather than individual source
    // dates. Use the city-local clock so their small/Lock Screen widgets keep
    // the same useful message until WidgetKit replaces the cache.
    var calendar = Calendar.current
    calendar.timeZone = timeZone
    let currentHour = calendar.component(.hour, from: referenceDate)
    let sunnyHours = Array(Set(city.sunnyHours + city.partlySunnyHours)).sorted()
    guard !sunnyHours.isEmpty else {
        return widgetLocalizedString("No Sun Today")
    }
    if sunnyHours.contains(currentHour) {
        return widgetLocalizedString("Sun Out Now")
    }
    guard let nextHour = sunnyHours.first(where: { $0 > currentHour }),
          let nextDate = calendar.date(
            bySettingHour: nextHour,
            minute: 0,
            second: 0,
            of: referenceDate
          ) else {
        return widgetLocalizedString("No More Sun Today")
    }
    return String(
        format: widgetLocalizedString("Sun Out in %@"),
        locale: locale,
        widgetCountdownText(to: nextDate, from: referenceDate)
    )
}

/// Formats the Detail-compatible duration without depending on the app process.
private func widgetCountdownText(to date: Date, from referenceDate: Date) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2
    formatter.zeroFormattingBehavior = .dropAll
    return formatter.string(
        from: max(0, date.timeIntervalSince(referenceDate))
    ) ?? widgetLocalizedString("less than one minute")
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

    // MARK: - Timeline Layout

    /// Builds capsule hours, current-time marker, and family-specific axis.
    var body: some View {
        // All downstream geometry derives from the same normalized hour array,
        // so capsules, current marker, and labels cannot drift out of alignment.
        let bounds = city.widgetCurrentDaylightBounds
        let hours = displayedHours
        let startHour = bounds.startHour
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
                        }
                    }

                    // An optional marker is emitted only when the city-local
                    // current hour is inside this daylight/capsule domain.
                    if let boundaryIndex = currentTimeBoundaryIndex(in: hours) {
                        currentTimeMarker
                            .frame(height: capsuleHeight)
                            .position(
                                // Place the marker in the gap nearest the city's current hour.
                                x: currentTimeMarkerX(
                                    for: boundaryIndex,
                                    capsuleWidth: capsuleWidth,
                                    hourCount: hours.count,
                                    capsuleSpacing: capsuleSpacing
                                ),
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
                    Text(SunnyHoursFormatting.chartHourLabel(bounds.endHour))
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
                    through: bounds.endHour
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
    }

    // MARK: - Timeline Rendering

    /// Returns the shared five-condition chart color for one displayed hour.
    private func segmentColor(for hour: Int) -> Color {
        guard let condition = condition(for: hour) else {
            return noSunColor
        }
        if usesSystemColors {
            return monochromeColor(for: condition)
        }

        if colorSchemeContrast == .increased {
            let colors = AppPalette.increasedContrastValues(for: colorScheme)
            return chartColor(for: condition, colors: colors)
        }

        return chartColor(for: condition, colors: palette)
    }

    /// Reads the precise cached weather condition. Older persisted widget
    /// snapshots fall back to their existing sunny/partly-sunny buckets until
    /// the provider refreshes them with the five-condition payload.
    private func condition(for hour: Int) -> AppWeatherCondition? {
        if let cachedCondition = city.hourlyConditions?.first(where: {
            $0.hour == hour
        })?.condition {
            return cachedCondition
        }
        if city.sunnyHours.contains(hour) { return .clear }
        if city.partlySunnyHours.contains(hour) { return .partlySunny }
        return nil
    }

    /// Neutral no-sun color shared by non-sunny chart slots.
    private var noSunColor: Color {
        if usesSystemColors {
            return .primary.opacity(
                colorSchemeContrast == .increased ? 0.24 : 0.14
            )
        }
        let colors = colorSchemeContrast == .increased
            ? AppPalette.increasedContrastValues(for: colorScheme)
            : palette
        return conditionAwareNoSunColor(in: colors)
    }

    /// WidgetKit may enforce monochrome/tinted rendering, where custom colors
    /// are unavailable. Preserve condition differences with distinct weights.
    private func monochromeColor(for condition: AppWeatherCondition) -> Color {
        switch condition {
        case .clear:
            .primary.opacity(1)
        case .partlySunny:
            .primary.opacity(0.62)
        case .rain:
            .primary.opacity(0.82)
        case .drizzle:
            .primary.opacity(0.38)
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            noSunColor
        }
    }

    /// Uses the exact full-color palette mapping from Detail's five-state
    /// daily and ten-day timeline renderers.
    private func chartColor(
        for condition: AppWeatherCondition,
        colors: AppPalette.Values
    ) -> Color {
        switch condition {
        case .clear:
            colors.dotSun
        case .partlySunny:
            colors.dotPartlyCloudy
        case .rain:
            colors.dotRain
        case .drizzle:
            colors.dotDrizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            conditionAwareNoSunColor(in: colors)
        }
    }

    /// Matches Detail's subtle condition-derived no-sun fill in full color.
    private func conditionAwareNoSunColor(in colors: AppPalette.Values) -> Color {
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
        return currentIndex + 1
    }

    /// Places a marker between real hour cells, or at the trailing edge when
    /// the final real forecast interval is current.
    private func currentTimeMarkerX(
        for boundaryIndex: Int,
        capsuleWidth: CGFloat,
        hourCount: Int,
        capsuleSpacing: CGFloat
    ) -> CGFloat {
        if boundaryIndex >= hourCount {
            return CGFloat(hourCount) * capsuleWidth
                + CGFloat(max(hourCount - 1, 0)) * capsuleSpacing
        }
        return CGFloat(boundaryIndex) * capsuleWidth
            + (CGFloat(boundaryIndex) - 0.5) * capsuleSpacing
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

    /// Maps four evenly spaced desired hours to the nearest actual capsule centers.
    private func timelineAxisMarkers(
        for hours: [Int],
        from startHour: Int,
        through endHour: Int
    ) -> [AxisMarker] {
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

    /// Builds the same five condition categories as Detail's ten-day legend.
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
                    item(
                        color: color(for: .cloudy),
                        title: widgetLocalizedString("No Sun")
                    )
                }
                HStack(spacing: 14) {
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

    /// Matches the five full-color palette categories used by Detail. In
    /// system-controlled widget rendering modes, use distinct monochrome
    /// weights because WidgetKit does not permit custom tint colors.
    private func color(for condition: AppWeatherCondition) -> Color {
        if usesSystemColors {
            switch condition {
            case .clear:
                return .primary.opacity(1)
            case .partlySunny:
                return .primary.opacity(0.62)
            case .rain:
                return .primary.opacity(0.82)
            case .drizzle:
                return .primary.opacity(0.38)
            case .partlyCloudy, .cloudy, .snow, .fog, .wind:
                return .primary.opacity(
                    colorSchemeContrast == .increased ? 0.24 : 0.14
                )
            }
        }

        let colors = colorSchemeContrast == .increased
            ? AppPalette.increasedContrastValues(for: colorScheme)
            : palette
        switch condition {
        case .clear:
            return colors.dotSun
        case .partlySunny:
            return colors.dotPartlyCloudy
        case .rain:
            return colors.dotRain
        case .drizzle:
            return colors.dotDrizzle
        case .partlyCloudy, .cloudy, .snow, .fog, .wind:
            return noSunColor(in: colors)
        }
    }

    /// Reproduces the condition-aware no-sun swatch from the Detail legend.
    private func noSunColor(in colors: AppPalette.Values) -> Color {
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
    for condition: AppWeatherCondition,
    colors: AppPalette.Values
) -> Color {
    switch condition.iconTone {
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

private extension WidgetSunnyWindowDay {
    /// Full source conditions for a five-color row. Existing snapshots created
    /// before this payload was added continue to draw their known sunny states
    /// over the neutral track until the next WidgetKit refresh replaces them.
    var chartHourlyConditions: [WidgetHourlyCondition] {
        if let hourlyConditions {
            return hourlyConditions
        }

        let knownHours = Array(Set(sunnyHours + partlySunnyHours)).sorted()
        return knownHours.map { hour in
            WidgetHourlyCondition(
                date: date.addingTimeInterval(TimeInterval(hour * 3_600)),
                hour: hour,
                condition: sunnyHours.contains(hour) ? .clear : .partlySunny
            )
        }
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
            longitude: 2.1686,
            daytimeHours: Array(6...21),
            sunnyHours: Array(8...19),
            partlySunnyHours: [7, 20]
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
            let condition: AppWeatherCondition
            switch hour {
            case 8...17:
                condition = .clear
            case 7, 20:
                condition = .partlySunny
            case 18:
                condition = .rain
            case 19:
                condition = .drizzle
            default:
                condition = .cloudy
            }
            return WidgetHourlyCondition(
                date: date,
                hour: hour,
                condition: condition
            )
        }
        city.currentCondition = .clear
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
                hourlyConditions: (6...21).compactMap { hour in
                    guard let hourDate = calendar.date(
                        bySettingHour: hour,
                        minute: 0,
                        second: 0,
                        of: date
                    ) else {
                        return nil
                    }
                    let condition: AppWeatherCondition
                    if (sunnyStart...sunnyEnd).contains(hour) {
                        condition = .clear
                    } else if hour == 6 || hour == sunnyEnd + 1 {
                        condition = .partlySunny
                    } else if hour == 18, offset.isMultiple(of: 3) {
                        condition = .rain
                    } else if hour == 19, offset.isMultiple(of: 3) {
                        condition = .drizzle
                    } else {
                        condition = .cloudy
                    }
                    return WidgetHourlyCondition(
                        date: hourDate,
                        hour: hour,
                        condition: condition
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

    /// Uses the same condition-derived no-sun fill as Detail's currently
    /// selected forecast, based on the widget's current destination condition.
    var widgetScreenTone: WeatherIconTone? {
        currentCondition?.iconTone
    }

    /// A rendering-safe current-day domain derived from WeatherKit's available
    /// daylight-marked hourly records. A full-day domain is used only when that
    /// source list is empty.
    var widgetCurrentDaylightBounds: SunnyHoursChartBounds {
        let sourceHours: [Int]
        if let hourlyConditions {
            sourceHours = hourlyConditions.map(\.hour)
        } else if !daytimeHours.isEmpty {
            sourceHours = daytimeHours
        } else {
            sourceHours = sunnyHours + partlySunnyHours
        }
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
            daytimeHours: snapshot.daytimeHours,
            sunnyHours: snapshot.sunnyHours,
            partlySunnyHours: snapshot.partlySunnyHours,
            hourlyConditions: snapshot.hourlyConditions,
            currentCondition: snapshot.currentCondition,
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
            hourlyConditions: nil,
            currentCondition: nil,
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
