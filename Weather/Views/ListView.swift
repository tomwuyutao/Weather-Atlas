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
        ZStack(alignment: .top) {
            nativeCityList

            listHeader
        }
        .environment(\.defaultMinListRowHeight, 0)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle(toolbarTitle)
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.smooth(duration: 0.24), value: listEditMode)
    }

    private var nativeCityList: some View {
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
                    contextMenuListID: isShowingAllLists ? nil : weatherService.activeListID,
                    usesAggregateSources: isShowingAllLists
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 76, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .environment(\.editMode, .constant(listEditMode ? .active : .inactive))
        // Keep the ranked sequence as one readable column on wide windows.
        // The outer flexible frame centers it without changing iPhone sizing.
        .frame(maxWidth: cityListContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var listHeader: some View {
        topToolbar {
            listTopToolbarActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: cityListContentMaxWidth)
        .frame(maxWidth: .infinity)
        // Accessibility: Announce the persistent list controls before scrolling rows.
        .accessibilitySortPriority(1)
    }

    private var cityListContentMaxWidth: CGFloat {
        760
    }

    private var sunninessGroupedCandidateRows: some View {
        sunninessGroupedCandidateRows(
            sunninessCandidateGroups,
            contextMenuListID: isShowingAllLists ? nil : weatherService.activeListID,
            usesAggregateSources: isShowingAllLists
        )
    }

    @ViewBuilder
    private func sunninessGroupedCandidateRows(
        _ groups: [SunninessCandidateGroup],
        contextMenuListID: CityListID?,
        usesAggregateSources: Bool = false
    ) -> some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
            HStack(spacing: CityListLayout.columnSpacing) {
                // Accessibility: The weather symbol is decorative because the
                // localized group title is exposed as a heading below.
                Image(systemName: group.icon)
                    .font(.body.weight(.semibold))
                    .weatherIconStyle(for: group.icon)
                    .frame(width: CityListLayout.rankColumnWidth, alignment: .leading)
                    .accessibilityHidden(true)

                Text(group.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.body.weight(.bold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)

                Spacer(minLength: 0)
            }
            .padding(.top, groupIndex == 0 ? 0 : 22)
            .padding(.bottom, 5)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(theme.colors.background)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(group.title.replacingOccurrences(of: "\n", with: " "))
            .accessibilityAddTraits(.isHeader)

            Rectangle()
                .fill(theme.colors.secondaryText.opacity(0.16))
                .frame(maxWidth: .infinity)
                .frame(height: 1)
                .padding(.bottom, 6)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(theme.colors.background)
                // Accessibility: The separator conveys no information beyond the
                // heading and must not interrupt row-by-row VoiceOver navigation.
                .accessibilityHidden(true)

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
                contextMenuListID: contextMenuListID,
                usesAggregateSources: usesAggregateSources
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
                    listToolbarActionIcon("checkmark", accessibilityLabel: localizedString("Done", locale: locale))
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
                    listToolbarActionIcon("pencil", accessibilityLabel: localizedString("Edit", locale: locale))
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
                // Accessibility: Communicate the active sort independently of
                // the visual checkmark shown in the menu label.
                .accessibilityAddTraits(selectedListSortMode == mode ? .isSelected : [])
            }
        } label: {
            listToolbarActionIcon("arrow.up.arrow.down", accessibilityLabel: localizedString("Sort", locale: locale))
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .padding(.vertical, -4)
        .accessibilityLabel(localizedString("Sort", locale: locale))
        .accessibilityValue(selectedListSortMode.title(locale: locale))
    }

    // MARK: - Accessibility - Toolbar Hit Targets

    private func listToolbarActionIcon(_ systemImage: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(theme.colors.primaryText)
            // Accessibility: Provide the recommended control target without
            // changing the visible SF Symbol or the surrounding glass capsule.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - List Rows

    func listRow(
        _ candidate: SunnyCandidate,
        rank: Int?,
        showsConditionIcon: Bool = true,
        showsWeatherMetrics: Bool = true,
        cityRenameAction: (() -> Void)? = nil
    ) -> some View {
        sunnyCandidateRow(
            candidate,
            rank: rank,
            compact: true,
            showsConditionIcon: showsConditionIcon,
            showsWeatherMetrics: showsWeatherMetrics,
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
        selectionAction: ((SunnyCandidate) -> Void)?,
        contextMenuListID: CityListID? = nil,
        usesAggregateSources: Bool = false
    ) -> some View {
        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
            let rank = rankOffset + index + 1
            let menuListID = contextMenuListID
                ?? (usesAggregateSources ? sourceListID(for: candidate.cityWeather) : nil)

            if let selectionAction, let menuListID {
                Button {
                    selectionAction(candidate)
                } label: {
                    listRow(candidate, rank: rank, showsConditionIcon: showsConditionIcon)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    cityActions(for: candidate.cityWeather, in: menuListID)
                } preview: {
                    listContextPreviewRow(candidate, rank: rank, showsConditionIcon: showsConditionIcon)
                }
                // Accessibility: Mirror long-press-only context-menu operations as
                // standard VoiceOver/Voice Control actions on the city row.
                .accessibilityActions {
                    listRowAccessibilityActions(for: candidate.cityWeather, in: menuListID)
                }
                .cityListNativeRowStyle(background: theme.colors.background)
            } else if let selectionAction {
                Button {
                    selectionAction(candidate)
                } label: {
                    listRow(candidate, rank: rank, showsConditionIcon: showsConditionIcon)
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

    // MARK: - Accessibility - City Context Actions

    @ViewBuilder
    private func listRowAccessibilityActions(for city: CityWeather, in listID: CityListID) -> some View {
        ForEach(managedLists.filter { $0.rawValue != listID.rawValue }) { destinationListID in
            Button {
                weatherService.moveCity(city, from: listID, to: destinationListID)
                Haptics.lightImpact()
            } label: {
                Text("\(localizedString("Move", locale: locale)), \(destinationListID.localizedDisplayName(locale: locale))")
            }
        }

        Button {
            beginCityRename(city.city)
        } label: {
            Text(localizedString("Rename", locale: locale))
        }

        Button(role: .destructive) {
            removeDisplayedCity(city, from: listID)
        } label: {
            Text(localizedString("Delete", locale: locale))
        }
    }

    private func deleteListCandidates(at offsets: IndexSet) {
        let sourceCities = offsets.compactMap { index -> (CityWeather, CityListID)? in
            let city = sortedListCandidates[index].cityWeather
            guard let sourceListID = sourceListID(for: city) else { return nil }
            return (city, sourceListID)
        }
        for (city, sourceListID) in sourceCities {
            removeDisplayedCity(city, from: sourceListID)
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
