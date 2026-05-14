import SwiftUI

struct MapFloatingLegend: View {
    let overlayMode: String
    var compact: Bool = false

    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue
    @AppStorage("distanceUnit") private var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue

    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var distUnit: DistanceUnit {
        DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers
    }

    private let conditions: [AppWeatherCondition] = [
        .clear, .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind
    ]

    private func conditionIcon(_ condition: AppWeatherCondition) -> String {
        switch condition {
        case .clear:        return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy:       return "cloud.fill"
        case .rain:         return "cloud.rain.fill"
        case .drizzle:      return "cloud.drizzle.fill"
        case .snow:         return "cloud.snow.fill"
        case .fog:          return "cloud.fog.fill"
        case .wind:         return "wind"
        }
    }

    private var leadingIcon: String {
        switch overlayMode {
        case "weather":       return "cloud.sun.fill"
        case "temperature":   return "thermometer.medium"
        case "cloudCover":    return "cloud.fill"
        case "precipitation": return "drop.fill"
        case "windSpeed":     return "wind"
        case "uvIndex":       return "sun.max.fill"
        case "humidity":      return "humidity.fill"
        case "visibility":    return "eye.fill"
        default:              return "circle.grid.2x2"
        }
    }

    // MARK: - Color functions (same as before)

    private func temperatureColor(celsius: Double) -> Color {
        if celsius <= 0 {
            let t = max(0, min(1, (celsius - (-20)) / 20.0))
            return Color(
                red: Double(0x15) / 255.0 + t * Double(0x57 - 0x15) / 255.0,
                green: Double(0x79) / 255.0 + t * Double(0xD3 - 0x79) / 255.0,
                blue: Double(0xC7) / 255.0 + t * Double(0xE5 - 0xC7) / 255.0
            )
        } else if celsius <= 10 {
            let t = max(0, min(1, celsius / 10.0))
            return Color(
                red: Double(0x57) / 255.0 + t * Double(0x7D - 0x57) / 255.0,
                green: Double(0xD3) / 255.0 + t * Double(0xD4 - 0xD3) / 255.0,
                blue: Double(0xE5) / 255.0 + t * Double(0xA0 - 0xE5) / 255.0
            )
        } else if celsius <= 20 {
            let t = max(0, min(1, (celsius - 10) / 10.0))
            return Color(
                red: Double(0x7D) / 255.0 + t * Double(0xFD - 0x7D) / 255.0,
                green: Double(0xD4) / 255.0 + t * Double(0xA4 - 0xD4) / 255.0,
                blue: Double(0xA0) / 255.0 + t * Double(0x09 - 0xA0) / 255.0
            )
        } else {
            let t = max(0, min(1, (celsius - 20) / 20.0))
            return Color(
                red: Double(0xFD) / 255.0 + t * Double(0xFB - 0xFD) / 255.0,
                green: Double(0xA4) / 255.0 + t * Double(0x43 - 0xA4) / 255.0,
                blue: Double(0x09) / 255.0 + t * Double(0x68 - 0x09) / 255.0
            )
        }
    }

    private func cloudColor(percent: Double) -> Color {
        let cover = percent / 100.0
        return Color(
            red: Double(0x15) / 255.0 + cover * (1.0 - Double(0x15) / 255.0),
            green: Double(0x79) / 255.0 + cover * (1.0 - Double(0x79) / 255.0),
            blue: Double(0xC7) / 255.0 + cover * (1.0 - Double(0xC7) / 255.0)
        )
    }

    private func precipitationColor(percent: Double) -> Color {
        let chance = percent / 100.0
        return Color(
            red: 1.0 + chance * (Double(0x57) / 255.0 - 1.0),
            green: 1.0 + chance * (Double(0xD3) / 255.0 - 1.0),
            blue: 1.0 + chance * (Double(0xE5) / 255.0 - 1.0)
        )
    }

    private func windColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0xFD) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0xA4) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0x09) / 255.0 - 1.0)
        )
    }

    private func uvColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0xFB) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0x43) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0x68) / 255.0 - 1.0)
        )
    }

    private func humidityColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0xBE) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0x9A) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0xED) / 255.0 - 1.0)
        )
    }

    private func visibilityColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0x15) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0x79) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0xC7) / 255.0 - 1.0)
        )
    }

    // MARK: - Gradient legend

    private func gradientLegend(colors gradColors: [Color], labels: [String]) -> some View {
        VStack(spacing: 4) {
            Spacer().frame(height: 2)

            LinearGradient(colors: gradColors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 8)
                .clipShape(Capsule())

            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    if index > 0 { Spacer() }
                    Text(label)
                        .font(.avenir(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if overlayMode == "weather" {
                legendContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.shared.colors.primaryText)
                        .frame(width: 18)

                    legendContent
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: compact ? 520 : .infinity, alignment: .leading)
        .padding(6)
        .themedGlass(in: Capsule())
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var legendContent: some View {
        switch overlayMode {
        case "weather":
            weatherDotLegend
        case "temperature":
            gradientLegend(
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
        case "cloudCover":
            gradientLegend(
                colors: [
                    cloudColor(percent: 0),
                    cloudColor(percent: 33),
                    cloudColor(percent: 66),
                    cloudColor(percent: 100)
                ],
                labels: ["0%", "25%", "50%", "75%", "100%"]
            )
        case "precipitation":
            gradientLegend(
                colors: [
                    precipitationColor(percent: 0),
                    precipitationColor(percent: 33),
                    precipitationColor(percent: 66),
                    precipitationColor(percent: 100)
                ],
                labels: ["0%", "25%", "50%", "75%", "100%"]
            )
        case "windSpeed":
            gradientLegend(
                colors: [
                    windColor(fraction: 0),
                    windColor(fraction: 0.25),
                    windColor(fraction: 0.5),
                    windColor(fraction: 0.75),
                    windColor(fraction: 1.0)
                ],
                labels: distUnit == .miles ? ["0", "15", "30", "45", "60 mph"] : ["0", "25", "50", "75", "100 km/h"]
            )
        case "uvIndex":
            gradientLegend(
                colors: [
                    uvColor(fraction: 0),
                    uvColor(fraction: 0.27),
                    uvColor(fraction: 0.55),
                    uvColor(fraction: 0.82),
                    uvColor(fraction: 1.0)
                ],
                labels: ["0", "3", "6", "9", "11+"]
            )
        case "humidity":
            gradientLegend(
                colors: [
                    humidityColor(fraction: 0),
                    humidityColor(fraction: 0.25),
                    humidityColor(fraction: 0.5),
                    humidityColor(fraction: 0.75),
                    humidityColor(fraction: 1.0)
                ],
                labels: ["0%", "25%", "50%", "75%", "100%"]
            )
        case "visibility":
            gradientLegend(
                colors: [
                    visibilityColor(fraction: 0),
                    visibilityColor(fraction: 0.25),
                    visibilityColor(fraction: 0.5),
                    visibilityColor(fraction: 0.75),
                    visibilityColor(fraction: 1.0)
                ],
                labels: distUnit == .miles ? ["0", "5", "9", "14", "19 mi"] : ["0", "8", "15", "23", "30 km"]
            )
        default:
            EmptyView()
        }
    }

    // MARK: - Legend icon style (light mode: outlined clouds, colored accents)

    private let legendGrey = Color(white: 0.35)

    private func legendConditionIcon(_ condition: AppWeatherCondition) -> String {
        guard colorScheme == .light else { return conditionIcon(condition) }
        switch condition {
        case .clear:        return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun"
        case .cloudy:       return "cloud"
        case .rain:         return "cloud.rain"
        case .drizzle:      return "cloud.drizzle"
        case .snow:         return "cloud.snow"
        case .fog:          return "cloud.fog"
        case .wind:         return "wind"
        }
    }

    private func legendIconPalette(for iconName: String) -> (primary: Color, secondary: Color) {
        if colorScheme == .dark {
            return AppTheme.shared.colors.weatherIconPalette(for: iconName)
        }
        let theme = AppTheme.shared.colors
        if iconName.contains("sun") && iconName.contains("cloud") {
            return (legendGrey, theme.sunIconColor)
        } else if iconName.contains("rain") || iconName.contains("drizzle") {
            return (legendGrey, theme.rainIconColor)
        } else if iconName.contains("snow") {
            return (legendGrey, theme.snowIconColor)
        } else if iconName.contains("fog") {
            return (legendGrey, legendGrey.opacity(0.5))
        } else if iconName.contains("sun") {
            return (theme.sunIconColor, theme.sunIconColor)
        } else if iconName.contains("wind") {
            return (legendGrey, legendGrey)
        } else {
            return (legendGrey, legendGrey)
        }
    }

    private func legendIconView(for condition: AppWeatherCondition) -> some View {
        let icon = legendConditionIcon(condition)
        let palette = legendIconPalette(for: icon)
        let yOffset: CGFloat = switch condition {
        case .rain, .drizzle, .snow: 3
        case .fog: 2
        default: 0
        }
        return Image(systemName: icon)
            .font(.system(size: 13))
            .symbolRenderingMode(.palette)
            .foregroundStyle(palette.primary, palette.secondary)
            .offset(y: yOffset)
    }

    // MARK: - Weather dot legend (single row with separators)

    private var separatorLine: some View {
        Text("|")
            .font(.system(size: 11, weight: .light))
            .foregroundStyle(.secondary.opacity(0.5))
    }

    private func dotPairEntry(_ condition: AppWeatherCondition) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(condition.dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: condition.dotColor.opacity(0.5), radius: 2)
            separatorLine
            legendIconView(for: condition)
        }
    }

    private var weatherDotLegend: some View {
        HStack(spacing: compact ? 18 : 0) {
            dotPairEntry(.clear)
            if !compact { Spacer() }
            dotPairEntry(.partlyCloudy)
            if !compact { Spacer() }
            dotPairEntry(.rain)
            if !compact { Spacer() }
            dotPairEntry(.drizzle)
            if !compact { Spacer() }
            // White dot | cloudy, snow, fog, wind icons
            Circle()
                .fill(AppWeatherCondition.cloudy.dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: AppWeatherCondition.cloudy.dotColor.opacity(0.5), radius: 2)
            separatorLine
                .padding(.leading, 5)
            ForEach(Array([AppWeatherCondition.cloudy, .snow, .fog, .wind].enumerated()), id: \.offset) { index, condition in
                legendIconView(for: condition)
                    .padding(.leading, 5)
            }
        }
    }
}
