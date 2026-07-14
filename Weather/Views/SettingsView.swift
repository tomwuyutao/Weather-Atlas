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

enum DistanceUnit: String, CaseIterable {
    case automatic = "automatic"
    case kilometers = "kilometers"
    case miles = "miles"
    case metersPerSecond = "metersPerSecond"

    static var systemDefault: DistanceUnit {
        let measurementSystem = Locale.autoupdatingCurrent.measurementSystem
        return (measurementSystem == .us || measurementSystem == .uk) ? .miles : .kilometers
    }

    static let defaultRawValue = DistanceUnit.systemDefault.rawValue

    static var settingsCases: [DistanceUnit] {
        [.miles, .kilometers, .metersPerSecond]
    }

    var resolved: DistanceUnit {
        switch self {
        case .automatic:
            return Self.systemDefault
        case .kilometers, .miles, .metersPerSecond:
            return self
        }
    }

    func windDisplayName(locale: Locale = .current) -> String {
        switch resolved {
        case .miles: return localizedString("Miles / Hour", locale: locale)
        case .kilometers: return localizedString("Kilometers / Hour", locale: locale)
        case .metersPerSecond: return localizedString("Meters / Second", locale: locale)
        case .automatic: return resolved.windDisplayName(locale: locale)
        }
    }

    var windAbbreviation: String {
        switch resolved {
        case .miles: return "mph"
        case .kilometers: return "km/h"
        case .metersPerSecond: return "m/s"
        case .automatic: return resolved.windAbbreviation
        }
    }

    private var speedUnit: UnitSpeed {
        switch resolved {
        case .kilometers: return .kilometersPerHour
        case .miles: return .milesPerHour
        case .metersPerSecond: return .metersPerSecond
        case .automatic: return resolved.speedUnit
        }
    }

    func displayWindSpeed(_ kmh: Double) -> String {
        let speed = Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
            .converted(to: speedUnit)
            .value
        return "\(Int(speed.rounded())) \(windAbbreviation)"
    }

}

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
        return "\(Int(temperature))°"
    }

}

enum AppTextSizeLevel: Int, CaseIterable {
    case xSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5
    case xxxLarge = 6
    // Accessibility: Mirror all five system accessibility Dynamic Type categories
    // when the user chooses an app-specific text size.
    case accessibility1 = 7
    case accessibility2 = 8
    case accessibility3 = 9
    case accessibility4 = 10
    case accessibility5 = 11

    static let defaultRawValue = AppTextSizeLevel.large.rawValue

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .xSmall: return .xSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .xLarge
        case .xxLarge: return .xxLarge
        case .xxxLarge: return .xxxLarge
        case .accessibility1: return .accessibility1
        case .accessibility2: return .accessibility2
        case .accessibility3: return .accessibility3
        case .accessibility4: return .accessibility4
        case .accessibility5: return .accessibility5
        }
    }

    func displayName(locale: Locale) -> String {
        switch self {
        case .xSmall: return localizedString("Extra Small", locale: locale)
        case .small: return localizedString("Small", locale: locale)
        case .medium: return localizedString("Medium", locale: locale)
        case .large: return localizedString("Default", locale: locale)
        case .xLarge: return localizedString("Large", locale: locale)
        case .xxLarge: return localizedString("Extra Large", locale: locale)
        case .xxxLarge: return localizedString("Extra Extra Large", locale: locale)
        case .accessibility1: return "\(localizedString("Extra Extra Large", locale: locale)) +"
        case .accessibility2: return "\(localizedString("Extra Extra Large", locale: locale)) ++"
        case .accessibility3: return "\(localizedString("Extra Extra Large", locale: locale)) +++"
        case .accessibility4: return "\(localizedString("Extra Extra Large", locale: locale)) ++++"
        case .accessibility5: return "\(localizedString("Extra Extra Large", locale: locale)) +++++"
        }
    }
}

// MARK: - Settings Screen

struct SettingsView: View {
    // MARK: Stored Preferences

    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.defaultRawValue
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

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .automatic
    }

    private var unitsSummary: String {
        let windUnit: String
        if locale.language.languageCode?.identifier == "en" {
            windUnit = selectedDistanceUnit.resolved.windAbbreviation
        } else {
            windUnit = selectedDistanceUnit.resolved.windDisplayName(locale: locale)
        }
        return "\(selectedUnit.resolved.displayName(locale: locale)), \(windUnit)"
    }

    private var selectedTextSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel(rawValue: appTextSizeLevel) ?? .large
    }

    private var resolvedDynamicTypeSize: DynamicTypeSize {
        // Accessibility: Respect the system size by default, including accessibility sizes.
        useSystemTextSize ? systemDynamicTypeSize : selectedTextSizeLevel.dynamicTypeSize
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
                        .accessibilityAddTraits(.isHeader)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    settingsDoneButton
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
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .presentationBackground(theme.colors.mapOcean)
        // Accessibility: Apply the user's system or explicit Dynamic Type choice throughout Settings.
        .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
        // Accessibility: The two-finger scrub first leaves a nested settings page,
        // then dismisses Settings from its root, matching the visible Back/Done controls.
        .accessibilityAction(.escape) {
            dismissSettingsAccessibility()
        }
    }

    // MARK: Toolbar

    @ViewBuilder
    private var settingsDoneButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .if(!usesLiquidGlassForm) { view in
                    view
                        // Accessibility: The resolved background color contrasts with
                        // both the light and dark accent fills in legacy styling.
                        .foregroundStyle(theme.colors.background)
                        // Accessibility: Provide the standard minimum touch target on legacy styling.
                        .frame(width: 44, height: 44)
                        .background(theme.colors.accent, in: Circle())
                        .contentShape(Circle())
                }
        }
        .if(usesLiquidGlassForm) { view in
            view
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("Done", locale: locale))
    }

    private var usesLiquidGlassForm: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
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
                settingsInfoRow(
                    localizedString("Version", locale: locale),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1",
                    systemImage: "info.circle"
                )
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
                .tint(.green)

                VStack(spacing: 18) {
                    HStack(spacing: 18) {
                        Text(verbatim: "A")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .accessibilityHidden(true)

                        steppedTextSizeSlider

                        Text(verbatim: "A")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
                            .accessibilityHidden(true)
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
        .background(NavigationPopGestureDisabler())
        .onAppear {
            textSizeSliderValue = Double(appTextSizeLevel)
        }
        .onChange(of: appTextSizeLevel) { _, newValue in
            guard !isDraggingTextSizeSlider else { return }
            textSizeSliderValue = Double(newValue)
        }
    }

    private var steppedTextSizeSlider: some View {
        Slider(
            value: Binding(
                get: { textSizeSliderValue },
                set: { newValue in
                    let clampedValue = min(max(newValue, 0), Double(AppTextSizeLevel.allCases.count - 1))
                    textSizeSliderValue = clampedValue
                    appTextSizeLevel = Int(clampedValue.rounded())
                }
            ),
            in: 0...Double(AppTextSizeLevel.allCases.count - 1),
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
        // Accessibility: Give the otherwise visual slider a stable name and spoken size value.
        .accessibilityLabel(localizedString("Text Size", locale: locale))
        .accessibilityValue(textSizeSliderDescription)
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

            Section {
                ForEach(DistanceUnit.settingsCases, id: \.rawValue) { unit in
                    settingsSelectionRow(
                        title: unit.windDisplayName(locale: locale),
                        subtitle: unit.windAbbreviation,
                        isSelected: selectedDistanceUnit.resolved == unit,
                        action: { distanceUnit = unit.rawValue }
                    )
                }
            } header: {
                settingsSectionHeader(localizedString("Wind Speed", locale: locale))
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
        if DistanceUnit(rawValue: distanceUnit) == .automatic {
            distanceUnit = DistanceUnit.systemDefault.rawValue
        }
    }

    // MARK: - Accessibility - Settings Navigation

    private func dismissSettingsAccessibility() {
        if showingAttributions {
            showingAttributions = false
        } else if showingUnits {
            showingUnits = false
        } else if showingTextSize {
            showingTextSize = false
        } else {
            dismiss()
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
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("Attributions", locale: locale))
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
                .accessibilityHidden(true)
        }
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
            // Accessibility: Form section labels participate in heading navigation.
            .accessibilityAddTraits(.isHeader)
    }

    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.secondaryText)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
        // Accessibility: Combine the styled label and value into one concise row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
                        .accessibilityHidden(true)
                }
            } label: {
                settingsLabel(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
        // Accessibility: State is spoken independently of the decorative checkmark.
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    .accessibilityHidden(true)
            } label: {
                settingsLabel(localizedString("Say Hello", locale: locale), systemImage: "envelope")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localizedString("Say Hello", locale: locale))
        .accessibilityValue("yutao5726@gmail.com")
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
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                } label: {
                    settingsLabel(title, systemImage: systemImage)
                }
            }
            .buttonStyle(.plain)
            // Accessibility: Identify these custom buttons as external links.
            .accessibilityLabel(title)
            .accessibilityValue(value)
            .accessibilityAddTraits(.isLink)
        }
    }
}

private struct NavigationPopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
}

#Preview("Settings View") {
    SettingsView(weatherService: WeatherService(), onReplayTutorial: {})
}
