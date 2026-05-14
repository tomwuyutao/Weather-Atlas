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
    @AppStorage("isGridView") private var isGridView: Bool = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let weatherService: WeatherService
    let onResetLists: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors
    @Environment(\.locale) private var locale

    @State private var showingResetConfirmation = false

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    private var selectedDistanceUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnit) ?? .kilometers
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        settingsSection(title: localizedString("General", locale: locale)) {
                            settingsMenuRow(icon: "thermometer.medium", label: localizedString("Temperature", locale: locale), value: selectedUnit.symbol) {
                                Picker(selection: Binding(get: { temperatureUnit }, set: { temperatureUnit = $0 })) {
                                    Text("Celsius (°C)").tag(TemperatureUnit.celsius.rawValue)
                                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit.rawValue)
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            }

                            rowDivider()

                            settingsMenuRow(icon: "ruler", label: localizedString("Distance", locale: locale), value: selectedDistanceUnit.symbol) {
                                Picker(selection: Binding(get: { distanceUnit }, set: { distanceUnit = $0 })) {
                                    Text("Kilometers (km)").tag(DistanceUnit.kilometers.rawValue)
                                    Text("Miles (mi)").tag(DistanceUnit.miles.rawValue)
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            }

                            rowDivider()

                            settingsMenuRow(icon: "globe", label: localizedString("Language", locale: locale), value: appLanguage == "zh-Hans" ? "中文" : "English") {
                                Picker(selection: Binding(get: { appLanguage }, set: { appLanguage = $0 })) {
                                    Text("English").tag("en")
                                    Text("中文").tag("zh-Hans")
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            }

                            rowDivider()

                            settingsMenuRow(icon: "circle.lefthalf.filled", label: localizedString("Theme", locale: locale), value: theme.style.displayName) {
                                Picker(selection: Binding(get: { theme.style }, set: { theme.style = $0 })) {
                                    Text("Light").tag(AppThemeStyle.light)
                                    Text("Dark").tag(AppThemeStyle.dark)
                                    Text("Auto").tag(AppThemeStyle.automatic)
                                } label: { EmptyView() }
                                .pickerStyle(.inline)
                            }

                            rowDivider()

                            Button {
                                showingResetConfirmation = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(colors.accent)
                                        .frame(width: 22)
                                    Text(localizedString("Reset Lists to Defaults", locale: locale))
                                        .font(.avenir(.body, weight: .medium))
                                        .foregroundStyle(colors.accent)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        settingsSection(title: localizedString("About", locale: locale)) {
                            settingsRow(icon: "info.circle", label: localizedString("Version", locale: locale), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            rowDivider()
                            settingsRow(icon: "cloud.sun", label: localizedString("Powered by", locale: locale), value: "Apple Weather")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle(localizedString("Settings", locale: locale))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    settingsCloseButton
                }
                .sharedBackgroundVisibility(.hidden)
                #else
                ToolbarItem {
                    settingsCloseButton
                }
                #endif
            }
            #if os(iOS)
            .toolbarBackground(colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .overlay {
                resetConfirmationOverlay
            }
            .animation(.easeOut(duration: 0.2), value: showingResetConfirmation)
        }
    }

    private var settingsCloseButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(colors.primaryText)
                .frame(width: 44, height: 44)
                .themedGlass(in: .circle)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var resetConfirmationOverlay: some View {
        if showingResetConfirmation {
            colors.modalOverlay
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showingResetConfirmation = false
                    }
                }

            VStack(spacing: 0) {
                Text("Reset Lists")
                    .font(.avenir(.headline, weight: .bold))
                    .foregroundStyle(colors.primaryText)
                    .padding(.top, 28)
                    .padding(.bottom, 10)

                Text("This will reset all city lists back to their defaults. Any cities you added or removed will be lost.")
                    .font(.avenir(.subheadline, weight: .regular))
                    .foregroundStyle(colors.primaryText.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                Divider()
                    .background(colors.primaryText.opacity(0.1))

                HStack(spacing: 0) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingResetConfirmation = false
                        }
                    } label: {
                        Text(localizedString("Cancel", locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .frame(height: 44)
                        .background(colors.primaryText.opacity(0.1))

                    Button {
                        onResetLists()
                        withAnimation(.easeOut(duration: 0.2)) {
                            showingResetConfirmation = false
                        }
                    } label: {
                        Text(localizedString("Reset", locale: locale))
                            .font(.avenir(.body, weight: .semibold))
                            .foregroundStyle(colors.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 280)
            .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 16))
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.avenir(.caption, weight: .semibold))
                .foregroundStyle(colors.primaryText.opacity(0.45))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func rowDivider() -> some View {
        Rectangle()
            .fill(colors.primaryText.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 50)
    }

    private func settingsRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.accent)
                .frame(width: 22)
            Text(label)
                .font(.avenir(.body, weight: .medium))
                .foregroundStyle(colors.primaryText)
            Spacer()
            Text(value)
                .font(.avenir(.body, weight: .medium))
                .foregroundStyle(colors.primaryText.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func settingsMenuRow<Content: View>(icon: String, label: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.accent)
                    .frame(width: 22)
                Text(label)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                Text(value)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(colors.primaryText.opacity(0.55))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.primaryText.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
