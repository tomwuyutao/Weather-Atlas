//
//  WeatherApp.swift
//  Weather
//
//  Purpose: Defines app launch, first-run language defaults, and the root
//  environment applied to every window.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - First-Run Language Selection

/// Selects a supported first-run language without overriding later user choices.
enum AppLanguageDefaults {
    /// Shared preference key read by the app and shortcut publisher.
    static let storageKey = "appLanguage"
    /// Language identifiers for which the bundled localization table is complete.
    static let supportedLanguageCodes = ["en", "fr", "de", "it", "ja", "ko", "pt", "ru", "zh-Hans", "es", "zh-Hant"]

    /// Seeds the language preference only when no app-specific choice exists.
    static func configureInitialLanguage() {
        // Do this once only. From then on, Settings owns the explicit choice.
        guard UserDefaults.standard.object(forKey: storageKey) == nil else { return }
        UserDefaults.standard.set(preferredDeviceLanguage(), forKey: storageKey)
    }

    /// Returns the first supported language in the device preference order.
    /// A full app reset uses this too, so it restores the same language a new
    /// installation would choose instead of arbitrarily returning to English.
    static func preferredDeviceLanguage() -> String {
        // Use the first device preference the bundled localization table supports.
        for identifier in Locale.preferredLanguages {
            if let supportedCode = supportedLanguageCode(for: identifier) {
                return supportedCode
            }
        }
        return "en"
    }

    /// Normalizes an Apple locale identifier to a bundled language code.
    private static func supportedLanguageCode(for identifier: String) -> String? {
        // iOS may return either underscore or hyphen locale separators. Work
        // with one normalized form before comparing the bundled languages.
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh-Hans") { return "zh-Hans" }
        if normalized.hasPrefix("zh-Hant") { return "zh-Hant" }

        let components = normalized.split(separator: "-").map(String.init)
        guard let languageCode = components.first else { return nil }
        if languageCode == "zh" {
            // Bare Chinese preferences need a region-based script choice.
            let regionCode = components.dropFirst().first?.uppercased()
            return ["TW", "HK", "MO"].contains(regionCode) ? "zh-Hant" : "zh-Hans"
        }
        return supportedLanguageCodes.contains(languageCode) ? languageCode : nil
    }
}

// MARK: - App Text-Size Policy

/// Resolves the text-size choice shared by SwiftUI content and UIKit surfaces.
enum AppTextSizePolicy {
    /// Preference key used by the Follow System toggle.
    static let useSystemKey = "useSystemTextSize"
    /// Preference key used by the app-specific size menu.
    static let appLevelKey = "appTextSizeLevel"

    /// Clamps either the system preference or the custom preference to the
    /// exact Small...Large range exposed by the app.
    static func effectiveDynamicTypeSize(
        useSystem: Bool,
        appLevel: Int,
        systemCategory: UIContentSizeCategory
    ) -> DynamicTypeSize {
        let requestedSize = useSystem
            ? DynamicTypeSize(systemCategory) ?? .large
            : AppTextSizeLevel.level(clamping: appLevel).dynamicTypeSize

        return min(
            max(requestedSize, AppTextSizeLevel.small.dynamicTypeSize),
            AppTextSizeLevel.xLarge.dynamicTypeSize
        )
    }

    /// Rebuilds the current policy directly from persisted preferences. Scene
    /// lifecycle callbacks use this before the SwiftUI root is mounted.
    @MainActor
    static func currentEffectiveContentSizeCategory(
        defaults: UserDefaults = .standard
    ) -> UIContentSizeCategory {
        let useSystem = defaults.object(forKey: useSystemKey) == nil
            ? true
            : defaults.bool(forKey: useSystemKey)
        let appLevel = defaults.object(forKey: appLevelKey) == nil
            ? AppTextSizeLevel.defaultRawValue
            : defaults.integer(forKey: appLevelKey)

        return UIContentSizeCategory(
            effectiveDynamicTypeSize(
                useSystem: useSystem,
                appLevel: appLevel,
                systemCategory: UIApplication.shared.preferredContentSizeCategory
            )
        )
    }

    /// Applies the resolved category only to the window scene being updated.
    @MainActor
    static func apply(
        _ category: UIContentSizeCategory,
        to scene: UIWindowScene
    ) {
        // UIKit throws when the getter is read before this trait has an
        // override, so assign directly instead of attempting an equality guard.
        scene.traitOverrides.preferredContentSizeCategory = category
    }

    /// Applies the persisted app policy to one connecting or returning scene.
    @MainActor
    static func applyCurrentPreferences(to scene: UIWindowScene) {
        apply(currentEffectiveContentSizeCategory(), to: scene)
    }
}

// MARK: - App Entry Point

/// Process entry point that creates shared state before opening themed windows.
@main
struct WeatherApp: App {
    /// UIKit delegate bridge used for Home Screen quick actions.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Persisted language identifier selected within the app.
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    /// Shared observable theme mode.
    @State private var theme = AppTheme.shared
    /// Shared place, weather, and current-location recommendation model.
    @State private var appModel: WeatherModel
    /// Shared tab, navigation, and modal presentation coordinator.
    @State private var router: AppNavigation
    /// Single queue for native alerts describing data that remains blank.
    @State private var missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state used by the offline-cache presentation.
    @State private var networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state for every app window.
    @State private var tutorial: TutorialPresentationState

    /// Creates the app's shared stores and navigation state.
    init() {
        // Both stores are created once and injected into the app-wide model,
        // so Your Location, Saved Places, Map, and widgets read the same data.
        AppLanguageDefaults.configureInitialLanguage()

        let placesStore = SavedPlacesStore()
        let recentSearches = RecentSearchStore()
        let missingDataAlerts = MissingDataAlertCenter()
        let networkConnectivity = NetworkConnectivity()

        let weatherStore = SavedPlacesWeatherStore(
            networkConnectivity: networkConnectivity
        )
        _appModel = State(
            initialValue: WeatherModel(
                placesStore: placesStore,
                weatherStore: weatherStore,
                recentSearches: recentSearches
            )
        )
        _router = State(initialValue: AppNavigation())
        _missingDataAlerts = State(initialValue: missingDataAlerts)
        _networkConnectivity = State(initialValue: networkConnectivity)
        _tutorial = State(initialValue: TutorialPresentationState())
    }

    /// Creates themed app windows backed by the shared place-owned model.
    var body: some Scene {
        // A `WindowGroup` supplies a separate SwiftUI window when the platform
        // supports it, while all windows receive the same app-level services.
        WindowGroup {
            ThemeRoot(
                theme: theme,
                appLocale: Locale(identifier: appLanguage),
                appModel: appModel,
                router: router,
                missingDataAlerts: missingDataAlerts,
                networkConnectivity: networkConnectivity,
                tutorial: tutorial
            )
        }
    }
}

// MARK: - Root Environment

/// Outer layer that applies the preferred scheme before inner content reads it.
struct ThemeRoot: View {
    /// User-selected theme mode.
    let theme: AppTheme
    /// Locale chosen in Settings.
    let appLocale: Locale
    /// Shared place and weather model.
    let appModel: WeatherModel
    /// Shared native navigation coordinator.
    let router: AppNavigation
    /// Shared native missing-data alert queue.
    let missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state.
    let networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state.
    let tutorial: TutorialPresentationState
    /// Applies the theme's scheme preference before constructing inner content.
    var body: some View {
        // Apply the preferred scheme outside `ThemeContent`. That lets the
        // inner environment read the final light/dark value, not a stale one.
        ThemeContent(
            theme: theme,
            appLocale: appLocale,
            appModel: appModel,
            router: router,
            missingDataAlerts: missingDataAlerts,
            networkConnectivity: networkConnectivity,
            tutorial: tutorial
        )
        .preferredColorScheme(theme.preferredColorScheme)
    }
}

/// Reads the effective scheme after the outer preference has been applied.
private struct ThemeContent: View {
    /// User-selected theme mode inherited from the outer root.
    let theme: AppTheme
    /// Locale propagated to formatters and localization lookups.
    let appLocale: Locale
    /// Shared model supplied to the root application view.
    let appModel: WeatherModel
    /// Shared navigation coordinator supplied to the root application view.
    let router: AppNavigation
    /// Shared native missing-data alert queue.
    let missingDataAlerts: MissingDataAlertCenter
    /// Shared system reachability state injected into every root screen.
    let networkConnectivity: NetworkConnectivity
    /// Shared first-run and contextual-tip state.
    let tutorial: TutorialPresentationState
    /// Effective scheme after the outer preferred-scheme override.
    @Environment(\.colorScheme) private var colorScheme
    /// Propagates Increase Contrast into the app's custom color palettes.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Disables custom interpolation throughout the app when Reduce Motion is on.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Reconciles the raw system preference after a suspended scene returns.
    @Environment(\.scenePhase) private var scenePhase
    /// Whether typography should follow the system rather than the in-app menu.
    @AppStorage(AppTextSizePolicy.useSystemKey) private var useSystemTextSize: Bool = true
    /// Persisted in-app text-size step used when system sizing is disabled.
    @AppStorage(AppTextSizePolicy.appLevelKey) private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue
    /// The device preference remains observable even while this scene applies
    /// its own capped UIKit trait for native menus and presentations.
    @State private var systemContentSizeCategory = UIApplication.shared.preferredContentSizeCategory

    /// Injects locale, text size, theme, tint, and contrast app-wide.
    var body: some View {
        // Resolve the custom palette after reading the system scheme and
        // contrast setting. Every descendant then receives matching colors.
        let resolvedColors = theme.colors(for: colorScheme, contrast: colorSchemeContrast)
        // Follow System still respects the same upper bound as the app's own
        // text-size menu. Resolve the exact category before applying SwiftUI's
        // dedicated modifier so system presentations inherit the same value.
        let effectiveDynamicTypeSize = AppTextSizePolicy.effectiveDynamicTypeSize(
            useSystem: useSystemTextSize,
            appLevel: appTextSizeLevel,
            systemCategory: systemContentSizeCategory
        )
        let effectiveContentSizeCategory = UIContentSizeCategory(effectiveDynamicTypeSize)
        ContentView(
            model: appModel,
            router: router,
            missingDataAlerts: missingDataAlerts,
            networkConnectivity: networkConnectivity,
            tutorial: tutorial
        )
            .environment(\.locale, appLocale)
            // The app stops at its largest supported text setting, including
            // when the person follows the system's text-size preference.
            .dynamicTypeSize(effectiveDynamicTypeSize)
            // SwiftUI's environment does not constrain UIKit-owned menus.
            // This zero-size probe updates only the hosting window scene.
            .background {
                SceneContentSizeCategoryOverride(
                    category: effectiveContentSizeCategory
                )
                .frame(width: 0, height: 0)
            }
            .environment(\.appTheme, theme)
            .environment(missingDataAlerts)
            .environment(networkConnectivity)
            .tint(resolvedColors.accent)
            // One root safeguard covers every current and future SwiftUI
            // animation in the app. The tutorial and pulsing Map marker also
            // skip their animation-only timing work at their source.
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .onChange(of: colorScheme, initial: true) { _, newScheme in
                // Retain the latest resolved system inputs so `AppTheme` can
                // compute its palette consistently outside this view as well.
                theme.systemScheme = newScheme
            }
            .onChange(of: colorSchemeContrast, initial: true) { _, newContrast in
                theme.systemContrast = newContrast
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIContentSizeCategory.didChangeNotification
                )
            ) { notification in
                let newCategory = notification.userInfo?[
                    UIContentSizeCategory.newValueUserInfoKey
                ] as? UIContentSizeCategory
                    ?? UIApplication.shared.preferredContentSizeCategory
                updateSystemContentSizeCategory(newCategory)
            }
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                guard newPhase == .active else { return }
                updateSystemContentSizeCategory(
                    UIApplication.shared.preferredContentSizeCategory
                )
            }
    }

    /// Stores only raw system changes; the effective value is derived in body.
    private func updateSystemContentSizeCategory(
        _ newCategory: UIContentSizeCategory
    ) {
        guard systemContentSizeCategory != newCategory else { return }
        systemContentSizeCategory = newCategory
    }
}

/// Bridges the effective category to the one UIKit scene hosting this view.
private struct SceneContentSizeCategoryOverride: UIViewRepresentable {
    /// Category already clamped to the app's supported range.
    let category: UIContentSizeCategory

    func makeUIView(context: Context) -> SceneContentSizeCategoryOverrideView {
        let view = SceneContentSizeCategoryOverrideView()
        view.category = category
        return view
    }

    func updateUIView(
        _ uiView: SceneContentSizeCategoryOverrideView,
        context: Context
    ) {
        uiView.category = category
        uiView.applyIfAttached()
    }
}

/// Applies the trait once its invisible probe has joined a concrete window.
private final class SceneContentSizeCategoryOverrideView: UIView {
    /// Latest category supplied by the SwiftUI root.
    var category: UIContentSizeCategory = .large

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyIfAttached()
    }

    /// Targets only this view's scene so one iPad window cannot alter another.
    func applyIfAttached() {
        guard let windowScene = window?.windowScene else { return }
        AppTextSizePolicy.apply(category, to: windowScene)
    }
}
