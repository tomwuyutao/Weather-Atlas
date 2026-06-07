//
//  IOSToolbar.swift
//  Weather
//
//  Shared toolbar helpers.
//

import SwiftUI

extension View {
    @ViewBuilder
    func iPhoneNativeBottomToolbarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.visible, for: .bottomBar)
        } else {
            self
        }
    }

    func iPhoneFloatingToolbarCapsule() -> some View {
        self
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(AppTheme.shared.colors.glassFill, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }

    func iPhoneFloatingToolbarCircle() -> some View {
        self
            .fixedSize()
            .frame(width: 52, height: 52)
            .background(AppTheme.shared.colors.glassFill, in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.6))
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
    }
}

extension ContentView {

    /// Whether the map is in a special full-screen mode.
    var isMapSpecialMode: Bool {
        false
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
                        PlatformFeedback.lightImpact()
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
                        PlatformFeedback.lightImpact()
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

    @ViewBuilder
    private var nativeMenuItems: some View {
        Button {
            #if os(macOS)
            openSettings()
            #else
            showingSettings = true
            #endif
        } label: {
            Label {
                Text(localizedString("Settings", locale: locale))
            } icon: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.primary)
            }
        }

        Divider()

        if selectedTab == 1 {
            Toggle(isOn: Binding(
                get: { showLegend },
                set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
            )) {
                Label {
                    Text(localizedString("Legend", locale: locale))
                } icon: {
                    Image(systemName: "eye")
                        .foregroundStyle(.primary)
                }
            }
        }

        Button {
            Task { await weatherService.refreshWeather() }
        } label: {
            Label {
                Text(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"))
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.primary)
            }
        }
        .disabled(weatherService.isLoading)

        Toggle(isOn: Binding(
            get: { filterSunny },
            set: { newValue in withAnimation { filterSunny = newValue } }
        )) {
            Label {
                Text(localizedString("Filter Sunny", locale: locale))
            } icon: {
                Image(systemName: "sun.max")
                    .foregroundStyle(.primary)
            }
        }

        Divider()

        if !isEditingListName,
           selectedTab == 1,
           showingMapExpandedCard,
           let city = tappedCity,
           cityIsInSidebar(city) {
            Button(
                localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"",
                systemImage: "trash",
                role: .destructive
            ) {
                weatherService.removeCity(city)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    tappedCity = nil
                    recenterOnAllCities = true
                }
            }
            .tint(theme.colors.destructive)
        }
    }

    var iOSNativeMenu: some View {
        Menu {
            nativeMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
                #if os(iOS)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                #endif
        }
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .menuOrder(.fixed)
    }

    #if os(iOS)
    private var shouldShowIPhonePreviewAddButton: Bool {
        guard selectedTab == 1,
              showingMapExpandedCard,
              let previewCity,
              !cityIsInSidebar(previewCity) else {
            return false
        }
        return true
    }

    private func addPreviewCityToList(_ listID: CityListID) {
        guard let city = previewCity else { return }
        Task {
            if listID == weatherService.activeListID {
                await addCityToSidebar(city)
            } else {
                await weatherService.addCityToList(city.city, listID: listID)
                PlatformFeedback.lightImpact()
                if let addedCity = weatherService.weatherData(for: listID).first(where: {
                    $0.city.name == city.city.name && $0.city.country == city.city.country
                }) {
                    tappedCity = addedCity
                }
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                previewCity = nil
                showingMapExpandedCard = false
            }
        }
    }

    @ViewBuilder
    private func iPhoneSearchOrAddButton(iconSize: CGFloat, frameSize: CGFloat) -> some View {
        if shouldShowIPhonePreviewAddButton {
            let lists = sidebarLists
            if lists.count > 1 {
                Menu {
                    ForEach(lists) { listID in
                        Button(listID.localizedDisplayName(locale: locale)) {
                            addPreviewCityToList(listID)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: frameSize, height: frameSize)
                }
                .buttonBorderShape(.circle)
                .fixedSize()
                .menuOrder(.fixed)
            } else {
                Button {
                    if let listID = lists.first {
                        addPreviewCityToList(listID)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: frameSize, height: frameSize)
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .fixedSize()
                .tint(.primary)
            }
        } else {
            Button {
                activateInlineSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: frameSize, height: frameSize)
            }
            .buttonStyle(.plain)
            .tint(.primary)
        }
    }

    @ViewBuilder
    var iPhoneFloatingBottomToolbarFallback: some View {
        if #available(iOS 26.0, *) {
            EmptyView()
        } else {
            HStack(spacing: 0) {
                Button {
                    dismissIPhoneRoute(.map)
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .iPhoneFloatingToolbarCapsule()

                Spacer(minLength: 12)

                HStack(spacing: 0) {
                    Button {
                        recenterOnAllCities = false
                        DispatchQueue.main.async {
                            recenterOnAllCities = true
                        }
                    } label: {
                        Image(systemName: "dot.squareshape.split.2x2")
                            .font(.system(size: 21, weight: .regular))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)

                    mapOverlayMenu
                        .font(.system(size: 21, weight: .regular))
                        .frame(width: 46, height: 46)

                    iOSNativeMenu
                        .font(.system(size: 21, weight: .regular))
                        .frame(width: 46, height: 46)
                }
                .iPhoneFloatingToolbarCapsule()

                Spacer(minLength: 12)

                iPhoneSearchOrAddButton(iconSize: 25, frameSize: 46)
                    .if(shouldShowIPhonePreviewAddButton) { view in
                        view.iPhoneFloatingToolbarCircle()
                    }
                    .if(!shouldShowIPhonePreviewAddButton) { view in
                        view.iPhoneFloatingToolbarCapsule()
                    }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ToolbarContentBuilder
    var iPhoneNativeBottomToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button {
                dismissIPhoneRoute(.map)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(.primary)
                    .foregroundColor(.primary)
            }
            .tint(.primary)

            Spacer()

            HStack(spacing: 0) {
                Button {
                    recenterOnAllCities = false
                    DispatchQueue.main.async {
                        recenterOnAllCities = true
                    }
                } label: {
                    Image(systemName: "dot.squareshape.split.2x2")
                        .foregroundStyle(.primary)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                .tint(.primary)

                mapOverlayMenu
                    .frame(width: 44, height: 44)

                iOSNativeMenu
                    .frame(width: 44, height: 44)
            }

            Spacer()

            iPhoneSearchOrAddButton(iconSize: 22, frameSize: 44)
        }
    }
    #endif
}
