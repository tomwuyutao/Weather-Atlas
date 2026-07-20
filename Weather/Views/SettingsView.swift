//
//  SettingsView.swift
//  Weather
//
//  Purpose: Provides preferences for units, language, appearance, and related
//  settings screens.
//

import SwiftUI
import UIKit

// MARK: - Unit Preferences

enum TemperatureUnit: String, CaseIterable {
    case automatic = "automatic"
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    static var systemDefault: TemperatureUnit {
        let sample = Measurement(value: 0, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather).locale(.autoupdatingCurrent))
        if sample.localizedCaseInsensitiveContains("F") {
            return .fahrenheit
        }
        if sample.localizedCaseInsensitiveContains("C") {
            return .celsius
        }
        return .celsius
    }

    static let defaultRawValue = TemperatureUnit.systemDefault.rawValue

    static var settingsCases: [TemperatureUnit] {
        [.celsius, .fahrenheit]
    }

    var resolved: TemperatureUnit {
        switch self {
        case .automatic:
            return Self.systemDefault
        case .celsius, .fahrenheit:
            return self
        }
    }

    func displayName(locale: Locale = .current) -> String {
        switch resolved {
        case .celsius: return localizedString("Celsius (°C)", locale: locale)
        case .fahrenheit: return localizedString("Fahrenheit (°F)", locale: locale)
        case .automatic: return resolved.displayName(locale: locale)
        }
    }

    private var measurementUnit: UnitTemperature {
        switch resolved {
        case .celsius: return .celsius
        case .fahrenheit: return .fahrenheit
        case .automatic: return resolved.measurementUnit
        }
    }

    func display(_ celsius: Double) -> String {
        let temperature = Measurement(value: celsius, unit: UnitTemperature.celsius)
            .converted(to: measurementUnit)
            .value
        return "\(Int(temperature.rounded()))°"
    }

}

enum AppTextSizeLevel: Int, CaseIterable {
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5

    static let defaultRawValue = AppTextSizeLevel.large.rawValue
    static let minimumDynamicTypeSize: DynamicTypeSize = .small
    static let maximumDynamicTypeSize: DynamicTypeSize = .xxLarge
    static let minimumSelectableRawValue = AppTextSizeLevel.small.rawValue
    static let maximumSelectableRawValue = AppTextSizeLevel.xxLarge.rawValue

    static func level(clamping rawValue: Int) -> AppTextSizeLevel {
        let clampedRawValue = min(
            max(rawValue, minimumSelectableRawValue),
            maximumSelectableRawValue
        )
        return AppTextSizeLevel(rawValue: clampedRawValue) ?? .large
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .xLarge
        case .xxLarge: return .xxLarge
        }
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .small: return localizedString("Small", locale: locale)
        case .medium: return localizedString("Medium", locale: locale)
        case .large: return localizedString("Default", locale: locale)
        case .xLarge: return localizedString("Large", locale: locale)
        case .xxLarge: return localizedString("Extra Large", locale: locale)
        }
    }
}

// MARK: - Settings Screen

struct SettingsView: View {
    // MARK: Stored Preferences

    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.defaultRawValue
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("useSystemTextSize") private var useSystemTextSize: Bool = true
    @AppStorage("appTextSizeLevel") private var appTextSizeLevel: Int = AppTextSizeLevel.defaultRawValue
    let weatherService: WeatherService
    let onReplayTutorial: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var systemDynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var showingEmailCopied = false
    @State private var showingAttributions = false
    @State private var showingUnits = false
    @State private var showingTextSize = false
    @State private var textSizeSliderValue = Double(AppTextSizeLevel.defaultRawValue)
    @State private var isDraggingTextSizeSlider = false

    // MARK: Resolved Preferences

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .automatic
    }

    private var unitsSummary: String {
        selectedUnit.resolved.displayName(locale: locale)
    }

    private var selectedTextSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel.level(clamping: appTextSizeLevel)
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        min(
            max(
                useSystemTextSize ? systemDynamicTypeSize : selectedTextSizeLevel.dynamicTypeSize,
                AppTextSizeLevel.minimumDynamicTypeSize
            ),
            AppTextSizeLevel.maximumDynamicTypeSize
        )
    }

    private var textSizeSummary: String {
        useSystemTextSize ? localizedString("System", locale: locale) : selectedTextSizeLevel.displayName(locale: locale)
    }

    // MARK: View Body

    @ViewBuilder
    var body: some View {
        NavigationStack {
            settingsForm
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(localizedString("Settings", locale: locale))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(settingsTitleColor)
                }

                ToolbarItem(placement: .topBarLeading) {
                    settingsCloseButton
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
            .navigationDestination(isPresented: $showingTextSize) {
                textSizeForm
                    .navigationTitle(localizedString("Text Size", locale: locale))
            }
        }
        // Keep the back-swipe recognizer disabled for the entire lifetime of the
        // text-size destination. The slider changes Dynamic Type live, which can
        // otherwise briefly rebuild its own view and re-enable the gesture mid-drag.
        .background(NavigationPopGestureDisabler(isDisabled: showingTextSize))
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .presentationBackground(theme.colors.mapOcean)
        // Apply the user's system or explicit text-size choice throughout Settings.
        .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
    }

    // MARK: Toolbar

    @ViewBuilder
    private var settingsCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(settingsTitleColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var settingsRowBackground: Color {
        theme.colors.settingsRowFill
    }

    private var settingsFormBackground: Color {
        theme.colors.mapOcean
    }

    private var settingsTitleColor: Color {
        theme.colors.primaryText
    }

    // MARK: Main Settings Form

    private var settingsForm: some View {
        Form {
            Section {
                settingsNavigationRow(
                    localizedString("Units", locale: locale),
                    value: unitsSummary,
                    systemImage: "ruler",
                    action: { showingUnits = true }
                )

                Picker(selection: Binding(get: { appLanguage }, set: { appLanguage = $0 })) {
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "Deutsch").tag("de")
                    Text(verbatim: "Italiano").tag("it")
                    Text(verbatim: "日本語").tag("ja")
                    Text(verbatim: "한국어").tag("ko")
                    Text(verbatim: "Português").tag("pt")
                    Text(verbatim: "Русский").tag("ru")
                    Text(verbatim: "简体中文").tag("zh-Hans")
                    Text(verbatim: "Español").tag("es")
                    Text(verbatim: "繁體中文").tag("zh-Hant")
                } label: {
                    settingsLabel(localizedString("Language", locale: locale), systemImage: "globe")
                }
                .tint(theme.colors.secondaryText)

                settingsNavigationRow(
                    localizedString("Text Size", locale: locale),
                    value: textSizeSummary,
                    systemImage: "textformat.size",
                    action: { showingTextSize = true }
                )

                Picker(selection: Binding(get: { theme.style }, set: { theme.style = $0 })) {
                    Text(localizedString("Light", locale: locale)).tag(AppThemeStyle.light)
                    Text(localizedString("Dark", locale: locale)).tag(AppThemeStyle.dark)
                    Text(localizedString("Auto", locale: locale)).tag(AppThemeStyle.automatic)
                } label: {
                    settingsLabel(localizedString("Theme", locale: locale), systemImage: "circle.lefthalf.filled")
                }
                .tint(theme.colors.secondaryText)
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
                } else {
                    WeatherDataUnavailableNotice(
                        message: localizedString("Missing app version data.", locale: locale)
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
                attributionsNavigationRow
                sayHelloRow
            } header: {
                settingsSectionHeader(localizedString("About", locale: locale))
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
            .background(settingsFormBackground)
        .task {
            normalizeLegacyAutomaticUnits()
            await weatherService.loadWeatherAttributionIfNeeded()
        }
    }

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

                    Text(textSizeSliderDescription)
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

    private var textSizeSliderDescription: String {
        guard !useSystemTextSize else {
            return localizedString("System", locale: locale)
        }
        let sliderLevel = AppTextSizeLevel(rawValue: Int(textSizeSliderValue.rounded())) ?? selectedTextSizeLevel
        return sliderLevel.displayName(locale: locale)
    }

    private var unitsForm: some View {
        Form {
            Section {
                ForEach(TemperatureUnit.settingsCases, id: \.rawValue) { unit in
                    settingsSelectionRow(
                        title: unit.displayName(locale: locale),
                        isSelected: selectedUnit.resolved == unit,
                        action: { temperatureUnit = unit.rawValue }
                    )
                }
            } header: {
                settingsSectionHeader(localizedString("Temperature", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        .onAppear {
            normalizeLegacyAutomaticUnits()
        }
    }

    private func normalizeLegacyAutomaticUnits() {
        if TemperatureUnit(rawValue: temperatureUnit) == .automatic {
            temperatureUnit = TemperatureUnit.systemDefault.rawValue
        }
    }

    // MARK: About and Attributions

    private var attributionsNavigationRow: some View {
        Button {
            showingAttributions = true
        } label: {
            HStack {
                settingsLabel(localizedString("Attributions", locale: locale), systemImage: "text.badge.checkmark")
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

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

            Section(localizedString("Cities", locale: locale)) {
                citiesAttributionRows
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
    }

    // MARK: Row Builders

    @ViewBuilder
    private var weatherAttributionRows: some View {
        settingsInfoRow(
            localizedString("Weather Data", locale: locale),
            value: weatherService.weatherAttributionMarkText,
            systemImage: "cloud.sun"
        )
        settingsLinkRow(
            localizedString("Weather Legal Sources", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: weatherService.weatherLegalPageURL
        )
        settingsLinkRow(
            localizedString("About WeatherKit", locale: locale),
            value: localizedString("View", locale: locale),
            systemImage: "doc.text",
            url: URL(string: "https://developer.apple.com/weatherkit/")
        )
    }

    @ViewBuilder
    private var mapAttributionRows: some View {
        settingsInfoRow(
            localizedString("Map Data", locale: locale),
            value: "\u{F8FF} " + localizedString("Apple Maps", locale: locale),
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
    private var citiesAttributionRows: some View {
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

    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.dotSun)
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
    }

    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.secondaryText)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
    }

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

    private var sayHelloRow: some View {
        Button {
            copySupportEmail()
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

    private func copySupportEmail() {
        let email = "yutao5726@gmail.com"
        UIPasteboard.general.string = email
    }

    @ViewBuilder
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

private struct NavigationPopGestureDisabler: UIViewControllerRepresentable {
    let isDisabled: Bool

    final class Coordinator {
        weak var gestureRecognizer: UIGestureRecognizer?
        var originalIsEnabled: Bool?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

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

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        if let originalIsEnabled = coordinator.originalIsEnabled {
            coordinator.gestureRecognizer?.isEnabled = originalIsEnabled
        }
    }
}

#Preview("Settings View") {
    SettingsView(weatherService: WeatherService(), onReplayTutorial: {})
}
