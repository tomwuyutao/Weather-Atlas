//
//  SunnyHoursStatusLine.swift
//  Weather
//
//  Purpose: Renders the shared highlighted sunny-hours phrase used by a
//  selected Map place and the large forecast-report hero.
//

import SwiftUI

/// A compact, localized sunny-hours phrase: an outlined sun followed by a
/// highlighted count and the secondary copy “of sun”.
///
/// Keeping this in one component ensures the Detail hero and Map floating
/// card present the same metric with identical hierarchy and spacing.
struct SunnyHoursStatusLine: View {
    let hours: Double

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sun.max")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.dotSun)


            HStack(spacing: 0) {
                Text(hourLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(theme.colors.dotSun)

                Text(" " + localizedString("of sun", locale: locale))
                    .font(.body)
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            }
        }
        .minimumScaleFactor(0.75)


    }

    /// The visible count is deliberately spelled out here; compact charts and
    /// rankings continue to use the shorter `11h` formatting.
    private var hourLabel: String {
        Self.hourLabel(hours: hours, locale: locale)
    }

    static func statusText(hours: Double, locale: Locale) -> String {
        "\(hourLabel(hours: hours, locale: locale)) \(localizedString("of sun", locale: locale))"
    }

    private static func hourLabel(hours: Double, locale: Locale) -> String {
        let count = SunnyHoursFormatting.hourCountText(hours, locale: locale)
        if hours == 1 {
            return String(
                format: localizedString("%@ hour", locale: locale),
                locale: locale,
                count
            )
        }
        return String(
            format: localizedString("%@ hours", locale: locale),
            locale: locale,
            count
        )
    }
}
