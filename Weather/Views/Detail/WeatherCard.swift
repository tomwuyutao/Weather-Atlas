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
    /// The gap between a card header and its primary content. Every report and
    /// planning card uses this single value so their titles sit on the same
    /// vertical rhythm.
    static let contentSpacing: CGFloat = 12
    static let padding: CGFloat = 18
    static let cornerRadius: CGFloat = 24
}

/// Reserves the ordinary content footprint of each card family while weather
/// data is loading or unavailable. These are minimums—not fixed heights—so
/// longer localized recovery text and Dynamic Type can still expand naturally.
enum WeatherCardFallbackLayout {
    /// Daily timelines consist of a 44-point track and a 14-point axis.
    static let dailyTimelineContentHeight: CGFloat = 62
    /// Ten-day timelines retain room for their axis, forecast rows, and key.
    static let tenDayTimelineContentHeight: CGFloat = 300
    /// The usual two-week Saved Places heat map remains visually anchored.
    static let savedDatesContentHeight: CGFloat = 144
    /// The planning preview normally presents up to three saved-place rows.
    static let savedPlacesContentHeight: CGFloat = 132
}

/// Consistent primary-card header with an optional secondary line and trailing
/// weather context such as a condition symbol or selected sunny window.
struct WeatherCardHeader<Trailing: View>: View {
    // MARK: - Content Supplied by the Calling Card

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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

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
