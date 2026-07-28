//
//  FloatingBox.swift
//  Weather
//
//  Purpose: Defines the single compact status surface shown above the shared
//  bottom toolbar for loading progress and forecast omissions.
//

import SwiftUI

// MARK: - Floating Status Content

/// Mutually exclusive status displayed by the shared floating box.
enum FloatingBoxContent {
    /// Fraction of configured city fetch attempts completed.
    case loading(progress: Double)
    /// Number of cities omitted because real forecast data is unavailable.
    case droppedCities(count: Int)
}

/// Compact Liquid Glass status box shared across the app's main destinations.
struct FloatingBox: View {
    let content: FloatingBoxContent

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 8) {
            switch content {
            case .loading(let progress):
                ProgressView()
                    .controlSize(.small)

                Text(localizedString("Loading Weather", locale: locale))

                Text(
                    String(
                        format: localizedString("(%lld%% completed)", locale: locale),
                        locale: locale,
                        Int((min(max(progress, 0), 1) * 100).rounded())
                    )
                )
                .monospacedDigit()

            case .droppedCities(let count):
                Image(systemName: "info.circle.fill")
                    .font(.footnote.weight(.semibold))

                Text(
                    count == 1
                        ? localizedString("1 city is dropped due to missing data.", locale: locale)
                        : String(
                            format: localizedString(
                                "%lld cities are dropped due to missing data.",
                                locale: locale
                            ),
                            locale: locale,
                            count
                        )
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(theme.colors.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedGlass(in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Route Status

extension ContentView {
    /// Omission count appropriate to the currently visible main destination.
    var floatingBoxDroppedCityCount: Int {
        guard !isListPreviewActive else { return 0 }

        switch currentRoute {
        case .map:
            return expectedForecastBoundaryOmissionCount(in: weatherService.cityWeatherData)
        case .cityDetail(let city):
            return isExpectedForecastBoundaryOmission(
                for: city,
                among: mapCities,
                on: selectedForecastDate
            ) ? 1 : 0
        case .listPreview:
            return 0
        case .list, nil:
            return rankingOmissionCount(in: weatherService.cityWeatherData)
        }
    }
}
