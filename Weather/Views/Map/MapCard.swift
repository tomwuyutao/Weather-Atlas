//
//  MapCard.swift
//  Weather
//
//  Purpose: Defines the single two-size floating surface used by Map. Find Sun
//  controls, progress, completed-search summaries, and recovery banners use the
//  compact size; place selections use the large size.
//

import SwiftUI

// MARK: - Shared Surface

/// The Map has one bottom surface with two layout modes. Keeping size as data
/// lets SwiftUI preserve the surface's identity while its geometry changes.
enum MapCardSize {
    case small
    case offline
    case large(horizontalPadding: CGFloat)

    var expandsToMaximumWidth: Bool {
        switch self {
        case .small, .offline: false
        case .large: true
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small, .offline: 16
        case .large(let horizontalPadding): horizontalPadding
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: MapCardLayout.compactHeight / 2
        case .offline: OfflineBannerLayout.cornerRadius
        case .large: MapCardLayout.largeCornerRadius
        }
    }
}

/// Geometry shared by every surface anchored above the Map tab bar.
enum MapCardLayout {
    static let compactHeight: CGFloat = 44
    static let compactHorizontalPadding: CGFloat = 14
    static let surfaceSpacing: CGFloat = 8
    static let bottomPadding: CGFloat = 18
    static let largeCornerRadius: CGFloat = 24
}

/// Motion is scoped to the bottom surface itself. Map annotation and selection
/// mutations must stay outside this transaction so MapKit never interpolates
/// marker positions while the surface morphs.
enum MapCardMotion {
    static func morph() -> Animation {
        .spring(response: 0.24, dampingFraction: 0.88)
    }

}

/// A native Liquid Glass surface for the Map's compact and expanded states.
/// The two states share one effect identifier so the enclosing
/// `GlassEffectContainer` can morph a compact control into its rounded card
/// without leaving the prior capsule visible beneath it.
struct MapCard<Content: View>: View {
    let size: MapCardSize
    let maximumWidth: CGFloat
    let bottomPadding: CGFloat
    /// Older-system matched geometry uses one shared identity instead.
    let fallbackGeometryID: String
    let glassNamespace: Namespace.ID
    let content: Content

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    init(
        size: MapCardSize,
        maximumWidth: CGFloat,
        bottomPadding: CGFloat = MapCardLayout.bottomPadding,
        fallbackGeometryID: String,
        glassNamespace: Namespace.ID,
        @ViewBuilder content: () -> Content
    ) {
        self.size = size
        self.maximumWidth = maximumWidth
        self.bottomPadding = bottomPadding
        self.fallbackGeometryID = fallbackGeometryID
        self.glassNamespace = glassNamespace
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let shape = MapCardShape(cornerRadius: size.cornerRadius)

        if reduceTransparency {
            glassSurface
                .contentShape(shape)
                .background(theme.colors.glassFill, in: shape)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.18),
                        lineWidth: 0.8
                    )
                )
                .matchedGeometryEffect(
                    id: fallbackGeometryID,
                    in: glassNamespace,
                    properties: .frame,
                    anchor: .bottom
                )
                .mapCardPositioned(
                    horizontalPadding: size.horizontalPadding,
                    maximumWidth: maximumWidth,
                    bottomPadding: bottomPadding
                )
        } else if #available(iOS 26.0, *) {
            glassSurface
                .contentShape(shape)
                // Keep the Map surface intentionally native: Liquid Glass is
                // the complete visual treatment, without an extra tint, edge
                // stroke, or custom glass-transition outline layered on top.
                .glassEffect(
                    size.expandsToMaximumWidth
                        ? .regular
                        : .regular.interactive(),
                    in: shape
                )
                .mapCardPositioned(
                    horizontalPadding: size.horizontalPadding,
                    maximumWidth: maximumWidth,
                    bottomPadding: bottomPadding
                )
        } else {
            glassSurface
                .contentShape(shape)
                .background(.ultraThinMaterial, in: shape)
                .mapCardPositioned(
                    horizontalPadding: size.horizontalPadding,
                    maximumWidth: maximumWidth,
                    bottomPadding: bottomPadding
                )
        }
    }

    private var glassSurface: some View {
        content
            .frame(
                maxWidth: size.expandsToMaximumWidth ? .infinity : nil,
                alignment: .bottom
            )
    }

}

private extension View {
    /// Positions the Map's shared bottom surface outside of the glass effect so
    /// the effect ID describes the visible material, not its safe-area inset.
    func mapCardPositioned(
        horizontalPadding: CGFloat,
        maximumWidth: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        padding(.horizontal, horizontalPadding)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: maximumWidth, alignment: .bottom)
    }
}

/// One animatable outline interpolates from a compact capsule to the large
/// continuous rounded rectangle without replacing the glass material.
private struct MapCardShape: InsettableShape {
    var cornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return RoundedRectangle(
            cornerRadius: max(0, cornerRadius - insetAmount),
            style: .continuous
        ).path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> MapCardShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Large Content

/// Geometry owned solely by the selected-place context card. Its more generous
/// edge insets stay independent from the compact Find Sun summary.
private enum MapPlaceContextCardLayout {
    static let horizontalPadding: CGFloat = 28
    static let verticalPadding: CGFloat = 20
    static let closeButtonSize: CGFloat = 44
    /// Action rows end with a 24-point glyph inside the 28-point card inset.
    /// A 44-point close target needs a 10-point smaller trailing inset for
    /// its centre to land on that same vertical trailing-glyph column.
    static let closeButtonTrailingInset: CGFloat = 18
    /// Align the close glyph with the title baseline rather than pinning it
    /// to the card's top edge.
    static let closeButtonTopInset: CGFloat = 12

    static func minimumHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        if dynamicTypeSize.isAccessibilitySize {
            return 150
        }
        switch dynamicTypeSize {
        case .xSmall, .small, .medium, .large:
            return 128
        case .xLarge:
            return 138
        default:
            return 150
        }
    }
}

/// Standard close affordance shared by every large Map-card body.
struct MapCardCloseButton: View {
    let title: LocalizedStringKey
    let diameter: CGFloat
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        diameter: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.diameter = diameter
        self.action = action
    }

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(title, systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: diameter >= 52 ? 24 : 16, weight: .semibold))
            .foregroundStyle(theme.colors.primaryText)
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .buttonStyle(.plain)

    }
}

/// The selected-place header follows the same information hierarchy as the
/// Map card reference: place first, then the selected day's total sunny time.
/// It is shared by saved, transient, and current-location Map selections.
private struct MapPlaceCardHeader: View {
    let placeName: String
    let weather: MapPlaceWeatherPresentation

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(placeName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                // The top-right actions reserve their real footprint below.
                // Keep the locality to one predictable header line and use a
                // tail ellipsis rather than allowing a long name to continue
                // underneath the enlarged close control.
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let recommendation = weather.recommendation {
            if recommendation.sunnyHourCount > 0 {
                SunnyHoursStatusLine(hours: recommendation.sunnyHourCount)
            } else {
                Text(localizedString("No Sun", locale: locale))
                    .font(.body)
                    .foregroundStyle(theme.colors.secondaryText)
            }
        } else if weather.isLoading {
            HStack(spacing: 3) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18)

                Text(localizedString("Loading Forecast", locale: locale))
            }
            .font(.body)
            .foregroundStyle(theme.colors.secondaryText)
        } else {
            Text(localizedString("Forecast unavailable", locale: locale))
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
        }
    }

}

// MARK: - Large Card Bodies

/// One compact, plain row makes every Map floating-card action use the same
/// icon, title, full-width divider treatment, and at-least-44-point hit
/// target. Icons stay directly on the card surface, keeping the action list
/// visually lighter than the card header.
private struct MapCardActionRow: View {
    static let iconWidth: CGFloat = 24
    static let iconSpacing: CGFloat = 12
    static let minimumHeight: CGFloat = 44

    let title: String
    let systemImage: String
    let trailingSystemImage: String?
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    init(
        title: String,
        systemImage: String,
        trailingSystemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Self.iconSpacing) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: Self.iconWidth)

                Text(title)
                    .font(.body)
                    // Context-card actions stay compact. Preserve their
                    // 44-point row rhythm by tail-truncating long city or
                    // country names instead of allowing a second line.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.body)
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(width: 24, height: Self.minimumHeight)

                }
            }
            .foregroundStyle(theme.colors.primaryText)
            .frame(
                maxWidth: .infinity,
                minHeight: Self.minimumHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

    }
}

/// Owns the one collapsed Find Sun row used by all place-context cards. The
/// regional options are intentionally inserted only after an explicit tap so
/// the initial card remains quick to scan and doesn't expose overlapping
/// search actions by default.
private struct MapFindSunDisclosure: View {
    let city: City
    let displayName: String
    let country: CountryPlacesOption?
    let continent: ContinentPlacesOption?
    let findSunNear: (City) -> Void
    let findSun: (MapSunQueryScope) -> Void

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        Menu {
            Button {
                findSunNear(city)
            } label: {
                MapContextMenuLabel(
                    resolved: findNearTitle,
                    systemImage: "location"
                )
            }

            Divider()

            if let country {
                Button {
                    findSun(.country(country))
                } label: {
                    MapContextMenuLabel(
                        resolved: country.localizedName(locale: locale),
                        systemImage: "flag"
                    )
                }
            }

            if let continent {
                Button {
                    findSun(.continent(continent))
                } label: {
                    MapContextMenuLabel(
                        resolved: continent.localizedName(locale: locale),
                        systemImage: "globe.europe.africa"
                    )
                }
            }
        }
        label: {
            HStack(spacing: MapCardActionRow.iconSpacing) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .frame(width: MapCardActionRow.iconWidth)

                Text(localizedString("Find Sun", locale: locale))
                    .font(.body)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(
                        width: MapCardActionRow.iconWidth,
                        height: MapCardActionRow.minimumHeight
                    )
            }
            .foregroundStyle(theme.colors.primaryText)
            .frame(
                maxWidth: .infinity,
                minHeight: MapCardActionRow.minimumHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.automatic)
        .buttonStyle(.plain)
    }

    private var findNearTitle: String {
        String(
            format: localizedString("Near %@", locale: locale),
            locale: locale,
            primaryPlaceName
        )
    }

    /// Map providers sometimes include a district after the locality. The
    /// nearby action needs a short, scannable place reference rather than
    /// repeating that full administrative label across two wrapped lines.
    private var primaryPlaceName: String {
        CurrentLocationMetadata.localityName(from: displayName) ?? displayName
    }

}

/// One weather presentation value lets selected saved places, Find Sun
/// results, and reverse-geocoded map taps all use the same card shell without
/// pretending that an unfinished forecast is already available.
struct MapPlaceWeatherPresentation {
    let recommendation: PlaceRecommendation?
    let isLoading: Bool
}

/// The common large Map selection card. It keeps a place's weather facts and
/// all possible follow-up actions together whether the place came from the
/// saved library, Find Sun, Search, or a direct map tap.
struct MapPlaceContextCard: View {
    let city: City
    let displayName: String
    let weather: MapPlaceWeatherPresentation
    let country: CountryPlacesOption?
    let continent: ContinentPlacesOption?
    /// Every city card exposes the same persistence action. Its title and
    /// effect switch between save and delete from the live `isSaved` state.
    let save: () -> Bool
    let removeSavedPlace: () -> Bool
    /// Device location deliberately remains transient, so its card omits the
    /// shared persistence row while every city card retains it.
    let showsPersistenceAction: Bool
    let isSaved: Bool
    let viewDetails: () -> Void
    let findSunNear: (City) -> Void
    let findSun: (MapSunQueryScope) -> Void
    let clearSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                MapPlaceCardHeader(
                    placeName: displayName,
                    weather: weather
                )
                    .padding(.trailing, headerTrailingReservation)

                firstRowDivider

                MapCardActionRow(
                    title: localizedString("View Details", locale: locale),
                    systemImage: "list.bullet.rectangle",
                    trailingSystemImage: "arrow.right"
                ) {
                    viewDetails()
                }

                rowDivider

                MapFindSunDisclosure(
                    city: city,
                    displayName: displayName,
                    country: country,
                    continent: continent,
                    findSunNear: findSunNear,
                    findSun: findSun
                )

                if showsPersistenceAction {
                    rowDivider

                    MapCardActionRow(
                        title: localizedString(
                            isSaved
                                ? "Delete from Saved Places"
                                : "Save Place",
                            locale: locale
                        ),
                        systemImage: isSaved ? "trash" : "bookmark"
                    ) {
                        if isSaved {
                            // Persisted markers use the exact same final row
                            // as transient ones, so each city card keeps all
                            // three actions in the same order.
                            _ = removeSavedPlace()
                        } else {
                            _ = save()
                        }
                    }
                }
            }
            .padding(.horizontal, MapPlaceContextCardLayout.horizontalPadding)
            .padding(.vertical, MapPlaceContextCardLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minHeight: MapPlaceContextCardLayout.minimumHeight(for: dynamicTypeSize)
            )

            MapCardCloseButton(
                title: "Close",
                diameter: MapPlaceContextCardLayout.closeButtonSize,
                action: clearSelection
            )
                .padding(.top, MapPlaceContextCardLayout.closeButtonTopInset)
                // Centre the larger 44-point close target on the same trailing
                // column as the 24-point arrows in the action rows below.
                .padding(
                    .trailing,
                    MapPlaceContextCardLayout.closeButtonTrailingInset
                )
                .zIndex(1)
        }

    }

    private var headerTrailingReservation: CGFloat {
        // The close button is the only top-right action. Every persistence
        // action lives in the shared final row below the header.
        MapPlaceContextCardLayout.closeButtonSize
            + MapPlaceContextCardLayout.closeButtonTrailingInset
    }

    /// Separates the header from the first action without visually attaching a
    /// divider to the sunny-hours status line above it.
    private var firstRowDivider: some View {
        Divider()
            .padding(.top, 16)
    }

    /// Full-width separators run beneath row icons as well as their labels,
    /// matching the compact native-list treatment requested for this card.
    private var rowDivider: some View {
        Divider()
    }
}

// MARK: - Reverse-Geocoded Place Cards

/// Presentation context for a reverse-geocoded map tap.
///
/// Keeping this value beside its card makes the direct-tap surface a complete
/// MapCard concern: MapView resolves factual location metadata and owns the
/// selection state, while this file defines how that state is shown.
struct MapTapRegionContext: Identifiable {
    /// The coordinate-backed city stays transient until the person chooses to
    /// save it from the card or its Detail report.
    let city: City
    /// The reverse-geocoded locality makes a tap-card identity stable while
    /// the selected coordinate remains on screen.
    let locality: String?
    /// The factual country scope available from the tapped coordinate.
    let country: CountryPlacesOption
    /// The continent scope is optional because the catalog deliberately omits
    /// unsupported or unknown regional mappings rather than guessing.
    let continent: ContinentPlacesOption?

    var id: String { "\(country.id)-\(locality ?? "")" }
}

/// Immediate acknowledgement for a bare map tap while reverse geocoding finds
/// its exact city, country, and time zone. It uses the normal large selected
/// surface so the resolved place card can replace it without a separate alert
/// or a delayed visual response.
struct MapLocationLoadingCard: View {
    let clearSelection: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(theme.colors.accent)

                Text("Loading Location")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)

                Spacer(minLength: MapPlaceContextCardLayout.closeButtonSize)
            }
            .padding(.horizontal, MapPlaceContextCardLayout.horizontalPadding)
            .padding(.vertical, MapPlaceContextCardLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(
                minHeight: MapPlaceContextCardLayout.minimumHeight(
                    for: dynamicTypeSize
                )
            )

            MapCardCloseButton(
                title: "Close",
                diameter: MapPlaceContextCardLayout.closeButtonSize,
                action: clearSelection
            )
            .padding(.top, MapPlaceContextCardLayout.closeButtonTopInset)
            .padding(.trailing, MapPlaceContextCardLayout.horizontalPadding)
        }
    }
}

/// Contextual regional search shown only after the user taps the map itself.
struct MapRegionContextCard: View {
    let context: MapTapRegionContext
    let weather: MapPlaceWeatherPresentation
    /// A direct map tap keeps the same save-or-delete action contract as all
    /// other place cards.
    let save: () -> Bool
    let removeSavedPlace: () -> Bool
    let isSaved: Bool
    let viewDetails: (City) -> Void
    /// The Map parent owns the query execution. This card only exposes the
    /// tapped city as the geographic origin for a nearby Find Sun request.
    let findSunNear: (City) -> Void
    let findSun: (MapSunQueryScope) -> Void
    let clearSelection: () -> Void

    var body: some View {
        MapPlaceContextCard(
            city: context.city,
            // The direct-tap card is one of the two dedicated places that may
            // show the reverse-geocoded locality plus area. Its marker and
            // every ordinary place label still use `displayName`.
            displayName: context.city.titleDisplayName,
            weather: weather,
            country: context.country,
            continent: context.continent,
            save: save,
            removeSavedPlace: removeSavedPlace,
            showsPersistenceAction: true,
            isSaved: isSaved,
            viewDetails: {
                viewDetails(context.city)
            },
            findSunNear: findSunNear,
            findSun: findSun,
            clearSelection: clearSelection
        )
    }
}

// MARK: - Saved Marker Presentation

/// A single stable map item using the saved-place presentation contract shared
/// by cards and weather rows.
struct PlacesMapPlacePresentation: Identifiable {
    let place: SavedPlace
    let recommendation: PlaceRecommendation?
    let isLoading: Bool

    var id: SavedPlace.ID { place.id }
}

#if DEBUG

// MARK: - Preview

/// Self-contained canvas fixture for reviewing the shared direct-tap card
/// without loading WeatherKit, reverse-geocoding, or a saved Places document.
private struct MapPlaceContextCardPreview: View {
    @State private var isSaved = false
    @Namespace private var glassNamespace

    private static let city = City(
        name: "Berlin",
        country: "Germany",
        latitude: 52.5200,
        longitude: 13.4050,
        timeZoneIdentifier: "Europe/Berlin"
    )

    private static let forecast = DailyForecast(
        date: Date(timeIntervalSince1970: 1_786_233_600),
        dailyLow: 13,
        dailyHigh: 24,
        symbolName: "cloud.sun.fill",
        condition: AppWeatherCondition(rawValue: "partlyCloudy"),
        hourlyForecasts: [],
        cloudCover: 0.25,
        precipitationChance: 0.05,
        uvIndex: 5,
        sunrise: nil,
        sunset: nil
    )

    private static let weather = CityWeather(
        city: city,
        dailyForecasts: [forecast],
        timeZone: TimeZone(secondsFromGMT: 3_600)!
    )

    private static let recommendation = PlaceRecommendation(
        cityWeather: weather,
        symbolName: forecast.symbolName,
        condition: forecast.condition,
        sunnyHourCount: 11
    )

    private static let country = CountryPlacesOption(
        iso2: "DE",
        englishName: "Germany",
        cities: []
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            AppPalette.light.background

            MapCard(
                size: .large(horizontalPadding: 16),
                maximumWidth: 390,
                fallbackGeometryID: "preview-tapped-place-card",
                glassNamespace: glassNamespace
            ) {
                MapPlaceContextCard(
                    city: Self.city,
                    displayName: Self.city.displayName,
                    weather: MapPlaceWeatherPresentation(
                        recommendation: Self.recommendation,
                        isLoading: false
                    ),
                    country: Self.country,
                    continent: .europe,
                    save: {
                        isSaved = true
                        return true
                    },
                    removeSavedPlace: {
                        isSaved = false
                        return true
                    },
                    showsPersistenceAction: true,
                    isSaved: isSaved,
                    viewDetails: {},
                    findSunNear: { _ in },
                    findSun: { _ in },
                    clearSelection: {}
                )
            }
        }
        .frame(width: 390, height: 520)
    }
}

#Preview("Map Place Sunny Hours Card", traits: .fixedLayout(width: 390, height: 520)) {
    MapPlaceContextCardPreview()
        .environment(\.appTheme, .shared)
}

/// Self-contained Find Sun fixture for the compact summary and native ranking
/// sheet, without loading MapKit or starting a weather request.
enum MapSunResultsPreviewData {
    private static let cities: [(String, String, Double)] = [
        ("Rome", "Italy", 12),
        ("Naples", "Italy", 10),
        ("Palermo", "Italy", 9),
        ("Bari", "Italy", 8),
        ("San Valentino in Abruzzo Citeriore", "Italy", 7)
    ]

    static var results: [MapSunSearchResult] {
        cities.map { name, country, sunnyHours in
            let city = City(
                name: name,
                country: country,
                latitude: 41.9,
                longitude: 12.5,
                timeZoneIdentifier: "Europe/Rome"
            )
            let forecast = DailyForecast(
                date: Date(timeIntervalSince1970: 1_786_233_600),
                dailyLow: 18,
                dailyHigh: 30,
                symbolName: "sun.max.fill",
                condition: AppWeatherCondition(rawValue: "clear"),
                hourlyForecasts: [],
                cloudCover: 0.1,
                precipitationChance: 0,
                uvIndex: 7,
                sunrise: nil,
                sunset: nil
            )
            let weather = CityWeather(
                city: city,
                dailyForecasts: [forecast],
                timeZone: TimeZone(identifier: "Europe/Rome")!
            )
            return MapSunSearchResult(
                recommendation: PlaceRecommendation(
                    cityWeather: weather,
                    symbolName: forecast.symbolName,
                    condition: forecast.condition,
                    sunnyHourCount: sunnyHours
                )
            )
        }
    }
}

private struct MapSunResultsSummaryPreview: View {
    let title: String

    @State private var isRankingPresented = false
    @Namespace private var glassNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            AppPalette.light.background

            MapCard(
                size: .small,
                maximumWidth: 390,
                fallbackGeometryID: "preview-sun-results-summary",
                glassNamespace: glassNamespace
            ) {
                MapSunSearchCapsule(
                    state: .results(
                        title: title,
                        showResults: { isRankingPresented = true },
                        clearResults: {}
                    )
                )
            }
        }
        .frame(width: 390, height: 180)
        .sheet(isPresented: $isRankingPresented) {
            FindSunListView(
                results: MapSunResultsPreviewData.results,
                title: title
            )
            .presentationDragIndicator(.visible)
        }
    }
}

#Preview("Map Find Sun Result Summary", traits: .fixedLayout(width: 390, height: 180)) {
    MapSunResultsSummaryPreview(title: "Italy")
        .environment(\.appTheme, .shared)
}

#endif
