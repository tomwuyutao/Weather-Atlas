//
//  WeatherDetailView+Header.swift
//  Weather
//
//  Extracted from WeatherDetailView.swift
//

import SwiftUI

extension WeatherDetailView {

    // MARK: - Inline Scrollable Header

    var inlineHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cityWeather.city.localizedName(locale: locale))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(isNow ? detailDisplayCondition.localizedDisplayName(locale: locale) : forecast.condition.localizedDisplayName(locale: locale))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: detailDisplayIcon)
                    .font(.system(size: 30, weight: .medium))
                    .weatherIconStyle(for: detailDisplayIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 38, height: 34)
                    .background(alignment: .top) {
                        if !detailDisplayIcon.contains("moon") {
                            WeatherEffectOverlay(
                                condition: detailDisplayCondition,
                                isCompact: true,
                                iconHeight: 48,
                                iconName: detailDisplayIcon,
                                dropColor: detailDisplayCondition == .drizzle ? AppTheme.shared.colors.dotRain : nil
                            )
                            .id("detail-header-effect-\(internalSelectedDay)-\(detailDisplayCondition.displayName)")
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: internalSelectedDay)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isNow {
                    Text(tempUnit.display(cityWeather.temperature))
                        .font(.system(size: 46, weight: .regular))
                        .contentTransition(.numericText())
                } else {
                    Text(tempUnit.display(forecast.dailyHigh))
                        .font(.system(size: 46, weight: .regular))
                        .contentTransition(.numericText())
                    Text(tempUnit.display(forecast.dailyLow))
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)
            }
            .animation(.smooth(duration: 0.3), value: internalSelectedDay)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            (colorScheme == .dark
             ? Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.48)
             : Color.white.opacity(0.62)),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
