//
//  SettingsView.swift
//  Weather
//
//  Purpose: Provides preferences for units, language, appearance, map source,
//  and related settings screens.
//

import SwiftUI
import MapKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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
    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit") private var distanceUnit: String = DistanceUnit.defaultRawValue
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    @AppStorage("mapProvider") private var mapProviderRaw: String = WeatherMapProvider.openStreetMap.rawValue
    let weatherService: WeatherService
    let onResetLists: () -> Void
    var onPlayTutorial: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var showingResetConfirmation = false
    @State private var showingEmailCopied = false

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .automatic
    }

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .automatic
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
            settingsForm
                .tabItem {
                    Label(localizedString("General", locale: locale), systemImage: "slider.horizontal.3")
                }

            NavigationStack {
                aboutForm
                    .navigationTitle(localizedString("About", locale: locale))
            }
            .tabItem {
                Label(localizedString("About", locale: locale), systemImage: "info.circle")
            }
        }
        .frame(width: 480, height: 440)
        .settingsResetAlert(isPresented: $showingResetConfirmation, locale: locale, onReset: onResetLists)
    }
    #endif

    private var settingsRowBackground: Color {
        #if os(macOS)
        Color.clear
        #else
        theme.colors.mapLand
        #endif
    }

    private var settingsFormBackground: Color {
        #if os(macOS)
        Color.clear
        #else
        theme.colors.mapOcean
        #endif
    }

    private var settingsForm: some View {
        Form {
            Section(localizedString("General", locale: locale)) {
                Picker(selection: Binding(get: { temperatureUnit }, set: { temperatureUnit = $0 })) {
                    Text(localizedString("Automatic", locale: locale)).tag(TemperatureUnit.automatic.rawValue)
                    Text(localizedString("Celsius (°C)", locale: locale)).tag(TemperatureUnit.celsius.rawValue)
                    Text(localizedString("Fahrenheit (°F)", locale: locale)).tag(TemperatureUnit.fahrenheit.rawValue)
                } label: {
                    settingsLabel(localizedString("Temperature", locale: locale), systemImage: "thermometer.medium")
                }
                .tint(.secondary)

                Picker(selection: Binding(get: { distanceUnit }, set: { distanceUnit = $0 })) {
                    Text(localizedString("Automatic", locale: locale)).tag(DistanceUnit.automatic.rawValue)
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
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Maps", locale: locale)) {
                mapProviderNavigationRow
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Tutorial", locale: locale)) {
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
            .listRowBackground(settingsRowBackground)

            Section {
                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label(localizedString("Reset Lists to Defaults", locale: locale), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.red)
                }
            }
            .listRowBackground(settingsRowBackground)

            #if os(iOS)
            Section(localizedString("About", locale: locale)) {
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
            }
            .listRowBackground(theme.colors.mapLand)
            #endif
        }
        .scrollContentBackground(.hidden)
            .background(settingsFormBackground)
        .task {
            await weatherService.loadWeatherAttributionIfNeeded()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private var mapProviderNavigationRow: some View {
        NavigationLink {
            mapProviderSelectionView
        } label: {
            LabeledContent {
                Text(currentMapProvider.localizedTitle(locale: locale))
                    .foregroundStyle(theme.colors.secondaryText)
            } label: {
                settingsLabel(localizedString("Map Source", locale: locale), systemImage: "map")
            }
        }
    }

    private var currentMapProvider: WeatherMapProvider {
        WeatherMapProvider(rawValue: mapProviderRaw) ?? .openStreetMap
    }

    private var mapProviderSelectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(localizedString("Choose a map style for comparing weather dots. OpenStreetMap is more minimal, with fewer labels and distractions. Apple Maps shows more place names and context, but the map can feel busier.", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        mapProviderOption(.openStreetMap)
                        mapProviderOption(.appleMaps)
                    }
                    VStack(spacing: 14) {
                        mapProviderOption(.openStreetMap)
                        mapProviderOption(.appleMaps)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground.ignoresSafeArea())
        .navigationTitle(localizedString("Map Source", locale: locale))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func mapProviderOption(_ provider: WeatherMapProvider) -> some View {
        let isSelected = currentMapProvider == provider
        return Button {
            withAnimation(.smooth(duration: 0.2)) {
                mapProviderRaw = provider.rawValue
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MapProviderPreview(provider: provider, accent: theme.colors.accent, isSelected: isSelected)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 6) {
                    Text(provider.localizedTitle(locale: locale))
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(theme.colors.accent)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? theme.colors.accent.opacity(0.12) : Color.primary.opacity(0.045))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? theme.colors.accent.opacity(0.78) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var aboutForm: some View {
        Form {
            Section(localizedString("About", locale: locale)) {
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
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
            .background(settingsFormBackground)
        .task {
            await weatherService.loadWeatherAttributionIfNeeded()
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    private var attributionsNavigationRow: some View {
        NavigationLink {
            attributionsForm
                .navigationTitle(localizedString("Attributions", locale: locale))
        } label: {
            settingsLabel(localizedString("Attributions", locale: locale), systemImage: "text.badge.checkmark")
        }
    }

    private var attributionsForm: some View {
        Form {
            Section(localizedString("Weather", locale: locale)) {
                weatherAttributionRows
            }
            .listRowBackground(settingsRowBackground)

            Section(localizedString("Maps", locale: locale)) {
                settingsLinkRow(
                    localizedString("Apple Maps", locale: locale),
                    value: localizedString("Legal", locale: locale),
                    systemImage: "apple.logo",
                    url: URL(string: "https://www.apple.com/legal/internet-services/maps/legal-en.html")
                )
                settingsInfoRow(
                    localizedString("OpenStreetMap", locale: locale),
                    value: "© OpenStreetMap contributors",
                    systemImage: "map"
                )
            }
            .listRowBackground(settingsRowBackground)
        }
        .scrollContentBackground(.hidden)
        .background(settingsFormBackground)
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

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
                .foregroundStyle(.primary)
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

    private var sayHelloRow: some View {
        Button {
            copySupportEmail()
            showingEmailCopied = true
        } label: {
            LabeledContent {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
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
        #if os(iOS)
        UIPasteboard.general.string = email
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(email, forType: .string)
        #endif
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
                    .foregroundStyle(.secondary)
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

private extension WeatherMapProvider {
    func localizedTitle(locale: Locale) -> String {
        switch self {
        case .openStreetMap: return localizedString("OpenStreetMap", locale: locale)
        case .appleMaps: return localizedString("Apple Maps", locale: locale)
        }
    }

    var settingsIcon: String {
        switch self {
        case .openStreetMap: return "globe"
        case .appleMaps: return "map"
        }
    }
}

private struct MapProviderPreview: View {
    let provider: WeatherMapProvider
    let accent: Color
    let isSelected: Bool
    @State private var tappedCity: CityWeather?
    @State private var recenterOnAllCities = true
    @State private var recenterUsesListCoordinates = true
    @State private var appleCameraPosition: MapCameraPosition = .region(Self.ukPreviewRegion)

    var body: some View {
        ZStack {
            switch provider {
            case .openStreetMap:
                MapLibreWebMapView(
                    cities: [],
                    fitCities: Self.ukPreviewCities,
                    selectedDayOffset: -1,
                    overlayMode: "weather",
                    filterSunny: false,
                    markerReloadID: 0,
                    markerSizeScale: 1.15,
                    showsMarkerHoverLabels: false,
                    focusedCountryBoundary: nil,
                    tappedCity: $tappedCity,
                    recenterOnAllCities: $recenterOnAllCities,
                    recenterUsesListCoordinates: $recenterUsesListCoordinates,
                    centerOnCity: nil,
                    leadingFitPadding: 0,
                    focusSelectedMarker: false,
                    allowsMarkerHover: false,
                    cameraProfile: .preview,
                    onMarkerTap: { _, _ in },
                    onMapClick: nil,
                    onMarkerCommandHover: nil,
                    onCameraMove: nil,
                    onMapGestureStart: nil
                )
            case .appleMaps:
                Map(position: $appleCameraPosition, interactionModes: []) {}
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            }
        }
        .allowsHitTesting(false)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? accent.opacity(0.78) : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .onAppear {
            appleCameraPosition = .region(Self.ukPreviewRegion)
            recenterOnAllCities = true
            recenterUsesListCoordinates = true
        }
    }

    private static var ukPreviewCities: [City] {
        [
            City(name: "London", country: "United Kingdom", latitude: 51.5072, longitude: -0.1276),
            City(name: "Edinburgh", country: "United Kingdom", latitude: 55.9533, longitude: -3.1883),
            City(name: "Cardiff", country: "United Kingdom", latitude: 51.4816, longitude: -3.1791),
            City(name: "Belfast", country: "United Kingdom", latitude: 54.5973, longitude: -5.9301)
        ]
    }

    private static let ukPreviewRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 54.35, longitude: -3.15),
        span: MKCoordinateSpan(latitudeDelta: 8.2, longitudeDelta: 8.4)
    )
}

#Preview("Settings") {
    SettingsView(weatherService: WeatherService(), onResetLists: {})
}
