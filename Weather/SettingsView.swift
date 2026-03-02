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
    let weatherService: WeatherService
    let onResetLists: () -> Void
    @Environment(\.dismiss) private var dismiss
    
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
                        Spacer()
                        Picker("", selection: $temperatureUnit) {
                            Text("°C").tag(TemperatureUnit.celsius.rawValue)
                            Text("°F").tag(TemperatureUnit.fahrenheit.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                    
                    // Default View
                    HStack {
                        Label("Default View", systemImage: isGridView ? "square.grid.2x2" : "list.bullet")
                            .font(.avenir(.body, weight: .medium))
                        Spacer()
                        Picker("", selection: $isGridView) {
                            Text("List").tag(false)
                            Text("Grid").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                    }
                    
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        Label("Reset Lists to Defaults", systemImage: "arrow.counterclockwise")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("General")
                        .font(.avenir(.footnote, weight: .medium))
                }
                
                // MARK: - About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                            .font(.avenir(.body, weight: .medium))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                            .font(.avenir(.body, weight: .regular))
                    }
                    
                    HStack {
                        Label("Powered by", systemImage: "cloud.sun")
                            .font(.avenir(.body, weight: .medium))
                        Spacer()
                        Text("Apple Weather")
                            .foregroundStyle(.secondary)
                            .font(.avenir(.body, weight: .regular))
                    }
                    
                    Link(destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!) {
                        HStack {
                            Label("Legal Attribution", systemImage: "doc.text")
                                .font(.avenir(.body, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
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
            .alert("Reset Lists", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    onResetLists()
                    dismiss()
                }
            } message: {
                Text("This will reset all city lists back to their defaults. Any cities you added or removed will be lost.")
            }
        }
    }
}

#Preview {
    SettingsView(
        weatherService: WeatherService(),
        onResetLists: { }
    )
}
