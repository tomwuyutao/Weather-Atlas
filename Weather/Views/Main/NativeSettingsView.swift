//
//  NativeSettingsView.swift
//  Weather
//
//  Purpose: Edits app preferences with system Form, Picker, Toggle, toolbar,
//  and confirmation components.
//

import SwiftUI

/// Native settings sheet for the redesigned app shell.
struct NativeSettingsView: View {
    let model: WeatherAtlasModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    @AppStorage("temperatureUnit")
    private var temperatureUnit = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnit = DistanceUnit.defaultRawValue
    @AppStorage("appLanguage")
    private var appLanguage = "en"
    @AppStorage("useSystemTextSize")
    private var useSystemTextSize = true
    @AppStorage("appTextSizeLevel")
    private var appTextSizeLevel = AppTextSizeLevel.defaultRawValue

    @State private var showingClearPlacesConfirmation = false
    @State private var settingsError: SettingsMutationError?

    var body: some View {
        NavigationStack {
            Form {
                unitsSection
                appearanceSection
                languageSection
                textSection
                dataSection
                aboutSection
            }
            .weatherAtlasScrollableBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .confirmationDialog(
                "Delete all saved places?",
                isPresented: $showingClearPlacesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Places", role: .destructive) {
                    clearAllPlaces()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This also removes every collection. Your app preferences are kept.")
            }
            .alert(
                "Settings",
                isPresented: settingsErrorIsPresented,
                presenting: settingsError
            ) { _ in
                Button("OK") {
                    settingsError = nil
                }
            } message: { error in
                Text(error.message)
            }
        }
    }

    private var unitsSection: some View {
        Section("Units") {
            Picker("Temperature", selection: $temperatureUnit) {
                ForEach(
                    [TemperatureUnit.automatic, .celsius, .fahrenheit],
                    id: \.rawValue
                ) { unit in
                    Text(unit.displayName(locale: locale))
                        .tag(unit.rawValue)
                }
            }

            Picker("Distance", selection: $distanceUnit) {
                ForEach(DistanceUnit.allCases, id: \.rawValue) { unit in
                    Text(unit.displayName(locale: locale))
                        .tag(unit.rawValue)
                }
            }
        }
    }

    private var settingsErrorIsPresented: Binding<Bool> {
        Binding(
            get: { settingsError != nil },
            set: { isPresented in
                if !isPresented {
                    settingsError = nil
                }
            }
        )
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: themeStyleBinding) {
                ForEach(AppThemeStyle.allCases, id: \.rawValue) { style in
                    Text(style.displayName(locale: locale))
                        .tag(style)
                }
            }
        }
    }

    private var languageSection: some View {
        Section("Language") {
            Picker("App Language", selection: $appLanguage) {
                ForEach(
                    AppLanguageDefaults.supportedLanguageCodes,
                    id: \.self
                ) { languageCode in
                    Text(languageDisplayName(for: languageCode))
                        .tag(languageCode)
                }
            }
        }
    }

    private var textSection: some View {
        Section {
            Toggle("Use System Text Size", isOn: $useSystemTextSize)

            if !useSystemTextSize {
                Picker("App Text Size", selection: $appTextSizeLevel) {
                    ForEach(AppTextSizeLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName(locale: locale))
                            .tag(level.rawValue)
                    }
                }
            }
        } header: {
            Text("Text Size")
        } footer: {
            Text("System text size supports the complete Accessibility range.")
        }
    }

    private var dataSection: some View {
        Section("Saved Data") {
            LabeledContent("Places") {
                Text(model.placesStore.allPlaces.count, format: .number)
            }
            LabeledContent("Collections") {
                Text(model.placesStore.collections.count, format: .number)
            }

            Button(
                "Delete All Places",
                systemImage: "trash",
                role: .destructive
            ) {
                showingClearPlacesConfirmation = true
            }
            .disabled(model.placesStore.allPlaces.isEmpty)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Weather Atlas") {
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Weather Data") {
                Text("Apple Weather")
                    .foregroundStyle(.secondary)
            }

            if let attribution = model.weatherStore.weatherAttribution {
                WeatherAttributionView(attribution: attribution)
            }

            Link(
                destination: URL(
                    string: "https://simplemaps.com/data/world-cities"
                )!
            ) {
                Label("About SimpleMaps", systemImage: "building.2")
            }

            Link(
                destination: URL(
                    string: "https://www.apple.com/legal/internet-services/maps/legal-en.html"
                )!
            ) {
                Label("Maps Legal Sources", systemImage: "map")
            }
        }
    }

    private var themeStyleBinding: Binding<AppThemeStyle> {
        Binding(
            get: { theme.style },
            set: { theme.style = $0 }
        )
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        return version ?? "1.0"
    }

    /// Returns each language's self-name so it remains recognizable after the
    /// interface language changes.
    private func languageDisplayName(for languageCode: String) -> String {
        switch languageCode {
        case "en": "English"
        case "fr": "Français"
        case "de": "Deutsch"
        case "it": "Italiano"
        case "ja": "日本語"
        case "ko": "한국어"
        case "pt": "Português"
        case "ru": "Русский"
        case "zh-Hans": "简体中文"
        case "es": "Español"
        case "zh-Hant": "繁體中文"
        default: languageCode
        }
    }

    private func clearAllPlaces() {
        do {
            try model.placesStore.resetToEmptyLibrary()
            model.weatherStore.retainWeather(for: [])
        } catch {
            settingsError = SettingsMutationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }
}

private struct SettingsMutationError: Identifiable {
    let id = UUID()
    let message: String
}
