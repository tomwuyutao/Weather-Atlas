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
    case listPreview
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

// MARK: - Floating Bottom Toolbar

extension ContentView {
    var dateSwitcherCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selectedDayOffset > 0 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .onTapGesture {
                    if selectedDayOffset > 0 {
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
                            Calendar.current.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
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
            if isListPreviewActive {
                bottomCancelListPreviewButton
            } else if let route = currentRoute {
                bottomBackButton(route)
            } else {
                bottomMoreButton
            }

            Spacer(minLength: 12)

            Group {
                if isListPreviewActive {
                    listPreviewCountPickerCapsule
                } else {
                    dateSwitcherCapsule
                }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 18, y: 8)

            Spacer(minLength: 12)

            if isListPreviewActive {
                bottomConfirmListPreviewButton
            } else if currentRoute == .addCityDetail || temporaryMapSearchCity != nil {
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

    var bottomCancelListPreviewButton: some View {
        Button {
            cancelGeneratedListPreview()
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
        .accessibilityLabel(localizedString("Cancel", locale: locale))
    }

    var bottomConfirmListPreviewButton: some View {
        Button {
            confirmGeneratedListPreview()
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
        .disabled(listPreviewCities.isEmpty)
        .accessibilityLabel(localizedString("Add", locale: locale))
    }

    var listPreviewCountPickerCapsule: some View {
        HStack(spacing: 8) {
            Button {
                guard listPreviewCityCount > 1 else { return }
                Haptics.lightImpact()
                withAnimation(.smooth(duration: 0.18)) {
                    listPreviewCityCount -= 1
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(listPreviewCityCount > 1 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(listPreviewCityCount <= 1)

            Text(cityCountText(listPreviewCityCount))
                .font(.avenir(.caption, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 92, minHeight: 36)

            Button {
                guard listPreviewCityCount < listPreviewMaximumCount else { return }
                Haptics.lightImpact()
                withAnimation(.smooth(duration: 0.18)) {
                    listPreviewCityCount += 1
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(listPreviewCityCount < listPreviewMaximumCount ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(listPreviewCityCount >= listPreviewMaximumCount)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .themedGlass(in: .capsule)
        .transition(.scale.combined(with: .opacity))
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
    func pushRoute(_ route: AppNavigationRoute) {
        if route == .list {
            showingMapExpandedCard = false
        } else if route == .listPreview {
            showingMapExpandedCard = false
        }
        if case .cityDetail = route {
            navigationPath.append(route)
            return
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
            showingMapExpandedCard = false
            tappedCity = nil
        case .list:
            navigationPath.removeAll { $0 == route }
            listEditMode = false
        case .cityDetail:
            navigationPath.removeAll { $0 == route }
            selectedDayOffset = 0
        case .addCityDetail:
            navigationPath.removeAll { $0 == route }
            addCityDetailCity = nil
        case .listPreview:
            navigationPath.removeAll { $0 == route }
            clearGeneratedListPreview()
        }
    }
}
