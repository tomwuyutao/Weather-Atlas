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
        VStack(spacing: 0) {
            listHeader

            ScrollView {
                LazyVStack(spacing: 0) {
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

                        if index < sortedListCandidates.count - 1 {
                            Divider()
                                .background(theme.colors.secondaryText.opacity(0.18))
                                .padding(.leading, listEditMode ? 78 : 34)
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
                if listEditMode {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            listEditMode = false
                        }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Menu {
                        Menu {
                            ForEach(WeatherListSortMode.allCases) { mode in
                                Button {
                                    listSortMode = mode.rawValue
                                } label: {
                                    primaryMenuLabel(mode.title(locale: locale), systemImage: selectedListSortMode == mode ? "checkmark" : mode.icon)
                                }
                            }
                        } label: {
                            primaryMenuLabel(localizedString("Sort", locale: locale), systemImage: "arrow.up.arrow.down")
                        }

                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
                                listEditMode = true
                            }
                        } label: {
                            primaryMenuLabel(localizedString("Edit", locale: locale), systemImage: "pencil")
                        }

                        Button {
                            activateSearch()
                        } label: {
                            primaryMenuLabel(localizedString("Add City", locale: locale), systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.colors.primaryText)
                            .frame(width: 38, height: 38)
                            .themedGlass(in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .tint(theme.colors.primaryText)
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
        }
        .animation(.smooth(duration: 0.2), value: listEditMode)
    }

    func removeListCity(_ city: CityWeather) {
        weatherService.removeCity(city, from: weatherService.activeListID)
        refreshCityOrder()
        Haptics.lightImpact()
    }
}

#Preview("List View") {
    ContentView(initialRoute: .list)
}
