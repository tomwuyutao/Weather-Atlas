//
//  MapCard.swift
//  Weather
//
//  Purpose: Defines the single two-size floating surface used by Map. Find Sun
//  controls, progress and recovery banners use the compact size; selections
//  and result panels use the large size and supply their own content.
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

/// One motion rule is shared by state mutations and the surface itself, which
/// prevents its content and geometry from animating with different timings.
enum MapCardMotion {
    static func morph(reduceMotion: Bool) -> Animation? {
        reduceMotion
            ? nil
            : .spring(response: 0.36, dampingFraction: 0.84)
    }
}

/// A native Liquid Glass surface for the Map's compact and expanded states.
/// The two states share one effect identifier so the enclosing
/// `GlassEffectContainer` can morph a compact control into its rounded card
/// without leaving the prior capsule visible beneath it.
struct MapCard<Content: View>: View {
    let size: MapCardSize
    let colorScheme: ColorScheme
    let maximumWidth: CGFloat
    /// A unique Liquid Glass identity for this physical surface on iOS 26.
    let glassEffectID: String
    /// Older-system matched geometry uses one shared identity instead.
    let fallbackGeometryID: String
    let glassNamespace: Namespace.ID
    /// Reports the right edge of the visible glass, rather than the expanded
    /// layout container. Map uses it to keep a long compact status capsule
    /// from colliding with its trailing utility controls.
    let onSurfaceTrailingEdgeChange: (CGFloat) -> Void
    let content: Content

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    init(
        size: MapCardSize,
        colorScheme: ColorScheme,
        maximumWidth: CGFloat,
        glassEffectID: String,
        fallbackGeometryID: String,
        glassNamespace: Namespace.ID,
        onSurfaceTrailingEdgeChange: @escaping (CGFloat) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.size = size
        self.colorScheme = colorScheme
        self.maximumWidth = maximumWidth
        self.glassEffectID = glassEffectID
        self.fallbackGeometryID = fallbackGeometryID
        self.glassNamespace = glassNamespace
        self.onSurfaceTrailingEdgeChange = onSurfaceTrailingEdgeChange
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        let shape = MapCardShape(cornerRadius: size.cornerRadius)

        if reduceTransparency || colorSchemeContrast == .increased {
            // Accessibility settings take precedence over translucency. The
            // same geometry match still gives the opaque fallback a coherent
            // compact-to-large movement.
            measuredGlassSurface
                .background(theme.colors.glassFill, in: shape)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(
                            colorSchemeContrast == .increased ? 0.90 : 0.18
                        ),
                        lineWidth: colorSchemeContrast == .increased ? 1 : 0.8
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
                    maximumWidth: maximumWidth
                )
        } else if #available(iOS 26.0, *) {
            // `glassEffectID` must be attached directly to the Glass effect.
            // Applying it outside a custom modifier looks valid in source but
            // gives iOS no material to pair, producing the old pop/fade.
            measuredGlassSurface
                .background(
                    theme.colors.glassFill.opacity(
                        colorScheme == .dark ? 0.18 : 0.22
                    ),
                    in: shape
                )
                // The compact surface is itself a direct action. The expanded
                // surface is a rounded card containing its own controls, so
                // it must not apply a capsule-style direct press response.
                .contentShape(shape)
                .glassEffect(
                    size.expandsToMaximumWidth
                        ? .regular
                        : .regular.interactive(),
                    in: shape
                )
                .glassEffectID(glassEffectID, in: glassNamespace)
                // The transition belongs on the actual glass effect. Applying
                // it to the container does not animate the inserted and
                // removed surfaces themselves.
                .glassEffectTransition(.matchedGeometry)
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.16),
                        lineWidth: 0.6
                    )
                )
                // Keep the outer positioning outside the material. The
                // compact Find Sun control must retain its intrinsic capsule
                // width instead of inheriting the card's maximum-width frame.
                .mapCardPositioned(
                    horizontalPadding: size.horizontalPadding,
                    maximumWidth: maximumWidth
                )
        } else {
            measuredGlassSurface
                .background(.ultraThinMaterial, in: shape)
                .background(
                    theme.colors.glassFill.opacity(
                        colorScheme == .dark ? 0.30 : 0.38
                    ),
                    in: shape
                )
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.16),
                        lineWidth: 0.6
                    )
                )
                // Older OS releases do not have `glassEffectID`, but keeping
                // the geometry match on the visible surface still makes the
                // capsule expand upward into the card rather than appear
                // separately.
                .matchedGeometryEffect(
                    id: fallbackGeometryID,
                    in: glassNamespace,
                    properties: .frame,
                    anchor: .bottom
                )
                .mapCardPositioned(
                    horizontalPadding: size.horizontalPadding,
                    maximumWidth: maximumWidth
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

    /// The outer layout wrapper expands to the map's maximum card width, even
    /// for a compact capsule. Measure the material itself so collision handling
    /// responds only to the width people can actually see.
    private var measuredGlassSurface: some View {
        glassSurface
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).maxX
            } action: { newTrailingEdge in
                onSurfaceTrailingEdgeChange(newTrailingEdge)
            }
    }
}

private extension View {
    /// Positions the Map's shared bottom surface outside of the glass effect so
    /// the effect ID describes the visible material, not its safe-area inset.
    func mapCardPositioned(
        horizontalPadding: CGFloat,
        maximumWidth: CGFloat
    ) -> some View {
        padding(.horizontal, horizontalPadding)
            .padding(.bottom, MapCardLayout.bottomPadding)
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

// MARK: - Compact Content

/// The single-line layout shared by Find Sun, progress, result-count, empty,
/// loading, and error states. The surrounding `MapCard` supplies its surface.
struct MapCardSmallContent<Content: View>: View {
    let content: Content
    private let horizontalPadding: CGFloat

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        horizontalPadding: CGFloat = MapCardLayout.compactHorizontalPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .font(.subheadline)
        .fontWeight(.regular)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
        .allowsTightening(true)
        .padding(.horizontal, horizontalPadding)
        .frame(
            minHeight: dynamicTypeSize.isAccessibilitySize
                ? 60
                : MapCardLayout.compactHeight
        )
        // Match `MapCardSize.small` exactly. At accessibility text sizes this
        // surface grows taller than a capsule, so a literal `Capsule` would
        // create a mismatched long-press highlight below the glass.
        .contentShape(
            RoundedRectangle(
                cornerRadius: MapCardLayout.compactHeight / 2,
                style: .continuous
            )
        )
        .accessibilityElement(children: .contain)
    }
}

/// An icon-only action that fits inside the fixed-height compact surface.
struct MapCardIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    /// Standard map recovery actions keep a 44-point layout width. A compact
    /// dismissal may opt into a narrower slot so a long status label remains
    /// readable without changing the button's native icon-only treatment.
    var layoutWidth: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .frame(width: layoutWidth, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
    }
}

// MARK: - Large Content

/// Geometry shared by saved-place, Find Sun, and current-location card bodies.
enum MapCardContentLayout {
    static let horizontalPadding: CGFloat = 22
    static let verticalPadding: CGFloat = 16
    static let iconWidth: CGFloat = 48
    static let iconHeight: CGFloat = 48
    static let closeClearance: CGFloat = 30

    static func height(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
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
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: "xmark", action: action)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .accessibilityLabel(Text(title))
    }
}

/// Formats the sunny interval consistently for every large Map-card body.
func mapCardSunnyHoursText(
    for recommendation: PlaceRecommendation,
    locale: Locale
) -> String {
    guard let range = recommendation.bestSunnyWindow else {
        return localizedString("No Sun", locale: locale)
    }

    let start = SunnyHoursFormatting.compactHourLabel(
        range.lowerBound,
        locale: locale
    )
    let end = SunnyHoursFormatting.compactHourLabel(
        range.upperBound + 1,
        locale: locale
    )
    return "\(start) – \(end)"
}

// MARK: - Large Card Bodies

/// Uses the same floating-card material and hierarchy as a saved-place card;
/// the top-right action differs because this transient result can be saved.
struct MapSunResultCard: View {
    let result: MapSunSearchResult
    let isSaved: Bool
    let viewDetails: () -> Void
    let save: () -> Void
    let clearSelection: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: viewDetails) {
                cardContent
                    .padding(.horizontal, MapCardContentLayout.horizontalPadding)
                    .padding(.vertical, MapCardContentLayout.verticalPadding)
                    // Reserve a second 44-point action slot for the bookmark
                    // that sits immediately before Close.
                    .padding(
                        .trailing,
                        MapCardContentLayout.closeClearance + 44
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: cardHeight)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: MapCardLayout.largeCornerRadius,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                if isSaved {
                    // The filled symbol acknowledges the completed save while
                    // keeping the same footprint as the original button.
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 44, height: 44)
                        .accessibilityLabel(
                            localizedString("Saved", locale: locale)
                        )
                } else {
                    Button("Save", systemImage: "bookmark", action: save)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .accessibilityLabel(
                            localizedString("Save", locale: locale)
                        )
                }

                MapCardCloseButton(
                    title: "Close",
                    action: clearSelection
                )
            }
            .zIndex(1)
        }
        .accessibilityElement(children: .contain)
    }

    private var cardHeight: CGFloat {
        MapCardContentLayout.height(for: dynamicTypeSize)
    }

    private var cardContent: some View {
        HStack(alignment: .center, spacing: 16) {
            let icon = "sun.max.fill"
            Image(systemName: icon)
                .font(.system(size: 40, weight: .medium))
                .weatherIconStyle(for: icon)
                .frame(
                    width: MapCardContentLayout.iconWidth,
                    height: MapCardContentLayout.iconHeight
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(mapCardSunnyHoursText(for: result.recommendation, locale: locale))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(
                        dynamicTypeSize.isAccessibilitySize ? 1 : 0.74
                    )

                Text(
                    "\(result.city.displayName) · \(localizedString("Sunny Hours", locale: locale))"
                )
                .font(.headline.weight(.regular))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(
                    dynamicTypeSize.isAccessibilitySize ? 1 : 0.72
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 4)
        }
    }
}

/// Read-only weather preview for the device location; it never saves a place.
struct MapCurrentLocationCard: View {
    let name: String
    let recommendation: PlaceRecommendation?
    let isLoading: Bool
    let clearSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 16) {
                if let recommendation {
                    let icon = recommendation.condition.displayIcon
                    Image(systemName: icon)
                        .font(.system(size: 40, weight: .medium))
                        // Map-card symbols match the selected place's dot.
                        .weatherIconStyle(for: recommendation.condition.iconTone)
                        .frame(
                            width: MapCardContentLayout.iconWidth,
                            height: MapCardContentLayout.iconHeight
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(mapCardSunnyHoursText(for: recommendation, locale: locale))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(
                                dynamicTypeSize.isAccessibilitySize ? 1 : 0.74
                            )

                        Text(name.isEmpty
                            ? localizedString("Sunny Hours", locale: locale)
                            : "\(name) · \(localizedString("Sunny Hours", locale: locale))")
                        .font(.headline.weight(.regular))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(
                            dynamicTypeSize.isAccessibilitySize ? 1 : 0.72
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.regular)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "cloud.slash")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(
                        width: MapCardContentLayout.iconWidth,
                        height: MapCardContentLayout.iconHeight
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            localizedString(
                                isLoading
                                    ? "Loading Forecast"
                                    : "Forecast unavailable",
                                locale: locale
                            )
                        )
                        .font(.title2.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(
                            dynamicTypeSize.isAccessibilitySize ? 1 : 0.74
                        )

                        Text(
                            name.isEmpty
                                ? localizedString("Current Location", locale: locale)
                                : name
                        )
                        .font(.headline.weight(.regular))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(
                            dynamicTypeSize.isAccessibilitySize ? 1 : 0.72
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, MapCardContentLayout.horizontalPadding)
            .padding(.vertical, MapCardContentLayout.verticalPadding)
            .padding(.trailing, MapCardContentLayout.closeClearance)
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: MapCardContentLayout.height(for: dynamicTypeSize)
            )

            MapCardCloseButton(
                title: "Close",
                action: clearSelection
            )
        }
        .accessibilityElement(children: .contain)
    }
}

/// Contextual regional search shown only after the user taps the map itself.
struct MapRegionContextCard: View {
    let context: MapTapRegionContext
    let viewDetails: (City) -> Void
    let findSun: (MapSunQueryScope) -> Void
    let clearSelection: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(context.title(locale: locale))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.trailing, MapCardContentLayout.closeClearance)

                VStack(spacing: 0) {
                    actionRow(
                        title: localizedString("View Details", locale: locale),
                        systemImage: "arrow.right"
                    ) {
                        viewDetails(context.city)
                    }

                    Divider()
                        .padding(.leading, 36)

                    actionRow(
                        title: findSunTitle(
                            for: context.country.localizedName(locale: locale)
                        ),
                        systemImage: "flag.fill"
                    ) {
                        findSun(.country(context.country))
                    }

                    if let continent = context.continent {
                        Divider()
                            .padding(.leading, 36)

                        actionRow(
                            title: findSunTitle(
                                for: continent.localizedName(locale: locale)
                            ),
                            systemImage: "globe.europe.africa"
                        ) {
                            findSun(.continent(continent))
                        }
                    }
                }
            }
            .padding(.horizontal, MapCardContentLayout.horizontalPadding)
            .padding(.vertical, MapCardContentLayout.verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)

            MapCardCloseButton(
                title: "Close",
                action: clearSelection
            )
        }
        .accessibilityElement(children: .contain)
    }

    private func findSunTitle(for regionName: String) -> String {
        String(
            format: localizedString("Find Sun in %@", locale: locale),
            locale: locale,
            regionName
        )
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .frame(width: 24, height: 44)
                    .accessibilityHidden(true)

                Text(title)
                    // Match the regular body styling used by the cities in
                    // Longest Sunny Hours; the queried place name above owns
                    // the card's emphasis.
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.primaryText)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A single stable map item using the saved-place presentation contract shared
/// by cards and weather rows.
struct PlacesMapPlacePresentation: Identifiable {
    let presentation: SavedPlacePresentation

    var id: City.ID { presentation.id }
    var place: SavedPlace { presentation.place }
    var recommendation: PlaceRecommendation? {
        presentation.recommendation
    }
    var isLoading: Bool { presentation.isLoading }
    var failureMessage: String? { presentation.failureMessage }
}

/// A compact, scrollable result surface keeps every ranked Find Sun result
/// reachable even when its marker is outside a dense cluster. Choosing a row
/// selects the same annotation/card state used by tapping its map dot.
struct MapSunResultsPanel: View {
    let results: [MapSunSearchResult]
    let title: String
    let select: (MapSunSearchResult) -> Void
    let clear: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    static func height(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 310 : 238
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(
                        localizedString(
                            "\(results.count) sunny places",
                            locale: locale
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, MapCardContentLayout.horizontalPadding)
                .padding(.top, MapCardContentLayout.verticalPadding)
                .padding(.trailing, MapCardContentLayout.closeClearance)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            let sunnyHours = SunnyHoursFormatting.hourCountLabel(
                                result.recommendation.sunnyHourCount,
                                locale: locale
                            )

                            VStack(spacing: 0) {
                                Button {
                                    select(result)
                                } label: {
                                    // Use the same icon/name/value grid as the
                                    // Saved Places sunny-hours ranking.
                                    HStack(spacing: WeatherCardLayout.headerSpacing) {
                                        Image(
                                            systemName: result.recommendation
                                                .condition.displayIcon
                                        )
                                        .weatherIconStyle(
                                            for: result.recommendation
                                                .condition.iconTone
                                        )
                                        .font(.callout.weight(.medium))
                                        .frame(
                                            width: WeatherCardLayout.leadingIconWidth,
                                            alignment: .leading
                                        )
                                        .accessibilityHidden(true)

                                        Text(result.city.displayName)
                                            .font(.body)
                                            .foregroundStyle(
                                                theme.colors.primaryText
                                            )
                                            .lineLimit(1)
                                            .layoutPriority(1)

                                        Spacer(minLength: 8)

                                        Text(sunnyHours)
                                            .font(.body)
                                            .foregroundStyle(
                                                theme.colors.primaryText
                                            )
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .fixedSize(
                                                horizontal: true,
                                                vertical: false
                                            )
                                    }
                                    .padding(
                                        .horizontal,
                                        MapCardContentLayout.horizontalPadding
                                    )
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 52
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(result.city.displayName)
                                .accessibilityValue(sunnyHours)
                                .accessibilityHint(
                                    localizedString(
                                        "Shows this place on the map.",
                                        locale: locale
                                    )
                                )

                                Divider()
                                    .padding(
                                        .leading,
                                        MapCardContentLayout.horizontalPadding
                                            + WeatherCardLayout.leadingIconWidth
                                            + WeatherCardLayout.headerSpacing
                                    )
                                    .opacity(
                                        result.id == results.last?.id ? 0 : 1
                                    )
                            }
                        }
                    }
                }
            }

            MapCardCloseButton(
                title: "Clear Results",
                action: clear
            )
        }
        .frame(height: Self.height(for: dynamicTypeSize))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}


/// The saved-place variant of the map card. Its `NavigationLink` opens the
/// full detail route, while the close button remains a separate hit target.
struct MapPlaceSelectionCard: View {
    let presentation: PlacesMapPlacePresentation
    let displayName: String
    let sortMode: WeatherMetricMode
    let clearSelection: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit")
    private var temperatureUnitRaw = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnitRaw = DistanceUnit.defaultRawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: AppRoute.place(id: presentation.id)) {
                cardContent
                    .padding(.horizontal, MapCardContentLayout.horizontalPadding)
                    .padding(.vertical, MapCardContentLayout.verticalPadding)
                    .padding(.trailing, MapCardContentLayout.closeClearance)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: cardHeight)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius:
                                MapCardLayout.largeCornerRadius,
                            style: .continuous
                        )
                    )
            }
            .buttonStyle(.plain)

            MapCardCloseButton(
                title: "Close",
                action: clearSelection
            )
                .zIndex(1)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var cardContent: some View {
        if let recommendation = presentation.recommendation {
            if dynamicTypeSize.isAccessibilitySize {
                // At large text sizes vertical content avoids forcing the city
                // name and selected metric into one unreadably narrow row.
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: recommendation.condition.displayIcon)
                        .font(.title2.weight(.medium))
                        .weatherIconStyle(for: recommendation.condition.iconTone)
                        .accessibilityHidden(true)

                    Text(metricValue(for: recommendation))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()

                    Text(displayName)
                        .font(.headline)

                    HStack(spacing: 6) {
                        Image(systemName: recommendation.condition.displayIcon)
                            .weatherIconStyle(for: recommendation.condition.iconTone)
                            .accessibilityHidden(true)

                        Text(sortMode.title(locale: locale))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: recommendation.condition.displayIcon)
                        .font(.system(size: 40, weight: .medium))
                        .weatherIconStyle(
                            for: recommendation.condition.iconTone
                        )
                        .frame(
                            width: MapCardContentLayout.iconWidth,
                            height: MapCardContentLayout.iconHeight
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(metricValue(for: recommendation))
                            .font(.system(size: 32, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)

                        Text(
                            "\(displayName) · \(sortMode.title(locale: locale))"
                        )
                        .font(.headline.weight(.regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    }

                    Spacer(minLength: 8)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.headline)

                if presentation.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardHeight: CGFloat {
        MapCardContentLayout.height(for: dynamicTypeSize)
    }

    private func metricValue(
        for recommendation: PlaceRecommendation
    ) -> String {
        switch sortMode {
        case .sunny:
            return mapCardSunnyHoursText(for: recommendation, locale: locale)
        case .temperature:
            return temperatureUnit.display(
                recommendation.forecast.dailyHigh
            )
        case .feelsLike:
            return recommendation.maximumFeelsLike.map(
                temperatureUnit.display
            ) ?? ""
        case .cloud:
            return recommendation.cloudCover.map(percentage) ?? ""
        case .rainChance:
            return recommendation.precipitationChance.map(percentage) ?? ""
        case .visibility:
            return recommendation.maximumVisibilityKilometers.map(
                distanceUnit.display
            ) ?? ""
        case .uvIndex:
            return recommendation.forecast.uvIndex.map(String.init) ?? ""
        }
    }

    private var temperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .systemDefault
    }

    private var distanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
