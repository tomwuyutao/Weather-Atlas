//
//  CityCandidateRows.swift
//  Weather
//
//  Purpose: Provides the shared ranked-city row, column metrics, and row
//  builders used consistently by Home, List, and Detail surfaces.
//

import SwiftUI

// MARK: - Shared Column Layout

enum CityListLayout {
    static let rankColumnWidth: CGFloat = 32
    static let columnSpacing: CGFloat = 5
    static let cityNameLeadingInset = rankColumnWidth + columnSpacing
}

// MARK: - Candidate Row

struct SunnyCandidateRow: View {
    let candidate: SunnyCandidate
    var rank: Int? = nil
    var compact: Bool = false
    var showsConditionIcon: Bool = true
    var showsWeatherMetrics: Bool = true
    var showsTemperature: Bool = true
    let tempUnit: TemperatureUnit
    var cityNameOverride: String? = nil
    var cityRenameAction: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        rowContent
    }

    private var rowContent: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            if let rank {
                CityRankLabel(rank: rank)
            }

            cityNameLabel(lineLimit: 1)

            Spacer(minLength: 8)

            if showsWeatherMetrics {
                weatherMetrics(usesFixedColumns: true)
            }

            renameButton
        }
        .padding(.horizontal, 0)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }

    private func cityNameLabel(lineLimit: Int) -> some View {
        Text(cityName)
            .font(.body.weight(.medium))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(lineLimit)
    }

    private func weatherMetrics(usesFixedColumns: Bool) -> some View {
        let icon = candidate.condition.displayIcon
        let cloudText = "\(Int((candidate.cloudCover * 100).rounded()))%"

        return HStack(spacing: usesFixedColumns ? 0 : 10) {
            if showsTemperature {
                HStack(spacing: 3) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption.weight(.medium))
                    Text(tempUnit.display(candidate.temperature))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: usesFixedColumns ? temperatureMetricWidth : nil, alignment: .leading)
            }

            HStack(spacing: 3) {
                Image(systemName: "cloud")
                    .font(.caption.weight(.medium))
                Text(cloudText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.colors.secondaryText)
            .frame(width: usesFixedColumns ? cloudMetricWidth : nil, alignment: .leading)
            .padding(.trailing, usesFixedColumns ? 5 : 0)

            if showsConditionIcon {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .weatherIconStyle(for: icon)
                    .frame(width: usesFixedColumns ? conditionMetricWidth : nil, alignment: .trailing)
            }
        }
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var renameButton: some View {
        if let cityRenameAction {
            Button(action: cityRenameAction) {
                Image(systemName: "pencil")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .padding(.vertical, -4)
        }
    }

    private var cityName: String {
        cityNameOverride
            ?? localizedCityDisplayName(for: candidate.cityWeather.city, locale: locale)
    }

    // MARK: Layout

    private var verticalPadding: CGFloat {
        compact ? 8 : 9
    }

    private var temperatureMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 72 : 58
    }

    private var cloudMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 72 : 58
    }

    private var conditionMetricWidth: CGFloat {
        dynamicTypeSize > .large ? 26 : 22
    }
}

struct CityRankLabel: View {
    let rank: Int

    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(verbatim: String(rank))
            .font(.system(size: rankFontSize, weight: .semibold, design: .default))
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 5)
            .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
    }

    private var rankFontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall: return 13
        case .small: return 14
        case .medium: return 15
        case .large: return 16
        case .xLarge: return 18
        default: return 20
        }
    }
}

// MARK: - ContentView Row Builders

extension ContentView {
    func sunnyCandidateRow(
        _ candidate: SunnyCandidate,
        rank: Int? = nil,
        compact: Bool = false,
        showsConditionIcon: Bool = true,
        showsWeatherMetrics: Bool = true,
        showsTemperature: Bool = true,
        cityNameOverride: String? = nil,
        cityRenameAction: (() -> Void)? = nil
    ) -> some View {
        SunnyCandidateRow(
            candidate: candidate,
            rank: rank,
            compact: compact,
            showsConditionIcon: showsConditionIcon,
            showsWeatherMetrics: showsWeatherMetrics,
            showsTemperature: showsTemperature,
            tempUnit: tempUnit,
            cityNameOverride: cityNameOverride ?? localizedCityName(for: candidate.cityWeather.city),
            cityRenameAction: cityRenameAction
        )
    }

    func listRow(
        _ candidate: SunnyCandidate,
        rank: Int?,
        showsConditionIcon: Bool = true,
        showsWeatherMetrics: Bool = true,
        showsTemperature: Bool = true,
        cityRenameAction: (() -> Void)? = nil
    ) -> some View {
        sunnyCandidateRow(
            candidate,
            rank: rank,
            compact: true,
            showsConditionIcon: showsConditionIcon,
            showsWeatherMetrics: showsWeatherMetrics,
            showsTemperature: showsTemperature,
            cityNameOverride: CityListID.customCityName(for: candidate.cityWeather.city)
                ?? localizedCityName(for: candidate.cityWeather.city),
            cityRenameAction: cityRenameAction
        )
    }

    @ViewBuilder
    func listCandidateRows(
        _ candidates: [SunnyCandidate],
        rankOffset: Int = 0,
        showsDividers: Bool,
        showsConditionIcon: Bool = true,
        showsTemperature: Bool = true,
        selectionAction: ((SunnyCandidate) -> Void)?,
        contextMenuListID: CityListID? = nil
    ) -> some View {
        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
            let rank = rankOffset + index + 1
            let menuListID = contextMenuListID

            if let selectionAction, let menuListID {
                Button {
                    selectionAction(candidate)
                } label: {
                    listRow(
                        candidate,
                        rank: rank,
                        showsConditionIcon: showsConditionIcon,
                        showsTemperature: showsTemperature
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    cityActions(for: candidate.cityWeather, in: menuListID)
                } preview: {
                    listContextPreviewRow(candidate, rank: rank, showsConditionIcon: showsConditionIcon)
                }
                .cityListNativeRowStyle(background: theme.colors.background)
            } else if let selectionAction {
                Button {
                    selectionAction(candidate)
                } label: {
                    listRow(
                        candidate,
                        rank: rank,
                        showsConditionIcon: showsConditionIcon,
                        showsTemperature: showsTemperature
                    )
                }
                .buttonStyle(.plain)
                .cityListNativeRowStyle(background: theme.colors.background)
            }

            if showsDividers && index < candidates.count - 1 {
                Divider()
                    .background(theme.colors.secondaryText.opacity(0.16))
                    .padding(.leading, CityListLayout.cityNameLeadingInset)
                    .cityListNativeRowStyle(background: theme.colors.background)
            }
        }
    }

    private func listContextPreviewRow(
        _ candidate: SunnyCandidate,
        rank: Int,
        showsConditionIcon: Bool
    ) -> some View {
        sunnyCandidateRow(candidate, rank: rank, compact: true, showsConditionIcon: showsConditionIcon)
            .padding(.vertical, 2)
            .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.colors.accent.opacity(0.35), lineWidth: 1)
            }
            .frame(width: 360)
    }
}

extension View {
    func cityListNativeRowStyle(background: Color) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}
