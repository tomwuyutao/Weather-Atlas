//
//  ContentView+iOSToolbar.swift
//  Weather
//
//  Shared toolbar helpers.
//

import SwiftUI
import MapKit

extension ContentView {

    /// Whether the map is in a special full-screen mode.
    var isMapSpecialMode: Bool {
        countrySelectionMode || isLoadingCountryOverview || countryOverviewActive
        || radialSearchMode || isLoadingRadialSearch || radialSearchActive
    }

    // MARK: - Date Switcher Capsule

    var iOSDateSwitcherCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset > -1 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > -1 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dateSwitcherForward = false
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                }

            Text(iOSDateText)
                .font(.avenir(.caption, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 80)
                .id("ios-date-\(selectedDayOffset)")
                .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    showingDatePopover = true
                }
                .popover(isPresented: $showingDatePopover) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: {
                                Calendar.current.date(byAdding: .day, value: max(0, selectedDayOffset), to: Date()) ?? Date()
                            },
                            set: { newDate in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: newDate))
                                if let days = components.day {
                                    withAnimation(.smooth(duration: 0.2)) {
                                        selectedDayOffset = max(0, min(9, days))
                                    }
                                }
                            }
                        ),
                        in: Date()...(Calendar.current.date(byAdding: .day, value: 9, to: Date()) ?? Date()),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 280, height: 300)
                    .padding(8)
                    .presentationCompactAdaptation(.popover)
                    .themedPopoverBackground()
                }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset < 9 ? .primary : .tertiary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset < 9 {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dateSwitcherForward = true
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset += 1
                        }
                    }
                }
        }
        .padding(6)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Native Menu

    var iOSNativeMenu: some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                Label(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

            Divider()

            if selectedTab == 1 {
                Toggle(isOn: Binding(
                    get: { showLegend },
                    set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
                )) {
                    Label(localizedString("Legend", locale: locale), systemImage: "eye")
                }
            }

            Button {
                Task { await weatherService.refreshWeather() }
            } label: {
                Label(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"), systemImage: "arrow.clockwise")
            }
            .disabled(weatherService.isLoading)

            if selectedTab == 1 {
                Toggle(isOn: Binding(
                    get: { isPlaying },
                    set: { newValue in
                        if newValue { iOSStartPlayback() } else { iOSStopPlayback() }
                    }
                )) {
                    Label(localizedString("Playback", locale: locale), systemImage: "play.fill")
                }
            }

            Toggle(isOn: Binding(
                get: { filterSunny },
                set: { newValue in withAnimation { filterSunny = newValue } }
            )) {
                Label(localizedString("Filter Sunny", locale: locale), systemImage: "sun.max")
            }

            Divider()

            if selectedTab == 0 {
                Toggle(isOn: Binding(
                    get: { isGridView },
                    set: { newValue in
                        withAnimation(.easeOut(duration: 0.15)) {
                            listContentOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isGridView = newValue
                            withAnimation(.easeIn(duration: 0.2)) {
                                listContentOpacity = 1
                            }
                        }
                    }
                )) {
                    Label(localizedString("Grid View", locale: locale), systemImage: "square.grid.2x2")
                }

                Toggle(isOn: Binding(
                    get: { isEditMode },
                    set: { newValue in withAnimation { isEditMode = newValue } }
                )) {
                    Label(localizedString("Edit Mode", locale: locale), systemImage: "pencil")
                }
            }

            if !isEditingListName {
                if let city = selectedTab == 1 ? (showingMapExpandedCard ? tappedCity : nil) : selectedCity,
                   cityIsInSidebar(city) {
                    Button(role: .destructive) {
                        weatherService.removeCity(city)
                        if selectedTab == 1 {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                showingMapExpandedCard = false
                                tappedCity = nil
                                recenterOnAllCities = true
                            }
                        } else if selectedCity?.id == city.id {
                            selectedCity = nil
                        }
                    } label: {
                        Label(localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"", systemImage: "trash")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuOrder(.fixed)
    }
}
