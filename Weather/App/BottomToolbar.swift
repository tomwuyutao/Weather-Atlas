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
    var bottomToolbarIconSize: CGFloat { 21 }
    var bottomCenterToolbarWidth: CGFloat { 165 }

    @ToolbarContentBuilder
    var nativeBottomToolbarItems: some ToolbarContent {
        if !showingSearchSheet {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .bottomBar) {
                    bottomLeadingToolbarControl
                }

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    bottomCenterToolbarControl
                }

                ToolbarSpacer(.flexible, placement: .bottomBar)

                ToolbarItem(placement: .bottomBar) {
                    bottomTrailingToolbarControl
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    HStack(spacing: 12) {
                        bottomLeadingToolbarControl

                        Spacer(minLength: 12)

                        bottomCenterToolbarControl

                        Spacer(minLength: 12)

                        bottomTrailingToolbarControl
                    }
                }
            }
        }
    }

    @ViewBuilder
    var bottomLeadingToolbarControl: some View {
        if isListPreviewActive {
            bottomCancelListPreviewButton
        } else if let route = currentRoute {
            bottomBackButton(route)
        } else {
            bottomMoreButton
        }
    }

    @ViewBuilder
    var bottomCenterToolbarControl: some View {
        if isListPreviewActive {
            listPreviewCountPickerControl
        } else {
            dateSwitcherControl
        }
    }

    @ViewBuilder
    var bottomTrailingToolbarControl: some View {
        if isListPreviewActive {
            bottomConfirmListPreviewButton
        } else if currentRoute == .addCityDetail || temporaryMapSearchCity != nil {
            bottomAddSearchedCityButton
        } else {
            bottomSearchButton
        }
    }

    var dateSwitcherControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selectedDayOffset > 0 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                .frame(minWidth: 30, minHeight: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard selectedDayOffset > 0 else { return }
                    Haptics.lightImpact()
                    dateSwitcherForward = false
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedDayOffset -= 1
                    }
                }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard selectedDayOffset > 0 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = false
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = 0
                }
            }
            .accessibilityLabel(localizedString("Previous Day", locale: locale))
            .accessibilityAddTraits(.isButton)

            Button {
                Haptics.lightImpact()
                showingDatePopover = true
            } label: {
                ZStack {
                    ForEach(0...9, id: \.self) { dayOffset in
                        Text(dateSwitcherText(for: dayOffset))
                            .font(.avenir(.subheadline, weight: .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .hidden()
                    }

                    Text(dateSwitcherText)
                        .font(.avenir(.subheadline, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .id("date-\(selectedDayOffset)")
                        .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
                        .clipped()
                }
            }
            .popover(isPresented: $showingDatePopover) {
                datePickerPopoverContent
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selectedDayOffset < 9 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                .frame(minWidth: 30, minHeight: 32)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard selectedDayOffset < 9 else { return }
                    Haptics.lightImpact()
                    dateSwitcherForward = true
                    withAnimation(.smooth(duration: 0.2)) {
                        selectedDayOffset += 1
                    }
                }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard selectedDayOffset < 9 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = true
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = 9
                }
            }
            .accessibilityLabel(localizedString("Next Day", locale: locale))
            .accessibilityAddTraits(.isButton)
        }
        .padding(.horizontal, 3)
        .frame(width: bottomCenterToolbarWidth)
    }

    func dateSwitcherText(for dayOffset: Int) -> String {
        if dayOffset == 0 { return localizedString("Today", locale: locale) }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMdEEE", options: 0, locale: locale)
        formatter.locale = locale
        return formatter.string(from: Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date())
    }

    var datePickerPopoverContent: some View {
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

    var bottomSearchButton: some View {
        Button {
            activateSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
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
                .font(.system(size: bottomToolbarIconSize, weight: .regular))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
        .accessibilityLabel(localizedString("Menu", locale: locale))
    }

    func primaryMenuLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(theme.colors.primaryText)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(theme.colors.accent)
                .tint(theme.colors.accent)
        }
        .tint(theme.colors.accent)
    }

    func bottomBackButton(_ route: AppNavigationRoute) -> some View {
        Button {
            popRoute(route)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: bottomToolbarIconSize, weight: .semibold))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
        .accessibilityLabel(localizedString("Back", locale: locale))
    }

    var bottomCancelListPreviewButton: some View {
        Button {
            cancelGeneratedListPreview()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: bottomToolbarIconSize, weight: .semibold))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
        .accessibilityLabel(localizedString("Cancel", locale: locale))
    }

    var bottomConfirmListPreviewButton: some View {
        Button {
            confirmGeneratedListPreview()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: bottomToolbarIconSize, weight: .semibold))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
        .disabled(listPreviewCities.isEmpty)
        .accessibilityLabel(localizedString("Add", locale: locale))
    }

    var listPreviewCountPickerControl: some View {
        HStack(spacing: 6) {
            Button {
                guard listPreviewCityCount > 1 else { return }
                Haptics.lightImpact()
                withAnimation(.smooth(duration: 0.18)) {
                    listPreviewCityCount -= 1
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(listPreviewCityCount > 1 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(minWidth: 30, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .disabled(listPreviewCityCount <= 1)

            Text(cityCountText(listPreviewCityCount))
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                guard listPreviewCityCount < listPreviewMaximumCount else { return }
                Haptics.lightImpact()
                withAnimation(.smooth(duration: 0.18)) {
                    listPreviewCityCount += 1
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(listPreviewCityCount < listPreviewMaximumCount ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(minWidth: 30, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .disabled(listPreviewCityCount >= listPreviewMaximumCount)
        }
        .padding(.horizontal, 3)
        .frame(width: bottomCenterToolbarWidth)
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
                .font(.system(size: bottomToolbarIconSize, weight: .semibold))
                .imageScale(.medium)
                .foregroundStyle(theme.colors.primaryText)
        }
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
                removeRoute(.addCityDetail)
                pushRoute(.cityDetail(savedCity.id))
            }
        }
    }

    func popRoute(_ route: AppNavigationRoute) {
        if navigationPath.last == route {
            navigationPath.removeLast()
            cleanupAfterLeavingRoute(route)
        } else {
            removeRoute(route)
        }
    }

    func removeRoute(_ route: AppNavigationRoute) {
        navigationPath.removeAll { $0 == route }
        cleanupAfterLeavingRoute(route)
    }

    func dismissRoute(_ route: AppNavigationRoute) {
        removeRoute(route)
    }

    private func cleanupAfterLeavingRoute(_ route: AppNavigationRoute) {
        switch route {
        case .map:
            showingMapExpandedCard = false
            tappedCity = nil
        case .list:
            listEditMode = false
        case .cityDetail:
            selectedDayOffset = 0
        case .addCityDetail:
            addCityDetailCity = nil
        case .listPreview:
            clearGeneratedListPreview()
        }
    }
}
