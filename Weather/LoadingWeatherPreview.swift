import SwiftUI

struct LoadingWeatherOverlay: View {
    let progress: Double
    let locale: Locale

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.colors.accent)

            Capsule()
                .fill(theme.colors.primaryText.opacity(0.15))
                .frame(width: 78, height: 3)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(theme.colors.accent)
                        .frame(width: 78 * max(0, min(1, progress)), height: 3)
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .themedGlass(in: .capsule)
        .fixedSize()
    }
}

private struct LoadingWeatherAnimationPreview: View {
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @State private var progress = 0.12

    var body: some View {
        ZStack {
            theme.colors.mapOcean.ignoresSafeArea()

            LoadingWeatherOverlay(
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
