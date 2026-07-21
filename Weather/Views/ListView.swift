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
    var fullListDestination: some View {
        listView
            .navigationTitle(toolbarTitle)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                showingMapExpandedCard = false
                listEditMode = false
            }
    }

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

            let droppedCityCount = rankingOmissionCount(
                in: forecastDateSourceCities
            )
            if droppedCityCount > 0 {
                forecastAvailabilityNote(droppedCityCount: droppedCityCount)
                    .padding(.leading, 5)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
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

#Preview("List View") {
    ContentView(initialRoute: .list)
}
