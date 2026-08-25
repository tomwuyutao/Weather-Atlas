//
//  Settings.swift
//  Weather
//
//  Purpose: Presents preferences, provider attribution, onboarding replay,
//  saved-name translation choices, and the app reset workflow.
//

import SwiftUI
import UIKit
import WeatherKit

// MARK: - Settings Root

/// A sheet-hosted navigation hierarchy for preferences, legal information,
/// and the destructive app reset action. Preferences use `@AppStorage` so the
/// corresponding services and views can observe the same persisted choices.
struct SettingsView: View {
    let model: WeatherModel
    let onResetApp: () throws -> Void
    /// Restarts the guided onboarding without clearing user data.
    let onReplayTutorial: () -> Void

    // MARK: - Persisted Preferences and Presentation State

    @AppStorage("temperatureUnit")
    private var temperatureUnit = TemperatureUnit.defaultRawValue
    @AppStorage("distanceUnit")
    private var distanceUnit = DistanceUnit.defaultRawValue
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("useSystemTextSize") private var useSystemTextSize = true
    @AppStorage("appTextSizeLevel")
    private var appTextSizeLevel = AppTextSizeLevel.defaultRawValue

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var destination: SettingsDestination?
    @State private var showsCopiedNotice = false
    @State private var showsResetAlert = false
    @State private var resetError: SettingsResetError?
    /// A language selection is held here until the person decides whether
    /// Saved Place labels should follow it.
    @State private var pendingLanguageCode: String?
    @State private var translatingPlaceNamesToLanguageCode: String?

    /// Converts the stored integer to a valid domain value, guarding against a
    /// stale value from an older app release or direct UserDefaults editing.
    private var textSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel.level(clamping: appTextSizeLevel)
    }

    // MARK: - Root Navigation and Safety Prompts

    var body: some View {
        NavigationStack {
            settingsForm
                // A custom principal view keeps this sheet's title vertically
                // aligned with its native close button without hiding the bar.
                .navigationTitle(Text(verbatim: ""))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Settings")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(theme.colors.primaryText)

                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark") {
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 44, height: 44)
                    }
                }
                .navigationDestination(item: $destination) { destination in
                    destinationView(destination)
                }
        }
        .background(theme.colors.background.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme)
        .presentationBackground(theme.colors.background)
        // A system alert provides the native modal confirmation surface here.
        .alert(
            "Clear Data and Reset App?",
            isPresented: $showsResetAlert
        ) {
            Button("Reset App", role: .destructive, action: resetApp)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes your saved places, preferences, and cached weather."
            )
        }
        .alert(
            "Settings",
            isPresented: showsResetError,
            presenting: resetError
        ) { _ in
            Button("OK") {
                resetError = nil
            }
        } message: { error in
            Text(error.message)
        }
        .alert(
            "Translate Saved Place Names?",
            isPresented: showsPlaceNameTranslationPrompt
        ) {
            Button("Translate Names") {
                commitPendingLanguageChange(translatingSavedPlaceNames: true)
            }
            Button("Keep Original Names") {
                commitPendingLanguageChange(translatingSavedPlaceNames: false)
            }
            Button("Cancel", role: .cancel) {
                pendingLanguageCode = nil
            }
        } message: {
            Text(
                "Translate the names of your saved places to \(pendingLanguageDisplayName)? Names without a translation stay unchanged."
            )
        }
    }

    // MARK: - Main Settings Categories

    /// The main form contains navigational summaries; detailed controls live
    /// in destination forms so the initial screen remains easy to scan.
    private var settingsForm: some View {
        Form {
            Section {
                navigationRow(
                    "Units",
                    value: resolvedTemperatureUnit.displayName(locale: locale),
                    systemImage: "ruler",
                    destination: .units
                )
                navigationRow(
                    "Language",
                    value: languageDisplayName(for: appLanguage),
                    systemImage: "globe",
                    destination: .language
                )
                textSizeMenuRow
                navigationRow(
                    "Theme",
                    value: theme.style.displayName(locale: locale),
                    systemImage: "circle.lefthalf.filled",
                    destination: .theme
                )
            } header: {
                sectionHeader("General")
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section {
                Button(action: onReplayTutorial) {
                    settingsLabel(
                        "Replay Tutorial",
                        systemImage: "play.circle"
                    )
                }

                Button(role: .destructive) {
                    showsResetAlert = true
                } label: {
                    settingsLabel(
                        "Clear Data and Reset App",
                        systemImage: "trash"
                    )
                }
            } header: {
                sectionHeader("Help")
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section {
                if let version = appVersion {
                    infoRow("Version", value: version, systemImage: "info.circle")
                }
                linkRow(
                    "Website",
                    systemImage: "safari",
                    url: URL(
                        string: "https://tomwuyutao.github.io/Weather-Atlas-Site/"
                    )
                )
                linkRow(
                    "Privacy Policy",
                    systemImage: "hand.raised",
                    url: URL(
                        string: "https://tomwuyutao.github.io/Weather-Atlas-Site/privacy/"
                    )
                )
                navigationRow(
                    "Attributions",
                    value: nil,
                    systemImage: "text.badge.checkmark",
                    destination: .attributions
                )
                sayHelloRow
            } header: {
                sectionHeader("About")
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
        .scrollContentBackground(.hidden)
        .background(theme.colors.background)
        .weatherContentColumn(standardMaximumWidth: .infinity)
        .task {
            // Attribution is provider data and may not be immediately present
            // in the weather store, so load it independently of forecasts.
            await model.weatherStore.loadAttributionIfNeeded()
        }
    }

    // MARK: - Destination Forms

    /// Value-based destination selection keeps navigation state in one enum
    /// instead of five separate Boolean flags.
    @ViewBuilder
    private func destinationView(
        _ destination: SettingsDestination
    ) -> some View {
        switch destination {
        case .units:
            unitsForm
                .navigationTitle("Units")
        case .language:
            languageForm
                .navigationTitle("Language")
        case .theme:
            themeForm
                .navigationTitle("Theme")
        case .attributions:
            attributionsForm
                .navigationTitle("Attributions")
        }
    }

    /// Unit choices write immediately to app storage, which lets weather text
    /// throughout the app reformat on its next SwiftUI update.
    private var unitsForm: some View {
        settingsDestinationForm {
            Section {
                ForEach(
                    [TemperatureUnit.celsius, .fahrenheit],
                    id: \.rawValue
                ) { unit in
                    selectionRow(
                        unit.displayName(locale: locale),
                        isSelected: resolvedTemperatureUnit == unit
                    ) {
                        temperatureUnit = unit.rawValue
                    }
                }
            } header: {
                sectionHeader("Temperature")
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section {
                ForEach(DistanceUnit.allCases, id: \.rawValue) { unit in
                    selectionRow(
                        unit.displayName(locale: locale),
                        isSelected:
                            (DistanceUnit(rawValue: distanceUnit)
                                ?? .kilometers) == unit
                    ) {
                        distanceUnit = unit.rawValue
                    }
                }
            } header: {
                sectionHeader("Distance")
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    private var languageForm: some View {
        settingsDestinationForm {
            Section {
                ForEach(
                    AppLanguageDefaults.supportedLanguageCodes,
                    id: \.self
                ) { code in
                    selectionRow(
                        languageDisplayName(for: code),
                        isSelected: appLanguage == code
                    ) {
                        requestLanguageChange(to: code)
                    }
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    /// Theme selection mutates the environment's shared theme object rather
    /// than locally styling this one screen.
    private var themeForm: some View {
        settingsDestinationForm {
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
                                    .foregroundStyle(
                                        theme.colors.secondaryText
                                    )

                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                }
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    /// Attribution is data-driven: WeatherKit's official mark is shown when
    /// its asynchronously loaded attribution object is available.
    private var attributionsForm: some View {
        settingsDestinationForm {
            Section("Weather") {
                if let attribution = model.weatherStore.weatherAttribution {
                    WeatherAttributionView(attribution: attribution)
                } else {
                    infoRow(
                        "Weather Data",
                        value: " Weather",
                        systemImage: "cloud.sun"
                    )
                }
                linkRow(
                    "Weather Legal Sources",
                    systemImage: "doc.text",
                    url: model.weatherStore.weatherAttribution?.legalPageURL
                )
                linkRow(
                    "About WeatherKit",
                    systemImage: "doc.text",
                    url: URL(string: "https://developer.apple.com/weatherkit/")
                )
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section("Maps") {
                infoRow("Map Data", value: " Map", systemImage: "map")
                linkRow(
                    "Maps Legal Sources",
                    systemImage: "doc.text",
                    url: URL(
                        string: "https://www.apple.com/legal/internet-services/maps/legal-en.html"
                    )
                )
                linkRow(
                    "About MapKit",
                    systemImage: "doc.text",
                    url: URL(
                        string: "https://developer.apple.com/documentation/mapkit/"
                    )
                )
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section("Search") {
                infoRow(
                    "Search",
                    value: "SimpleMaps World Cities",
                    systemImage: "magnifyingglass"
                )
                linkRow(
                    "About SimpleMaps",
                    systemImage: "doc.text",
                    url: URL(string: "https://simplemaps.com/data/world-cities")
                )
            }
            .listRowBackground(theme.colors.settingsRowFill)

            Section("Cities Data") {
                infoRow(
                    "Cities Data",
                    value: "SimpleMaps World Cities",
                    systemImage: "building.2"
                )
                linkRow(
                    "About SimpleMaps",
                    systemImage: "doc.text",
                    url: URL(string: "https://simplemaps.com/data/world-cities")
                )
                linkRow(
                    "GeoNames",
                    systemImage: "character.bubble",
                    url: URL(string: "https://www.geonames.org/")
                )
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    // MARK: - Reusable Rows and Formatting Helpers

    /// Applies the shared background treatment to every pushed settings form.
    private func settingsDestinationForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form(content: content)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .weatherContentColumn(standardMaximumWidth: .infinity)
    }

    private func settingsLabel(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.dotSun)

        }
    }

    private func sectionHeader(
        _ title: LocalizedStringKey
    ) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(theme.colors.primaryText)
    }

    private func infoRow(
        _ title: LocalizedStringKey,
        value: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text(value)
                .foregroundStyle(theme.colors.secondaryText)
        } label: {
            settingsLabel(title, systemImage: systemImage)
        }
    }

    /// A plain button gives consistent custom row styling while the enum state
    /// above still drives native NavigationStack destinations.
    private func navigationRow(
        _ title: LocalizedStringKey,
        value: String?,
        systemImage: String,
        destination: SettingsDestination
    ) -> some View {
        Button {
            self.destination = destination
        } label: {
            HStack(spacing: 8) {
                settingsLabel(title, systemImage: systemImage)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)

            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// A direct native menu keeps the text-size selection on the main Settings
    /// screen instead of pushing a slider-only destination.
    private var textSizeMenuRow: some View {
        Menu {
            Button {
                useSystemTextSize = true
            } label: {
                textSizeMenuOption(
                    localizedString("Follow System", locale: locale),
                    isSelected: useSystemTextSize
                )
            }

            Divider()

            ForEach(AppTextSizeLevel.allCases, id: \.rawValue) { level in
                Button {
                    useSystemTextSize = false
                    appTextSizeLevel = level.rawValue
                } label: {
                    textSizeMenuOption(
                        level.displayName(locale: locale),
                        isSelected: !useSystemTextSize
                            && textSizeLevel == level
                    )
                }
            }
        } label: {
            HStack(spacing: 8) {
                settingsLabel("Text Size", systemImage: "textformat.size")
                Spacer(minLength: 8)
                Text(
                    useSystemTextSize
                        ? localizedString("Follow System", locale: locale)
                        : textSizeLevel.displayName(locale: locale)
                )
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func textSizeMenuOption(
        _ title: String,
        isSelected: Bool
    ) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func selectionRow(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(theme.colors.primaryText)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)

                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)

    }

    @ViewBuilder
    private func linkRow(
        _ title: LocalizedStringKey,
        systemImage: String,
        url: URL?
    ) -> some View {
        if let url {
            Button {
                openURL(url)
            } label: {
                HStack {
                    settingsLabel(title, systemImage: systemImage)
                    Spacer(minLength: 8)
                    Text("View")
                        .foregroundStyle(theme.colors.secondaryText)
                    Image(systemName: "arrow.up.forward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.colors.secondaryText)

                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Copies the contact address intentionally, then confirms the action in a
    /// small native alert rather than opening the user's mail client.
    private var sayHelloRow: some View {
        Button {
            UIPasteboard.general.string = "yutao5726@gmail.com"
            showsCopiedNotice = true
        } label: {
            HStack {
                settingsLabel("Say Hello", systemImage: "envelope")
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(theme.colors.secondaryText)

            }
        }
        .buttonStyle(.plain)

        .alert("Email Copied", isPresented: $showsCopiedNotice) {
            Button("OK", role: .cancel) {}
        }
    }

    /// Canvas draws a compact diagonal light/dark swatch without bundling image
    /// assets for every theme option.
    private func themeIndicator(for style: AppThemeStyle) -> some View {
        let fills: (Color, Color)
        switch style {
        case .automatic:
            fills = (AppPalette.light.background, AppPalette.dark.background)
        case .automaticBlack:
            fills = (AppPalette.light.background, AppPalette.black.background)
        case .light:
            fills = (AppPalette.light.background, AppPalette.light.background)
        case .dark:
            fills = (AppPalette.dark.background, AppPalette.dark.background)
        case .black:
            fills = (AppPalette.black.background, AppPalette.black.background)
        }

        return Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(fills.1)
            )
            var firstHalf = Path()
            firstHalf.move(to: .zero)
            firstHalf.addLine(to: CGPoint(x: size.width, y: 0))
            firstHalf.addLine(to: CGPoint(x: 0, y: size.height))
            firstHalf.closeSubpath()
            context.fill(firstHalf, with: .color(fills.0))
        }
        .frame(width: 32, height: 32)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    theme.colors.secondaryText.opacity(0.28),
                    lineWidth: 0.75
                )
        }

    }

    private var resolvedTemperatureUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .systemDefault
    }

    private var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private func languageDisplayName(for code: String) -> String {
        // Show each option in its own language rather than localizing the
        // language name into the currently selected app language.
        switch code {
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
        default: code
        }
    }

    // MARK: - Saved-Place Name Translation

    /// Defers changing the app language until the person has chosen how saved
    /// place labels should behave in that language.
    private func requestLanguageChange(to code: String) {
        guard code != appLanguage,
              translatingPlaceNamesToLanguageCode == nil else {
            return
        }
        pendingLanguageCode = code
    }

    private var showsPlaceNameTranslationPrompt: Binding<Bool> {
        Binding(
            get: { pendingLanguageCode != nil },
            set: { isPresented in
                if !isPresented { pendingLanguageCode = nil }
            }
        )
    }

    private var pendingLanguageDisplayName: String {
        languageDisplayName(for: pendingLanguageCode ?? appLanguage)
    }

    /// Commits the selected language in both cases. Translation is opt-in for
    /// that language change; declining suppresses every saved-place translated
    /// label and restores the original saved text instead.
    private func commitPendingLanguageChange(
        translatingSavedPlaceNames: Bool
    ) {
        guard let targetLanguageCode = pendingLanguageCode else { return }
        pendingLanguageCode = nil
        appLanguage = targetLanguageCode
        SavedPlaceNameTranslationPreference.setEnabled(
            translatingSavedPlaceNames
        )

        guard translatingSavedPlaceNames,
              !model.placesStore.allPlaces.isEmpty else {
            return
        }
        translatingPlaceNamesToLanguageCode = targetLanguageCode
        Task {
            await translateSavedPlaceNames(to: targetLanguageCode)
        }
    }

    /// Resolves the original saved label — either the city name or the person's
    /// rename — only through the bundled GeoNames data. A label with no GeoNames
    /// match is deliberately omitted, which keeps the original visible.
    private func translateSavedPlaceNames(to targetLanguageCode: String) async {
        guard translatingPlaceNamesToLanguageCode == targetLanguageCode else {
            return
        }
        var translatedNames: [SavedPlace.ID: String] = [:]
        let targetLocale = Locale(identifier: targetLanguageCode)
        for place in model.placesStore.allPlaces {
            guard let translatedName = await CityNameLocalizationCatalog.localizedName(
                matchingSavedPlaceLabel: place.translationSourceName,
                locale: targetLocale
            ) else {
                continue
            }
            translatedNames[place.id] = translatedName
        }
        do {
            try model.placesStore.replaceTranslatedDisplayNames(
                translatedNames,
                languageIdentifier: targetLanguageCode
            )
        } catch {
            resetError = SettingsResetError(
                message: localizedString(
                    "Translated saved-place names could not be saved. Original names are unchanged.",
                    locale: targetLocale
                )
            )
        }
        finishSavedPlaceNameTranslation()
    }

    private func finishSavedPlaceNameTranslation() {
        translatingPlaceNamesToLanguageCode = nil
    }

    // MARK: - Reset Handling

    /// Adapts optional error state to the Boolean binding expected by `alert`.
    private var showsResetError: Binding<Bool> {
        Binding(
            get: { resetError != nil },
            set: { isPresented in
                if !isPresented {
                    resetError = nil
                }
            }
        )
    }

    private func resetApp() {
        // The root owns the multi-store reset sequence. Settings only presents
        // the destructive confirmation and turns a thrown error into an alert.
        do {
            try onResetApp()
        } catch {
            resetError = SettingsResetError(
                message: localizedPlacesErrorDescription(error, locale: locale)
            )
        }
    }
}

// MARK: - Weather Attribution

/// Apple-provided attribution mark with a native legal-page link.
///
/// Keeps Apple Weather's official attribution visible and links directly to
/// the provider's legal page.
private struct WeatherAttributionView: View {
    let attribution: WeatherAttribution

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Link(destination: attribution.legalPageURL) {
            HStack {
                // `AsyncImage` is explicit about loading and failure so the
                // attribution row remains useful even if the mark URL is slow
                // or unavailable on the current network.
                AsyncImage(url: markURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxWidth: 120,
                                maxHeight: 24,
                                alignment: .leading
                            )
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 24, minHeight: 24)

                    case .failure:
                        Text(attribution.serviceName)
                            .font(.footnote)
                    @unknown default:
                        EmptyView()
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            }
            .contentShape(.rect)
        }
    }

    /// WeatherKit provides separate light and dark artwork, so select the one
    /// with sufficient contrast for the currently resolved color scheme.
    private var markURL: URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }
}

// MARK: - Settings Navigation Values

/// The finite list of pushed settings screens. `rawValue` supplies stable
/// identity for `navigationDestination(item:)`.
private enum SettingsDestination: String, Hashable, Identifiable {
    case units
    case language
    case theme
    case attributions

    var id: String { rawValue }
}

/// Error wrapper required for presentation via `alert(item:)`.
private struct SettingsResetError: Identifiable {
    let id = UUID()
    let message: String
}
