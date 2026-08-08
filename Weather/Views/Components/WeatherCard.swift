//
//  WeatherCard.swift
//  Weather
//
//  Purpose: Defines the shared header geometry for Weather Atlas's primary
//  forecast and recommendation cards.
//

import SwiftUI

enum WeatherCardLayout {
    static let leadingIconWidth: CGFloat = 32
    static let headerSpacing: CGFloat = 5
    static let padding: CGFloat = 18
    static let cornerRadius: CGFloat = 24
}

/// Consistent primary-card header with an optional secondary line and trailing
/// weather context such as a condition symbol or selected sunny window.
struct WeatherCardHeader<Trailing: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.appTheme) private var theme

    init(
        icon: String,
        title: LocalizedStringKey,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: WeatherCardLayout.headerSpacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.primaryText)
                .frame(
                    width: WeatherCardLayout.leadingIconWidth,
                    alignment: .leading
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WeatherCardHeader where Trailing == EmptyView {
    init(
        icon: String,
        title: LocalizedStringKey,
        subtitle: String? = nil
    ) {
        self.init(icon: icon, title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}
