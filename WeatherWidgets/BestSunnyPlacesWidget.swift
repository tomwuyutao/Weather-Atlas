//
//  BestSunnyPlacesWidget.swift
//  WeatherWidgets
//
//  Purpose: Displays configurable home and lock-screen weather widgets.
//

import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetStore {
    static let appGroupIdentifier = "group.Yutao-Wu.Weather"
    static let catalogKey = "bestSunnyPlacesWidgetCatalog"

    static func catalog() -> WidgetCatalog? {
        guard let data = UserDefaults(suiteName: appGroupIdentifier)?.data(forKey: catalogKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetCatalog.self, from: data)
    }
}

private struct WidgetCity: Codable, Hashable, Identifiable {
    let id: String
    let cityName: String
    let temperature: String
    let cloudCover: String
    let conditionIcon: String
    let daytimeHours: [Int]
    let sunnyHours: [Int]
    let partlySunnyHours: [Int]
}

private struct WidgetList: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let listName: String
    let title: String
    let topCityIDs: [String]
    let cities: [WidgetCity]
}

private struct WidgetCatalog: Codable, Hashable {
    let activeListID: String
    let updatedAt: Date
    let lists: [WidgetList]
}

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
        let lists = WidgetStore.catalog()?.lists ?? []
        return identifiers.compactMap { id in
            lists.first(where: { $0.id == id }).map(WidgetListEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetListEntity] {
        (WidgetStore.catalog()?.lists ?? []).map(WidgetListEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetListEntity] {
        try await suggestedEntities().filter {
            $0.displayName.localizedCaseInsensitiveContains(string)
        }
    }
}

private extension WidgetListEntity {
    init(_ list: WidgetList) {
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
        let cities = WidgetStore.catalog()?.lists.flatMap(\.cities) ?? []
        return identifiers.compactMap { id in
            cities.first(where: { $0.id == id }).map(WidgetCityEntity.init)
        }
    }

    func suggestedEntities() async throws -> [WidgetCityEntity] {
        (WidgetStore.catalog()?.lists.flatMap(\.cities) ?? []).map(WidgetCityEntity.init)
    }

    func entities(matching string: String) async throws -> [WidgetCityEntity] {
        try await suggestedEntities().filter {
            $0.cityName.localizedCaseInsensitiveContains(string)
        }
    }
}

private extension WidgetCityEntity {
    init(_ city: WidgetCity) {
        id = city.id
        cityName = city.cityName
    }
}

struct BestSunnyPlacesConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Best Sunny Places"
    static var description = IntentDescription("Choose the list shown in this widget.")

    @Parameter(title: "List") var list: WidgetListEntity?

    init() {}
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
              let list = WidgetStore.catalog()?.lists.first(where: { $0.id == listID }) else {
            return []
        }
        return list.cities.map(WidgetCityEntity.init)
    }
}

private struct BestSunnyPlacesEntry: TimelineEntry {
    let date: Date
    let list: WidgetList?

    static let preview = BestSunnyPlacesEntry(date: .now, list: .preview)
}

private struct BestSunnyPlacesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BestSunnyPlacesEntry { .preview }

    func snapshot(for configuration: BestSunnyPlacesConfigurationIntent, in context: Context) async -> BestSunnyPlacesEntry {
        BestSunnyPlacesEntry(date: .now, list: selectedList(for: configuration))
    }

    func timeline(for configuration: BestSunnyPlacesConfigurationIntent, in context: Context) async -> Timeline<BestSunnyPlacesEntry> {
        let entry = BestSunnyPlacesEntry(date: .now, list: selectedList(for: configuration))
        let refreshDate = entry.date.addingTimeInterval(60 * 60)
        return Timeline(entries: [entry], policy: .after(refreshDate))
    }

    private func selectedList(for configuration: BestSunnyPlacesConfigurationIntent) -> WidgetList? {
        let catalog = WidgetStore.catalog()
        let listID = configuration.list?.id ?? catalog?.activeListID
        return catalog?.lists.first(where: { $0.id == listID })
    }
}

struct BestSunnyPlacesWidget: Widget {
    static let kind = "BestSunnyPlacesWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: BestSunnyPlacesConfigurationIntent.self, provider: BestSunnyPlacesProvider()) { entry in
            BestSunnyPlacesWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Best Sunny Places")
        .description("See the clearest cities in a chosen list.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct BestSunnyPlacesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BestSunnyPlacesEntry

    var body: some View {
        if let list = entry.list, !list.topCityIDs.isEmpty {
            content(list)
        } else {
            WidgetEmptyState(title: "Best Sunny Places", symbol: "sun.max.fill")
        }
    }

    private func content(_ list: WidgetList) -> some View {
        let places = list.topCityIDs.compactMap { id in list.cities.first(where: { $0.id == id }) }
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 8) {
            Label(list.title, systemImage: "sun.max.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(WidgetColors.navy)
                .lineLimit(1)

            ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                family == .systemSmall
                    ? AnyView(compactRow(place, rank: index + 1))
                    : AnyView(fullRow(place, rank: index + 1))
            }
        }
    }

    private func compactRow(_ place: WidgetCity, rank: Int) -> some View {
        HStack(spacing: 7) {
            rankLabel(rank)
            Text(place.cityName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: place.conditionIcon)
                .font(.subheadline.weight(.medium))
                .symbolRenderingMode(.multicolor)
        }
    }

    private func fullRow(_ place: WidgetCity, rank: Int) -> some View {
        HStack(spacing: 7) {
            rankLabel(rank)
            Text(place.cityName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(place.temperature)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .monospacedDigit()
            Label(place.cloudCover, systemImage: "cloud")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .monospacedDigit()
            Image(systemName: place.conditionIcon)
                .font(.subheadline.weight(.medium))
                .symbolRenderingMode(.multicolor)
        }
    }

    private func rankLabel(_ rank: Int) -> some View {
        Text("\(rank)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 10, alignment: .leading)
    }
}

private struct SunnyHoursLockScreenEntry: TimelineEntry {
    let date: Date
    let city: WidgetCity?

    static let preview = SunnyHoursLockScreenEntry(date: .now, city: .preview)
}

private struct SunnyHoursLockScreenProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SunnyHoursLockScreenEntry { .preview }

    func snapshot(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> SunnyHoursLockScreenEntry {
        SunnyHoursLockScreenEntry(date: .now, city: selectedCity(for: configuration))
    }

    func timeline(for configuration: SunnyHoursLockScreenConfigurationIntent, in context: Context) async -> Timeline<SunnyHoursLockScreenEntry> {
        let entry = SunnyHoursLockScreenEntry(date: .now, city: selectedCity(for: configuration))
        return Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60)))
    }

    private func selectedCity(for configuration: SunnyHoursLockScreenConfigurationIntent) -> WidgetCity? {
        guard let listID = configuration.list?.id,
              let cityID = configuration.city?.id else {
            return nil
        }
        return WidgetStore.catalog()?.lists
            .first(where: { $0.id == listID })?
            .cities.first(where: { $0.id == cityID })
    }
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
    let entry: SunnyHoursLockScreenEntry

    var body: some View {
        if let city = entry.city, !city.daytimeHours.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "sun.max.fill")
                    Text(city.cityName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("Sunny Hours")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))

                SunnyHoursTimeline(city: city, currentDate: entry.date)
                    .frame(height: 16)
            }
        } else {
            WidgetEmptyState(title: "Sunny Hours", symbol: "sun.max.fill")
        }
    }
}

private struct SunnyHoursTimeline: View {
    let city: WidgetCity
    let currentDate: Date

    var body: some View {
        GeometryReader { proxy in
            let startHour = city.daytimeHours.min() ?? 6
            let endHour = city.daytimeHours.max() ?? 21
            let range = max(endHour - startHour + 1, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                HStack(spacing: 2) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        Capsule()
                            .fill(segmentColor(for: hour))
                    }
                }
                .padding(.vertical, 2)

                if Calendar.current.component(.hour, from: currentDate) >= startHour,
                   Calendar.current.component(.hour, from: currentDate) <= endHour {
                    let currentHour = Calendar.current.component(.hour, from: currentDate)
                    Capsule()
                        .fill(.white)
                        .frame(width: 1.5)
                        .offset(x: CGFloat(currentHour - startHour) / CGFloat(range) * proxy.size.width)
                }
            }
        }
        .accessibilityLabel("Sunny hours timeline")
    }

    private func segmentColor(for hour: Int) -> Color {
        if city.sunnyHours.contains(hour) { return .yellow }
        if city.partlySunnyHours.contains(hour) { return .yellow.opacity(0.48) }
        return .clear
    }
}

private struct WidgetEmptyState: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(WidgetColors.navy)
            Spacer()
            Text("Open Weather Atlas to update this widget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum WidgetColors {
    static let navy = Color(red: 0.12, green: 0.28, blue: 0.55)
}

private extension WidgetList {
    static let preview = WidgetList(
        id: "europe",
        displayName: "Europe",
        listName: "Europe",
        title: "Best Sunny Places",
        topCityIDs: ["barcelona", "rome", "athens"],
        cities: [
            WidgetCity(id: "barcelona", cityName: "Barcelona", temperature: "30°", cloudCover: "8%", conditionIcon: "sun.max.fill", daytimeHours: Array(6...21), sunnyHours: Array(8...19), partlySunnyHours: [7, 20]),
            WidgetCity(id: "rome", cityName: "Rome", temperature: "29°", cloudCover: "12%", conditionIcon: "cloud.sun", daytimeHours: Array(6...21), sunnyHours: Array(9...18), partlySunnyHours: [7, 8, 19]),
            WidgetCity(id: "athens", cityName: "Athens", temperature: "28°", cloudCover: "16%", conditionIcon: "sun.max.fill", daytimeHours: Array(6...21), sunnyHours: Array(8...20), partlySunnyHours: [7])
        ]
    )
}

private extension WidgetCity {
    static let preview = WidgetList.preview.cities[0]
}

@main
struct WeatherWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BestSunnyPlacesWidget()
        SunnyHoursLockScreenWidget()
    }
}

#Preview(as: .systemSmall) {
    BestSunnyPlacesWidget()
} timeline: {
    BestSunnyPlacesEntry.preview
}

#Preview(as: .systemMedium) {
    BestSunnyPlacesWidget()
} timeline: {
    BestSunnyPlacesEntry.preview
}

#Preview(as: .accessoryRectangular) {
    SunnyHoursLockScreenWidget()
} timeline: {
    SunnyHoursLockScreenEntry.preview
}
