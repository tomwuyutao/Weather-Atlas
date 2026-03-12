import SwiftUI

struct LegendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.themeColors) private var colors
    @Environment(\.locale) private var locale

    private let conditions: [AppWeatherCondition] = [
        .clear, .partlyCloudy, .cloudy, .rain, .drizzle, .snow, .fog, .wind
    ]

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

                    Text("Weather Dot Colors")
                        .font(.avenir(.subheadline, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
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
