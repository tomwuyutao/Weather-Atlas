//
//  CityCandidateRows.swift
//  Weather
//
//  Purpose: Provides the shared ranked-city row, column metrics, and row
//  builders used consistently by Home, List, and Detail surfaces.
//

import SwiftUI

// MARK: - Shared Column Layout

/// Shared column geometry keeping ranked rows aligned across screens.
enum CityListLayout {
    /// Width reserved for the optional rank number.
    static let rankColumnWidth: CGFloat = 32
    /// Horizontal spacing between rank, name, and metric columns.
    static let columnSpacing: CGFloat = 5
    /// Leading inset matching a row whose rank column is present.
    static let cityNameLeadingInset = rankColumnWidth + columnSpacing
}

// MARK: - Candidate Row

/// Configurable ranked-city row shared by Home, List, and detail contexts.
struct SunnyCandidateRow: View {
    /// Complete ranking inputs for the displayed city.
    let candidate: SunnyCandidate
    /// Optional one-based rank column.
    var rank: Int? = nil
    /// Whether the row uses reduced vertical padding.
    var compact: Bool = false
    /// Whether to show the normalized condition symbol.
    var showsConditionIcon: Bool = true
    /// Whether to show the entire trailing metrics group.
    var showsWeatherMetrics: Bool = true
    /// Whether temperature participates in the metrics group.
    var showsTemperature: Bool = true
    /// Resolved temperature unit used to format the daily high.
    let tempUnit: TemperatureUnit
    /// Optional externally supplied city label.
    var cityNameOverride: String? = nil
    /// Optional rename action shown as a trailing pencil button.
    var cityRenameAction: (() -> Void)? = nil

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// App-selected locale used for default city naming.
    @Environment(\.locale) private var locale
    /// Text category used to widen fixed metric columns.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    /// Exposes the configured row content.
    var body: some View {
        rowContent
    }

    /// Composes rank, city name, metrics, and optional rename action.
    private var rowContent: some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            if let rank {
                CityRankLabel(rank: rank)
            }

            // Apply an override before falling back to the localized catalog name.
            Text(
                cityNameOverride
                    ?? localizedCityDisplayName(for: candidate.cityWeather.city, locale: locale)
            )
            .font(.body.weight(.medium))
            .foregroundStyle(theme.colors.primaryText)
            .lineLimit(1)

            Spacer(minLength: 8)

            if showsWeatherMetrics {
                weatherMetrics(usesFixedColumns: true)
            }

            // Supply a rename affordance only when the parent owns that workflow.
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
        .padding(.horizontal, 0)
        .padding(.vertical, compact ? 8 : 9)
        .contentShape(Rectangle())
    }

    /// Builds temperature, cloud-cover, and condition metric columns.
    private func weatherMetrics(usesFixedColumns: Bool) -> some View {
        let icon = candidate.condition.displayIcon
        let cloudText = "\(Int((candidate.cloudCover * 100).rounded()))%"
        // Temperature and cloud cover share one Dynamic Type-aware column width.
        let metricWidth: CGFloat = dynamicTypeSize > .large ? 72 : 58

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
                .frame(width: usesFixedColumns ? metricWidth : nil, alignment: .leading)
            }

            HStack(spacing: 3) {
                Image(systemName: "cloud")
                    .font(.caption.weight(.medium))
                Text(cloudText)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(theme.colors.secondaryText)
            .frame(width: usesFixedColumns ? metricWidth : nil, alignment: .leading)
            .padding(.trailing, usesFixedColumns ? 5 : 0)

            if showsConditionIcon {
                Image(systemName: icon)
                    .font(.caption.weight(.medium))
                    .weatherIconStyle(for: icon)
                    .frame(
                        width: usesFixedColumns ? (dynamicTypeSize > .large ? 26 : 22) : nil,
                        alignment: .trailing
                    )
            }
        }
        .foregroundStyle(theme.colors.secondaryText)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

}

/// Fixed-width one-based rank label aligned across candidate rows.
struct CityRankLabel: View {
    /// One-based position displayed by the row.
    let rank: Int

    /// Active semantic palette.
    @Environment(\.appTheme) private var theme
    /// Text category used to scale the numeric rank.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Builds the monoline rank label.
    var body: some View {
        Text(verbatim: String(rank))
            // Map the numeric rank to the supported text categories in place.
            .font(.system(
                size: {
                    switch dynamicTypeSize {
                    case .xSmall: return 13
                    case .small: return 14
                    case .medium: return 15
                    case .large: return 16
                    case .xLarge: return 18
                    default: return 20
                    }
                }(),
                weight: .semibold,
                design: .default
            ))
            .foregroundStyle(theme.colors.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.leading, 5)
            .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
    }

}

// MARK: - ContentView Row Builders

extension ContentView {
    /// Creates a shared candidate row using root locale, theme, and temperature state.
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

    /// Creates the compact list variant with persisted city renames applied.
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
    /// Builds selectable ranked rows, optional context menus, and aligned dividers.
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
                    // Keep the context preview fixed-width and visually separated.
                    sunnyCandidateRow(
                        candidate,
                        rank: rank,
                        compact: true,
                        showsConditionIcon: showsConditionIcon
                    )
                    .padding(.vertical, 2)
                    .background(
                        theme.colors.listCardFill,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.colors.accent.opacity(0.35), lineWidth: 1)
                    }
                    .frame(width: 360)
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

}

// MARK: - Saved-City Context Menu

extension ContentView {
    @ViewBuilder
    /// Supplies rename, move, and delete actions for a city in a known list.
    func cityActions(for city: CityWeather, in listID: CityListID) -> some View {
        let destinationLists = managedLists.filter { $0.rawValue != listID.rawValue }

        if !destinationLists.isEmpty {
            Menu {
                ForEach(destinationLists) { destinationListID in
                    Button {
                        weatherService.moveCity(city, from: listID, to: destinationListID)
                        Haptics.lightImpact()
                    } label: {
                        primaryMenuLabel(
                            destinationListID.localizedDisplayName(locale: locale),
                            systemImage: "list.bullet"
                        )
                    }
                }
            } label: {
                primaryMenuLabel(
                    localizedString("Move", locale: locale),
                    systemImage: "arrow.right"
                )
            }
        }

        Button {
            cityToRename = city.city
            cityRenameText = CityListID.customCityName(for: city.city)
                ?? localizedCityName(for: city.city)
            showingCityRenameAlert = true
        } label: {
            primaryMenuLabel(
                localizedString("Rename", locale: locale),
                systemImage: "pencil"
            )
        }

        Button {
            weatherService.removeCity(city, from: listID)
        } label: {
            Label {
                Text(localizedString("Delete", locale: locale))
            } icon: {
                Image(systemName: "trash")
                    .foregroundStyle(theme.colors.destructive)
            }
        }
        .tint(theme.colors.destructive)
    }
}

extension View {
    /// Applies the native list-row insets and background shared by city lists.
    func cityListNativeRowStyle(background: Color) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}
