import SwiftUI

enum InfoViewSource {
    case list, map, detail
}

struct InfoView: View {
    var source: InfoViewSource = .list

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue

    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
    }

    private var sectionOrder: [InfoViewSource] {
        switch source {
        case .list:   return [.list, .map, .detail]
        case .map:    return [.map, .list, .detail]
        case .detail: return [.detail, .list, .map]
        }
    }

    private func calloutLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text("—")
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // A stat card matching WeatherStatCard exactly, with annotations to the right
    private func statCard(label: String, value: String, isSelected: Bool = false, annotations: [String]) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 10) {
                Text(label)
                    .font(.avenir(.footnote, weight: .medium))
                    .foregroundStyle(isSelected ? colors.primaryText : colors.secondaryText)
                Text(value)
                    .font(.avenir(.title2, weight: .semibold))
                    .foregroundStyle(colors.primaryText)
            }
            .frame(width: 150)
            .frame(height: 110)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? colors.listCardFill.mix(with: .black, by: 0.25)
                          : colors.listCardFill)
            )

            VStack(alignment: .leading, spacing: 6) {
                ForEach(annotations, id: \.self) { annotation in
                    calloutLabel(annotation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("List View")
                .font(.avenir(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Tokyo")
                        .font(.avenir(.body, weight: .medium))
                    Spacer()
                    Text(tempUnit == .fahrenheit ? "75°" : "24°")
                        .font(.avenir(.title2, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 4)
                    Image(systemName: "sun.max.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                        .frame(width: 32)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 12))

                calloutLabel("Current temp (Now) or daily high (Today+)")
            }
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map View")
                .font(.avenir(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tempUnit == .fahrenheit ? "75°" : "24°")
                            .font(.system(size: 42, weight: .medium, design: .default))
                            .foregroundStyle(.primary)
                        Text("Highest Temperature")
                            .font(.avenir(.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("Tokyo")
                        .font(.avenir(.body, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(spacing: 20) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.yellow)
                        .frame(width: 56, height: 48)
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle()
                                    .fill(i == 0 ? AppWeatherCondition.clear.dotColor : AppWeatherCondition.partlyCloudy.dotColor)
                                    .frame(width: 8, height: 8)
                                    .opacity(i == 0 ? 1 : 0.6)
                            }
                        }
                        HStack(spacing: 6) {
                            ForEach(0..<5, id: \.self) { _ in
                                Circle()
                                    .fill(AppWeatherCondition.partlyCloudy.dotColor)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.6)
                            }
                        }
                    }
                }
                .padding(.trailing, 10)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 3) {
                calloutLabel("Large number — current temp (Now) or daily high (Today+), or overlay value")
                calloutLabel("Label below — data type shown")
                calloutLabel("Colored dots — 10-day weather conditions")
            }
            .padding(.leading, 4)
        }
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detail View")
                .font(.avenir(.title3, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tempUnit == .fahrenheit ? "75°" : "24°")
                        .font(.avenir(.largeTitle, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Sunny")
                        .font(.avenir(.title3, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.leading, 16)
                .padding(.vertical, 24)
                Spacer()
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.trailing, 24)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colors.dotSun)
            )

            VStack(alignment: .leading, spacing: 4) {
                calloutLabel("Large number — current temp (Now) or high/low (Today+)")
                calloutLabel("Condition label — current weather condition")
            }
            .padding(.leading, 4)

            statCard(
                label: "Temperature",
                value: tempUnit == .fahrenheit ? "68° / 75°" : "20° / 24°",
                isSelected: true,
                annotations: ["Low / High (Today+)", "Current temp only (Now)"]
            )
            statCard(
                label: "Feels Like",
                value: tempUnit == .fahrenheit ? "65° / 72°" : "18° / 22°",
                annotations: ["Low / High (Today+)", "Current feels like (Now)"]
            )
            statCard(
                label: "Cloud Cover",
                value: "12%",
                annotations: ["Daytime avg (Today+)", "Current reading (Now)"]
            )
            statCard(
                label: "Precipitation",
                value: "5%",
                annotations: ["Full-day max (Today+)", "100% if raining, 0% otherwise (Now)"]
            )
            statCard(
                label: "Wind Speed",
                value: "25 km/h",
                annotations: ["Full-day wind (Today+)", "Current wind (Now)"]
            )
            statCard(
                label: "UV Index",
                value: "6",
                annotations: ["Daily peak (Today+)", "Current UV (Now)"]
            )
            statCard(
                label: "Humidity",
                value: "65%",
                annotations: ["Daily max (Today+)", "Current humidity (Now)"]
            )
            statCard(
                label: "Visibility",
                value: "15 km",
                annotations: ["Daily max (Today+)", "Current visibility (Now)"]
            )

            VStack(alignment: .leading, spacing: 4) {
                calloutLabel("Tap any card to switch the hourly chart")
                calloutLabel("\"—\" shown when data is unavailable")
            }
            .padding(.leading, 4)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Info")
                        .font(.avenir(.title, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 40)

                    ForEach(sectionOrder, id: \.self) { section in
                        switch section {
                        case .list:
                            listSection
                        case .map:
                            mapSection
                        case .detail:
                            detailSection
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }

            // Dismiss button
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
