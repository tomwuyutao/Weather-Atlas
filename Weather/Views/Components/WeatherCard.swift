//
//  WeatherCard.swift
//  Weather
//
//  Purpose: Defines the shared header geometry for Weather Atlas's primary
//  forecast and recommendation cards.
//

import SwiftUI

// MARK: - Shared Card Geometry

/// Measurements used by every primary card. Centralizing them makes cards in
/// Home and Detail align even though each owns different content.
enum WeatherCardLayout {
    static let leadingIconWidth: CGFloat = 32
    static let headerSpacing: CGFloat = 5
    static let padding: CGFloat = 18
    static let cornerRadius: CGFloat = 24
}

/// Consistent primary-card header with an optional secondary line and trailing
/// weather context such as a condition symbol or selected sunny window.
struct WeatherCardHeader<Trailing: View>: View {
    // MARK: Content Supplied by the Calling Card

    let icon: String
    let title: LocalizedStringKey
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.appTheme) private var theme

    /// The generic trailing closure lets callers add an icon, a sun-window
    /// label, or nothing without duplicating the header's alignment rules.
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
        // The fixed leading icon column is the shared alignment anchor for
        // headers, dividers, and rows throughout the card family.
        HStack(alignment: .center, spacing: WeatherCardLayout.headerSpacing) {
            Image(systemName: icon)
                .foregroundStyle(theme.colors.primaryText)
                .frame(
                    width: WeatherCardLayout.leadingIconWidth,
                    alignment: .leading
                )
                // Every card already names its content in text. Repeating an
                // SF Symbol's generic name adds noise without adding meaning.
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Header Without Trailing Content

/// Convenience initializer used by simple cards that need only icon and text.
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
