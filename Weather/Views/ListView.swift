//
//  ListView.swift
//  Weather
//
//  Purpose: Shows the active city list, with sorting and
//  inline edit controls for removing cities.
//

import SwiftUI

// MARK: - List View

extension ContentView {
    var listView: some View {
        GeometryReader { geometry in
            let maxContentWidth = cityListContentMaxWidth(for: geometry.size)

            ZStack(alignment: .top) {
                nativeCityList(maxContentWidth: maxContentWidth)

                listHeader(maxContentWidth: maxContentWidth)
            }
            .environment(\.defaultMinListRowHeight, 0)
            .background(theme.colors.background.ignoresSafeArea())
            .navigationTitle(toolbarTitle)
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .animation(.smooth(duration: 0.24), value: listEditMode)
        }
    }

    private func nativeCityList(maxContentWidth: CGFloat) -> some View {
        List {
            if listEditMode {
                ForEach(sortedListCandidates) { candidate in
                    listRow(
                        candidate,
                        rank: nil,
                        showsWeatherMetrics: false,
                        cityRenameAction: { beginCityRename(candidate.cityWeather.city) }
                    )
                    .cityListNativeRowStyle(background: theme.colors.background)
                }
                .onDelete(perform: deleteListCandidates)
            } else if selectedListSortMode == .sunny {
                sunninessGroupedCandidateRows
            } else {
                listCandidateRows(
                    sortedListCandidates,
                    showsDividers: false,
                    selectionAction: { candidate in
                        presentDetail(for: candidate.cityWeather)
                    },
                    contextMenuListID: weatherService.activeListID
                )
            }

            let droppedCityCount = expectedForecastBoundaryOmissionCount(
                in: forecastDateSourceCities
            )
            if droppedCityCount > 0 {
                forecastAvailabilityNote(droppedCityCount: droppedCityCount)
                    .padding(.leading, 5)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .cityListNativeRowStyle(background: theme.colors.background)
            }

            if let explanation = missingForecastExplanation(for: forecastDateSourceCities) {
                WeatherDataUnavailableNotice(message: explanation)
                    .cityListNativeRowStyle(background: theme.colors.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 76, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .environment(\.editMode, .constant(listEditMode ? .active : .inactive))
        // Keep the ranked sequence as one readable column on wide windows.
        // The outer flexible frame centers it without changing iPhone sizing.
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    private func listHeader(maxContentWidth: CGFloat) -> some View {
        topToolbar {
            listTopToolbarActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    private func cityListContentMaxWidth(for size: CGSize) -> CGFloat {
        // A narrower landscape iPad column keeps a long ranked list easy to scan.
        usesIPadLandscapeLayout(for: size) ? 680 : 760
    }

    private var sunninessGroupedCandidateRows: some View {
        sunninessGroupedCandidateRows(
            sunninessCandidateGroups,
            contextMenuListID: weatherService.activeListID
        )
    }

    @ViewBuilder
    private func sunninessGroupedCandidateRows(
        _ groups: [SunninessCandidateGroup],
        contextMenuListID: CityListID?
    ) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
            HStack(spacing: CityListLayout.columnSpacing) {
                Image(systemName: group.icon)
                    .font(.body.weight(.semibold))
                    .weatherIconStyle(for: group.icon)
                    .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)

                Text(group.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.body.weight(.bold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }
            .padding(.top, groupIndex == 0 ? 0 : 22)
            .padding(.bottom, 5)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(theme.colors.background)

            Rectangle()
                .fill(theme.colors.secondaryText.opacity(0.16))
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(theme.colors.background)

            let rankOffset = groups
                .prefix(groupIndex)
                .reduce(0) { $0 + $1.candidates.count }

            listCandidateRows(
                group.candidates,
                rankOffset: rankOffset,
                showsDividers: false,
                showsConditionIcon: false,
                selectionAction: { candidate in
                    presentDetail(for: candidate.cityWeather)
                },
                contextMenuListID: contextMenuListID
            )
        }
    }

    private var listTopToolbarActions: some View {
        topToolbarActionCapsule {
            if listEditMode {
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        listEditMode = false
                    }
                } label: {
                    listToolbarActionIcon("checkmark")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .padding(.vertical, -4)
            } else {
                listSortControl

                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        listEditMode = true
                    }
                } label: {
                    listToolbarActionIcon("pencil")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -6)
                .padding(.vertical, -4)

            }
        }
    }

    private var listSortControl: some View {
        Menu {
            ForEach(WeatherListSortMode.allCases) { mode in
                Button {
                    listSortMode = mode.rawValue
                } label: {
                    primaryMenuLabel(mode.title(locale: locale), systemImage: selectedListSortMode == mode ? "checkmark" : mode.icon)
                }
            }
        } label: {
            listToolbarActionIcon("arrow.up.arrow.down")
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
    }

    private func listToolbarActionIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(theme.colors.primaryText)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: - List Rows

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

    private func deleteListCandidates(at offsets: IndexSet) {
        for index in offsets where sortedListCandidates.indices.contains(index) {
            weatherService.removeCity(sortedListCandidates[index].cityWeather)
        }
        Haptics.lightImpact()
    }

    private func beginCityRename(_ city: City) {
        cityToRename = city
        cityRenameText = CityListID.customCityName(for: city) ?? localizedCityName(for: city)
        showingCityRenameAlert = true
    }
}

private extension View {
    func cityListNativeRowStyle(background: Color) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(background)
    }
}

#Preview("List View") {
    ContentView(initialRoute: .list)
}
