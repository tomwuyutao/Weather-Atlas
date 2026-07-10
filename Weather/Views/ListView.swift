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
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedListCandidates.enumerated()), id: \.element.id) { index, candidate in
                        if listEditMode {
                            listRow(candidate, rank: nil) {
                                removeListCity(candidate.cityWeather)
                            }
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 76)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)

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

    private var listHeader: some View {
        topToolbar {
            listTopToolbarActions
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
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

    func listRow(_ candidate: SunnyCandidate, rank: Int?, deleteAction: (() -> Void)? = nil) -> some View {
        sunnyCandidateRow(candidate, rank: rank, compact: true, deleteAction: deleteAction)
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
