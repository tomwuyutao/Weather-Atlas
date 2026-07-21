//
//  ForecastOmissionNotice.swift
//  Weather
//
//  Purpose: Presents the compact, non-error notice used when cities fall
//  outside the selected date's real WeatherKit forecast range.
//

import SwiftUI

// MARK: - Expected Forecast Omissions

/// A compact informational box for cities omitted because the selected calendar
/// date sits outside the real forecast range WeatherKit returned for them.
/// Unlike a genuine missing-data failure, this range edge never opens an alert.
struct ForecastOmissionNotice: View {
    let droppedCityCount: Int

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        let message = forecastOmissionMessage(
            droppedCityCount: droppedCityCount,
            locale: locale
        )

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.footnote.weight(.semibold))

            Text(message)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.colors.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedGlass(in: .rect(cornerRadius: 16))
    }
}

func forecastOmissionMessage(droppedCityCount: Int, locale: Locale) -> String {
    if droppedCityCount == 1 {
        return localizedString("1 city is dropped due to missing data.", locale: locale)
    }
    return String(
        format: localizedString("%lld cities are dropped due to missing data.", locale: locale),
        locale: locale,
        droppedCityCount
    )
}

