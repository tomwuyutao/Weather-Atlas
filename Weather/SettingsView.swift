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
    @State private var showingTempPicker = false
    @State private var showingViewPicker = false
    @State private var showingLanguagePicker = false
    @State private var showingThemePicker = false

    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }

    var body: some View {
        NavigationStack {
            ZStack {
                colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {

                        // MARK: General
                        settingsSection(title: "General") {
                            // Temperature
                            settingsRow(icon: "thermometer.medium", label: "Temperature", value: selectedUnit.symbol, isPresented: $showingTempPicker) {
                                showingTempPicker = true
                            } popoverContent: {
                                VStack(alignment: .leading, spacing: 0) {
                                    menuRow(icon: "thermometer.medium", label: "Celsius (°C)", isSelected: selectedUnit == .celsius) {
                                        temperatureUnit = TemperatureUnit.celsius.rawValue
                                        showingTempPicker = false
                                    }
                                    menuRow(icon: "thermometer.medium", label: "Fahrenheit (°F)", isSelected: selectedUnit == .fahrenheit) {
                                        temperatureUnit = TemperatureUnit.fahrenheit.rawValue
                                        showingTempPicker = false
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(width: 220)
                                .themedPopoverBackground()
                                .presentationCompactAdaptation(.popover)
                            }

                            rowDivider()

                            // Default View
                            settingsRow(
                                icon: isGridView ? "square.grid.2x2" : "list.bullet",
                                label: "Default View",
                                value: isGridView ? "Grid" : "List",
                                isPresented: $showingViewPicker
                            ) {
                                showingViewPicker = true
                            } popoverContent: {
                                VStack(alignment: .leading, spacing: 0) {
                                    menuRow(icon: "list.bullet", label: "List", isSelected: !isGridView) {
                                        isGridView = false
                                        showingViewPicker = false
                                    }
                                    menuRow(icon: "square.grid.2x2", label: "Grid", isSelected: isGridView) {
                                        isGridView = true
                                        showingViewPicker = false
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(width: 220)
                                .themedPopoverBackground()
                                .presentationCompactAdaptation(.popover)
                            }

                            rowDivider()

                            // Language
                            settingsRow(
                                icon: "globe",
                                label: "Language",
                                value: appLanguage == "zh-Hans" ? "中文" : "English",
                                isPresented: $showingLanguagePicker
                            ) {
                                showingLanguagePicker = true
                            } popoverContent: {
                                VStack(alignment: .leading, spacing: 0) {
                                    menuRow(icon: "globe", label: "English", isSelected: appLanguage == "en") {
                                        appLanguage = "en"
                                        showingLanguagePicker = false
                                    }
                                    menuRow(icon: "globe", label: "中文", isSelected: appLanguage == "zh-Hans") {
                                        appLanguage = "zh-Hans"
                                        showingLanguagePicker = false
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(width: 220)
                                .themedPopoverBackground()
                                .presentationCompactAdaptation(.popover)
                            }

                            rowDivider()

                            // Theme
                            settingsRow(
                                icon: "circle.lefthalf.filled",
                                label: "Theme",
                                value: theme.style.displayName,
                                isPresented: $showingThemePicker
                            ) {
                                showingThemePicker = true
                            } popoverContent: {
                                VStack(alignment: .leading, spacing: 0) {
                                    menuRow(icon: "sun.max", label: "Light", isSelected: theme.style == .light) {
                                        theme.style = .light
                                        showingThemePicker = false
                                    }
                                    menuRow(icon: "moon", label: "Dark", isSelected: theme.style == .dark) {
                                        theme.style = .dark
                                        showingThemePicker = false
                                    }
                                    menuRow(icon: "circle.lefthalf.filled", label: "Auto", isSelected: theme.style == .automatic) {
                                        theme.style = .automatic
                                        showingThemePicker = false
                                    }
                                }
                                .padding(.vertical, 8)
                                .frame(width: 220)
                                .themedPopoverBackground()
                                .presentationCompactAdaptation(.popover)
                            }

                            rowDivider()

                            // Reset
                            menuRow(icon: "arrow.counterclockwise", label: "Reset Lists to Defaults", tint: colors.accent) {
                                showingResetConfirmation = true
                            }
                        }

                        // MARK: About
                        settingsSection(title: "About") {
                            settingsRow(icon: "info.circle", label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")

                            rowDivider()

                            settingsRow(icon: "cloud.sun", label: "Powered by", value: "Apple Weather")
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

    // MARK: - Section / Row Helpers

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

    /// Row with a tappable chevron — opens a popover picker.
    @ViewBuilder
    private func settingsRow(icon: String, label: String, value: String, isPresented: Binding<Bool>, action: @escaping () -> Void, @ViewBuilder popoverContent: @escaping () -> some View) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.primaryText.opacity(0.55))
                    .frame(width: 22)
                Text(label)
                    .font(.avenir(.body, weight: .medium))
                    .foregroundStyle(colors.primaryText)
                Spacer()
                Text(value)
                    .font(.avenir(.body, weight: .regular))
                    .foregroundStyle(colors.primaryText.opacity(0.45))
                    .popover(isPresented: isPresented, attachmentAnchor: .point(.bottom), arrowEdge: .top) {
                        popoverContent()
                    }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.primaryText.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Display-only row (no action, no chevron).
    @ViewBuilder
    private func settingsRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(colors.primaryText.opacity(0.55))
                .frame(width: 22)
            Text(label)
                .font(.avenir(.body, weight: .medium))
                .foregroundStyle(colors.primaryText)
            Spacer()
            Text(value)
                .font(.avenir(.body, weight: .regular))
                .foregroundStyle(colors.primaryText.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    /// A single option row inside a popover menu — label + small dot on the right for selected.
    @ViewBuilder
    private func menuRow(icon: String, label: String, isSelected: Bool = false, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.avenir(.body, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                Spacer()
                if isSelected {
                    Circle()
                        .fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Color.primary))
                        .frame(width: 6, height: 6)
                        .frame(width: 13)
                }
            }
            .padding(.leading, 24)
            .padding(.trailing, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
