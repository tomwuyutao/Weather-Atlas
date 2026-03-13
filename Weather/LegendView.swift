import SwiftUI

struct LegendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors
    @Environment(\.locale) private var locale
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("mapOverlayMode") private var mapOverlayMode: String = "weather"

    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private let conditions: [AppWeatherCondition] = [
        .clear, .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind
    ]

    private func temperatureColor(celsius: Double) -> Color {
        // Dark blue #1579C7 (≤-20°C) → Cyan #57D3E5 (0°C) → Green #8BBD9F (10°C) → Yellow #FDA409 (20°C) → Red #FB4368 (≥40°C)
        if celsius <= 0 {
            // Dark blue → Cyan: -20 to 0
            let t = Double(max(0, min(1, (celsius - (-20)) / 20.0)))
            return Color(
                red: Double(0x15) / 255.0 + t * Double(0x57 - 0x15) / 255.0,
                green: Double(0x79) / 255.0 + t * Double(0xD3 - 0x79) / 255.0,
                blue: Double(0xC7) / 255.0 + t * Double(0xE5 - 0xC7) / 255.0
            )
        } else if celsius <= 10 {
            // Cyan → Green: 0 to 10
            let t = Double(max(0, min(1, celsius / 10.0)))
            return Color(
                red: Double(0x57) / 255.0 + t * Double(0x7D - 0x57) / 255.0,
                green: Double(0xD3) / 255.0 + t * Double(0xD4 - 0xD3) / 255.0,
                blue: Double(0xE5) / 255.0 + t * Double(0xA0 - 0xE5) / 255.0
            )
        } else if celsius <= 20 {
            // Green → Yellow: 10 to 20
            let t = Double(max(0, min(1, (celsius - 10) / 10.0)))
            return Color(
                red: Double(0x7D) / 255.0 + t * Double(0xFD - 0x7D) / 255.0,
                green: Double(0xD4) / 255.0 + t * Double(0xA4 - 0xD4) / 255.0,
                blue: Double(0xA0) / 255.0 + t * Double(0x09 - 0xA0) / 255.0
            )
        } else {
            // Yellow → Red: 20 to 40
            let t = Double(max(0, min(1, (celsius - 20) / 20.0)))
            return Color(
                red: Double(0xFD) / 255.0 + t * Double(0xFB - 0xFD) / 255.0,
                green: Double(0xA4) / 255.0 + t * Double(0x43 - 0xA4) / 255.0,
                blue: Double(0x09) / 255.0 + t * Double(0x68 - 0x09) / 255.0
            )
        }
    }

    private func cloudColor(percent: Double) -> Color {
        let cover = percent / 100.0
        // Dark blue #1579C7 (clear) → pure white #FFFFFF (fully cloudy)
        return Color(
            red: Double(0x15) / 255.0 + cover * (1.0 - Double(0x15) / 255.0),
            green: Double(0x79) / 255.0 + cover * (1.0 - Double(0x79) / 255.0),
            blue: Double(0xC7) / 255.0 + cover * (1.0 - Double(0xC7) / 255.0)
        )
    }

    private func precipitationColor(percent: Double) -> Color {
        let chance = percent / 100.0
        // Pure white #FFFFFF (0%) → cyan #57D3E5 (100%)
        return Color(
            red: 1.0 + chance * (Double(0x57) / 255.0 - 1.0),
            green: 1.0 + chance * (Double(0xD3) / 255.0 - 1.0),
            blue: 1.0 + chance * (Double(0xE5) / 255.0 - 1.0)
        )
    }

    private func gradientScaleView(colors gradColors: [Color], labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Gradient bar
            LinearGradient(colors: gradColors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 12)
                .clipShape(Capsule())

            // Labels evenly spaced below
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if index > 0 { Spacer() }
                    Text(label)
                        .font(.avenir(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Legend")
                        .font(.avenir(.title2, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 40)
                        .padding(.bottom, 8)

                    // MARK: Weather dot colors
                    Text("Weather Dot Colors")
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)

                    VStack(spacing: 0) {
                        ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                            if index > 0 {
                                Divider()
                                    .padding(.leading, 52)
                                    .opacity(0.5)
                            }

                            HStack(spacing: 16) {
                                Circle()
                                    .fill(condition.dotColor)
                                    .frame(width: 14, height: 14)
                                    .shadow(color: condition.dotColor.opacity(0.6), radius: 4)
                                    .frame(width: 36)

                                Text(condition.localizedDisplayName(locale: locale))
                                    .font(.avenir(.body, weight: .medium))
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))

                    // MARK: Temperature overlay scale
                    Text("Temperature Overlay")
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    gradientScaleView(
                        colors: [
                            temperatureColor(celsius: -20),
                            temperatureColor(celsius: 0),
                            temperatureColor(celsius: 10),
                            temperatureColor(celsius: 20),
                            temperatureColor(celsius: 40)
                        ],
                        labels: tempUnit == .fahrenheit
                            ? ["-4°F", "32°F", "50°F", "68°F", "104°F"]
                            : ["-20°C", "0°C", "10°C", "20°C", "40°C"]
                    )

                    // MARK: Cloud cover overlay scale
                    Text("Cloud Cover Overlay")
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    gradientScaleView(
                        colors: [
                            cloudColor(percent: 0),
                            cloudColor(percent: 33),
                            cloudColor(percent: 66),
                            cloudColor(percent: 100)
                        ],
                        labels: ["0%", "25%", "50%", "75%", "100%"]
                    )

                    // MARK: Precipitation overlay scale
                    Text("Precipitation Overlay")
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    gradientScaleView(
                        colors: [
                            precipitationColor(percent: 0),
                            precipitationColor(percent: 33),
                            precipitationColor(percent: 66),
                            precipitationColor(percent: 100)
                        ],
                        labels: ["0%", "25%", "50%", "75%", "100%"]
                    )
                }
                .padding(.leading, 24)
                .padding(.trailing, 20)
                .padding(.bottom, 40)
            }

            // X dismiss button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .themedGlass(in: .circle)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 20)
        }
    }
}
