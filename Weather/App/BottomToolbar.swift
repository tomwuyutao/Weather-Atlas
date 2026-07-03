//
//  BottomToolbar.swift
//  Weather
//
//  Purpose: Defines app navigation routes and the floating bottom toolbar
//  used by Home, List, Detail, and Map.
//

import SwiftUI

// MARK: - Navigation Routes

enum AppNavigationRoute: Hashable {
    case map
    case list
    case cityDetail(UUID)
    case addCityDetail
    case listManager
}

// MARK: - Current Route Helpers

extension ContentView {
    var currentRoute: AppNavigationRoute? {
        navigationPath.last
    }

    var isMapRoute: Bool {
        currentRoute == .map
    }

    var isListRoute: Bool {
        currentRoute == .list
    }

    var isDetailRoute: Bool {
        if case .cityDetail = currentRoute {
            return true
        }
        return currentRoute == .addCityDetail
    }
}

// MARK: - Toolbar Compatibility

extension View {
    @ViewBuilder
    func nativeBottomToolbarBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.visible, for: .bottomBar)
        } else {
            self
        }
    }
}

// MARK: - Floating Bottom Toolbar

extension ContentView {
    var dateSwitcherCapsule: some View {
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

            Text(dateSwitcherText)
                .font(.avenir(.caption, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 80)
                .id("date-\(selectedDayOffset)")
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
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    var floatingBottomToolbar: some View {
        HStack(alignment: .center) {
            if currentRoute == .addCityDetail {
                bottomAddSearchedCityButton
            } else if let route = currentRoute {
                bottomBackButton(route)
            } else {
                bottomMoreButton
            }

            Spacer(minLength: 12)

            dateSwitcherCapsule
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)

            Spacer(minLength: 12)

            bottomSearchButton
        }
    }

    var homeBottomToolbar: some View {
        floatingBottomToolbar
    }

    func backDateBottomToolbar(_ route: AppNavigationRoute) -> some View {
        floatingBottomToolbar
    }

    var mapBottomToolbar: some View {
        floatingBottomToolbar
    }

    var bottomSearchButton: some View {
        Button {
            activateInlineSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Search", locale: locale))
    }

    var bottomSettingsButton: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Settings", locale: locale))
    }

    var bottomMoreButton: some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                primaryMenuLabel(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

            Button {
                refreshActiveWeather()
            } label: {
                primaryMenuLabel(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"), systemImage: "arrow.clockwise")
            }
            .disabled(weatherService.isLoading)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .tint(.primary)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Menu", locale: locale))
    }

    func primaryMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.primary)
        }
    }

    func bottomBackButton(_ route: AppNavigationRoute) -> some View {
        Button {
            dismissRoute(route)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Back", locale: locale))
    }

    var bottomAddSearchedCityButton: some View {
        Button {
            addSearchedDetailCityToActiveList()
        } label: {
            Label(localizedString("Add", locale: locale), systemImage: "plus")
                .font(.system(size: 17, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .frame(height: 46)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(theme.colors.accent)
        .disabled(addCityDetailCity == nil)
        .accessibilityLabel(localizedString("Add", locale: locale))
    }
}

// MARK: - Map and Menu Controls

extension ContentView {
    @ViewBuilder
    private var nativeMenuItems: some View {
        Button {
            showingSettings = true
        } label: {
            Label {
                Text(localizedString("Settings", locale: locale))
            } icon: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.primary)
            }
        }

        if isMapRoute {
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
            refreshActiveWeather()
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

        if isMapRoute,
           showingMapExpandedCard,
           let city = tappedCity,
           cityIsInActiveList(city) {
            Button(
                localizedString("Delete", locale: locale) + " \"" + city.city.localizedName(locale: locale) + "\"",
                systemImage: "trash",
                role: .destructive
            ) {
                weatherService.removeCity(city)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    tappedCity = nil
                    mapRecenterRequest = .listCoordinates
                }
            }
            .tint(theme.colors.destructive)
        }
    }

    var nativeMenu: some View {
        Menu {
            nativeMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.primary)
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
    }

    private var shouldShowPreviewAddButton: Bool {
        guard isMapRoute,
              showingMapExpandedCard,
              let previewCity,
              !cityIsInActiveList(previewCity) else {
            return false
        }
        return true
    }

    private func addPreviewCityToList(_ listID: CityListID) {
        guard let city = previewCity else { return }
        Task {
            if listID == weatherService.activeListID {
                await addCityToActiveList(city)
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
    func searchOrAddButton(iconSize: CGFloat, frameSize: CGFloat) -> some View {
        if shouldShowPreviewAddButton {
            let lists = managedLists
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
                .frame(width: frameSize, height: frameSize)
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
                .frame(width: frameSize, height: frameSize)
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

    var mapControlCluster: some View {
        HStack(spacing: 8) {
            Button {
                mapRecenterRequest = nil
                DispatchQueue.main.async {
                    mapRecenterRequest = .listCoordinates
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
                .buttonStyle(.plain)

            nativeMenu
                .font(.system(size: 21, weight: .regular))
                .frame(width: 46, height: 46)
                .buttonStyle(.plain)
        }
        .controlSize(.regular)
    }
}

// MARK: - Navigation Helpers

extension ContentView {
    func pushRoute(_ route: AppNavigationRoute, showsBackButton: Bool = false) {
        if route == .map {
            showingListManager = false
        } else if route == .list {
            showingListManager = false
            showingMapExpandedCard = false
        }
        if case .cityDetail = route {
            navigationPath.append(route)
            return
        }
        if route == .map || route == .list {
            routeShowsBackButton = showsBackButton
        }
        guard !navigationPath.contains(route) else { return }
        navigationPath.append(route)
    }

    func presentDetail(for city: CityWeather) {
        tappedCity = city
        showingMapExpandedCard = false
        pushRoute(.cityDetail(city.id))
    }

    func addSearchedDetailCityToActiveList() {
        guard let city = addCityDetailCity else { return }

        Task {
            await addCityToActiveList(city)
            await MainActor.run {
                let savedCity = weatherService.cityWeatherData.first {
                    $0.city.name == city.city.name && $0.city.country == city.city.country
                } ?? city

                addCityDetailCity = nil
                tappedCity = savedCity
                previewCity = nil
                navigationPath.removeAll { $0 == .addCityDetail }
                pushRoute(.cityDetail(savedCity.id))
            }
        }
    }

    func dismissRoute(_ route: AppNavigationRoute) {
        switch route {
        case .map:
            navigationPath.removeAll { $0 == route }
            routeShowsBackButton = false
            showingMapExpandedCard = false
            tappedCity = nil
        case .list:
            navigationPath.removeAll { $0 == route }
            routeShowsBackButton = false
            listEditMode = false
        case .cityDetail:
            navigationPath.removeAll { $0 == route }
            selectedDayOffset = 0
        case .addCityDetail:
            navigationPath.removeAll { $0 == route }
            addCityDetailCity = nil
        case .listManager:
            navigationPath.removeAll { $0 == route }
            showingListManager = false
        }
    }
}
