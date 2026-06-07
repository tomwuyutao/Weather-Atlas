//
//  SettingsView.swift
//  Weather
//
//  Created by Tom on 02/03/2026.
//

import SwiftUI

enum DistanceUnit: String, CaseIterable {
    case kilometers = "kilometers"
    case miles = "miles"

    var symbol: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    func display(_ km: Double) -> String {
        switch self {
        case .kilometers:
            let rounded = (km * 10).rounded() / 10
            return rounded >= 10 ? "\(Int(rounded))km" : String(format: "%.1fkm", rounded)
        case .miles:
            let mi = km * 0.621371
            let rounded = (mi * 10).rounded() / 10
            return rounded >= 10 ? "\(Int(rounded))mi" : String(format: "%.1fmi", rounded)
        }
    }

    func displayWindSpeed(_ kmh: Double) -> String {
        switch self {
        case .kilometers:
            return "\(Int(kmh)) km/h"
        case .miles:
            let mph = kmh * 0.621371
            return "\(Int(mph)) mph"
        }
    }

    var windSpeedUnit: String {
        switch self {
        case .kilometers: return "km/h"
        case .miles: return "mph"
        }
    }
}

enum TemperatureUnit: String, CaseIterable {
    case celsius = "celsius"
    case fahrenheit = "fahrenheit"

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    func display(_ celsius: Double) -> String {
        switch self {
        case .celsius:
            return "\(Int(celsius))°"
        case .fahrenheit:
            return "\(Int(celsius * 9.0 / 5.0 + 32))°"
        }
    }

    func displayRange(low: Double, high: Double) -> String {
        switch self {
        case .celsius:
            return "\(Int(low))-\(Int(high))°"
        case .fahrenheit:
            let fLow = Int(low * 9.0 / 5.0 + 32)
            let fHigh = Int(high * 9.0 / 5.0 + 32)
            return "\(fLow)-\(fHigh)°"
        }
    }

    func displaySlash(low: Double, high: Double) -> String {
        switch self {
        case .celsius:
            return "\(Int(low))°/\(Int(high))°"
        case .fahrenheit:
            let fLow = Int(low * 9.0 / 5.0 + 32)
            let fHigh = Int(high * 9.0 / 5.0 + 32)
            return "\(fLow)°/\(fHigh)°"
        }
    }
}

struct SettingsView: View {
    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.kilometers.rawValue
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let weatherService: WeatherService
    let onResetLists: () -> Void
    var onPlayTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingResetConfirmation = false

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .kilometers
    }

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        nativeMacSettingsBody
        #else
        NavigationStack {
            settingsForm
            .navigationTitle(localizedString("Settings", locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    settingsDoneButton
                }
            }
            #endif
        }
        .background(theme.colors.mapOcean.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme(for: colorScheme))
        .presentationBackground(theme.colors.mapOcean)
        .settingsResetAlert(isPresented: $showingResetConfirmation, locale: locale, onReset: onResetLists)
        #endif
    }

    #if os(iOS)
    @ViewBuilder
    private var settingsDoneButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 18, weight: .semibold))
                .if(!isIOS26OrLater) { view in
                    view
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(theme.colors.accent, in: Circle())
                        .contentShape(Circle())
                }
        }
        .if(isIOS26OrLater) { view in
            view
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
        }
        .buttonStyle(.plain)
    }

    private var isIOS26OrLater: Bool {
        if #available(iOS 26.0, *) {
            true
        } else {
            false
        }
    }
    #endif

    #if os(macOS)
    private var nativeMacSettingsBody: some View {
        TabView {
            Tab(localizedString("General", locale: locale), systemImage: "gear") {
                settingsForm
            }

            Tab(localizedString("About", locale: locale), systemImage: "info.circle") {
                aboutForm
            }
        }
        .scenePadding()
        .frame(width: 420)
        .frame(minHeight: 260)
        .settingsResetAlert(isPresented: $showingResetConfirmation, locale: locale, onReset: onResetLists)
    }
    #endif

    private var settingsForm: some View {
        Form {
            Section(localizedString("General", locale: locale)) {
                Picker(selection: Binding(get: { temperatureUnit }, set: { temperatureUnit = $0 })) {
                    Text(localizedString("Celsius (°C)", locale: locale)).tag(TemperatureUnit.celsius.rawValue)
                    Text(localizedString("Fahrenheit (°F)", locale: locale)).tag(TemperatureUnit.fahrenheit.rawValue)
                } label: {
                    settingsLabel(localizedString("Temperature", locale: locale), systemImage: "thermometer.medium")
                }
                .tint(.secondary)

                Picker(selection: Binding(get: { distanceUnit }, set: { distanceUnit = $0 })) {
                    Text(localizedString("Kilometers (km)", locale: locale)).tag(DistanceUnit.kilometers.rawValue)
                    Text(localizedString("Miles (mi)", locale: locale)).tag(DistanceUnit.miles.rawValue)
                } label: {
                    settingsLabel(localizedString("Distance", locale: locale), systemImage: "ruler")
                }
                .tint(.secondary)

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
                .tint(.secondary)

                Picker(selection: Binding(get: { theme.style }, set: { theme.style = $0 })) {
                    Text(localizedString("Light", locale: locale)).tag(AppThemeStyle.light)
                    Text(localizedString("Dark", locale: locale)).tag(AppThemeStyle.dark)
                    Text(localizedString("Auto", locale: locale)).tag(AppThemeStyle.automatic)
                } label: {
                    settingsLabel(localizedString("Theme", locale: locale), systemImage: "circle.lefthalf.filled")
                }
                .tint(.secondary)

                Button {
                    onPlayTutorial()
                } label: {
                    Label {
                        Text(localizedString("Replay Tutorial", locale: locale))
                            .foregroundStyle(theme.colors.primaryText)
                    } icon: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .font(.body.weight(.medium))
                }
                .tint(theme.colors.primaryText)
            }
            .listRowBackground(theme.colors.mapLand)

            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label(localizedString("Reset Lists to Defaults", locale: locale), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(theme.colors.mapLand)

            #if os(iOS)
            Section(localizedString("About", locale: locale)) {
                settingsInfoRow(
                    localizedString("Version", locale: locale),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    systemImage: "info.circle"
                )
                settingsInfoRow(
                    localizedString("Weather Data", locale: locale),
                    value: "Apple Weather",
                    systemImage: "cloud.sun"
                )
            }
            .listRowBackground(theme.colors.mapLand)
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.mapOcean)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private var aboutForm: some View {
        Form {
            Section(localizedString("About", locale: locale)) {
                settingsInfoRow(
                    localizedString("Version", locale: locale),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                    systemImage: "info.circle"
                )
                settingsInfoRow(localizedString("Powered by", locale: locale), value: "Apple Weather", systemImage: "cloud.sun")
            }
            .listRowBackground(theme.colors.mapLand)
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.mapOcean)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private func settingsLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
        }
    }

    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            settingsLabel(title, systemImage: systemImage)
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
#Preview("Settings") {
    SettingsView(weatherService: WeatherService(), onResetLists: {})
}
