import SwiftUI

struct WeatherIntroOverlay: View {
    @Binding var isPresented: Bool

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var stepIndex = 0
    @State private var pulse = false

    private let steps: [WeatherIntroStep] = [
        WeatherIntroStep(
            title: "See weather at a glance",
            message: "Weather dots show each city's conditions directly on the map.",
            systemImage: "circle.grid.3x3.fill",
            visual: .dots
        ),
        WeatherIntroStep(
            title: "Tap any city",
            message: "A city dot opens a compact forecast card with today's weather and the next days.",
            systemImage: "hand.tap.fill",
            visual: .card
        ),
        WeatherIntroStep(
            title: "Organize cities",
            message: "Use lists to group the places you check most often.",
            systemImage: "list.bullet.rectangle.fill",
            visual: .lists
        ),
        WeatherIntroStep(
            title: "Compare overlays",
            message: "Switch map layers for temperature, rain, wind, UV, humidity, and visibility.",
            systemImage: "square.3.layers.3d.down.right",
            visual: .overlays
        )
    ]

    private var currentStep: WeatherIntroStep {
        steps[stepIndex]
    }

    private var progressText: String {
        "\(stepIndex + 1) / \(steps.count)"
    }

    var body: some View {
        ZStack {
            theme.colors.mapOcean.opacity(colorScheme == .dark ? 0.92 : 0.86)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                topBar

                Spacer(minLength: 0)

                introVisual
                    .frame(maxWidth: 520)
                    .frame(height: 310)
                    .padding(.horizontal, 24)
                    .id(currentStep.visual)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

                VStack(spacing: 10) {
                    Label {
                        Text(localizedString(String.LocalizationValue(currentStep.title), locale: locale))
                            .font(.avenir(.title2, weight: .bold))
                            .multilineTextAlignment(.center)
                    } icon: {
                        Image(systemName: currentStep.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundStyle(theme.colors.primaryText)

                    Text(localizedString(String.LocalizationValue(currentStep.message), locale: locale))
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 430)
                }
                .padding(.horizontal, 24)

                controls
            }
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onAppear {
            pulse = true
        }
    }

    private var topBar: some View {
        HStack {
            Text(progressText)
                .font(.avenir(.caption, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .themedGlass(in: .capsule)

            Spacer()

            Button(localizedString("Skip", locale: locale)) {
                dismissIntro()
            }
            .font(.avenir(.callout, weight: .semibold))
            .foregroundStyle(theme.colors.primaryText)
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .themedGlass(in: .capsule)
        }
        .padding(.horizontal, 18)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == stepIndex ? theme.colors.accent : theme.colors.primaryText.opacity(0.2))
                        .frame(width: index == stepIndex ? 22 : 7, height: 7)
                }
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        stepIndex = max(0, stepIndex - 1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(stepIndex == 0 ? theme.colors.secondaryText.opacity(0.35) : theme.colors.primaryText)
                .disabled(stepIndex == 0)
                .themedGlass(in: .circle)

                Button {
                    if stepIndex == steps.count - 1 {
                        dismissIntro()
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            stepIndex += 1
                        }
                    }
                } label: {
                    Text(localizedString(String.LocalizationValue(stepIndex == steps.count - 1 ? "Start" : "Continue"), locale: locale))
                        .font(.avenir(.headline, weight: .bold))
                        .frame(maxWidth: 220)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(theme.colors.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var introVisual: some View {
        switch currentStep.visual {
        case .dots:
            dotsVisual
        case .card:
            cardVisual
        case .lists:
            listsVisual
        case .overlays:
            overlaysVisual
        }
    }

    private var dotsVisual: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.colors.mapLand.opacity(0.22))
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 80, style: .continuous)
                        .fill(theme.colors.mapLand.opacity(0.45))
                        .frame(width: 220, height: 150)
                        .offset(x: -40, y: 30)
                }
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 90, style: .continuous)
                        .fill(theme.colors.mapLand.opacity(0.35))
                        .frame(width: 250, height: 130)
                        .offset(x: 50, y: 20)
                }

            ForEach(IntroDot.sampleDots) { dot in
                Circle()
                    .fill(dot.color(theme))
                    .frame(width: dot.emphasized ? 16 : 10, height: dot.emphasized ? 16 : 10)
                    .shadow(color: dot.color(theme).opacity(0.65), radius: dot.emphasized ? 15 : 8)
                    .scaleEffect(pulse && dot.emphasized ? 1.18 : 1.0)
                    .position(x: dot.x, y: dot.y)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(dot.delay), value: pulse)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .themedGlass(in: .rect(cornerRadius: 28))
    }

    private var cardVisual: some View {
        ZStack(alignment: .bottom) {
            dotsVisual
                .opacity(0.58)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizedString("24 degrees", locale: locale))
                        .font(.system(size: 36, weight: .semibold))
                    Text(localizedString("Current Temperature", locale: locale))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(localizedString("Barcelona", locale: locale))
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 20) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(theme.colors.sunIconColor)
                    dotGrid
                }
            }
            .foregroundStyle(theme.colors.primaryText)
            .padding(20)
            .frame(maxWidth: 410)
            .frame(height: 128)
            .themedGlass(in: .rect(cornerRadius: 24))
            .padding(18)
            .scaleEffect(pulse ? 1.02 : 0.98)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
        }
    }

    private var listsVisual: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                introListHeader(title: "Europe", count: 25, expanded: true)
                introCityRow(color: theme.colors.dotRain, city: "London", temp: "19 degrees")
                introCityRow(color: theme.colors.dotSun, city: "Madrid", temp: "28 degrees")
                introCityRow(color: theme.colors.dotPartlyCloudy, city: "Vienna", temp: "22 degrees")
                introCityRow(color: theme.colors.dotCloudy, city: "Prague", temp: "20 degrees")
            }
            .padding(18)
            .frame(width: 260)
            .themedGlass(in: .rect(cornerRadius: 24))

            VStack(spacing: 10) {
                Image(systemName: "plus")
                Image(systemName: "pencil")
                Image(systemName: "sidebar.left")
            }
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(theme.colors.primaryText)
            .padding(12)
            .themedGlass(in: .capsule)
        }
    }

    private var overlaysVisual: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                introOverlayPill("Weather", active: stepIndex % 2 == 1)
                introOverlayPill("Temp", active: true)
                introOverlayPill("Rain", active: false)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [theme.colors.dotRain.opacity(0.55), theme.colors.dotPartlyCloudy.opacity(0.55), theme.colors.destructive.opacity(0.55)],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ))

                HStack(spacing: 18) {
                    Image(systemName: "square.3.layers.3d.down.right")
                    Image(systemName: "thermometer.medium")
                    Image(systemName: "cloud.rain")
                    Image(systemName: "wind")
                }
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
            }
            .frame(height: 190)
            .themedGlass(in: .rect(cornerRadius: 28))
        }
    }

    private var dotGrid: some View {
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { column in
                        let index = row * 5 + column
                        Circle()
                            .fill(IntroDot.gridColors[index % IntroDot.gridColors.count](theme))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
    }

    private func introListHeader(title: String, count: Int, expanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .foregroundStyle(theme.colors.secondaryText)
            Text(localizedString(String.LocalizationValue(title), locale: locale))
                .font(.headline.weight(.semibold))
            Spacer()
            Text("\(count)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .themedGlass(in: .capsule)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(theme.colors.primaryText)
    }

    private func introCityRow(color: Color, city: String, temp: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .shadow(color: color.opacity(0.55), radius: 5)
            Text(localizedString(String.LocalizationValue(city), locale: locale))
                .lineLimit(1)
            Spacer()
            Text(localizedString(String.LocalizationValue(temp), locale: locale))
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(1)
        }
        .font(.avenir(.callout, weight: .medium))
        .foregroundStyle(theme.colors.primaryText)
    }

    private func introOverlayPill(_ text: String, active: Bool) -> some View {
        Text(localizedString(String.LocalizationValue(text), locale: locale))
            .font(.avenir(.caption, weight: .bold))
            .foregroundStyle(active ? Color.white : theme.colors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(active ? theme.colors.accent : theme.colors.glassFill, in: Capsule())
    }

    private func dismissIntro() {
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
        }
    }
}

private struct WeatherIntroStep {
    let title: String
    let message: String
    let systemImage: String
    let visual: WeatherIntroVisual
}

private enum WeatherIntroVisual {
    case dots
    case card
    case lists
    case overlays
}

private struct IntroDot: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let emphasized: Bool
    let delay: Double
    let color: (AppTheme) -> Color

    static let sampleDots: [IntroDot] = [
        IntroDot(x: 72, y: 86, emphasized: false, delay: 0.0) { $0.colors.dotRain },
        IntroDot(x: 168, y: 118, emphasized: true, delay: 0.2) { $0.colors.dotSun },
        IntroDot(x: 290, y: 78, emphasized: false, delay: 0.4) { $0.colors.dotCloudy },
        IntroDot(x: 375, y: 142, emphasized: false, delay: 0.1) { $0.colors.dotPartlyCloudy },
        IntroDot(x: 245, y: 212, emphasized: true, delay: 0.3) { $0.colors.dotDrizzle },
        IntroDot(x: 116, y: 238, emphasized: false, delay: 0.5) { $0.colors.dotRain },
        IntroDot(x: 344, y: 246, emphasized: false, delay: 0.6) { $0.colors.dotSun }
    ]

    static let gridColors: [(AppTheme) -> Color] = [
        { $0.colors.dotRain },
        { $0.colors.dotRain },
        { $0.colors.dotCloudy },
        { $0.colors.dotSun },
        { $0.colors.dotPartlyCloudy }
    ]
}

#Preview("Weather Intro") {
    WeatherIntroOverlay(isPresented: .constant(true))
        .environment(\.appTheme, AppTheme.shared)
        .environment(\.themeColors, AppTheme.shared.colors)
}
