import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors
    @AppStorage("temperatureUnit") private var temperatureUnitRaw: String = TemperatureUnit.celsius.rawValue

    private var tempUnit: TemperatureUnit {
        TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Info")
                        .font(.avenir(.title, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.top, 40)

                    // MARK: List row
                    VStack(alignment: .leading, spacing: 8) {
                        Text("List View")
                            .font(.avenir(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
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

                            calloutLabel("Daytime high (7AM–7PM)")
                        }
                    }

                    // MARK: Map card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Map Card")
                            .font(.avenir(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)

                        // Card preview
                        HStack(alignment: .center, spacing: 0) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(tempUnit == .fahrenheit ? "75°" : "24°")
                                    .font(.custom("AvenirNext-Medium", size: 38, relativeTo: .largeTitle))
                                    .foregroundStyle(.primary)
                                Text("Tokyo")
                                    .font(.avenir(.body, weight: .semibold))
                                    .foregroundStyle(.primary)
                                HStack(spacing: 12) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "cloud.fill").font(.system(size: 13))
                                        Text("12%").font(.avenir(.footnote, weight: .medium))
                                    }
                                    HStack(spacing: 4) {
                                        Image(systemName: "drop.fill").font(.system(size: 13))
                                        Text("5%").font(.avenir(.footnote, weight: .medium))
                                    }
                                    HStack(spacing: 5) {
                                        ForEach(0..<7, id: \.self) { i in
                                            Circle()
                                                .fill(i == 0 ? AppWeatherCondition.clear.dotColor : AppWeatherCondition.partlyCloudy.dotColor)
                                                .frame(width: i == 0 ? 8 : 6, height: i == 0 ? 8 : 6)
                                                .opacity(i == 0 ? 1 : 0.6)
                                        }
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.yellow)
                                .frame(width: 56, height: 48)
                                .padding(.trailing, 10)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(colors.listCardFill, in: RoundedRectangle(cornerRadius: 20))

                        // Annotations below card
                        VStack(alignment: .leading, spacing: 3) {
                            calloutLabel("Large number — daytime high (7AM–7PM)")
                            calloutLabel("Cloud & rain % — full-day averages")
                            calloutLabel("Colored dots — 7-day weather conditions")
                        }
                        .padding(.leading, 4)
                    }

                    // MARK: Detail stat cards
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detail Cards")
                            .font(.avenir(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)

                        statCard(
                            label: "Temperature",
                            value: tempUnit == .fahrenheit ? "68° / 75°" : "20° / 24°",
                            annotations: ["Low / High", "Daytime (7AM–7PM)"]
                        )
                        statCard(
                            label: "Feels Like",
                            value: tempUnit == .fahrenheit ? "65° / 72°" : "18° / 22°",
                            annotations: ["Low / High", "Daytime (7AM–7PM)"]
                        )
                        statCard(
                            label: "Cloud Cover",
                            value: "12%",
                            annotations: ["Full-day average"]
                        )
                        statCard(
                            label: "Precipitation",
                            value: "5%",
                            annotations: ["Full-day average"]
                        )
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
