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

            List {
                ForEach(Array(sortedListCandidates.enumerated()), id: \.element.id) { index, candidate in
                    if listEditMode {
                        listRow(candidate, rank: nil)
                    } else {
                        Button {
                            presentDetail(for: candidate.cityWeather)
                        } label: {
                            listRow(candidate, rank: index + 1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            cityActions(for: candidate.cityWeather, in: weatherService.activeListID)
                        } preview: {
                            listContextPreviewRow(candidate, rank: index + 1)
                        }
                    }
                }
                .onDelete { offsets in
                    for offset in offsets {
                        guard sortedListCandidates.indices.contains(offset) else { continue }
                        removeListCity(sortedListCandidates[offset].cityWeather)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(theme.colors.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.editMode, Binding<EditMode>(
                get: { listEditMode ? .active : .inactive },
                set: { mode in
                    withAnimation(.smooth(duration: 0.2)) {
                        listEditMode = mode.isEditing
                    }
                }
            ))
        }
        .padding(.top, -56)
        .background(theme.colors.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                    .tint(theme.colors.primaryText)

                    Button {
                        withAnimation(.smooth(duration: 0.2)) {
                            listEditMode = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .accessibilityLabel(localizedString("Edit", locale: locale))

                    Button {
                        activateSearch()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.colors.primaryText)
                    }
                    .accessibilityLabel(localizedString("Add City", locale: locale))
                }
            }
        }
    }

    private var listHeader: some View {
        HStack {
            listNavigationTitleMenu

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
                    Text(listID.localizedDisplayName(locale: locale))
                        .foregroundStyle(theme.colors.primaryText)
                }
            }

            Divider()

            Button {
                listEditMode = false
                activateAddListOptions()
            } label: {
                primaryMenuLabel(localizedString("Add List", locale: locale), systemImage: "plus")
            }

            Divider()

            Button {
                showingDeleteListConfirmation = true
            } label: {
                Label {
                    Text(localizedString("Delete List", locale: locale))
                        .foregroundStyle(theme.colors.primaryText)
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(theme.colors.destructive)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(toolbarTitle)
                    .font(.system(.title, design: .serif).weight(.semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
        .menuOrder(.fixed)
        .tint(theme.colors.primaryText)
        .buttonStyle(.plain)
    }

    func listRow(_ candidate: SunnyCandidate, rank: Int?) -> some View {
        sunnyCandidateRow(candidate, rank: rank, compact: true)
    }

    private func listContextPreviewRow(_ candidate: SunnyCandidate, rank: Int) -> some View {
        sunnyCandidateRow(candidate, rank: rank, compact: true)
            .padding(.vertical, 2)
            .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(theme.colors.accent.opacity(0.35), lineWidth: 1)
            }
            .frame(width: 360)
    }

    func removeListCity(_ city: CityWeather) {
        weatherService.removeCity(city, from: weatherService.activeListID)
        Haptics.lightImpact()
    }
}

#Preview("List View") {
    ContentView(initialRoute: .list)
}
