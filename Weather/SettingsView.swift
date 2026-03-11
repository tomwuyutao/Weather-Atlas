//
//  SettingsView.swift
//  Weather
//
//  Created by Tom on 02/03/2026.
//

import SwiftUI

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
}

struct SettingsView: View {
    @AppStorage("temperatureUnit") private var temperatureUnit: String = TemperatureUnit.celsius.rawValue
    @AppStorage("isGridView") private var isGridView: Bool = false
    @AppStorage("appLanguage") private var appLanguage: String = "en"
    let weatherService: WeatherService
    let onResetLists: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors

    @State private var showingResetConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // MARK: General
                        settingsSection(title: "General") {
                            // Temperature
                            settingsRow(icon: "thermometer.medium", label: "Temperature") {
                                Picker("", selection: $temperatureUnit) {
                                    Text("°C").tag(TemperatureUnit.celsius.rawValue)
                                    Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }

                            rowDivider()

                            // Default View
                            settingsRow(icon: isGridView ? "square.grid.2x2" : "list.bullet", label: "Default View") {
                                Picker("", selection: $isGridView) {
                                    Text("List").tag(false)
                                    Text("Grid").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                            }

                            rowDivider()

                            // Language
                            settingsRow(icon: "globe", label: "Language") {
                                Picker("", selection: $appLanguage) {
                                    Text("English").tag("en")
                                    Text("中文").tag("zh-Hans")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 140)
                            }

                            rowDivider()

                            // Theme
                            settingsRow(icon: "circle.lefthalf.filled", label: "Theme") {
                                let themeBinding = Bindable(theme)
                                Picker("", selection: themeBinding.style) {
                                    ForEach(AppThemeStyle.allCases, id: \.self) { style in
                                        Text(style.displayName).tag(style)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            rowDivider()

                            // Reset
                            Button {
                                showingResetConfirmation = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(colors.primaryText.opacity(0.55))
                                        .frame(width: 22)
                                    Text("Reset Lists to Defaults")
                                        .font(.avenir(.body, weight: .medium))
                                        .foregroundStyle(colors.primaryText)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        // MARK: About
                        settingsSection(title: "About") {
                            settingsRow(icon: "info.circle", label: "Version") {
                                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                                    .font(.avenir(.body, weight: .regular))
                                    .foregroundStyle(colors.primaryText.opacity(0.5))
                            }

                            rowDivider()

                            settingsRow(icon: "cloud.sun", label: "Powered by") {
                                Text("Apple Weather")
                                    .font(.avenir(.body, weight: .regular))
                                    .foregroundStyle(colors.primaryText.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(colors.primaryText.opacity(0.45))
                    }
                }
            }
            .toolbarBackground(colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .overlay {
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
                            .padding(.top, 20)
                            .padding(.bottom, 8)

                        Text("This will reset all city lists back to their defaults. Any cities you added or removed will be lost.")
                            .font(.avenir(.subheadline, weight: .regular))
                            .foregroundStyle(colors.primaryText.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)

                        Divider()
                            .background(colors.primaryText.opacity(0.1))

                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showingResetConfirmation = false
                                }
                            } label: {
                                Text("Cancel")
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
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showingResetConfirmation = false
                                }
                                onResetLists()
                                dismiss()
                            } label: {
                                Text("Reset")
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(colors.primaryText.opacity(0.07), lineWidth: 1)
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: showingResetConfirmation)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.avenir(.footnote, weight: .semibold))
                .foregroundStyle(colors.primaryText.opacity(0.45))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colors.primaryText.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.primaryText.opacity(0.55))
                .frame(width: 22)
            Text(label)
                .font(.avenir(.body, weight: .medium))
                .foregroundStyle(colors.primaryText)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Rectangle()
            .fill(colors.primaryText.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }
}

#Preview("Settings") {
    SettingsView(
        weatherService: WeatherService(),
        onResetLists: { }
    )
}
