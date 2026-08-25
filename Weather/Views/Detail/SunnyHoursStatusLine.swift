//
//  SunnyHoursStatusLine.swift
//  Weather
//
//  Purpose: Renders the shared highlighted sunny-hours phrase used by a
//  selected Map place and the large forecast-report hero.
//

import SwiftUI

// MARK: - Shared Sunny-Hours Status

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

            Text(attributedStatusText)
                .font(.body)
                .foregroundStyle(theme.colors.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
        .minimumScaleFactor(0.75)

    }

    // MARK: - Formatting

    /// The visible count is deliberately spelled out here; compact charts and
    /// rankings continue to use the shorter `11h` formatting.
    private var hourLabel: String {
        Self.hourLabel(hours: hours, locale: locale)
    }

    /// Keeps the highlighted count as a movable placeholder inside one
    /// localized sentence. Languages that place the descriptive phrase before
    /// the duration can therefore reorder it without losing the visual emphasis.
    private var attributedStatusText: AttributedString {
        var emphasizedHours = AttributedString(hourLabel)
        emphasizedHours.font = .body.weight(.semibold)
        emphasizedHours.foregroundColor = theme.colors.dotSun

        var resource: LocalizedStringResource = "\(emphasizedHours) of sun"
        resource.locale = locale
        return AttributedString(localized: resource)
    }

    static func statusText(hours: Double, locale: Locale) -> String {
        let localizedHours = hourLabel(hours: hours, locale: locale)
        var resource: LocalizedStringResource = "\(localizedHours) of sun"
        resource.locale = locale
        return String(localized: resource)
    }

    private static func hourLabel(hours: Double, locale: Locale) -> String {
        // Sunny hours count discrete hourly forecast rows. Keeping that count
        // as an integer interpolation lets the String Catalog select every
        // locale's plural category, including Russian one/few/many forms.
        let count = Int64(hours.rounded())
        var resource: LocalizedStringResource = "\(count) hours"
        resource.locale = locale
        return String(localized: resource)
    }
}
