//
//  AppTheme.swift
//  Weather
//
//  Purpose: Centralizes palette values, localization lookup, theme resolution,
//  responsive layout, interaction feedback, and shared SwiftUI modifiers.
//
//  Reading guide: raw colors live first, then become semantic `ThemeColors`,
//  `AppTheme` chooses the active palette from system/preferences, and the final
//  section exposes small `View` modifiers so screens need not repeat styling.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - App Locale Lookup

/// Looks up a localized string for a specific locale supplied by SwiftUI.
///
/// `String.LocalizationValue` preserves the lookup key for the String Catalog.
/// Assigning the locale to `LocalizedStringResource` makes this independent of
/// the device locale when the app lets a person choose its own language.
func localizedString(_ key: String.LocalizationValue, locale: Locale) -> String {
    // Resolve the resource against the explicit in-app locale.
    var resource = LocalizedStringResource(key)
    resource.locale = locale
    return String(localized: resource)
}

// MARK: - Shared App Palette

/// Primitive semantic colors shared by the app and widget extension.
/// The palette names describe a visual role rather than a particular screen, so
/// a sunny dot, chart, and toolbar can agree without sharing hard-coded hexes.
enum AppPalette {
    /// Complete palette values before they are adapted into app theme aliases.
    /// This nested value type is deliberately "flat": a light/dark palette is
    /// one replaceable bundle, while `ThemeColors` later adds view-friendly names.
    struct Values {
        /// Primary foreground color.
        let titleText: Color
        /// Secondary foreground color.
        let secondaryText: Color
        /// Main canvas color.
        let background: Color
        /// Destructive-action color.
        let destructive: Color
        /// Fully sunny semantic color.
        let dotSun: Color
        /// Contrast-safe sunny foreground for symbols and charts.
        let sunForeground: Color
        /// Partly sunny semantic color.
        let dotPartlyCloudy: Color
        /// Cloudy semantic color.
        let dotCloudy: Color
        /// Rain semantic color.
        let dotRain: Color
        /// Contrast-safe rain foreground.
        let rainForeground: Color
        /// Drizzle semantic color.
        let dotDrizzle: Color
        /// Contrast-safe drizzle foreground.
        let drizzleForeground: Color
        /// Subdued row and panel fill.
        let settingsRow: Color
    }

    // MARK: Base Palettes

    /// Standard light-appearance palette.
    static let light = Values(
        titleText: Color(hex: 0x262626),
        secondaryText: Color(hex: 0x6D6D6D),
        background: Color(hex: 0xFAF8F2),
        destructive: Color(hex: 0xD14D30),
        dotSun: Color(hex: 0xFBC056),
        sunForeground: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAE38E),
        dotCloudy: Color(hex: 0xC8C8C8),
        dotRain: Color(hex: 0x5AA4F3),
        rainForeground: Color(hex: 0x5AA4F3),
        dotDrizzle: Color(hex: 0x67D1F0),
        drizzleForeground: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0xF4EFE4)
    )

    /// Standard charcoal dark-appearance palette.
    static let dark = Values(
        titleText: Color(hex: 0xFEFEFE),
        secondaryText: Color(hex: 0x929292),
        background: Color(hex: 0x262626),
        destructive: Color(hex: 0xD14D30),
        dotSun: Color(hex: 0xFBC056),
        sunForeground: Color(hex: 0xFBC056),
        dotPartlyCloudy: Color(hex: 0xFAE38E),
        dotCloudy: Color(hex: 0xC8C8C8),
        dotRain: Color(hex: 0x5AA4F3),
        rainForeground: Color(hex: 0x5AA4F3),
        dotDrizzle: Color(hex: 0x67D1F0),
        drizzleForeground: Color(hex: 0x67D1F0),
        settingsRow: Color(hex: 0x303030)
    )

    // Black keeps the dark palette's content colors while replacing its main
    // canvas with true black for OLED displays and a stronger dark appearance.
    /// True-black dark palette used by Black theme modes.
    static let black = Values(
        titleText: dark.titleText,
        secondaryText: dark.secondaryText,
        background: Color(hex: 0x000000),
        destructive: dark.destructive,
        dotSun: dark.dotSun,
        sunForeground: dark.sunForeground,
        dotPartlyCloudy: dark.dotPartlyCloudy,
        dotCloudy: dark.dotCloudy,
        dotRain: dark.dotRain,
        rainForeground: dark.rainForeground,
        dotDrizzle: dark.dotDrizzle,
        drizzleForeground: dark.drizzleForeground,
        settingsRow: Color(hex: 0x181818)
    )

    /// Returns the standard palette matching a resolved color scheme.
    static func values(for colorScheme: ColorScheme) -> Values {
        colorScheme == .dark ? dark : light
    }

    /// Returns a WCAG-stronger variant for the system contrast preference.
    /// Increased contrast is calculated from the same semantic colors rather
    /// than maintained as a second unrelated set of hexadecimal constants.
    static func increasedContrastValues(for colorScheme: ColorScheme) -> Values {
        increasedContrastValues(
            for: values(for: colorScheme),
            colorScheme: colorScheme
        )
    }

    /// Increased-contrast variant that retains a true-black canvas.
    static var increasedContrastBlack: Values {
        increasedContrastValues(for: black, colorScheme: .dark)
    }

    /// Strengthens text, border, and fill separation for one base palette.
    /// Light palettes blend several colored marks toward primary text because
    /// pale yellow/grey otherwise lose contrast against the warm background.
    private static func increasedContrastValues(
        for palette: Values,
        colorScheme: ColorScheme
    ) -> Values {
        if colorScheme == .dark {
            return Values(
                titleText: palette.titleText,
                secondaryText: palette.secondaryText,
                background: palette.background,
                destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
                dotSun: palette.dotSun,
                sunForeground: palette.sunForeground,
                dotPartlyCloudy: palette.dotPartlyCloudy,
                dotCloudy: palette.dotCloudy,
                dotRain: palette.dotRain,
                rainForeground: palette.rainForeground,
                dotDrizzle: palette.dotDrizzle,
                drizzleForeground: palette.drizzleForeground,
                settingsRow: palette.settingsRow
            )
        }

        return Values(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive.interpolated(with: palette.titleText, by: 0.12),
            dotSun: palette.dotSun.interpolated(with: palette.titleText, by: 0.48),
            sunForeground: palette.sunForeground.interpolated(
                with: palette.titleText,
                by: 0.12
            ),
            dotPartlyCloudy: palette.dotPartlyCloudy.interpolated(with: palette.titleText, by: 0.55),
            dotCloudy: palette.dotCloudy.interpolated(with: palette.titleText, by: 0.66),
            dotRain: palette.dotRain.interpolated(with: palette.titleText, by: 0.10),
            rainForeground: palette.rainForeground.interpolated(
                with: palette.titleText,
                by: 0.08
            ),
            dotDrizzle: palette.dotDrizzle.interpolated(with: palette.titleText, by: 0.35),
            drizzleForeground: palette.drizzleForeground.interpolated(
                with: palette.titleText,
                by: 0.08
            ),
            settingsRow: palette.settingsRow
        )
    }
}

// MARK: - Color Construction and Interpolation

extension Color {
    /// Creates an opaque sRGB color from a six-digit RGB hexadecimal value.
    /// The bit shifts extract red, green, and blue bytes from `0xRRGGBB`, then
    /// divide by 255 because SwiftUI's `Color` initializer expects 0...1 values.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8) & 0xFF) / 255.0
        let blue = Double(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    /// Blends two resolved sRGB colors by a clamped interpolation fraction.
    /// UIKit supplies component extraction because SwiftUI `Color` can represent
    /// dynamic/system colors without directly exposing RGB components.
    func interpolated(with other: Color, by amount: Double) -> Color {
        // Clamping makes a caller's small arithmetic error safe: 0 returns self,
        // 1 returns `other`, and anything in between linearly blends components.
        let fraction = max(0, min(1, amount))
        let first = UIColor(self)
        let second = UIColor(other)
        var red1: CGFloat = 0
        var green1: CGFloat = 0
        var blue1: CGFloat = 0
        var alpha1: CGFloat = 0
        var red2: CGFloat = 0
        var green2: CGFloat = 0
        var blue2: CGFloat = 0
        var alpha2: CGFloat = 0

        // Some dynamic colors cannot resolve to RGB in this context. Choose the
        // nearer endpoint instead of failing or inventing component values.
        guard first.getRed(&red1, green: &green1, blue: &blue1, alpha: &alpha1),
              second.getRed(&red2, green: &green2, blue: &blue2, alpha: &alpha2) else {
            return fraction < 0.5 ? self : other
        }

        return Color(
            red: Double(red1 + (red2 - red1) * fraction),
            green: Double(green1 + (green2 - green1) * fraction),
            blue: Double(blue1 + (blue2 - blue1) * fraction),
            opacity: Double(alpha1 + (alpha2 - alpha1) * fraction)
        )
    }
}

// MARK: - Theme Style

/// Persisted appearance modes offered by the Theme settings screen.
/// Raw strings are stable storage values; the enum keeps every switch over theme
/// choice exhaustive in Swift code.
enum AppThemeStyle: String, CaseIterable {
    case automatic = "automatic"
    case automaticBlack = "automaticBlack"
    case light = "light"
    case dark = "dark"
    case black = "black"

    /// Initial theme preference for new installations.
    static let defaultRawValue = AppThemeStyle.automatic.rawValue

    /// Localized row title for this theme mode.
    func displayName(locale: Locale) -> String {
        switch self {
        case .automatic: return localizedString("Automatic", locale: locale)
        case .automaticBlack: return localizedString("Automatic (Black)", locale: locale)
        case .light: return localizedString("Light", locale: locale)
        case .dark: return localizedString("Dark", locale: locale)
        case .black: return localizedString("Black", locale: locale)
        }
    }
}

// MARK: - Theme Colors

/// Semantic colors consumed by app views after appearance resolution.
/// Screens should normally use these names instead of choosing a base palette:
/// that way changing a palette or contrast policy affects the whole app coherently.
struct ThemeColors {
    // Palette values
    /// Primary heading and content foreground.
    let titleText: Color
    /// De-emphasized labels and outlines.
    let secondaryText: Color
    /// Main app background.
    let background: Color
    /// Destructive control foreground.
    let destructive: Color
    /// Fully sunny weather mark.
    let dotSun: Color
    /// Contrast-safe sunny foreground.
    let sunForeground: Color
    /// Partly sunny weather mark.
    let dotPartlyCloudy: Color
    /// Cloudy weather mark.
    let dotCloudy: Color
    /// Rain weather mark.
    let dotRain: Color
    /// Contrast-safe rain foreground.
    let rainForeground: Color
    /// Drizzle weather mark.
    let dotDrizzle: Color
    /// Contrast-safe drizzle foreground.
    let drizzleForeground: Color
    /// Subdued settings row and chart panel fill.
    let settingsRowFill: Color

    // MARK: Semantic View Aliases

    // Semantic aliases intentionally reuse the compact palette above. They keep
    // call sites readable without duplicating palette storage or values.
    /// Standard primary foreground alias.
    var primaryText: Color { titleText }
    /// Global control tint.
    var accent: Color { primaryText }

    /// Tint participating in translucent glass surfaces.
    var glassFill: Color { background }
    /// Highlight used by the sunny-only filter.
    var filterSunny: Color { dotSun }

    /// The upper bound for the shared sunny-hours color scale used by the map
    /// and Saved Places heatmap. Longer days intentionally share the same
    /// fully-sunny endpoint.
    static let sunnyHoursColorScaleMaximum = 10.0

    /// Maps total sunny hours onto the shared quiet-to-vivid sunny ramp.
    ///
    /// Zero hours uses the plain surface fill. Positive values use the same
    /// curved sunny-yellow opacity, reaching its strongest value at ten
    /// hours. Keeping this calculation in the theme keeps Map dots and the
    /// Saved Places heatmap visually identical.
    func sunnyHoursColor(
        for sunnyHours: Double,
        colorScheme: ColorScheme
    ) -> Color {
        let fraction = min(
            max(sunnyHours / Self.sunnyHoursColorScaleMaximum, 0),
            1
        )
        guard fraction > 0 else {
            return glassFill.opacity(colorScheme == .dark ? 0.34 : 0.56)
        }

        let curvedFraction = pow(fraction, 1.55)
        return dotSun.opacity(0.16 + 0.79 * curvedFraction)
    }

    /// Fully opaque Map-dot equivalent of `sunnyHoursColor(for:colorScheme:)`.
    ///
    /// MapKit draws dots over variable terrain, so applying alpha directly can
    /// make lower-sun dots look transparent. Pre-blending the same ramp with a
    /// very light neutral gray preserves its soft progression while keeping
    /// every marker solid and legible above the map.
    func sunnyHoursMapDotColor(for sunnyHours: Double) -> Color {
        let fraction = min(
            max(sunnyHours / Self.sunnyHoursColorScaleMaximum, 0),
            1
        )
        let lightGrayBase = Color.white.interpolated(with: dotCloudy, by: 0.55)
        guard fraction > 0 else { return lightGrayBase }

        let curvedFraction = pow(fraction, 1.55)
        let sunnyOpacity = 0.16 + 0.79 * curvedFraction
        return lightGrayBase.interpolated(with: dotSun, by: sunnyOpacity)
    }

    /// Returns the exact semantic marker color for a normalized weather tone.
    ///
    /// Weather symbols must match their corresponding Map marker rather than
    /// mixing a neutral cloud outline with a colored secondary layer. The shared
    /// tone also lets the widget extension use this visual vocabulary.
    func weatherIconColor(for tone: WeatherIconTone) -> Color {
        switch tone {
        case .clear:
            return dotSun
        case .partlySunny:
            return dotPartlyCloudy
        case .cloudy:
            return dotCloudy
        case .rain:
            return dotRain
        case .drizzle:
            return dotDrizzle
        }
    }

    /// Returns the semantic marker color for a raw weather SF Symbol name.
    ///
    /// This is a fallback for source symbols that have not yet been normalized.
    /// New weather views should pass the normalized condition's `iconTone` so a
    /// partly-cloudy icon does not lose its distinct neutral map-dot color.
    func weatherIconColor(for iconName: String) -> Color {
        weatherIconColor(for: WeatherIconTone(symbolName: iconName))
    }

    /// Returns a low-saturation canvas color derived from the same condition
    /// tone as the matching weather symbol. Blending toward the active app
    /// background preserves the palette in light, dark, and black appearances
    /// without introducing screen-specific color constants.
    func weatherBackgroundColor(for tone: WeatherIconTone?) -> Color {
        guard let tone else { return background }
        return weatherIconColor(for: tone).interpolated(
            with: background,
            by: 0.78
        )
    }

    /// A quiet inactive fill for sunny-hour timelines. It follows the same
    /// condition-derived canvas as the report, but stays lighter so sunny and
    /// rainy intervals remain the chart's primary signals.
    func weatherNoSunTimelineColor(for tone: WeatherIconTone?) -> Color {
        guard let tone else { return settingsRowFill }
        return weatherIconColor(for: tone).interpolated(
            with: background,
            by: 0.86
        )
    }
}

// MARK: - Concrete Theme Values

extension ThemeColors {
    /// Standard light semantic theme.
    static let light = ThemeColors(palette: AppPalette.light)
}

// MARK: - Dark Themes

extension ThemeColors {
    /// Standard charcoal dark semantic theme.
    static let dark = ThemeColors(palette: AppPalette.dark)

    /// True-black dark semantic theme.
    static let black = ThemeColors(palette: AppPalette.black)
}

// MARK: - Increased Contrast Palettes

// These palettes activate only with the system Increase Contrast setting.
// Text colors meet a 4.5:1 minimum and meaningful palette colors meet a 3:1 minimum
// against their corresponding base backgrounds.
extension ThemeColors {
    /// Increased-contrast light semantic theme.
    static let increasedContrastLight = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .light)
    )

    /// Increased-contrast charcoal dark semantic theme.
    static let increasedContrastDark = ThemeColors(
        palette: AppPalette.increasedContrastValues(for: .dark)
    )

    /// Increased-contrast true-black semantic theme.
    static let increasedContrastBlack = ThemeColors(
        palette: AppPalette.increasedContrastBlack
    )
}

/// Keeps the primitive-to-semantic conversion private so only named complete
/// themes can construct `ThemeColors`; views cannot accidentally omit a color.
private extension ThemeColors {
    /// Maps primitive shared palette values into app semantic aliases.
    init(palette: AppPalette.Values) {
        self.init(
            titleText: palette.titleText,
            secondaryText: palette.secondaryText,
            background: palette.background,
            destructive: palette.destructive,
            dotSun: palette.dotSun,
            sunForeground: palette.sunForeground,
            dotPartlyCloudy: palette.dotPartlyCloudy,
            dotCloudy: palette.dotCloudy,
            dotRain: palette.dotRain,
            rainForeground: palette.rainForeground,
            dotDrizzle: palette.dotDrizzle,
            drizzleForeground: palette.drizzleForeground,
            settingsRowFill: palette.settingsRow
        )
    }
}

// MARK: - Theme Manager

@Observable
/// Observable theme manager shared across every app window.
/// `@Observable` makes the chosen style and resolved colors reactive for SwiftUI
/// without requiring each screen to subscribe to UserDefaults independently.
class AppTheme {
    /// Process-wide theme manager instance.
    static let shared = AppTheme()

    /// Persisted appearance selection; updates storage whenever it changes.
    /// `didSet` is the narrow persistence boundary: views edit this enum, while
    /// the manager owns the raw UserDefaults key and migration fallback.
    var style: AppThemeStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "appThemeStyle")
        }
    }

    /// The effective app color scheme, kept in sync by ThemeContent after the app's
    /// appearance preference has been applied. This lets non-view code and view
    /// modifiers use the exact same palette as the current SwiftUI environment.
    var systemScheme: ColorScheme = .light

    /// The current system contrast preference, kept in sync by ThemeContent.
    var systemContrast: ColorSchemeContrast = .standard

    /// Resolved colors using the stored effective scheme — reactive, used everywhere.
    /// This computed property is the normal entry point for a view modifier that
    /// needs the same palette as the current SwiftUI environment.
    var colors: ThemeColors {
        resolvedColors(for: systemScheme, contrast: systemContrast)
    }

    /// Resolved colors for an explicit color scheme (used by ThemeContent during environment setup).
    func colors(
        for scheme: ColorScheme,
        contrast: ColorSchemeContrast? = nil
    ) -> ThemeColors {
        resolvedColors(for: scheme, contrast: contrast ?? systemContrast)
    }

    /// The ColorScheme to apply to the window (nil = follow system).
    /// Returning `nil` deliberately lets SwiftUI respond live to device changes.
    var preferredColorScheme: ColorScheme? {
        switch style {
        case .light: return .light
        case .dark, .black: return .dark
        case .automatic, .automaticBlack: return nil
        }
    }

    /// Restores the persisted style while normalizing invalid values.
    /// A removed/unknown raw string gracefully becomes Automatic rather than
    /// leaving the app in an unrenderable preference state.
    private init() {
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? AppThemeStyle.defaultRawValue
        self.style = AppThemeStyle(rawValue: raw) ?? .automatic
    }

    /// Chooses the exact semantic palette for scheme, contrast, and theme style.
    /// The black variants only apply when the effective scheme is dark; forcing
    /// black in a light scheme would break the promise of the Light selection.
    private func resolvedColors(
        for resolvedScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> ThemeColors {
        // True-black themes only replace the regular dark palette.
        if resolvedScheme == .dark && (style == .black || style == .automaticBlack) {
            return contrast == .increased ? .increasedContrastBlack : .black
        }
        if contrast == .increased {
            return resolvedScheme == .dark ? .increasedContrastDark : .increasedContrastLight
        }
        return resolvedScheme == .dark ? .dark : .light
    }
}

extension EnvironmentValues {
    /// Observable Weather Atlas theme manager.
    /// `@Entry` is SwiftUI's modern way to define a custom Environment value;
    /// its stable shared default keeps previews and screens usable by default.
    @Entry var appTheme: AppTheme = .shared
}

// MARK: - Internal View Modifiers

/// Applies the same one-color semantic tint as the matching Map marker.
/// The modifier reads the environment at render time, so symbols automatically
/// recolor if the person changes the theme while a screen remains visible.
private struct WeatherIconStyleModifier: ViewModifier {
    /// Active theme palette.
    @Environment(\.appTheme) private var theme
    /// The semantic weather tone that selects the matching Map-dot tint.
    let tone: WeatherIconTone

    /// Applies monochrome rendering so every visible part of a condition symbol
    /// uses the same semantic color as its Map marker.
    func body(content: Content) -> some View {
        content
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(theme.colors.weatherIconColor(for: tone))
    }
}

// MARK: - High-Contrast Translucent Surfaces

// These surface modifiers replace translucency with opaque, outlined surfaces
// when Reduce Transparency or Increase Contrast is enabled.
private extension View {
    /// Replaces translucency with an opaque outlined surface when required.
    /// This is a private building block used by the card modifier below, so each
    /// screen gets the same fallback behavior without branching on preferences.
    func highLegibilityGlass<Shape: InsettableShape>(
        theme: ThemeColors,
        contrast: ColorSchemeContrast,
        in shape: Shape
    ) -> some View {
        background(theme.glassFill, in: shape)
            .overlay(
                shape.stroke(
                    theme.primaryText.opacity(contrast == .increased ? 0.90 : 0.18),
                    lineWidth: contrast == .increased ? 1 : 0.8
                )
            )
    }
}

/// Translucent card surface shared by Detail View's report sections.
/// The generic `InsettableShape` accepts rounded rectangles, capsules, and other
/// SwiftUI shapes while preserving a matching clipped background and border.
private struct GlassCardModifier<Shape: InsettableShape>: ViewModifier {
    /// Active theme palette.
    @Environment(\.appTheme) private var theme
    /// System preference requiring a stronger card outline.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Resolved scheme used to tune translucent fill opacity.
    let colorScheme: ColorScheme
    /// Insettable card boundary.
    let shape: Shape
    /// Interactive glass is reserved for surfaces that actually receive input.
    let isInteractive: Bool

    @ViewBuilder
    /// Applies the detail-card surface appropriate to the OS and contrast setting.
    func body(content: Content) -> some View {
        // Increased contrast gets an opaque shape first; visual legibility
        // takes precedence over glass decoration.
        if colorSchemeContrast == .increased {
            content.highLegibilityGlass(
                theme: theme.colors,
                contrast: colorSchemeContrast,
                in: shape
            )
        } else if #available(iOS 26.0, *) {
            // Liquid Glass is used only on the OS that provides it. Older iOS
            // versions receive a native material fallback in the final branch.
            if isInteractive {
                // Interactive glass responds to touch/hover; static report cards
                // use the calmer regular style to avoid implying a button.
                content
                    .background(
                        theme.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22),
                        in: shape
                    )
                    .glassEffect(.regular.interactive(), in: shape)
                    .overlay(
                        shape.stroke(
                            theme.colors.primaryText.opacity(0.16),
                            lineWidth: 0.6
                        )
                    )
            } else {
                content
                    .background(
                        theme.colors.glassFill.opacity(colorScheme == .dark ? 0.18 : 0.22),
                        in: shape
                    )
                    .glassEffect(.regular, in: shape)
                    .overlay(
                        shape.stroke(
                            theme.colors.primaryText.opacity(0.16),
                            lineWidth: 0.6
                        )
                    )
            }
        } else {
            // `.ultraThinMaterial` is the closest broadly available native
            // approximation of the translucent surface on pre-iOS-26 systems.
            content
                .background(.ultraThinMaterial, in: shape)
                .background(
                    theme.colors.glassFill.opacity(colorScheme == .dark ? 0.30 : 0.38),
                    in: shape
                )
                .overlay(
                    shape.stroke(
                        theme.colors.primaryText.opacity(0.16),
                        lineWidth: 0.6
                    )
                )
        }
    }
}

/// Applies the warm Weather Atlas canvas while retaining a native List or Form.
/// `scrollContentBackground(.hidden)` removes only the system canvas; List/Form
/// retain their scrolling, grouping, and interaction behavior.
private struct ScrollableBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
    }
}

/// Applies the palette canvas to native stacks and empty states.
/// `ignoresSafeArea()` fills behind system bars so a navigation stack has no
/// visible seam at the screen edge.
private struct ScreenBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.background(theme.colors.background.ignoresSafeArea())
    }
}

/// Applies a muted, condition-derived canvas behind an entire weather report.
/// A missing condition deliberately falls back to the normal app canvas rather
/// than implying a weather state that the source did not provide.
private struct WeatherConditionScreenBackgroundModifier: ViewModifier {
    @Environment(\.appTheme) private var theme
    let tone: WeatherIconTone?

    func body(content: Content) -> some View {
        content.background(
            theme.colors.weatherBackgroundColor(for: tone).ignoresSafeArea()
        )
    }
}

// MARK: - Public View Modifier APIs

extension View {
    /// Applies the Map marker's semantic color to a raw weather SF Symbol.
    /// Prefer the tone overload when the caller has normalized weather.
    func weatherIconStyle(for iconName: String) -> some View {
        modifier(WeatherIconStyleModifier(tone: WeatherIconTone(symbolName: iconName)))
    }

    /// Applies the exact Map marker color for a normalized weather tone.
    /// This avoids losing condition detail when multiple conditions share one
    /// canonical SF Symbol, such as partly sunny and partly cloudy.
    func weatherIconStyle(for tone: WeatherIconTone) -> some View {
        modifier(WeatherIconStyleModifier(tone: tone))
    }

    /// Wraps static report content in the shared translucent card treatment.
    /// Call this for information-only surfaces; use the interactive variant only
    /// when the wrapped content is actually a control.
    func detailTranslucentCard<Shape: InsettableShape>(colorScheme: ColorScheme, in shape: Shape) -> some View {
        modifier(
            GlassCardModifier(
                colorScheme: colorScheme,
                shape: shape,
                isInteractive: false
            )
        )
    }

    /// Wraps an input surface in the app's interactive floating glass treatment.
    func weatherInteractiveGlass<Shape: InsettableShape>(
        colorScheme: ColorScheme,
        in shape: Shape
    ) -> some View {
        modifier(
            GlassCardModifier(
                colorScheme: colorScheme,
                shape: shape,
                isInteractive: true
            )
        )
    }

    /// Gives comparable report and planning actions one native presentation.
    /// On iOS 26 this is Apple's interactive Liquid Glass capsule; earlier
    /// deployments retain the closest native bordered control instead of a
    /// hand-built material imitation.
    @ViewBuilder
    func weatherGlassActionStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    /// Keeps system List/Form behavior while replacing only its canvas color.
    func weatherScrollableBackground() -> some View {
        modifier(ScrollableBackgroundModifier())
    }

    /// Uses the active Weather Atlas canvas behind native screen content.
    func weatherScreenBackground() -> some View {
        modifier(ScreenBackgroundModifier())
    }

    /// Uses the selected condition's muted semantic color as a report canvas.
    /// This is paired with `weatherIconStyle(for:)` so the hero icon and
    /// background always share one theme-defined weather vocabulary.
    func weatherConditionScreenBackground(
        for tone: WeatherIconTone?
    ) -> some View {
        modifier(WeatherConditionScreenBackgroundModifier(tone: tone))
    }

}
