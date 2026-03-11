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
    
    @State private var showingResetConfirmation = false
    
    private var selectedUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnit) ?? .celsius
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Display
                Section {
                    // Temperature Unit
                    HStack {
                        Label("Temperature", systemImage: "thermometer.medium")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Picker("", selection: $temperatureUnit) {
                            Text("°C").tag(TemperatureUnit.celsius.rawValue)
                            Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        .tint(.primary)
                    }
                    
                    // Default View
                    HStack {
                        Label("Default View", systemImage: isGridView ? "square.grid.2x2" : "list.bullet")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Picker("", selection: $isGridView) {
                            Text("List").tag(false)
                            Text("Grid").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        .tint(.primary)
                    }
                    
                    // Language
                    HStack {
                        Label("Language", systemImage: "globe")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Picker("", selection: $appLanguage) {
                            Text("English").tag("en")
                            Text("中文").tag("zh-Hans")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                        .tint(.primary)
                    }
                    
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Lists to Defaults", systemImage: "arrow.counterclockwise")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("General")
                        .font(.avenir(.footnote, weight: .medium))
                }
                
                // MARK: - About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                            .font(.avenir(.body, weight: .regular))
                    }
                    
                    HStack {
                        Label("Powered by", systemImage: "cloud.sun")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("Apple Weather")
                            .foregroundStyle(.secondary)
                            .font(.avenir(.body, weight: .regular))
                    }
                } header: {
                    Text("About")
                        .font(.avenir(.footnote, weight: .medium))
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
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if showingResetConfirmation {
                    theme.colors.modalOverlay
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showingResetConfirmation = false
                            }
                        }
                    
                    VStack(spacing: 0) {
                        Text("Reset Lists")
                            .font(.avenir(.headline, weight: .bold))
                            .padding(.top, 20)
                            .padding(.bottom, 8)
                        
                        Text("This will reset all city lists back to their defaults. Any cities you added or removed will be lost.")
                            .font(.avenir(.subheadline, weight: .regular))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                        
                        Divider()
                        
                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showingResetConfirmation = false
                                }
                            } label: {
                                Text("Cancel")
                                    .font(.avenir(.body, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()
                                .frame(height: 44)
                            
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    showingResetConfirmation = false
                                }
                                onResetLists()
                                dismiss()
                            } label: {
                                Text("Reset")
                                    .font(.avenir(.body, weight: .semibold))
                                    .foregroundStyle(theme.colors.destructive)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 280)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: showingResetConfirmation)
        }
    }
}

#Preview("Settings") {
    SettingsView(
        weatherService: WeatherService(),
        onResetLists: { }
    )
}
