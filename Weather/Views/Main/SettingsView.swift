//
//  SettingsView.swift
//  Weather
//
//  Purpose: Presents Weather Atlas's warm, compact settings hierarchy using
//  the place-owned architecture.
//

import SwiftUI
import UIKit
import WeatherKit

struct SettingsView: View {
    let model: WeatherAtlasModel
    let onReplayTutorial: () -> Void
    let onResetApp: () throws -> Void

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
    @State private var showingEmailCopied = false
    @State private var showingResetConfirmation = false
    @State private var resetError: SettingsResetError?
    @State private var textSizeSliderValue = Double(
        AppTextSizeLevel.defaultRawValue
    )

    private var selectedTextSizeLevel: AppTextSizeLevel {
        AppTextSizeLevel.level(clamping: appTextSizeLevel)
    }

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("")
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
        // Live Dynamic Type changes can rebuild the text-size destination
        // during an edge swipe. Keep interactive pop disabled until that
        // destination is dismissed, then restore its previous UIKit state.
        .background(
            NavigationPopGestureDisabler(
                isDisabled: destination == .textSize
            )
        )
        .background(theme.colors.background.ignoresSafeArea())
        .preferredColorScheme(theme.preferredColorScheme)
        .presentationBackground(theme.colors.background)
        .confirmationDialog(
            "Clear Data and Reset App",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
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
            isPresented: resetErrorIsPresented,
            presenting: resetError
        ) { _ in
            Button("OK") {
                resetError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

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
                navigationRow(
                    "Text Size",
                    value: useSystemTextSize
                        ? localizedString("System", locale: locale)
                        : selectedTextSizeLevel.displayName(locale: locale),
                    systemImage: "textformat.size",
                    destination: .textSize
                )
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
                    settingsLabel("Replay Tutorial", systemImage: "play.circle")
                }

                Button(role: .destructive) {
                    showingResetConfirmation = true
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
        .task {
            await model.weatherStore.loadAttributionIfNeeded()
        }
    }

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
        case .textSize:
            textSizeForm
                .navigationTitle("Text Size")
        case .theme:
            themeForm
                .navigationTitle("Theme")
        case .attributions:
            attributionsForm
                .navigationTitle("Attributions")
        }
    }

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
                        appLanguage = code
                    }
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    private var textSizeForm: some View {
        settingsDestinationForm {
            Section {
                Toggle("Use System Text Size", isOn: $useSystemTextSize)
                    .tint(theme.colors.accent)

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Text(verbatim: "A")
                            .font(.system(size: 18))
                            .frame(width: 44)

                        Slider(
                            value: $textSizeSliderValue,
                            in: Double(
                                AppTextSizeLevel.minimumSelectableRawValue
                            )...Double(
                                AppTextSizeLevel.maximumSelectableRawValue
                            ),
                            step: 1
                        )
                        .tint(theme.colors.accent)
                        .onChange(of: textSizeSliderValue) { _, newValue in
                            appTextSizeLevel = Int(newValue.rounded())
                        }

                        Text(verbatim: "A")
                            .font(.system(size: 34))
                            .frame(width: 44)
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                    .opacity(useSystemTextSize ? 0.42 : 1)

                    Text(
                        useSystemTextSize
                            ? localizedString("System", locale: locale)
                            : selectedTextSizeLevel.displayName(locale: locale)
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
                }
                .disabled(useSystemTextSize)
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
        .onAppear {
            textSizeSliderValue = Double(selectedTextSizeLevel.rawValue)
        }
    }

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

    private var attributionsForm: some View {
        settingsDestinationForm {
            Section("Weather") {
                if let attribution = model.weatherStore.weatherAttribution {
                    AppleWeatherCombinedMarkRow(attribution: attribution)
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
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    private func settingsDestinationForm<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form(content: content)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
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
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

    private var sayHelloRow: some View {
        Button {
            UIPasteboard.general.string = "yutao5726@gmail.com"
            showingEmailCopied = true
        } label: {
            HStack {
                settingsLabel("Say Hello", systemImage: "envelope")
                Spacer(minLength: 8)
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .alert("Email Copied", isPresented: $showingEmailCopied) {
            Button("OK", role: .cancel) {}
        }
    }

    private func themeIndicator(for style: AppThemeStyle) -> some View {
        let dark = Color(hex: 0x262626)
        let fills: (Color, Color)
        switch style {
        case .automatic:
            fills = (AppPalette.light.background, dark)
        case .automaticBlack:
            fills = (AppPalette.light.background, AppPalette.black.background)
        case .light:
            fills = (AppPalette.light.background, AppPalette.light.background)
        case .dark:
            fills = (dark, dark)
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

    private var resetErrorIsPresented: Binding<Bool> {
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
        do {
            try onResetApp()
        } catch {
            resetError = SettingsResetError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }
}

/// Displays WeatherKit's official mark for the active interface appearance.
private struct AppleWeatherCombinedMarkRow: View {
    let attribution: WeatherAttribution

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Weather attribution")
    }

    private var markURL: URL {
        colorScheme == .dark
            ? attribution.combinedMarkDarkURL
            : attribution.combinedMarkLightURL
    }
}

// MARK: - Navigation Gesture Bridge

/// Temporarily disables interactive navigation pop while Text Size is open.
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

    func updateUIViewController(
        _ uiViewController: UIViewController,
        context: Context
    ) {
        DispatchQueue.main.async {
            guard let gestureRecognizer = uiViewController
                .navigationController?
                .interactivePopGestureRecognizer else {
                return
            }

            context.coordinator.gestureRecognizer = gestureRecognizer
            if isDisabled {
                if context.coordinator.originalIsEnabled == nil {
                    context.coordinator.originalIsEnabled =
                        gestureRecognizer.isEnabled
                }
                gestureRecognizer.isEnabled = false
            } else if let originalIsEnabled =
                context.coordinator.originalIsEnabled {
                gestureRecognizer.isEnabled = originalIsEnabled
                context.coordinator.originalIsEnabled = nil
            }
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: UIViewController,
        coordinator: Coordinator
    ) {
        if let originalIsEnabled = coordinator.originalIsEnabled {
            coordinator.gestureRecognizer?.isEnabled = originalIsEnabled
        }
    }
}

private enum SettingsDestination: String, Hashable, Identifiable {
    case units
    case language
    case textSize
    case theme
    case attributions

    var id: String { rawValue }
}

private struct SettingsResetError: Identifiable {
    let id = UUID()
    let message: String
}
