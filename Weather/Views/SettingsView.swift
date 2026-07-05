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

    static let defaultRawValue = DistanceUnit.automatic.rawValue

    var resolved: DistanceUnit {
        switch self {
        case .automatic:
            let measurementSystem = Locale.autoupdatingCurrent.measurementSystem
            return (measurementSystem == .us || measurementSystem == .uk) ? .miles : .kilometers
        case .kilometers, .miles:
            return self
        }
    }

    var symbol: String {
        switch resolved {
        case .kilometers: return "km"
        case .miles: return "mi"
        case .automatic: return resolved.symbol
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
        case .automatic:
            return resolved.display(km)
        }
    }

    func displayWindSpeed(_ kmh: Double) -> String {
        switch resolved {
        case .kilometers:
            return "\(Int(kmh)) km/h"
        case .miles:
            let mph = kmh * 0.621371
            return "\(Int(mph)) mph"
        case .automatic:
            return resolved.displayWindSpeed(kmh)
        }
    }

    var windSpeedUnit: String {
        switch resolved {
        case .kilometers: return "km/h"
        case .miles: return "mph"
        case .automatic: return resolved.windSpeedUnit
        }
    }
}

enum TemperatureUnit: String, CaseIterable {
    case automatic = "automatic"
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    static let defaultRawValue = TemperatureUnit.automatic.rawValue

    var resolved: TemperatureUnit {
        switch self {
        case .automatic:
            let sample = Measurement(value: 0, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .weather).locale(.autoupdatingCurrent))
            return sample.localizedCaseInsensitiveContains("F") ? .fahrenheit : .celsius
        case .celsius, .fahrenheit:
            return self
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

// MARK: - Settings Screen

struct SettingsView: View {
    // MARK: Stored Preferences

    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.defaultRawValue
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let weatherService: WeatherService
    let onResetLists: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var showingResetConfirmation = false
    @State private var showingEmailCopied = false
    @State private var showingAttributions = false

    // MARK: Resolved Preferences

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .automatic
    }

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .automatic
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
        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .presentationBackground(theme.colors.mapOcean)
        .settingsResetAlert(isPresented: $showingResetConfirmation, locale: locale, onReset: onResetLists)
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
                .tint(theme.colors.accent)
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
        colorScheme == .dark ? theme.colors.accent : theme.colors.primaryText
    }

    // MARK: Main Settings Form

    private var settingsForm: some View {
        Form {
            Section {
                Picker(selection: Binding(get: { temperatureUnit }, set: { temperatureUnit = $0 })) {
                    Text(localizedString("Automatic", locale: locale)).tag(TemperatureUnit.automatic.rawValue)
                    Text(localizedString("Celsius (°C)", locale: locale)).tag(TemperatureUnit.celsius.rawValue)
                    Text(localizedString("Fahrenheit (°F)", locale: locale)).tag(TemperatureUnit.fahrenheit.rawValue)
                } label: {
                    settingsLabel(localizedString("Temperature", locale: locale), systemImage: "thermometer.medium")
                }
                .tint(theme.colors.accent)

                Picker(selection: Binding(get: { distanceUnit }, set: { distanceUnit = $0 })) {
                    Text(localizedString("Automatic", locale: locale)).tag(DistanceUnit.automatic.rawValue)
                    Text(localizedString("Kilometers (km)", locale: locale)).tag(DistanceUnit.kilometers.rawValue)
                    Text(localizedString("Miles (mi)", locale: locale)).tag(DistanceUnit.miles.rawValue)
                } label: {
                    settingsLabel(localizedString("Distance", locale: locale), systemImage: "ruler")
                }
                .tint(theme.colors.accent)

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
                .tint(theme.colors.accent)

                Picker(selection: Binding(get: { theme.style }, set: { theme.style = $0 })) {
                    Text(localizedString("Light", locale: locale)).tag(AppThemeStyle.light)
                    Text(localizedString("Dark", locale: locale)).tag(AppThemeStyle.dark)
                    Text(localizedString("Auto", locale: locale)).tag(AppThemeStyle.automatic)
                } label: {
                    settingsLabel(localizedString("Theme", locale: locale), systemImage: "circle.lefthalf.filled")
                }
                .tint(theme.colors.accent)
            } header: {
                settingsSectionHeader(localizedString("General", locale: locale))
            }
            .listRowBackground(settingsRowBackground)

            Section {
                Button {
                    showingResetConfirmation = true
                } label: {
                    Label(localizedString("Reset Lists to Defaults", locale: locale), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(theme.colors.dotSun)
                }
            }
            .listRowBackground(settingsRowBackground)

            Section {
                settingsInfoRow(
                    localizedString("Version", locale: locale),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    systemImage: "info.circle"
                )
                settingsLinkRow(
                    localizedString("Website", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "safari",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-app-website/")
                )
                settingsLinkRow(
                    localizedString("Privacy Policy", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "hand.raised",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-app-website/privacy/")
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

    // MARK: About and Attributions

    private var aboutForm: some View {
        Form {
            Section {
                settingsInfoRow(
                    localizedString("Version", locale: locale),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    systemImage: "info.circle"
                )
                settingsLinkRow(
                    localizedString("Website", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "safari",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-app-website/")
                )
                settingsLinkRow(
                    localizedString("Privacy Policy", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "hand.raised",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-app-website/privacy/")
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
                    .foregroundStyle(theme.colors.accent)
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
                settingsLinkRow(
                    "\u{F8FF} " + localizedString("Apple Maps", locale: locale),
                    value: localizedString("Legal", locale: locale),
                    systemImage: "map",
                    url: URL(string: "https://www.apple.com/legal/internet-services/maps/legal-en.html")
                )
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
            .foregroundStyle(theme.colors.accent)
    }

    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.accent)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
    }

    // MARK: Support Actions

    private var sayHelloRow: some View {
        Button {
            copySupportEmail()
            showingEmailCopied = true
        } label: {
            LabeledContent {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(theme.colors.accent)
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
                    .foregroundStyle(theme.colors.accent)
                } label: {
                    settingsLabel(title, systemImage: systemImage)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    func settingsResetAlert(isPresented: Binding<Bool>, locale: Locale, onReset: @escaping () -> Void) -> some View {
        alert(localizedString("Reset Lists", locale: locale), isPresented: isPresented) {
            Button(localizedString("Cancel", locale: locale), role: .cancel) {}
            Button(localizedString("Reset", locale: locale), role: .destructive) {
                onReset()
            }
        } message: {
            Text(localizedString("This will reset all city lists back to their defaults. Any cities you added or removed will be lost.", locale: locale))
        }
    }
}

#Preview("Settings View") {
    SettingsView(weatherService: WeatherService(), onResetLists: {})
}
