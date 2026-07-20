//
//  Legend.swift
//  Weather
//
//  Purpose: Draws the floating map legend for weather dots and metric
//  gradients across the supported overlay modes.
//

import SwiftUI

// MARK: - Floating Map Legend

struct MapFloatingLegend: View {
    let overlayMode: String
    var compact: Bool = false
    var onClose: (() -> Void)? = nil

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.defaultRawValue

    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .automatic
    }

    private var palette: ThemeColors {
        theme.colors
    }

    private var saturatedPartlySunnyColor: Color {
        palette.dotPartlyCloudy.interpolated(with: palette.filterSunny, by: 0.18)
    }

    private var legendWidth: CGFloat {
        overlayMode == "weather" ? (compact ? 168 : 162) : (compact ? 112 : 108)
    }

    private var legendLabelFont: Font {
        .caption.weight(.medium)
    }

    private var legendValueFont: Font {
        .caption2.weight(.medium)
    }

    private var weatherLegendItems: [(title: String, color: Color)] {
        [
            (localizedString("Clear", locale: locale), palette.dotSun),
            (localizedString("Partly Sunny", locale: locale), palette.dotPartlyCloudy),
            (localizedString("Rain", locale: locale), palette.dotRain),
            (localizedString("Drizzle", locale: locale), palette.dotDrizzle),
            (wrappedCloudyConditionsTitle, palette.dotCloudy),
            (localizedString("Night", locale: locale), theme.colors.moonIconColor)
        ]
    }

    // MARK: - Localized Legend Layout

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

    private func temperatureColor(celsius: Double) -> Color {
        if celsius <= 0 {
            return palette.dotRain.interpolated(with: palette.dotDrizzle, by: max(0, min(1, (celsius + 20) / 20)))
        } else if celsius <= 10 {
            return palette.dotDrizzle.interpolated(with: palette.dotCloudy, by: max(0, min(1, celsius / 10)))
        } else if celsius <= 20 {
            return palette.dotCloudy.interpolated(with: saturatedPartlySunnyColor, by: max(0, min(1, (celsius - 10) / 10)))
        } else {
            return saturatedPartlySunnyColor.interpolated(with: palette.destructive, by: max(0, min(1, (celsius - 20) / 20)))
        }
    }

    private func cloudColor(percent: Double) -> Color {
        palette.dotRain.interpolated(with: palette.dotCloudy, by: max(0, min(1, percent / 100.0)))
    }

    private func precipitationColor(percent: Double) -> Color {
        palette.dotCloudy.interpolated(with: palette.dotDrizzle, by: max(0, min(1, percent / 100.0)))
    }

    private func uvColor(fraction: Double) -> Color {
        palette.dotCloudy.interpolated(with: palette.destructive, by: max(0, min(1, fraction)))
    }

    // MARK: - Gradient legend

    private func verticalGradientLegend(colors gradColors: [Color], labels: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            LinearGradient(colors: gradColors, startPoint: .top, endPoint: .bottom)
                .frame(width: compact ? 8 : 10, height: compact ? 112 : 132)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(legendValueFont)
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

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            legendContent
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 10 : 12)
        .padding(.trailing, onClose == nil ? 0 : 20)
        .frame(width: overlayMode == "weather" ? nil : legendWidth, alignment: .leading)
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
    private var legendContent: some View {
        switch overlayMode {
        case "weather":
            weatherDotLegend
        case "temperature":
            verticalGradientLegend(
                colors: [
                    temperatureColor(celsius: 40),
                    temperatureColor(celsius: 20),
                    temperatureColor(celsius: 10),
                    temperatureColor(celsius: 0),
                    temperatureColor(celsius: -20)
                ],
                labels: tempUnit.resolved == .fahrenheit
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
                .font(legendLabelFont)
                .foregroundStyle(theme.colors.primaryText)
                .fixedSize(horizontal: true, vertical: true)
        }
    }

    private var weatherDotLegend: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 11) {
            ForEach(Array(weatherLegendItems.enumerated()), id: \.offset) { _, item in
                conditionEntry(title: item.title, color: item.color)
            }
        }
    }
}
