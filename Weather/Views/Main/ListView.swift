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
    /// Wraps the full city list in its navigation and toolbar destination.
    var fullListDestination: some View {
        listView
            .navigationTitle(toolbarTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    listSwitcher(titleOverride: nil, navigationBarStyle: true)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            listEditMode.toggle()
                        }
                    } label: {
                        Image(systemName: listEditMode ? "checkmark" : "pencil")
                    }
                }
            }
            .onAppear {
                isMapCardPresented = false
                listEditMode = false
            }
            .onDisappear {
                listEditMode = false
            }
    }

    /// Builds the responsive list screen and its top controls.
    var listView: some View {
        GeometryReader { geometry in
            // A narrower landscape iPad column keeps a long ranked list scannable.
            let maxContentWidth = usesIPadLandscapeLayout(for: geometry.size) ? 680.0 : 760.0

            nativeCityList(maxContentWidth: maxContentWidth)
                .environment(\.defaultMinListRowHeight, 0)
                .background(theme.colors.background.ignoresSafeArea())
                .animation(.smooth(duration: 0.24), value: listEditMode)
        }
    }

    @ViewBuilder
    /// Builds the empty-list action or native editable city rows.
    private func nativeCityList(maxContentWidth: CGFloat) -> some View {
        if weatherService.cityListCoordinates().isEmpty {
            emptyListContent
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .frame(maxWidth: maxContentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            List {
                if listEditMode {
                    ForEach(sortedListCandidates) { candidate in
                        listRow(
                            candidate,
                            rank: nil,
                            showsWeatherMetrics: false,
                            cityRenameAction: {
                                // Seed and present the native city-rename alert.
                                let city = candidate.cityWeather.city
                                cityToRename = city
                                cityRenameText = CityListID.customCityName(for: city) ?? localizedCityName(for: city)
                                showingCityRenameAlert = true
                            }
                        )
                        .cityListNativeRowStyle(background: theme.colors.background)
                    }
                    .onDelete { offsets in
                        // Remove candidate rows selected through native list editing.
                        for index in offsets where sortedListCandidates.indices.contains(index) {
                            weatherService.removeCity(sortedListCandidates[index].cityWeather)
                        }
                        Haptics.lightImpact()
                    }
                } else if selectedListSortMode == .sunny {
                    sunninessGroupedCandidateRows(
                        sunninessCandidateGroups,
                        contextMenuListID: weatherService.activeListID
                    )
                } else {
                    listMetricHeading(for: selectedListSortMode)

                    listCandidateRows(
                        sortedListCandidates,
                        showsDividers: false,
                        listMetricMode: selectedListSortMode,
                        selectionAction: { candidate in
                            presentDetail(for: candidate.cityWeather)
                        },
                        contextMenuListID: weatherService.activeListID
                    )
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 16, for: .scrollContent)
            .environment(\.editMode, .constant(listEditMode ? .active : .inactive))
            // Keep the ranked sequence as one readable column on wide windows.
            // The outer flexible frame centers it without changing iPhone sizing.
            .frame(maxWidth: maxContentWidth)
            .frame(maxWidth: .infinity)
        }
    }

    /// Empty-list explanation and direct New City action shared with Home.
    var emptyListContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(theme.colors.accent)

            Text(
                String(
                    format: localizedString("No cities in %@ yet", locale: locale),
                    locale: locale,
                    toolbarTitle
                )
            )
            .font(.headline)
            .foregroundStyle(theme.colors.primaryText)
            .multilineTextAlignment(.center)

            Button {
                presentNewCitySearch()
            } label: {
                Label(localizedString("New City", locale: locale), systemImage: "plus")
                    .font(.body.weight(.semibold))
                    // Yellow calls to action retain the same dark ink in both
                    // appearances, matching the list-management actions.
                    .foregroundStyle(AppPalette.light.titleText)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(theme.colors.dotSun, in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    /// Builds grouped candidate sections with continuous one-based ranks.
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
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)
            }
            .padding(.top, groupIndex == 0 ? 8 : 30)
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
                listMetricMode: .sunny,
                selectionAction: { candidate in
                    presentDetail(for: candidate.cityWeather)
                },
                contextMenuListID: contextMenuListID
            )
        }
    }

    /// Labels a non-sunniness ranking with the same semantic icon as its sort option.
    private func listMetricHeading(for mode: WeatherListSortMode) -> some View {
        HStack(spacing: CityListLayout.columnSpacing) {
            Image(systemName: mode.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)

            Text(mode.title(locale: locale))
                .font(.body.weight(.bold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 5)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(theme.colors.background)
    }

    /// Menu for selecting the persisted city ordering rule.
    var listSortControl: some View {
        Menu {
            ForEach(WeatherListSortMode.allCases) { mode in
                Button {
                    listSortMode = mode.rawValue
                } label: {
                    primaryMenuLabel(mode.title(locale: locale), systemImage: selectedListSortMode == mode ? "checkmark" : mode.icon)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
    }

}

#Preview("List View") {
    ContentView(initialRoute: .list)
}
