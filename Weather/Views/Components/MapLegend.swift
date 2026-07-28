//
//  MapLegend.swift
//  Weather
//
//  Purpose: Draws the floating map legend for weather dots and metric
//  gradients across the supported overlay modes.
//

import SwiftUI

// MARK: - Floating Map Legend

/// Floating explanation of the active map marker metric and color scale.
struct MapFloatingLegend: View {
    /// Raw overlay-mode identifier shared with map controls.
    let overlayMode: String
    /// Whether to use the reduced detail-map presentation.
    var compact: Bool = false
    /// Optional close action for the full-map floating legend.
    var onClose: (() -> Void)? = nil

    /// App-selected locale used for labels and number formatting.
    @Environment(\.locale) private var locale
    /// Resolved appearance used for shadow tuning.
    @Environment(\.colorScheme) private var colorScheme
    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Persisted raw temperature preference.
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue

    /// Convenience access to the resolved semantic colors.
    private var palette: ThemeColors {
        theme.colors
    }

    // MARK: - Localized Legend Layout

    /// Cloudy-category label with an optional deliberate compact line break.
    private var wrappedCloudyConditionsTitle: String {
        let title = localizedString("Cloudy, Windy, Snowy, Foggy", locale: locale)
        let separator = title.contains("、") ? "、" : ","
        let conditions = title
            .components(separatedBy: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard conditions.count == 4 else { return title }

        let joiner = separator == "、" ? separator : "\(separator) "
        let firstLine = conditions.prefix(2).joined(separator: joiner)
        let secondLine = conditions.suffix(2).joined(separator: joiner)
        return "\(firstLine)\(separator)\n\(secondLine)"
    }

    // MARK: - Overlay Color Scales

    /// Maps Celsius into the same continuous color ramp used by annotations.
    private func temperatureColor(celsius: Double) -> Color {
        if celsius <= 0 {
            return palette.dotRain.interpolated(with: palette.dotDrizzle, by: max(0, min(1, (celsius + 20) / 20)))
        } else if celsius <= 10 {
            return palette.dotDrizzle.interpolated(with: palette.dotCloudy, by: max(0, min(1, celsius / 10)))
        } else if celsius <= 20 {
            // Compensate partly-sunny yellow for MapKit's muted saturation.
            return palette.dotCloudy.interpolated(
                with: palette.dotPartlyCloudy.interpolated(with: palette.filterSunny, by: 0.18),
                by: max(0, min(1, (celsius - 10) / 10))
            )
        } else {
            return palette.dotPartlyCloudy
                .interpolated(with: palette.filterSunny, by: 0.18)
                .interpolated(
                    with: palette.destructive,
                    by: max(0, min(1, (celsius - 20) / 20))
                )
        }
    }

    /// Maps cloud percentage into its marker gradient.
    private func cloudColor(percent: Double) -> Color {
        palette.dotRain.interpolated(with: palette.dotCloudy, by: max(0, min(1, percent / 100.0)))
    }

    /// Maps precipitation percentage into its marker gradient.
    private func precipitationColor(percent: Double) -> Color {
        palette.dotCloudy.interpolated(with: palette.dotDrizzle, by: max(0, min(1, percent / 100.0)))
    }

    /// Maps a normalized UV value into its marker gradient.
    private func uvColor(fraction: Double) -> Color {
        palette.dotCloudy.interpolated(with: palette.destructive, by: max(0, min(1, fraction)))
    }

    // MARK: - Gradient legend

    /// Builds a vertical continuous scale with localized endpoint labels.
    private func verticalGradientLegend(colors gradColors: [Color], labels: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            LinearGradient(colors: gradColors, startPoint: .top, endPoint: .bottom)
                .frame(width: compact ? 8 : 10, height: compact ? 112 : 132)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.colors.secondaryText)
                    if index < labels.count - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: compact ? 112 : 132)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Body

    /// Builds the adaptive floating legend card.
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            legendContent
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 10 : 12)
        .padding(.trailing, onClose == nil ? 0 : 20)
        // Continuous scales are narrower than the categorical weather legend.
        .frame(
            width: overlayMode == "weather" ? nil : (compact ? 112 : 108),
            alignment: .leading
        )
        .themedGlass(in: .rect(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(theme.colors.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(compact ? -9 : -8)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in })
        .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
        .fixedSize(horizontal: true, vertical: false)
        .id("\(overlayMode)-\(colorScheme == .dark ? "dark" : "light")")
    }

    @ViewBuilder
    /// Selects categorical or continuous legend content for the overlay mode.
    private var legendContent: some View {
        switch overlayMode {
        case "weather":
            // Show every recognized condition category and semantic dot color.
            VStack(alignment: .leading, spacing: compact ? 9 : 11) {
                ForEach(Array([
                    (localizedString("Clear", locale: locale), palette.dotSun),
                    (localizedString("Partly Sunny", locale: locale), palette.dotPartlyCloudy),
                    (localizedString("Rain", locale: locale), palette.dotRain),
                    (localizedString("Drizzle", locale: locale), palette.dotDrizzle),
                    (wrappedCloudyConditionsTitle, palette.dotCloudy)
                ].enumerated()), id: \.offset) { _, item in
                    conditionEntry(title: item.0, color: item.1)
                }
            }
        case "temperature":
            verticalGradientLegend(
                colors: [
                    temperatureColor(celsius: 40),
                    temperatureColor(celsius: 20),
                    temperatureColor(celsius: 10),
                    temperatureColor(celsius: 0),
                    temperatureColor(celsius: -20)
                ],
                // Resolve obsolete automatic values before choosing endpoints.
                labels: (TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic).resolved == .fahrenheit
                    ? ["104°F", "68°F", "50°F", "32°F", "-4°F"]
                    : ["40°C", "20°C", "10°C", "0°C", "-20°C"]
            )
        case "cloudCover":
            verticalGradientLegend(
                colors: [
                    cloudColor(percent: 100),
                    cloudColor(percent: 66),
                    cloudColor(percent: 33),
                    cloudColor(percent: 0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case "precipitation":
            verticalGradientLegend(
                colors: [
                    precipitationColor(percent: 100),
                    precipitationColor(percent: 66),
                    precipitationColor(percent: 33),
                    precipitationColor(percent: 0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case "uvIndex":
            verticalGradientLegend(
                colors: [
                    uvColor(fraction: 1.0),
                    uvColor(fraction: 0.82),
                    uvColor(fraction: 0.55),
                    uvColor(fraction: 0.27),
                    uvColor(fraction: 0)
                ],
                labels: ["11+", "9", "6", "3", "0"]
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Weather dot legend

    /// Builds one condition name and marker sample row.
    private func conditionEntry(title: String, color: Color) -> some View {
        let isWrappedCondition = title.contains("\n")
        let rowAlignment: VerticalAlignment = isWrappedCondition ? .top : .center

        return HStack(alignment: rowAlignment, spacing: compact ? 10 : 12) {
            Circle()
                .fill(color)
                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                .shadow(color: color.opacity(0.5), radius: 2)
                .padding(.top, isWrappedCondition ? (compact ? 4 : 5) : 0)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

}
