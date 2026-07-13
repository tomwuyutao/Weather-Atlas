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

    var symbol: String {
        switch resolved {
        case .kilometers: return "km"
        case .miles: return "mi"
        case .metersPerSecond: return "m/s"
        case .automatic: return resolved.symbol
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

    func display(_ km: Double) -> String {
        switch resolved {
        case .kilometers:
            let rounded = (km * 10).rounded() / 10
            return rounded >= 10 ? "\(Int(rounded))km" : String(format: "%.1fkm", rounded)
        case .miles:
            let mi = km * 0.621371
            let rounded = (mi * 10).rounded() / 10
            return rounded >= 10 ? "\(Int(rounded))mi" : String(format: "%.1fmi", rounded)
        case .metersPerSecond:
            return DistanceUnit.kilometers.display(km)
        case .automatic:
            return resolved.display(km)
        }
    }

    func displayWindSpeed(_ kmh: Double, locale: Locale = .autoupdatingCurrent) -> String {
        switch resolved {
        case .kilometers:
            return "\(Int(kmh.rounded())) km/h"
        case .miles:
            let mph = kmh * 0.621371
            return "\(Int(mph.rounded())) mph"
        case .metersPerSecond:
            let metersPerSecond = kmh / 3.6
            return "\(Int(metersPerSecond.rounded())) m/s"
        case .automatic:
            return resolved.displayWindSpeed(kmh, locale: locale)
        }
    }

    func windSpeedUnit(locale: Locale = .autoupdatingCurrent) -> String {
        switch resolved {
        case .kilometers:
            return "km/h"
        case .miles:
            return "mph"
        case .metersPerSecond:
            return "m/s"
        case .automatic:
            return resolved.windSpeedUnit(locale: locale)
        }
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

    var symbol: String {
        switch resolved {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        case .automatic: return resolved.symbol
        }
    }

    func display(_ celsius: Double) -> String {
        switch resolved {
        case .celsius:
            return "\(Int(celsius))°"
        case .fahrenheit:
            return "\(Int(celsius * 9.0 / 5.0 + 32))°"
        case .automatic:
            return resolved.display(celsius)
        }
    }

    func displayRange(low: Double, high: Double) -> String {
        switch resolved {
        case .celsius:
            return "\(Int(low))-\(Int(high))°"
        case .fahrenheit:
            let fLow = Int(low * 9.0 / 5.0 + 32)
            let fHigh = Int(high * 9.0 / 5.0 + 32)
            return "\(fLow)-\(fHigh)°"
        case .automatic:
            return resolved.displayRange(low: low, high: high)
        }
    }

    func displaySlash(low: Double, high: Double) -> String {
        switch resolved {
        case .celsius:
            return "\(Int(low))°/\(Int(high))°"
        case .fahrenheit:
            let fLow = Int(low * 9.0 / 5.0 + 32)
            let fHigh = Int(high * 9.0 / 5.0 + 32)
            return "\(fLow)°/\(fHigh)°"
        case .automatic:
            return resolved.displaySlash(low: low, high: high)
        }
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
        .environment(\.dynamicTypeSize, resolvedDynamicTypeSize)
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
                        .foregroundStyle(.white)
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

                        steppedTextSizeSlider

                        Text(verbatim: "A")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(theme.colors.secondaryText)
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

    // MARK: About and Attributions

    private var aboutForm: some View {
        Form {
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
            await weatherService.loadWeatherAttributionIfNeeded()
        }
    }

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
