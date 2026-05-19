import SwiftUI

struct MapFloatingLegend: View {
    let overlayMode: String
    var compact: Bool = false
    var onClose: (() -> Void)? = nil

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

    private var weatherLegendItems: [(title: String, color: Color)] {
        [
            (localizedString("Clear", locale: locale), AppWeatherCondition.clear.dotColor),
            (localizedString("Partly Sunny", locale: locale), AppWeatherCondition.partlySunny.dotColor),
            (localizedString("Rain", locale: locale), AppWeatherCondition.rain.dotColor),
            (localizedString("Drizzle", locale: locale), AppWeatherCondition.drizzle.dotColor),
            ("Cloudy / Snow /\nWind / Fog", AppWeatherCondition.cloudy.dotColor)
        ]
    }

    // MARK: - Color functions (same as before)

    private func temperatureColor(celsius: Double) -> Color {
        if celsius <= 0 {
            return Color(hex: 0xBCCFDC).mix(with: Color(hex: 0x6EACE8), by: max(0, min(1, (celsius + 20) / 20)))
        } else if celsius <= 10 {
            return Color(hex: 0x6EACE8).mix(with: Color(hex: 0xEEB368), by: max(0, min(1, celsius / 10)))
        } else if celsius <= 20 {
            return Color(hex: 0xEEB368).mix(with: Color(hex: 0xE87957), by: max(0, min(1, (celsius - 10) / 10)))
        } else {
            return Color(hex: 0xE87957).mix(with: Color(hex: 0xFB4368), by: max(0, min(1, (celsius - 20) / 20)))
        }
    }

    private func cloudColor(percent: Double) -> Color {
        Color.white.mix(with: Color(hex: 0xBCCFDC), by: max(0, min(1, percent / 100.0)))
    }

    private func precipitationColor(percent: Double) -> Color {
        Color.white.mix(with: Color(hex: 0xBCCFDC), by: max(0, min(1, percent / 100.0)))
    }

    private func windColor(fraction: Double) -> Color {
        Color.white.mix(with: Color(hex: 0xEEB368), by: max(0, min(1, fraction)))
    }

    private func uvColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0xE8) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0x79) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0x57) / 255.0 - 1.0)
        )
    }

    private func humidityColor(fraction: Double) -> Color {
        return Color(
            red: 1.0 + fraction * (Double(0xBC) / 255.0 - 1.0),
            green: 1.0 + fraction * (Double(0xCF) / 255.0 - 1.0),
            blue: 1.0 + fraction * (Double(0xDC) / 255.0 - 1.0)
        )
    }

    private func visibilityColor(fraction: Double) -> Color {
        Color.white.mix(with: Color(hex: 0xBCCFDC), by: max(0, min(1, fraction)))
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
                        .font(.avenir(.caption2, weight: .medium))
                        .foregroundStyle(.secondary)
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
        .frame(width: compact ? 154 : 178, alignment: .leading)
        .background(themeCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: compact ? 26 : 28, height: compact ? 26 : 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)
            }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 18, x: 0, y: 10)
        .transition(.scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
        .fixedSize(horizontal: true, vertical: false)
        .id("\(overlayMode)-\(colorScheme == .dark ? "dark" : "light")")
    }

    private var themeCardFill: Color {
        colorScheme == .dark
            ? AppTheme.shared.colors.listCardFill.opacity(0.96)
            : AppTheme.shared.colors.listCardFill.opacity(0.92)
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
                labels: tempUnit == .fahrenheit
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
        case "windSpeed":
            verticalGradientLegend(
                colors: [
                    windColor(fraction: 1.0),
                    windColor(fraction: 0.75),
                    windColor(fraction: 0.5),
                    windColor(fraction: 0.25),
                    windColor(fraction: 0)
                ],
                labels: distUnit == .miles ? ["60 mph", "45", "30", "15", "0"] : ["100 km/h", "75", "50", "25", "0"]
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
        case "humidity":
            verticalGradientLegend(
                colors: [
                    humidityColor(fraction: 1.0),
                    humidityColor(fraction: 0.75),
                    humidityColor(fraction: 0.5),
                    humidityColor(fraction: 0.25),
                    humidityColor(fraction: 0)
                ],
                labels: ["100%", "75%", "50%", "25%", "0%"]
            )
        case "visibility":
            verticalGradientLegend(
                colors: [
                    visibilityColor(fraction: 1.0),
                    visibilityColor(fraction: 0.75),
                    visibilityColor(fraction: 0.5),
                    visibilityColor(fraction: 0.25),
                    visibilityColor(fraction: 0)
                ],
                labels: distUnit == .miles ? ["19 mi", "14", "9", "5", "0"] : ["30 km", "23", "15", "8", "0"]
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
                .font(.avenir(.caption, weight: .medium))
                .foregroundStyle(AppTheme.shared.colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weatherDotLegend: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 11) {
            ForEach(Array(weatherLegendItems.enumerated()), id: \.offset) { _, item in
                conditionEntry(title: item.title, color: item.color)
            }
        }
    }
}
