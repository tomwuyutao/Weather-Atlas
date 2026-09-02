//
//  Widgets.swift
//  WeatherWidgets
//
//  Purpose: Registers widget kinds and owns their shared WidgetKit contract.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

// MARK: - Extension Entry Point

/// Widget extension entry point. Individual widget families and their previews
/// live in dedicated source files so this registration list stays easy to scan.
@main
struct WeatherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
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
        let retiredCities = catalog?.resolvedRetiredCities ?? []
        return identifiers.compactMap { id in
            if id == WidgetDataStore.currentLocationIdentifier {
                return defaultLocation
            }
            if let city = cities.first(where: {
                $0.id == id
            }), city.hasResolvableWidgetLocation {
                // App Intents requires the rehydrated entity to retain the exact
                // canonical identifier WidgetKit persisted.
                return WidgetCityEntity(city, identifier: id)
            }

            if let retiredCity = retiredCities.first(where: {
                $0.id == id
            }) {
                // An exact canonical identity always wins over historic aliases
                // accidentally propagated by catalogs from older releases.
                return WidgetCityEntity(retiredCity, identifier: id)
            }

            if let retiredCity = retiredCities.first(where: {
                $0.matchesWidgetIdentifier(id)
            }) {
                // Preserve the deleted selection's last published name and
                // subtitle while retaining the exact App Intent identifier.
                // The provider recognizes this as retired and keeps it unavailable.
                return WidgetCityEntity(retiredCity, identifier: id)
            }

            if let city = cities.first(where: {
                $0.matchesWidgetIdentifier(id)
            }), city.hasResolvableWidgetLocation {
                // A continuously migrated pre-UUID selection reaches this path
                // only when no deleted identity still owns its legacy alias.
                return WidgetCityEntity(city, identifier: id)
            }

            // Catalogs written before identity tombstones cannot recover a name
            // for a place that was already deleted. Preserve that existing
            // selection's exact ID and use the localized generic fallback; never
            // substitute the current default or a similarly named active city.
            return WidgetCityEntity(
                id: id,
                cityName: WidgetDataStore.localizedText(for: "Saved Place")
            )
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

extension WidgetCityEntity {
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

// MARK: - Timeline Entry

/// The historical type name is retained because it participates in existing
/// AppIntent/widget configurations; the entry is shared by every widget size.
/// A TimelineEntry is an immutable snapshot: WidgetKit later renders it without
/// rerunning the provider or reading live WeatherKit state from a view body.
struct SunnyHoursLockScreenEntry: TimelineEntry {
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

// MARK: - Widget Locale Lookup

/// Looks up widget copy that the localized main app published into the app group.
/// The widget target may be launched independently, so it reads the app-selected
/// language from shared storage instead of assuming its process has that context.
func widgetLocalizedString(_ key: String) -> String {
    WidgetDataStore.localizedText(for: key)
}

// MARK: - Widget Text-Size Policy

/// Applies the app's Small...Large typography contract inside WidgetKit.
/// Follow System remains live in the extension process; a fixed app choice
/// remains exact. Both paths use the same upper and lower bounds as the app.
struct WidgetTextSizePolicyModifier: ViewModifier {
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

// MARK: - Deep Links

/// Builds a city-specific deep link carrying exact missing-data diagnostics when
/// needed. WidgetKit opens a Saved Place directly in Detail, while the special
/// Current Location selection opens its matching app report. URLComponents
/// safely percent-encodes the stable identifier and user-visible name.
func widgetPlaceURL(for city: WidgetDataCity, issue: WeatherDataIssue?) -> URL? {
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

// MARK: - Widget Missing-Data Presentation

/// Compact visible fallback for missing widget configuration or unavailable
/// WeatherKit data.
/// This is intentionally one reusable state, so every family communicates that
/// no forecast was invented instead of showing an empty card.
struct WidgetDataUnavailablePlaceholder: View {
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
        AppIntentConfiguration(
            kind: Self.kind,
            intent: SunnyHoursLockScreenConfigurationIntent.self,
            provider: SunnyHoursLockScreenProvider()
        ) { entry in
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
        .configurationDisplayName(
            WidgetDataStore.localizedText(for: "Sunny Hours")
        )
        .description(
            WidgetDataStore.localizedText(
                for: "Track sunny hours for a chosen city."
            )
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

// MARK: - Family Routing

/// Chooses the existing size-specific presentation inside the shared widget kind.
/// `@ViewBuilder` permits the `if` branches to produce different concrete SwiftUI
/// view types while still satisfying the single `some View` body requirement.
private struct SunnyHoursHomeScreenWidgetView: View {
    /// WidgetKit's currently rendered Home Screen family.
    @Environment(\.widgetFamily) private var family
    /// Timeline entry shared by the Small, Medium, and Large presentations.
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
