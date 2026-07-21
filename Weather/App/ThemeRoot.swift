//
//  ThemeRoot.swift
//  Weather
//
//  Purpose: Applies theme, locale, text-size, contrast, and motion settings at the app root.
//

import SwiftUI

/// Outer layer: sets the preferred color scheme so the inner layer reads the correct one.
struct ThemeRoot: View {
    let theme: AppTheme
    let appLocale: Locale
    let weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ThemeContent(
            theme: theme,
            appLocale: appLocale,
            weatherService: weatherService
        )
            .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
    }
}

/// Inner layer reads `colorScheme` after the preference has been applied, so
/// automatic mode sees the system value and forced modes see their override.
private struct ThemeContent: View {
    let theme: AppTheme
    let appLocale: Locale
    let weatherService: WeatherService
    @Environment(\.colorScheme) private var colorScheme
    // Propagate Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    // Read Reduce Motion once at the app root so every screen follows it.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue

    private var preferredDynamicTypeSize: DynamicTypeSize {
        AppTextSizeLevel.level(clamping: appTextSizeLevel).dynamicTypeSize
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        min(
            max(
                useSystemTextSize ? systemDynamicTypeSize : preferredDynamicTypeSize,
                AppTextSizeLevel.minimumDynamicTypeSize
            ),
            AppTextSizeLevel.maximumDynamicTypeSize
        )
    }

    var body: some View {
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        ContentView(weatherService: weatherService)
            .environment(\.locale, appLocale)
            .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
            .environment(\.appTheme, theme)
            .tint(resolvedColors.accent)
            // Disable app-supplied animation without altering state transitions.
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                theme.systemScheme = newScheme
            }
            .onChange(of: colorSchemeContrast, initial: true) { _, newContrast in
                theme.systemContrast = newContrast
            }
    }
}
