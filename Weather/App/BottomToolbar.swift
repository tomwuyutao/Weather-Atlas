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
                .foregroundStyle(selectedDayOffset > -1 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > -1 {
                        Haptics.lightImpact()
                        dateSwitcherForward = false
                        withAnimation(.smooth(duration: 0.2)) {
                            selectedDayOffset -= 1
                        }
                    }
                }

            Button {
                showingDatePopover = true
            } label: {
                Text(dateSwitcherText)
                    .font(.avenir(.caption, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 80, minHeight: 36)
                    .id("date-\(selectedDayOffset)")
                    .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                .foregroundStyle(selectedDayOffset < 9 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset < 9 {
                        Haptics.lightImpact()
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
            if let route = currentRoute {
                bottomBackButton(route)
            } else {
                bottomMoreButton
            }

            Spacer(minLength: 12)

            dateSwitcherCapsule
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)

            Spacer(minLength: 12)

            if currentRoute == .addCityDetail || temporaryMapSearchCity != nil {
                bottomAddSearchedCityButton
            } else {
                bottomSearchButton
            }
        }
    }

    var homeBottomToolbar: some View {
        floatingBottomToolbar
    }

    func backDateBottomToolbar(_ route: AppNavigationRoute) -> some View {
        floatingBottomToolbar
    }

    var mapBottomToolbar: some View {
        HStack(alignment: .center) {
            if let route = currentRoute {
                bottomBackButton(route)
            } else {
                bottomMoreButton
            }

            Spacer(minLength: 12)

            mapControls
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .themedGlass(in: .capsule)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)

            Spacer(minLength: 12)

            if temporaryMapSearchCity != nil {
                bottomAddSearchedCityButton
            } else {
                bottomSearchButton
            }
        }
    }

    var bottomSearchButton: some View {
        Button {
            activateSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Search", locale: locale))
    }

    var bottomMoreButton: some View {
        Menu {
            Button {
                showingSettings = true
            } label: {
                primaryMenuLabel(localizedString("Settings", locale: locale), systemImage: "gearshape")
            }

            Button {
                refreshWeather()
            } label: {
                primaryMenuLabel(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"), systemImage: "arrow.clockwise")
            }
            .disabled(weatherService.isLoading)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuOrder(.fixed)
        .tint(theme.colors.primaryText)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Menu", locale: locale))
    }

    func primaryMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(theme.colors.primaryText)
        }
    }

    func bottomBackButton(_ route: AppNavigationRoute) -> some View {
        Button {
            dismissRoute(route)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .accessibilityLabel(localizedString("Back", locale: locale))
    }

    var bottomAddSearchedCityButton: some View {
        let lists = managedLists
        return Button {
            if lists.count > 1 {
                showingAddSearchedCityListDialog = true
            } else {
                if let listID = lists.first {
                    addCity(to: listID)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 46, height: 46)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .themedGlass(in: Circle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)
        .disabled(addCityDetailCity == nil || lists.isEmpty)
        .accessibilityLabel(localizedString("Add", locale: locale))
        .confirmationDialog(
            localizedString("Add to List", locale: locale),
            isPresented: $showingAddSearchedCityListDialog,
            titleVisibility: .visible
        ) {
            ForEach(lists) { listID in
                Button(listID.localizedDisplayName(locale: locale)) {
                    addCity(to: listID)
                }
            }
            Button(localizedString("Cancel", locale: locale), role: .cancel) {}
        }
    }
}

// MARK: - Map and Menu Controls

extension ContentView {
    @ViewBuilder
    private var mapMoreMenuItems: some View {
        Button {
            showingSettings = true
        } label: {
            Label {
                Text(localizedString("Settings", locale: locale))
                    .foregroundStyle(theme.colors.primaryText)
            } icon: {
                Image(systemName: "gearshape")
                    .foregroundStyle(theme.colors.primaryText)
            }
        }

        Toggle(isOn: Binding(
            get: { showLegend },
            set: { newValue in withAnimation(.smooth(duration: 0.3)) { showLegend = newValue } }
        )) {
            Label {
                Text(localizedString("Legend", locale: locale))
                    .foregroundStyle(theme.colors.primaryText)
            } icon: {
                Image(systemName: "eye")
                    .foregroundStyle(theme.colors.primaryText)
            }
        }

        Button {
            refreshWeather()
        } label: {
            Label {
                Text(localizedString("Refresh", locale: locale) + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"))
                    .foregroundStyle(theme.colors.primaryText)
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
        .disabled(weatherService.isLoading)

        Toggle(isOn: Binding(
            get: { filterSunny },
            set: { newValue in withAnimation { filterSunny = newValue } }
        )) {
            Label {
                Text(localizedString("Filter Sunny", locale: locale))
                    .foregroundStyle(theme.colors.primaryText)
            } icon: {
                Image(systemName: "sun.max")
                    .foregroundStyle(theme.colors.primaryText)
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

    var mapMoreMenu: some View {
        Menu {
            mapMoreMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 46, height: 36)
                .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .tint(theme.colors.primaryText)
    }

    var mapControls: some View {
        HStack(spacing: 8) {
            Button {
                mapRecenterRequest = nil
                DispatchQueue.main.async {
                    mapRecenterRequest = .listCoordinates
                }
            } label: {
                Image(systemName: "dot.squareshape.split.2x2")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(theme.colors.primaryText)
                    .frame(width: 46, height: 36)
            }
            .buttonStyle(.plain)
            .tint(theme.colors.primaryText)

            mapOverlayMenu
                .font(.system(size: 21, weight: .regular))
                .frame(width: 46, height: 36)
                .buttonStyle(.plain)

            mapMoreMenu
                .font(.system(size: 21, weight: .regular))
                .frame(width: 46, height: 36)
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

    func addCity(to listID: CityListID) {
        guard let city = addCityDetailCity else { return }

        Task {
            if listID == weatherService.activeListID {
                await addCityToActiveList(city)
            } else {
                await weatherService.addCityToList(city.city, listID: listID)
                Haptics.lightImpact()
                await switchToList(listID)
            }

            await MainActor.run {
                guard let savedCity = weatherService.cityWeatherData.first(where: {
                    $0.city.name == city.city.name && $0.city.country == city.city.country
                }) else {
                    weatherService.reportDeveloperWarning(
                        title: "Added City Missing",
                        message: "After adding \(city.city.localizedName()) to \(listID.rawValue), the saved city could not be found in fetched weather data."
                    )
                    return
                }

                addCityDetailCity = nil
                tappedCity = savedCity
                temporaryMapSearchCity = nil
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
