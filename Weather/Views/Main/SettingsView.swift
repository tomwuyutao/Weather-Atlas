//
//  SettingsView.swift
//  Weather
//
//  Purpose: Provides preferences for units, language, appearance, and related
//  settings screens.
//

import SwiftUI
import UIKit
import WeatherKit

// MARK: - Settings Screen

/// Native form-based preferences, help, attribution, and support screen.
struct SettingsView: View {
    // MARK: Stored Preferences

    /// Persisted raw temperature preference.
    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.defaultRawValue
    /// Persisted distance preference used for visibility.
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.defaultRawValue
    /// Persisted in-app language identifier.
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    /// Whether typography follows the system Dynamic Type category.
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    /// Persisted custom text-size step when system sizing is disabled.
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue
    /// Shared weather service supplying attribution metadata.
    let weatherService: WeatherService
    /// Callback that dismisses Settings and starts tutorial replay.
    let onReplayTutorial: () -> Void
    /// Clears persisted app data and restarts first-launch onboarding.
    let onResetApp: () -> Void
    /// Native sheet dismissal action.
    @Environment(\.dismiss) private var dismiss
    /// Active semantic palette and theme manager.
    @Environment(\.appTheme) private var theme
    /// App-selected locale used by Settings copy.
    @Environment(\.locale) private var locale
    /// Resolved appearance used by form surfaces.
    @Environment(\.colorScheme) private var colorScheme
    /// System text category shown when automatic sizing is enabled.
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    /// Native URL opener for legal and support links.
    @Environment(\.openURL) private var openURL

    /// Controls the temporary copied-email confirmation.
    @State private var showingEmailCopied = false
    /// Whether the Attributions navigation destination is active.
    @State private var showingAttributions = false
    /// Whether the Units navigation destination is active.
    @State private var showingUnits = false
    /// Whether the Language navigation destination is active.
    @State private var showingLanguage = false
    /// Whether the Text Size navigation destination is active.
    @State private var showingTextSize = false
    /// Whether the Theme navigation destination is active.
    @State private var showingTheme = false
    /// Controls confirmation before destructive full-app reset.
    @State private var showingResetAppConfirmation = false
    /// Continuous slider value mapped back to discrete text-size steps.
    @State private var textSizeSliderValue = Double(AppTextSizeLevel.defaultRawValue)
    /// Whether a text-size drag is currently suppressing navigation pop gestures.
    @State private var isDraggingTextSizeSlider = false

    // MARK: Resolved Preferences

    /// Clamped custom text-size step represented by persisted state.
    private var selectedTextSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel.level(clamping: appTextSizeLevel)
    }

    // MARK: View Body

    @ViewBuilder
    /// Builds the Settings navigation stack and all preference destinations.
    var body: some View {
        NavigationStack {
            settingsForm
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localizedString("Settings", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                ToolbarItem(placement: .topBarLeading) {
                    // Dismiss Settings from its root toolbar.
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationDestination(isPresented: $showingAttributions) {
                attributionsForm
                    .navigationTitle(localizedString("Attributions", locale: locale))
            }
            .navigationDestination(isPresented: $showingUnits) {
                unitsForm
                    .navigationTitle(localizedString("Units", locale: locale))
            }
            .navigationDestination(isPresented: $showingLanguage) {
                languageForm
                    .navigationTitle(localizedString("Language", locale: locale))
            }
            .navigationDestination(isPresented: $showingTextSize) {
                textSizeForm
                    .navigationTitle(localizedString("Text Size", locale: locale))
            }
            .navigationDestination(isPresented: $showingTheme) {
                themeForm
                    .navigationTitle(localizedString("Theme", locale: locale))
            }
        }
        // Keep the back-swipe recognizer disabled for the entire lifetime of the
        // text-size destination. The slider changes Dynamic Type live, which can
        // otherwise briefly rebuild its own view and re-enable the gesture mid-drag.
        .background(NavigationPopGestureDisabler(isDisabled: showingTextSize))
        .background(theme.colors.background.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .presentationBackground(theme.colors.background)
        // Apply the user's system or explicit text-size choice throughout Settings.
        .environment(
            \.dynamicTypeSize,
            min(
                max(
                    useSystemTextSize ? systemDynamicTypeSize : selectedTextSizeLevel.dynamicTypeSize,
                    AppTextSizeLevel.minimumDynamicTypeSize
                ),
                AppTextSizeLevel.maximumDynamicTypeSize
            )
        )
    }

    // MARK: Adaptive Appearance

    /// Semantic background used by native form rows.
    private var settingsRowBackground: Color {
        theme.colors.settingsRowFill
    }

    /// Semantic canvas used behind native form sections.
    private var settingsFormBackground: Color {
        theme.colors.background
    }

    // MARK: Main Settings Form

    /// Builds root preference, Help, attribution, and support sections.
    private var settingsForm: some View {
        Form {
            Section {
                settingsNavigationRow(
                    localizedString("Units", locale: locale),
                    // Show the validated, resolved temperature preference.
                    value: (TemperatureUnit(rawValue: temperatureUnit) ?? .automatic)
                        .resolved
                        .displayName(locale: locale),
                    systemImage: "ruler",
                    action: { showingUnits = true }
                )

                settingsNavigationRow(
                    localizedString("Language", locale: locale),
                    value: languageDisplayName(for: appLanguage),
                    systemImage: "globe",
                    action: { showingLanguage = true }
                )

                settingsNavigationRow(
                    localizedString("Text Size", locale: locale),
                    // Summarize whether text follows the system or the custom step.
                    value: useSystemTextSize
                        ? localizedString("System", locale: locale)
                        : selectedTextSizeLevel.displayName(locale: locale),
                    systemImage: "textformat.size",
                    action: { showingTextSize = true }
                )

                settingsNavigationRow(
                    localizedString("Theme", locale: locale),
                    value: theme.style.displayName(locale: locale),
                    systemImage: "circle.lefthalf.filled",
                    action: { showingTheme = true }
                )
            } header: {
                settingsSectionHeader(localizedString("General", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

            Section {
                Button {
                    onReplayTutorial()
                } label: {
                    settingsLabel(localizedString("Replay Tutorial", locale: locale), systemImage: "play.circle")
                }

                Button(role: .destructive) {
                    showingResetAppConfirmation = true
                } label: {
                    settingsLabel(
                        localizedString("Clear Data and Reset App", locale: locale),
                        systemImage: "trash"
                    )
                }
            } header: {
                settingsSectionHeader(localizedString("Help", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

            Section {
                if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   !appVersion.isEmpty {
                    settingsInfoRow(
                        localizedString("Version", locale: locale),
                        value: appVersion,
                        systemImage: "info.circle"
                    )
                }
                settingsLinkRow(
                    localizedString("Website", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "safari",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas-Site/")
                )
                settingsLinkRow(
                    localizedString("Privacy Policy", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "hand.raised",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas-Site/privacy/")
                )
                // Open the full list of WeatherKit, MapKit, and city-data sources.
                Button {
                    showingAttributions = true
                } label: {
                    HStack {
                        settingsLabel(
                            localizedString("Attributions", locale: locale),
                            systemImage: "text.badge.checkmark"
                        )
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                sayHelloRow
            } header: {
                settingsSectionHeader(localizedString("About", locale: locale))
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        .task {
            // Migrate the obsolete automatic-unit raw value to the current contract.
            if TemperatureUnit(rawValue: temperatureUnit) == .automatic {
                temperatureUnit = TemperatureUnit.systemDefault.rawValue
            }
            // Load Apple Weather attribution once for the legal-source row.
            if weatherService.weatherAttribution == nil {
                do {
                    weatherService.weatherAttribution = try await weatherService.weatherKitService.attribution
                } catch { }
            }
        }
        .alert(localizedString("Clear Data and Reset App", locale: locale), isPresented: $showingResetAppConfirmation) {
            Button(localizedString("Cancel", locale: locale), role: .cancel) {}
            Button(localizedString("Reset App", locale: locale), role: .destructive) {
                onResetApp()
            }
        } message: {
            Text(localizedString("This removes your lists, saved cities, preferences, and cached weather, then restarts setup.", locale: locale))
        }
    }

    // MARK: Language Preferences

    /// Builds one full-width row for every supported in-app language.
    private var languageForm: some View {
        Form {
            Section {
                ForEach(AppLanguageDefaults.supportedLanguageCodes, id: \.self) { languageCode in
                    settingsSelectionRow(
                        title: languageDisplayName(for: languageCode),
                        isSelected: appLanguage == languageCode,
                        action: { requestLanguageChange(to: languageCode) }
                    )
                }
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
    }

    /// Returns each language's self-name so it remains recognizable in any locale.
    private func languageDisplayName(for languageCode: String) -> String {
        switch languageCode {
        case "en": return "English"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "it": return "Italiano"
        case "ja": return "日本語"
        case "ko": return "한국어"
        case "pt": return "Português"
        case "ru": return "Русский"
        case "zh-Hans": return "简体中文"
        case "es": return "Español"
        case "zh-Hant": return "繁體中文"
        default: return languageCode
        }
    }

    /// Applies interface-language changes without altering stored place names.
    private func requestLanguageChange(to languageCode: String) {
        guard languageCode != appLanguage else { return }
        appLanguage = languageCode
    }

    // MARK: Theme Preferences

    /// Builds five full-width theme selection rows.
    private var themeForm: some View {
        Form {
            Section {
                ForEach(AppThemeStyle.allCases, id: \.rawValue) { style in
                    Button {
                        theme.style = style
                    } label: {
                        HStack(spacing: 12) {
                            themeIndicator(for: style)

                            Text(style.displayName(locale: locale))
                                .foregroundStyle(theme.colors.primaryText)

                            Spacer(minLength: 8)

                            if theme.style == style {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
    }

    /// Previews the light, charcoal, and black canvases used by each theme mode.
    private func themeIndicator(for style: AppThemeStyle) -> some View {
        // Keep the indicator's charcoal sample fixed to the product's exact
        // Dark canvas instead of deriving it from the currently resolved theme.
        let darkIndicatorColor = Color(hex: 0x262626)
        let fills: (topLeading: Color, bottomTrailing: Color)
        switch style {
        case .automatic:
            fills = (AppPalette.light.background, darkIndicatorColor)
        case .automaticBlack:
            fills = (AppPalette.light.background, AppPalette.black.background)
        case .light:
            fills = (AppPalette.light.background, AppPalette.light.background)
        case .dark:
            fills = (darkIndicatorColor, darkIndicatorColor)
        case .black:
            fills = (AppPalette.black.background, AppPalette.black.background)
        }

        return Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(fills.bottomTrailing)
            )

            // Automatic modes divide their two possible canvases diagonally.
            var topLeadingHalf = Path()
            topLeadingHalf.move(to: .zero)
            topLeadingHalf.addLine(to: CGPoint(x: size.width, y: 0))
            topLeadingHalf.addLine(to: CGPoint(x: 0, y: size.height))
            topLeadingHalf.closeSubpath()
            context.fill(topLeadingHalf, with: .color(fills.topLeading))
        }
        .frame(width: 32, height: 32)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.colors.secondaryText.opacity(0.28), lineWidth: 0.75)
        }
    }

    /// Builds automatic sizing toggle, preview, and custom slider controls.
    private var textSizeForm: some View {
        Form {
            Section {
                Toggle(isOn: $useSystemTextSize) {
                    Text(localizedString("Use System Text Size", locale: locale))
                        .foregroundStyle(theme.colors.primaryText)
                }
                .tint(theme.colors.accent)

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        Text(verbatim: "A")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 44)

                        steppedTextSizeSlider

                        Text(verbatim: "A")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(width: 44)
                    }
                    .opacity(useSystemTextSize ? 0.42 : 1)

                    // Name the custom slider step, or System while it is disabled.
                    Text(
                        useSystemTextSize
                            ? localizedString("System", locale: locale)
                            : (AppTextSizeLevel(rawValue: Int(textSizeSliderValue.rounded()))
                                ?? selectedTextSizeLevel).displayName(locale: locale)
                    )
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowBackground(settingsRowBackground)

        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        .onAppear {
            let level = selectedTextSizeLevel
            appTextSizeLevel = level.rawValue
            textSizeSliderValue = Double(level.rawValue)
        }
        .onChange(of: appTextSizeLevel) { _, newValue in
            guard !isDraggingTextSizeSlider else { return }
            let level = AppTextSizeLevel.level(clamping: newValue)
            if newValue != level.rawValue {
                appTextSizeLevel = level.rawValue
            }
            textSizeSliderValue = Double(level.rawValue)
        }
    }

    /// Bridges a continuous native slider to supported discrete size steps.
    private var steppedTextSizeSlider: some View {
        Slider(
            value: Binding(
                get: { textSizeSliderValue },
                set: { newValue in
                    let clampedValue = min(
                        max(newValue, Double(AppTextSizeLevel.minimumSelectableRawValue)),
                        Double(AppTextSizeLevel.maximumSelectableRawValue)
                    )
                    textSizeSliderValue = clampedValue
                    appTextSizeLevel = Int(clampedValue.rounded())
                }
            ),
            in: Double(AppTextSizeLevel.minimumSelectableRawValue)...Double(AppTextSizeLevel.maximumSelectableRawValue),
            step: 1,
            onEditingChanged: { isEditing in
                isDraggingTextSizeSlider = isEditing
                if !isEditing {
                    textSizeSliderValue = Double(appTextSizeLevel)
                }
            }
        )
        .disabled(useSystemTextSize)
        .tint(theme.colors.accent)
        .frame(height: 36)
    }

    // MARK: Units

    /// Builds selectable temperature and distance-unit rows.
    private var unitsForm: some View {
        Form {
            Section {
                // Automatic is migrated above, so Settings exposes explicit units.
                ForEach([TemperatureUnit.celsius, .fahrenheit], id: \.rawValue) { unit in
                    settingsSelectionRow(
                        title: unit.displayName(locale: locale),
                        // Compare against the validated, resolved stored unit.
                        isSelected: (TemperatureUnit(rawValue: temperatureUnit) ?? .automatic).resolved == unit,
                        action: { temperatureUnit = unit.rawValue }
                    )
                }
            } header: {
                settingsSectionHeader(localizedString("Temperature", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

            Section {
                ForEach(DistanceUnit.allCases, id: \.rawValue) { unit in
                    settingsSelectionRow(
                        title: unit.displayName(locale: locale),
                        isSelected: (DistanceUnit(rawValue: distanceUnit) ?? .kilometers) == unit,
                        action: { distanceUnit = unit.rawValue }
                    )
                }
            } header: {
                settingsSectionHeader(localizedString("Distance", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        .onAppear {
            // Migrate the obsolete automatic-unit raw value to the current contract.
            if TemperatureUnit(rawValue: temperatureUnit) == .automatic {
                temperatureUnit = TemperatureUnit.systemDefault.rawValue
            }
        }
    }

    // MARK: About and Attributions

    /// Builds WeatherKit, MapKit, and city-catalog attribution sections.
    private var attributionsForm: some View {
        Form {
            Section(localizedString("Weather", locale: locale)) {
                weatherAttributionRows
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Maps", locale: locale)) {
                mapAttributionRows
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Search", locale: locale)) {
                searchAttributionRows
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Cities Data", locale: locale)) {
                cityCatalogAttributionRows
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("City Name Translations", locale: locale)) {
                cityTranslationAttributionRows
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
    }

    // MARK: Attribution Rows

    @ViewBuilder
    /// Apple Weather mark and legal link rows.
    private var weatherAttributionRows: some View {
        settingsInfoRow(
            localizedString("Weather Data", locale: locale),
            // Apple Weather's attribution mark is fixed by the provider.
            value: " Weather",
            systemImage: "cloud.sun"
        )
        settingsLinkRow(
            localizedString("Weather Legal Sources", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            // The legal URL is unavailable until WeatherKit attribution loads.
            url: weatherService.weatherAttribution?.legalPageURL
        )
        settingsLinkRow(
            localizedString("About WeatherKit", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://developer.apple.com/weatherkit/")
        )
    }

    @ViewBuilder
    /// Apple Maps attribution and legal link rows.
    private var mapAttributionRows: some View {
        settingsInfoRow(
            localizedString("Map Data", locale: locale),
            value: "\u{F8FF} Map",
            systemImage: "map"
        )
        settingsLinkRow(
            localizedString("Maps Legal Sources", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://www.apple.com/legal/internet-services/maps/legal-en.html")
        )
        settingsLinkRow(
            localizedString("About MapKit", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://developer.apple.com/documentation/mapkit/")
        )
    }

    @ViewBuilder
    /// Online place-search source and its documentation link.
    private var searchAttributionRows: some View {
        settingsInfoRow(
            localizedString("Search", locale: locale),
            value: "Open-Meteo / GeoNames",
            systemImage: "magnifyingglass"
        )
        settingsLinkRow(
            "Open-Meteo",
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://open-meteo.com/en/docs/geocoding-api")
        )
    }

    @ViewBuilder
    /// Bundled city-catalog source and its documentation link.
    private var cityCatalogAttributionRows: some View {
        settingsInfoRow(
            localizedString("Cities Data", locale: locale),
            value: localizedString("SimpleMaps World Cities", locale: locale),
            systemImage: "building.2"
        )
        settingsLinkRow(
            localizedString("About SimpleMaps", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://simplemaps.com/data/world-cities")
        )
    }

    @ViewBuilder
    /// City-name translation source and its documentation link.
    private var cityTranslationAttributionRows: some View {
        settingsInfoRow(
            localizedString("City Name Translations", locale: locale),
            value: "GeoNames",
            systemImage: "character.book.closed"
        )
        settingsLinkRow(
            localizedString("About GeoNames", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://www.geonames.org/about.html")
        )
    }

    // MARK: Reusable Rows

    /// Builds a standard icon-and-title Settings label.
    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.dotSun)
        }
    }

    /// Builds a consistent native form section header.
    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
    }

    /// Builds a read-only labeled Settings value row.
    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.secondaryText)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
    }

    /// Builds a value-summary row that opens a nested destination.
    private func settingsNavigationRow(_ title: String, value: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(value)
                        .foregroundStyle(theme.colors.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                }
            } label: {
                settingsLabel(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
    }

    /// Builds a full-width selectable row with trailing checkmark state.
    private func settingsSelectionRow(
        title: String,
        subtitle: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(theme.colors.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Support Actions

    /// Support-email row with a temporary copied confirmation.
    private var sayHelloRow: some View {
        Button {
            // Copy the support address before presenting native confirmation.
            UIPasteboard.general.string = "yutao5726@gmail.com"
            showingEmailCopied = true
        } label: {
            LabeledContent {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(theme.colors.secondaryText)
            } label: {
                settingsLabel(localizedString("Say Hello", locale: locale), systemImage: "envelope")
            }
        }
        .buttonStyle(.plain)
        .alert(localizedString("Email Copied", locale: locale), isPresented: $showingEmailCopied) {
            Button(localizedString("OK", locale: locale), role: .cancel) {}
        }
    }

    @ViewBuilder
    /// Builds a native external-link row disabled when its URL is unavailable.
    private func settingsLinkRow(_ title: String, value: String, systemImage: String, url: URL?) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(value)
                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                } label: {
                    settingsLabel(title, systemImage: systemImage)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Navigation Gesture Bridge

/// Temporarily disables interactive navigation pop while dragging the slider.
private struct NavigationPopGestureDisabler: UIViewControllerRepresentable {
    /// Whether the enclosing navigation controller's pop gesture is disabled.
    let isDisabled: Bool

    /// Retains the gesture's previous enabled state for restoration.
    final class Coordinator {
        /// Weak reference avoids extending UIKit gesture lifetime.
        weak var gestureRecognizer: UIGestureRecognizer?
        /// Original enabled state captured before the first disable.
        var originalIsEnabled: Bool?
    }

    /// Creates storage for the prior gesture state.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Creates an invisible controller used to locate its navigation controller.
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    /// Applies the desired gesture state after the controller joins navigation.
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let gestureRecognizer = uiViewController.navigationController?.interactivePopGestureRecognizer else {
                return
            }
            context.coordinator.gestureRecognizer = gestureRecognizer

            if isDisabled {
                if context.coordinator.originalIsEnabled == nil {
                    context.coordinator.originalIsEnabled = gestureRecognizer.isEnabled
                }
                gestureRecognizer.isEnabled = false
            } else if let originalIsEnabled = context.coordinator.originalIsEnabled {
                gestureRecognizer.isEnabled = originalIsEnabled
                context.coordinator.originalIsEnabled = nil
            }
        }
    }

    /// Restores the gesture state captured before this representable intervened.
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let originalIsEnabled = coordinator.originalIsEnabled {
            coordinator.gestureRecognizer?.isEnabled = originalIsEnabled
        }
    }
}

#Preview("Settings View") {
    SettingsView(weatherService: WeatherService(), onReplayTutorial: {}, onResetApp: {})
}
