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

    /// Detail routes use the displayed city's own forecast range in the shared
    /// date switcher. Other routes continue to use the active list's date union.
    var detailDateSwitcherCity: CityWeather? {
        switch currentRoute {
        case .cityDetail(let city), .addCityDetail(let city):
            return city
        default:
            return nil
        }
    }

    var addCityDetailCity: CityWeather? {
        guard case .addCityDetail(let city) = currentRoute else { return nil }
        return city
    }

    var isAddCityDetailRoute: Bool {
        addCityDetailCity != nil
    }

    /// The searched city currently eligible to be added, whether it is shown in
    /// the dedicated add-detail route or as a temporary card on the full map.
    var cityPendingAddition: CityWeather? {
        addCityDetailCity ?? citySearchState.temporaryMapCity
    }
}

// MARK: - Native Bottom Toolbar

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
        } else if !dateSwitcherHasSelectedDate {
            missingForecastDateControl
        } else {
            dateSwitcherControl
        }
    }

    private var dateSwitcherHasSelectedDate: Bool {
        dateSwitcherAvailableForecastDates.contains {
            Calendar.current.isDate($0, inSameDayAs: dateSwitcherSelectedForecastDate)
        }
    }

    private var missingForecastDateControl: some View {
        Button {
            DeveloperWarningCenter.showMissingData(
                message: missingForecastDateMessage,
                locale: locale
            )
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.destructive)
                .frame(width: bottomCenterToolbarWidth, height: 44)
                .contentShape(Capsule())
        }
    }

    private var missingForecastDateMessage: String {
        if let explanation = missingForecastExplanation(for: dateSwitcherForecastSourceCities) {
            return explanation
        }
        let subject = detailDateSwitcherCity.map { localizedCityName(for: $0.city) } ?? toolbarTitle
        return String(
            format: localizedString("Missing forecast data for the selected date in %@.", locale: locale),
            locale: locale,
            subject
        )
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
                isEnabled: dateSwitcherPreviousForecastDate != nil
            ) {
                guard let previousForecastDate = dateSwitcherPreviousForecastDate else { return }
                Haptics.lightImpact()
                dateSwitcherForward = false
                withAnimation(.smooth(duration: 0.2)) {
                    dateSwitcherSelectedForecastDate = previousForecastDate
                }
            }

            Button {
                Haptics.lightImpact()
                showingDatePopover = true
            } label: {
                ZStack {
                    ForEach(dateSwitcherAvailableForecastDates, id: \.self) { date in
                        Text(dateSwitcherText(for: date))
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
                        .id("date-\(dateSwitcherSelectedForecastDate.timeIntervalSinceReferenceDate)")
                        .transition(.push(from: dateSwitcherForward ? .trailing : .leading))
                        .clipped()
                }
                .frame(minWidth: 72, minHeight: 32)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDatePopover) {
                datePickerPopoverContent
            }

            dateStepperButton(
                systemImage: "chevron.right",
                isEnabled: dateSwitcherNextForecastDate != nil
            ) {
                guard let nextForecastDate = dateSwitcherNextForecastDate else { return }
                Haptics.lightImpact()
                dateSwitcherForward = true
                withAnimation(.smooth(duration: 0.2)) {
                    dateSwitcherSelectedForecastDate = nextForecastDate
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(width: bottomCenterToolbarWidth)
    }

    func dateStepperButton(
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? theme.colors.primaryText : theme.colors.primaryText.opacity(0.35))
            .frame(minWidth: 30, minHeight: 32)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .disabled(!isEnabled)
    }

    func dateSwitcherText(for date: Date) -> String {
        if Calendar.current.isDate(date, inSameDayAs: forecastDateToday) {
            return localizedString("Today", locale: locale)
        }
        return date.formatted(
            Date.FormatStyle.dateTime
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    @ViewBuilder
    var datePickerPopoverContent: some View {
        if let dateRange = dateSwitcherForecastDateRange {
            DatePicker(
                dateSwitcherText,
                selection: Binding(
                    get: {
                        dateSwitcherSelectedForecastDate
                    },
                    set: { newDate in
                        let normalizedDate = Calendar.current.startOfDay(for: newDate)
                        guard dateSwitcherAvailableForecastDates.contains(where: {
                            Calendar.current.isDate($0, inSameDayAs: normalizedDate)
                        }) else {
                            return
                        }
                        withAnimation(.smooth(duration: 0.2)) {
                            dateSwitcherSelectedForecastDate = normalizedDate
                        }
                    }
                ),
                in: dateRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 280, height: 300)
            .padding(8)
            .presentationCompactAdaptation(.popover)
            .themedPopoverBackground()
        } else {
            WeatherDataUnavailableNotice(
                message: missingForecastDateMessage
            )
            .padding(16)
        }
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
        }
        .tint(theme.colors.accent)
    }

    var bottomBackButton: some View {
        Button(localizedString("Back", locale: locale), systemImage: "chevron.left") {
            popCurrentRoute()
        }
    }

    var bottomCancelListPreviewButton: some View {
        Button(localizedString("Cancel", locale: locale), systemImage: "xmark") {
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
        .disabled(cityPendingAddition == nil || lists.isEmpty)
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
        guard let city = cityPendingAddition else { return }
        let originatedFromTemporaryMapCity = addCityDetailCity == nil

        Task {
            let didAdd: Bool
            if listID == weatherService.activeListID {
                didAdd = addCityToActiveList(city)
            } else {
                didAdd = weatherService.addCityToList(city, listID: listID)
                if didAdd {
                    Haptics.lightImpact()
                }
                await switchToList(listID)
            }

            await MainActor.run {
                guard let savedCity = weatherService.cityWeatherData.first(where: {
                    weatherService.citiesMatch($0.city, city.city)
                }) else {
                    weatherService.reportDeveloperWarning(
                        title: "Added City Missing",
                        message: "After adding \(city.city.localizedName()) to \(listID.rawValue), the saved city could not be found in fetched weather data."
                    )
                    return
                }

                selectedMapCity = savedCity
                citySearchState.temporaryMapCity = nil
                if originatedFromTemporaryMapCity {
                    // A map search should remain on the map after saving; the
                    // temporary card simply becomes the saved city's card.
                    showingMapExpandedCard = true
                } else {
                    if case .addCityDetail = navigationPath.last {
                        navigationPath.removeLast()
                    }
                    pushRoute(.cityDetail(savedCity))
                }
                if didAdd {
                    showCityAddedConfirmation(
                        cityAddedConfirmationMessage(
                            cityName: localizedCityName(for: savedCity.city),
                            listName: listID.localizedDisplayName(locale: locale)
                        )
                    )
                }
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
        case .cityDetail, .addCityDetail:
            break
        case .listPreview:
            clearGeneratedListPreview()
        }
    }

}
