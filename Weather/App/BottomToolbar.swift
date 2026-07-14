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
    case cityDetail(CityWeather)
    case addCityDetail(CityWeather)
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

    var addCityDetailCity: CityWeather? {
        guard case .addCityDetail(let city) = currentRoute else { return nil }
        return city
    }

    var isAddCityDetailRoute: Bool {
        addCityDetailCity != nil
    }
}

// MARK: - Floating Bottom Toolbar

extension ContentView {
    var bottomToolbarIconSize: CGFloat { 21 }
    var bottomCenterToolbarWidth: CGFloat { 165 }

    @ToolbarContentBuilder
    var nativeBottomToolbarItems: some ToolbarContent {
        if !citySearchState.isPresented {
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
        } else if currentRoute != nil {
            bottomBackButton
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
        } else if isAddCityDetailRoute || citySearchState.temporaryMapCity != nil {
            bottomAddSearchedCityButton
        } else {
            bottomSearchButton
        }
    }

    var dateSwitcherControl: some View {
        HStack(spacing: 6) {
            dateStepperButton(
                systemImage: "chevron.left",
                isEnabled: selectedDayOffset > 0,
                accessibilityLabel: localizedString("Previous Day", locale: locale)
            ) {
                guard selectedDayOffset > 0 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = false
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset -= 1
                }
            } longPressAction: {
                guard selectedDayOffset > 0 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = false
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = 0
                }
            }

            Button {
                Haptics.lightImpact()
                showingDatePopover = true
            } label: {
                ZStack {
                    ForEach(0...9, id: \.self) { dayOffset in
                        Text(dateSwitcherText(for: dayOffset))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .hidden()
                    }

                    Text(dateSwitcherText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .id("date-\(selectedDayOffset)")
                        .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
                        .clipped()
                }
                .frame(minWidth: 72, minHeight: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // Accessibility: Name the date control by its current selection.
            .accessibilityLabel(dateSwitcherText)
            // Accessibility: Let Voice Control target the same date text that is
            // visible in the toolbar, while retaining the native Button action.
            .accessibilityInputLabels([Text(dateSwitcherText)])
            .popover(isPresented: $showingDatePopover) {
                datePickerPopoverContent
            }

            dateStepperButton(
                systemImage: "chevron.right",
                isEnabled: selectedDayOffset < 9,
                accessibilityLabel: localizedString("Next Day", locale: locale)
            ) {
                guard selectedDayOffset < 9 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = true
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset += 1
                }
            } longPressAction: {
                guard selectedDayOffset < 9 else { return }
                Haptics.lightImpact()
                dateSwitcherForward = true
                withAnimation(.smooth(duration: 0.2)) {
                    selectedDayOffset = 9
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(width: bottomCenterToolbarWidth)
    }

    func dateStepperButton(
        systemImage: String,
        isEnabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        longPressAction: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
            .frame(minWidth: 30, minHeight: 32)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.45, perform: longPressAction)
            .disabled(!isEnabled)
            // Accessibility: Mirror the custom tap and long-press gestures as standard actions.
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(dateSwitcherText)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                action()
            }
            .accessibilityAction(named: Text(
                systemImage == "chevron.left"
                    ? localizedString("Today", locale: locale)
                    : dateSwitcherText(for: 9)
            )) {
                longPressAction()
            }
    }

    func dateSwitcherText(for dayOffset: Int) -> String {
        if dayOffset == 0 { return localizedString("Today", locale: locale) }
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return date.formatted(
            Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    var datePickerPopoverContent: some View {
        DatePicker(
            dateSwitcherText,
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
        Button(localizedString("Search", locale: locale), systemImage: "magnifyingglass") {
            activateSearch()
        }
    }

    var bottomMoreButton: some View {
        Menu(localizedString("Menu", locale: locale), systemImage: "ellipsis") {
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
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
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
                // Accessibility: The adjacent text already names the menu action.
                .accessibilityHidden(true)
        }
        .tint(theme.colors.accent)
    }

    var bottomBackButton: some View {
        Button(localizedString("Back", locale: locale), systemImage: "chevron.left") {
            popCurrentRoute()
        }
    }

    var bottomCancelListPreviewButton: some View {
        Button(localizedString("Cancel", locale: locale), systemImage: "chevron.left") {
            cancelGeneratedListPreview()
        }
    }

    var bottomConfirmListPreviewButton: some View {
        Button(localizedString("Add", locale: locale), systemImage: "plus") {
            confirmGeneratedListPreview()
        }
        .disabled(listPreviewCities.isEmpty)
    }

    var listPreviewCountPickerControl: some View {
        HStack(spacing: 6) {
            Button {
                changeListPreviewCityCount(by: -1)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(listPreviewState.cityCount > 1 ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(minWidth: 30, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .disabled(listPreviewState.cityCount <= 1)

            Text(cityCountText(listPreviewState.cityCount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                changeListPreviewCityCount(by: 1)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(listPreviewState.cityCount < listPreviewMaximumCount ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
                    .frame(minWidth: 30, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .disabled(listPreviewState.cityCount >= listPreviewMaximumCount)
        }
        .padding(.horizontal, 3)
        .frame(width: bottomCenterToolbarWidth)
        // Accessibility: Present the visual minus/count/plus cluster as one adjustable control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localizedString("Cities", locale: locale))
        .accessibilityValue(cityCountText(listPreviewState.cityCount))
        // Accessibility: Voice Control can target the adjustable element by either
        // its visible count or its concise control name.
        .accessibilityInputLabels([
            Text(cityCountText(listPreviewState.cityCount)),
            Text(localizedString("Cities", locale: locale))
        ])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                changeListPreviewCityCount(by: 1)
            case .decrement:
                changeListPreviewCityCount(by: -1)
            @unknown default:
                break
            }
        }
    }

    private func changeListPreviewCityCount(by delta: Int) {
        let updatedCount = min(max(listPreviewState.cityCount + delta, 1), listPreviewMaximumCount)
        guard updatedCount != listPreviewState.cityCount else { return }
        Haptics.lightImpact()
        withAnimation(.smooth(duration: 0.18)) {
            listPreviewState.cityCount = updatedCount
        }
    }

    var bottomAddSearchedCityButton: some View {
        let lists = managedLists
        return Button(localizedString("Add City", locale: locale), systemImage: "plus") {
            if lists.count > 1 {
                citySearchState.showsListPicker = true
            } else {
                if let listID = lists.first {
                    addCity(to: listID)
                }
            }
        }
        .disabled(addCityDetailCity == nil || lists.isEmpty)
        .confirmationDialog(
            localizedString("Add to List", locale: locale),
            isPresented: $citySearchState.showsListPicker,
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

    func navigateToMap() {
        guard let mapIndex = navigationPath.lastIndex(of: .map) else {
            pushRoute(.map)
            return
        }

        let routesAboveMap = navigationPath.count - mapIndex - 1
        if routesAboveMap > 0 {
            navigationPath.removeLast(routesAboveMap)
        }
    }

    func presentDetail(for city: CityWeather) {
        showingMapExpandedCard = false
        pushRoute(.cityDetail(city))
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

                selectedMapCity = savedCity
                citySearchState.temporaryMapCity = nil
                if case .addCityDetail = navigationPath.last {
                    navigationPath.removeLast()
                }
                pushRoute(.cityDetail(savedCity))
                showCityAddedConfirmation("\(localizedCityName(for: savedCity.city)) was added to \(listID.localizedDisplayName(locale: locale)).")
            }
        }
    }

    func popRoute(_ route: AppNavigationRoute) {
        guard navigationPath.contains(route) else { return }
        if navigationPath.last == route {
            navigationPath.removeLast()
        } else {
            navigationPath.removeAll { $0 == route }
        }
        cleanupAfterLeavingRoute(route)
    }

    func popCurrentRoute() {
        guard let route = navigationPath.popLast() else { return }
        cleanupAfterLeavingRoute(route)
    }

    private func cleanupAfterLeavingRoute(_ route: AppNavigationRoute) {
        switch route {
        case .map:
            showingMapExpandedCard = false
            selectedMapCity = nil
        case .list:
            listEditMode = false
        case .cityDetail:
            selectedDayOffset = 0
        case .addCityDetail:
            break
        case .listPreview:
            clearGeneratedListPreview()
        }
    }
}
