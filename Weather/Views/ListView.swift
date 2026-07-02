//
//  ListView.swift
//  Weather
//
//  Purpose: Shows the active city list, with sorting and
//  inline edit controls for city rename/remove actions.
//

import SwiftUI

// MARK: - List View

extension ContentView {
    var listView: some View {
        VStack(spacing: 0) {
            listHeader

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(sortedListCandidates.enumerated()), id: \.element.id) { index, candidate in
                        if listEditMode {
                            listRow(candidate, rank: index + 1)
                        } else {
                            Button {
                                presentDetail(for: candidate.cityWeather)
                            } label: {
                                listRow(candidate, rank: index + 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                cityActions(for: candidate.cityWeather, in: weatherService.activeListID)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .scrollContentBackground(.hidden)
        }
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var listHeader: some View {
        VStack(spacing: 0) {
            topToolbar {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(WeatherListSortMode.allCases) { mode in
                            Button {
                                weatherListSortModeRaw = mode.rawValue
                            } label: {
                                Label(mode.title(locale: locale), systemImage: listSortMode == mode ? "checkmark" : mode.icon)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .themedGlass(in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            listEditMode.toggle()
                        }
                    } label: {
                        Image(systemName: listEditMode ? "checkmark" : "pencil")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .themedGlass(in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    func listRow(_ candidate: SunnyCandidate, rank: Int) -> some View {
        HStack(spacing: 8) {
            if listEditMode {
                Button {
                    removeListCity(candidate.cityWeather)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.colors.destructive)
                        .frame(width: 34, height: 44)
                }
                .buttonStyle(.plain)
            }

            sunnyCandidateRow(candidate, rank: rank, compact: false)

            if listEditMode {
                Button {
                    beginEditingListCity(candidate.cityWeather)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                        .frame(width: 38, height: 44)
                        .themedGlass(in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.2), value: listEditMode)
    }

    func beginEditingListCity(_ city: CityWeather) {
        listToRenameID = nil
        showingRenameAlert = false
        cityToRename = city
        cityToRenameListID = weatherService.activeListID
        cityRenameText = city.city.localizedName(locale: locale)
        showingCityRenameAlert = true
    }

    func removeListCity(_ city: CityWeather) {
        weatherService.removeCity(city, from: weatherService.activeListID)
        refreshCityOrder()
        PlatformFeedback.lightImpact()
    }
}
