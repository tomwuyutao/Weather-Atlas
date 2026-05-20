import SwiftUI

struct LoadingWeatherOverlay: View {
    let iconName: String
    let progress: Double
    let locale: Locale

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                ZStack {
                    Image(systemName: iconName)
                        #if os(macOS)
                        .font(.system(size: 28, weight: .medium))
                        #else
                        .font(.system(size: 40, weight: .medium))
                        #endif
                        .weatherIconStyle(for: iconName)
                        .compatSymbolReplaceTransition()
                        .animation(.snappy(duration: 0.42), value: iconName)
                }
                #if os(macOS)
                .frame(width: 44, height: 34)
                #else
                .frame(width: 62, height: 50)
                #endif

                Text(localizedString("Loading Weather", locale: locale))
                    #if os(macOS)
                    .font(.headline.weight(.semibold))
                    #else
                    .font(.avenir(.title3, weight: .semibold))
                    #endif

                Capsule()
                    .fill(theme.colors.primaryText.opacity(0.15))
                    .frame(width: 118, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.colors.accent)
                            .frame(width: 118 * max(0, min(1, progress)), height: 3)
                    }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .themedGlass(in: .rect(cornerRadius: 24))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

private struct LoadingWeatherAnimationPreview: View {
    private let icons = [
        "sun.max.fill",
        "cloud.sun.fill",
        "cloud.fill",
        "cloud.rain.fill",
        "cloud.drizzle.fill",
        "snowflake",
        "cloud.fog.fill",
        "wind"
    ]

    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @State private var iconIndex = 0
    @State private var progress = 0.12

    var body: some View {
        ZStack {
            theme.colors.mapOcean.ignoresSafeArea()

            LoadingWeatherOverlay(
                iconName: icons[iconIndex],
                progress: progress,
                locale: locale
            )
        }
        .frame(width: 360, height: 300)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    withAnimation(.snappy(duration: 0.42)) {
                        iconIndex = (iconIndex + 1) % icons.count
                        progress = progress >= 0.92 ? 0.12 : progress + 0.16
                    }
                }
            }
        }
    }
}

#Preview("Loading Icon Animation") {
    LoadingWeatherAnimationPreview()
}
