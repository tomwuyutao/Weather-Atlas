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
            if listEditMode {
                nativeEditingList
            } else {
                listBrowsingScroll
            }

            listHeader
        }
        .environment(\.defaultMinListRowHeight, 0)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.smooth(duration: 0.24), value: listEditMode)
    }

    private var listBrowsingScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if selectedListSortMode == .sunny {
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
            .padding(.horizontal, 16)
            .padding(.top, 76)
            .padding(.bottom, 16)
        }
        .scrollContentBackground(.hidden)
    }

    private var nativeEditingList: some View {
        List {
            ForEach(sortedListCandidates) { candidate in
                listRow(
                    candidate,
                    rank: nil,
                    showsWeatherMetrics: false,
                    cityRenameAction: { beginCityRename(candidate.cityWeather.city) }
                )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(theme.colors.background)
            }
            .onDelete(perform: deleteListCandidates)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 76, for: .scrollContent)
        .contentMargins(.bottom, 16, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
    }

    private var listHeader: some View {
        topToolbar {
            listTopToolbarActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
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

            Divider()
                .padding(.bottom, 6)

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

                Button {
                    activateSearch()
                } label: {
                    listToolbarActionIcon("plus", accessibilityLabel: localizedString("Add City", locale: locale))
                }
                .buttonStyle(.plain)
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
            listToolbarActionIcon("arrow.up.arrow.down", accessibilityLabel: localizedString("Sort", locale: locale))
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
        .buttonStyle(.plain)
    }

    private func listToolbarActionIcon(_ systemImage: String, accessibilityLabel: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(theme.colors.primaryText)
            .frame(width: 32, height: 36)
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityLabel)
    }

    private var listNavigationTitleMenu: some View {
        Menu {
            ForEach(managedLists) { listID in
                Button {
                    listEditMode = false
                    Task {
                        await switchToList(listID)
                    }
                } label: {
                    HStack {
                        Text(listID.localizedDisplayName(locale: locale))
                            .foregroundStyle(theme.colors.primaryText)

                        Spacer()

                        if listID.rawValue == weatherService.activeListID.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }
                }
            }

            Divider()

            Button {
                listEditMode = false
                activateAddListOptions()
            } label: {
                primaryMenuLabel(localizedString("New List", locale: locale), systemImage: "plus")
            }

            Button {
                listEditMode = false
                listToRenameID = weatherService.activeListID
                renameAlertText = weatherService.activeListID.localizedDisplayName(locale: locale)
                showingRenameAlert = true
            } label: {
                primaryMenuLabel(localizedString("Rename List", locale: locale), systemImage: "pencil")
            }

            Button {
                listToDeleteID = weatherService.activeListID
                showingDeleteListConfirmation = true
            } label: {
                Label {
                    Text(localizedString("Delete List", locale: locale))
                        .foregroundStyle(theme.colors.primaryText)
                } icon: {
                    Image(systemName: "trash")
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(theme.colors.destructive)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(toolbarTitle)
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
            }
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
    }

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
                    listContextPreviewRow(candidate, rank: index + 1, showsConditionIcon: showsConditionIcon)
                }
            } else if let selectionAction {
                Button {
                    selectionAction(candidate)
                } label: {
                    listRow(candidate, rank: rank, showsConditionIcon: showsConditionIcon)
                }
                .buttonStyle(.plain)
            }

            if showsDividers && index < candidates.count - 1 {
                Divider()
                    .background(theme.colors.secondaryText.opacity(0.16))
                    .padding(.leading, CityListLayout.cityNameLeadingInset)
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
        renameAlertText = CityListID.customCityName(for: city) ?? localizedCityName(for: city)
        showingCityRenameAlert = true
    }
}

#Preview("List View") {
    ContentView(initialRoute: .list)
}
