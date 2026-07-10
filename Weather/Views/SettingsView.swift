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

    var windDisplayName: String {
        switch resolved {
        case .miles: return "Miles / Hour"
        case .kilometers: return "Kilometers / Hour"
        case .metersPerSecond: return "Meters / Second"
        case .automatic: return resolved.windDisplayName
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
        return sample.localizedCaseInsensitiveContains("F") ? .fahrenheit : .celsius
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

    var displayName: String {
        switch resolved {
        case .celsius: return "Celsius"
        case .fahrenheit: return "Fahrenheit"
        case .automatic: return resolved.displayName
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

    var displayName: String {
        switch self {
        case .xSmall: return "Extra Small"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Default"
        case .xLarge: return "Large"
        case .xxLarge: return "Extra Large"
        case .xxxLarge: return "Extra Extra Large"
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @State private var showingEmailCopied = false
    @State private var showingAttributions = false
    @State private var showingUnits = false
    @State private var showingTextSize = false
    @State private var textSizeSliderValue = Double(AppTextSizeLevel.defaultRawValue)
    @State private var isDraggingTextSizeSlider = false
    @State private var isCommittingTextSizeSlider = false

    // MARK: Resolved Preferences

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .automatic
    }

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .automatic
    }

    private var unitsSummary: String {
        "\(selectedUnit.resolved.displayName), \(selectedDistanceUnit.resolved.windAbbreviation)"
    }

    private var selectedTextSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel(rawValue: appTextSizeLevel) ?? .large
    }

    private var textSizeSummary: String {
        useSystemTextSize ? localizedString("System", locale: locale) : selectedTextSizeLevel.displayName
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
                .tint(theme.colors.accent)

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
                .tint(theme.colors.accent)
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
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas/")
                )
                settingsLinkRow(
                    localizedString("Privacy Policy", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "hand.raised",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas/privacy/")
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
                    Divider()

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
                }
            }
            .listRowBackground(settingsRowBackground)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    textSizePreviewCard
                        .environment(\.dynamicTypeSize, textSizePreviewDynamicTypeSize)

                    Text(localizedString("This previews how text size affects the app.", locale: locale))
                        .font(.footnote)
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        .onAppear {
            textSizeSliderValue = Double(appTextSizeLevel)
        }
        .onChange(of: appTextSizeLevel) { _, newValue in
            if isCommittingTextSizeSlider {
                isCommittingTextSizeSlider = false
                return
            }
            guard !isDraggingTextSizeSlider else { return }
            textSizeSliderValue = Double(newValue)
        }
    }

    private var steppedTextSizeSlider: some View {
        Slider(
            value: Binding(
                get: { textSizeSliderValue },
                set: { newValue in
                    textSizeSliderValue = min(max(newValue, 0), Double(AppTextSizeLevel.allCases.count - 1))
                }
            ),
            in: 0...Double(AppTextSizeLevel.allCases.count - 1),
            onEditingChanged: { isEditing in
                isDraggingTextSizeSlider = isEditing
                if !isEditing {
                    commitTextSizeSliderValue()
                }
            }
        )
        .disabled(useSystemTextSize)
        .tint(theme.colors.accent)
        .frame(height: 36)
    }

    private func commitTextSizeSliderValue() {
        let maximumLevel = AppTextSizeLevel.allCases.count - 1
        let roundedValue = min(max(Int(textSizeSliderValue.rounded()), 0), maximumLevel)
        isCommittingTextSizeSlider = true
        appTextSizeLevel = roundedValue
        Task { @MainActor in
            await Task.yield()
            isCommittingTextSizeSlider = false
        }
    }

    private var textSizePreviewDynamicTypeSize: DynamicTypeSize {
        if useSystemTextSize {
            return dynamicTypeSize
        }
        let previewLevel = AppTextSizeLevel(rawValue: Int(textSizeSliderValue.rounded())) ?? selectedTextSizeLevel
        return previewLevel.dynamicTypeSize
    }

    private var textSizePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(theme.colors.dotSun)
                Text(localizedString("Best Sunny Places", locale: locale))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
            }

            let candidates = textSizePreviewCandidates
            if candidates.isEmpty {
                Text(localizedString("No sunny places for this date.", locale: locale))
                    .font(.callout)
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                    .background(theme.colors.glassFill.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                        SunnyCandidateRow(
                            candidate: candidate,
                            rank: index + 1,
                            compact: true,
                            tempUnit: selectedUnit
                        )

                        if index < candidates.count - 1 {
                            Divider()
                                .background(theme.colors.secondaryText.opacity(0.16))
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    private var textSizePreviewCandidates: [SunnyCandidate] {
        Array(
            textSizePreviewCandidates(for: textSizePreviewCities, dayOffset: textSizePreviewDayOffset)
                .filter { $0.condition.isSunny }
                .prefix(3)
        )
    }

    private var textSizePreviewDayOffset: Int {
        let cities = textSizePreviewCities
        let dayOffsets = Array(1...9)
        return dayOffsets.first { dayOffset in
            textSizePreviewCandidates(for: cities, dayOffset: dayOffset).contains { $0.condition.isSunny }
        } ?? 1
    }

    private var textSizePreviewCities: [CityWeather] {
        weatherService.cityWeatherData.isEmpty ? Self.samplePreviewCities : weatherService.cityWeatherData
    }

    private func textSizePreviewCandidates(for cities: [CityWeather], dayOffset: Int) -> [SunnyCandidate] {
        cities
            .map { cityWeather -> SunnyCandidate in
                let forecast = cityWeather.forecast(for: dayOffset)
                let condition = SunninessScoring.condition(for: forecast.symbolName)
                return SunnyCandidate(
                    cityWeather: cityWeather,
                    score: condition.sunninessScore,
                    condition: condition,
                    cloudCover: forecast.cloudCover,
                    precipitationChance: forecast.precipitationChance,
                    temperature: forecast.dailyHigh
                )
            }
            .sorted(by: isBetterTextSizePreviewCandidate)
    }

    private func isBetterTextSizePreviewCandidate(_ lhs: SunnyCandidate, than rhs: SunnyCandidate) -> Bool {
        if lhs.condition.sunninessRank != rhs.condition.sunninessRank {
            return lhs.condition.sunninessRank < rhs.condition.sunninessRank
        }

        switch (lhs.cloudCover, rhs.cloudCover) {
        case let (lhsCloud?, rhsCloud?) where lhsCloud != rhsCloud:
            return lhsCloud < rhsCloud
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.cityWeather.city.localizedName(locale: locale) < rhs.cityWeather.city.localizedName(locale: locale)
        }
    }

    private static let samplePreviewCities: [CityWeather] = [
        samplePreviewCity(name: "Barcelona", country: "Spain", latitude: 41.3874, longitude: 2.1686, dayOneSymbol: "sun.max.fill", high: 29, cloudCover: 0.08),
        samplePreviewCity(name: "Rome", country: "Italy", latitude: 41.9028, longitude: 12.4964, dayOneSymbol: "sun.max.fill", high: 28, cloudCover: 0.12),
        samplePreviewCity(name: "Lisbon", country: "Portugal", latitude: 38.7223, longitude: -9.1393, dayOneSymbol: "cloud.sun", high: 25, cloudCover: 0.32)
    ]

    private static func samplePreviewCity(
        name: String,
        country: String,
        latitude: Double,
        longitude: Double,
        dayOneSymbol: String,
        high: Double,
        cloudCover: Double
    ) -> CityWeather {
        let city = City(
            name: name,
            country: country,
            latitude: latitude,
            longitude: longitude,
            timeZoneIdentifier: "Europe/Madrid"
        )
        let forecasts = (0..<10).map { dayOffset in
            samplePreviewForecast(
                dayOffset: dayOffset,
                symbolName: dayOffset == 1 ? dayOneSymbol : "cloud.sun",
                high: high + Double(dayOffset % 3),
                cloudCover: dayOffset == 1 ? cloudCover : 0.45
            )
        }
        let condition = AppWeatherCondition.fromWeatherSymbol(dayOneSymbol)
        return CityWeather(
            city: city,
            condition: condition,
            temperature: high,
            symbolName: dayOneSymbol,
            dailyForecasts: forecasts,
            timeZone: TimeZone(identifier: city.timeZoneIdentifier ?? "Europe/Madrid") ?? .current,
            currentCloudCover: cloudCover
        )
    }

    private static func samplePreviewForecast(
        dayOffset: Int,
        symbolName: String,
        high: Double,
        cloudCover: Double
    ) -> DailyForecast {
        DailyForecast(
            dayOffset: dayOffset,
            dailyLow: high - 7,
            dailyHigh: high,
            symbolName: symbolName,
            condition: AppWeatherCondition.fromWeatherSymbol(symbolName),
            hourlyForecasts: [],
            cloudCover: cloudCover,
            precipitationChance: cloudCover > 0.65 ? 0.18 : 0.03,
            visibility: 24,
            feelsLikeLow: nil,
            feelsLikeHigh: nil,
            humidity: 0.48,
            windSpeed: 9,
            uvIndex: 7,
            maxHumidity: 0.58,
            maxVisibility: 24,
            sunrise: nil,
            sunset: nil
        )
    }

    private var unitsForm: some View {
        Form {
            Section {
                ForEach(TemperatureUnit.settingsCases, id: \.rawValue) { unit in
                    settingsSelectionRow(
                        title: unit.displayName,
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
                        title: unit.windDisplayName,
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
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas/")
                )
                settingsLinkRow(
                    localizedString("Privacy Policy", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "hand.raised",
                    url: URL(string: "https://tomwuyutao.github.io/Weather-Atlas/privacy/")
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

            Section(localizedString("Cities Data", locale: locale)) {
                settingsLinkRow(
                    localizedString("SimpleMaps World Cities", locale: locale),
                    value: localizedString("View", locale: locale),
                    systemImage: "building.2",
                    url: URL(string: "https://simplemaps.com/data/world-cities")
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
            .foregroundStyle(theme.colors.primaryText)
    }

    private func settingsInfoRow(_ title: String, value: String, systemImage: String) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.accent)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
    }

    private func settingsNavigationRow(_ title: String, value: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent {
                HStack(spacing: 8) {
                    Text(value)
                        .foregroundStyle(theme.colors.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.accent)
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
                        .foregroundStyle(theme.colors.accent)
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

#Preview("Settings View") {
    SettingsView(weatherService: WeatherService(), onReplayTutorial: {})
}
