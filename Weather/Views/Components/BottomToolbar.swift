//
//  BottomToolbar.swift
//  Weather
//
//  Purpose: Defines the shared top and bottom toolbars, list switching, and
//  forecast-date selection used by every app destination.
//

import Foundation
import SwiftUI

// MARK: - List and Date Selection

extension ContentView {
    /// Lists all persisted city collections in their user-controlled order.
    var managedLists: [CityListID] {
        weatherService.availableLists
    }

    /// Reloads list metadata after a management operation changes persistence.
    func refreshListOrder() {
        weatherService.reloadAvailableLists()
    }

    /// Activates and fetches a list, preserving Map or List while returning an
    /// open city report to Home so it cannot continue showing another list's city.
    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }

        let shouldReturnHome = if case .cityDetail = currentRoute {
            true
        } else {
            false
        }

        if shouldReturnHome {
            // A sidebar choice is immediate. Do not leave Detail visible while
            // the selected list's weather request is still in flight.
            navigationPath = []
        }

        await weatherService.switchList(to: listID)

        centerMapOnDots()
    }

    /// Changes lists synchronously from an on-screen list control so Map and
    /// List remain visible and can show loading progress immediately.
    func beginSwitchToList(_ listID: CityListID) {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }

        let routeToPreserve = currentRoute
        if case .cityDetail = routeToPreserve {
            navigationPath = []
        }

        weatherService.beginSwitchList(to: listID)

        // A List(selection:) in the iPad sidebar can pop the detail stack as
        // its selected value changes. Restore the current primary destination
        // after activation, while Detail deliberately remains at Home.
        switch routeToPreserve {
        case let .some(route) where route == .map || route == .list:
            Task { @MainActor in
                // Let List(selection:) commit its split-view update before
                // restoring the destination it otherwise pops to Home.
                try? await Task.sleep(for: .milliseconds(100))
                navigationPath = [route]
            }
        default:
            break
        }

        centerMapOnDots()
    }

    /// Today normalized to the device calendar's start of day.
    var forecastDateToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Read-write adapter between the toolbar and root forecast-date state.
    var dateSwitcherSelectedForecastDate: Date {
        get { selectedForecastDate }
        nonmutating set { selectedForecastDate = newValue }
    }

    /// Sorted dates offered by the toolbar for its current source cities.
    var dateSwitcherAvailableForecastDates: [Date] {
        // Detail follows one city's range; Home, List, and Map use the active list.
        switch currentRoute {
        case .cityDetail(let city):
            return availableForecastDates(for: [city])
        default:
            return availableForecastDates(for: weatherService.cityWeatherData)
        }
    }

    /// Returns the unique sorted selection dates supplied by a city collection.
    func availableForecastDates(for cities: [CityWeather]) -> [Date] {
        Array(Set(cities.flatMap { cityWeather in
            cityWeather.dailyForecasts.compactMap { forecast in
                cityWeather.selectionDate(for: forecast)
            }
        })).sorted()
    }
}

// MARK: - Top Toolbar

extension ContentView {
    /// Localized title for the active list or generated preview.
    var toolbarTitle: String {
        weatherService.activeListID.localizedDisplayName(locale: locale)
    }

    /// Builds the standard top row with list switcher and optional accessory.
    func topToolbar<Accessory: View>(
        titleOverride: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            listSwitcher(titleOverride: titleOverride)
            Spacer(minLength: 12)
            accessory()
        }
        .frame(maxWidth: .infinity)
    }

    /// Wraps compact top actions in the shared Liquid Glass capsule.
    func topToolbarActionCapsule<Content: View>(
        spacing: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: spacing) {
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .themedGlass(in: .capsule)
    }

    /// Builds the active-list menu with creation and management actions.
    func listSwitcher(
        titleOverride: String?,
        navigationBarStyle: Bool = false
    ) -> some View {
        Group {
            Menu {
                ForEach(managedLists) { listID in
                    Button {
                        listEditMode = false
                        beginSwitchToList(listID)
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
                    presentListManagement()
                } label: {
                    primaryMenuLabel(
                        localizedString("Manage Lists", locale: locale),
                        systemImage: "slider.horizontal.3"
                    )
                }
            } label: {
                HStack(spacing: 6) {
                    Text(titleOverride ?? toolbarTitle)
                        .font(
                            navigationBarStyle
                                ? .headline.weight(.semibold)
                                : .system(size: 32, weight: .semibold, design: .serif)
                        )
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                    if titleOverride == nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: navigationBarStyle ? 10 : 14, weight: .semibold))
                            .foregroundStyle(theme.colors.accent)
                    }
                }
            }
            .menuOrder(.fixed)
        }
    }

    /// Builds a consistently styled label for native app menus.
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
}

// MARK: - Native Bottom Toolbar

extension ContentView {
    /// Fixed width that keeps the date switcher stable as labels change.
    var dateSwitcherWidth: CGFloat { 165 }

    @ToolbarContentBuilder
    /// Supplies native bottom-bar placements with a pre-iOS-26 grouped fallback.
    var bottomToolbarItems: some ToolbarContent {
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
    /// Selects the screen-specific leading action for the native bottom bar.
    var bottomLeadingToolbarControl: some View {
        if isListPreviewActive {
            // Cancel a generated-list preview without persisting it.
            Button(localizedString("Cancel", locale: locale), systemImage: "xmark") {
                cancelGeneratedListPreview()
            }
        } else {
            switch currentRoute {
            case .some(.list):
                listSortControl
            case .some(.map):
                mapOverlayMenu
            case .some(.cityDetail(let city)):
                if let sourceListID = detailSourceListID(for: city) {
                    detailCityMoreMenu(for: city, sourceListID: sourceListID)
                } else {
                    EmptyView()
                }
            case .some(.listPreview):
                // A preview without initialized draft state still cancels natively.
                Button(localizedString("Cancel", locale: locale), systemImage: "xmark") {
                    cancelGeneratedListPreview()
                }
            case nil:
                Button(localizedString("Settings", locale: locale), systemImage: "slider.horizontal.3") {
                    showingSettings = true
                }
                .tint(theme.colors.accent)
            }
        }
    }

    /// Selects the date switcher or generated-list city-count control while
    /// preserving one stable toolbar host as forecast results arrive.
    var bottomCenterToolbarControl: some View {
        ZStack {
            // Retain this fixed host even when partial weather updates temporarily
            // add or remove the date switcher. Replacing a native toolbar item while
            // its Menu is open causes iOS to dismiss that menu immediately.
            Color.clear
                .frame(width: dateSwitcherWidth, height: 44)

            if isListPreviewActive {
                listPreviewCountPickerControl
            } else {
                // Keep the selected date visible when a newly selected list has
                // no forecast for it. The unavailable direction is disabled by
                // the stepper itself, while the date can still open Calendar.
                dateSwitcherControl
            }
        }
        // Anchor Calendar to the fixed native toolbar host rather than its
        // replaceable inner label. Forecast updates can rebuild that label
        // while the popover is presenting, particularly on iPad.
        .popover(isPresented: $showingDatePopover) {
            datePickerPopoverContent
        }
    }

    @ViewBuilder
    /// Selects the compact global New menu or generated-list preview confirmation.
    var bottomTrailingToolbarControl: some View {
        if isListPreviewActive {
            // Save the currently generated list preview.
            Button(localizedString("Create", locale: locale), systemImage: "checkmark") {
                confirmGeneratedListPreview()
            }
            .disabled(listPreviewCities.isEmpty)
        } else {
            Menu {
                Button {
                    presentNewCitySearch()
                } label: {
                    Label(localizedString("New City", locale: locale), systemImage: "building.2")
                }

                Button {
                    addListSheetState.selectedDetent = .medium
                    addListSheetState.isPresented = true
                } label: {
                    Label(localizedString("New List", locale: locale), systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuOrder(.fixed)
            .tint(theme.colors.accent)
        }
    }

    /// Renders previous, calendar, and next controls for the selected date source.
    var dateSwitcherControl: some View {
        let selectedDateIsAvailable = dateSwitcherAvailableForecastDates.contains {
            Calendar.current.isDate($0, inSameDayAs: dateSwitcherSelectedForecastDate)
        }

        return HStack(spacing: 6) {
            dateStepperButton(
                systemImage: "chevron.left",
                isEnabled: dateSwitcherAvailableForecastDates.last {
                    $0 < dateSwitcherSelectedForecastDate
                } != nil
            ) {
                guard let previousForecastDate = dateSwitcherAvailableForecastDates.last(where: {
                    $0 < dateSwitcherSelectedForecastDate
                }) else { return }
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

                    Text(dateSwitcherText(for: dateSwitcherSelectedForecastDate))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(
                            selectedDateIsAvailable
                                ? theme.colors.primaryText
                                : theme.colors.primaryText.opacity(0.35)
                        )
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

            dateStepperButton(
                systemImage: "chevron.right",
                isEnabled: dateSwitcherAvailableForecastDates.first {
                    $0 > dateSwitcherSelectedForecastDate
                } != nil
            ) {
                guard let nextForecastDate = dateSwitcherAvailableForecastDates.first(where: {
                    $0 > dateSwitcherSelectedForecastDate
                }) else { return }
                Haptics.lightImpact()
                dateSwitcherForward = true
                withAnimation(.smooth(duration: 0.2)) {
                    dateSwitcherSelectedForecastDate = nextForecastDate
                }
            }
        }
        .padding(.horizontal, 3)
        .frame(width: dateSwitcherWidth)
    }

    /// Builds a compact date arrow that ignores taps when no adjacent date exists.
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

    /// Formats Today specially and all other dates in the app-selected locale.
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
    /// Presents a graphical picker constrained to dates represented by forecasts.
    var datePickerPopoverContent: some View {
        let dates = dateSwitcherAvailableForecastDates
        if let firstDate = dates.first, let lastDate = dates.last {
            // The currently displayed date can sit just outside this list's
            // forecast range after a list switch. Include it in the native
            // picker's bounds so the dimmed date button still opens Calendar.
            let normalizedSelection = Calendar.current.startOfDay(
                for: dateSwitcherSelectedForecastDate
            )
            let pickerRange = min(firstDate, normalizedSelection)...max(lastDate, normalizedSelection)

            DatePicker(
                dateSwitcherText(for: dateSwitcherSelectedForecastDate),
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
                // The graphical picker needs continuous bounds around represented dates.
                in: pickerRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .frame(width: 280, height: 300)
            .padding(8)
            .presentationCompactAdaptation(.popover)
            .themedPopoverBackground()
        } else {
            EmptyView()
        }
    }

    /// Adjusts how many ranked cities the generated list will contain.
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

            // The displayed count remains a stepper label and also opens native
            // numeric entry for larger changes.
            Button {
                listPreviewCityCountEntry = listPreviewState.cityCount
                showingListPreviewCityCountEntry = true
            } label: {
                Text(
                    verbatim: String(listPreviewState.cityCount)
                        + " "
                        + localizedString(
                            listPreviewState.cityCount == 1 ? "City" : "Cities",
                            locale: locale
                        )
                )
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.colors.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alert(
                localizedString("Number of Cities", locale: locale),
                isPresented: $showingListPreviewCityCountEntry
            ) {
                TextField(
                    localizedString("Number of Cities", locale: locale),
                    value: $listPreviewCityCountEntry,
                    format: .number
                )
                .keyboardType(.numberPad)

                Button(localizedString("Cancel", locale: locale), role: .cancel) {}

                Button(localizedString("Done", locale: locale)) {
                    guard let enteredCount = listPreviewCityCountEntry,
                          (1...listPreviewMaximumCount).contains(enteredCount) else {
                        return
                    }
                    Haptics.lightImpact()
                    withAnimation(.smooth(duration: 0.18)) {
                        listPreviewState.cityCount = enteredCount
                    }
                }
                .disabled(
                    listPreviewCityCountEntry.map {
                        !(1...listPreviewMaximumCount).contains($0)
                    } ?? true
                )
            } message: {
                Text(
                    String(
                        format: localizedString(
                            "Enter a number from 1 to %lld. A list can contain up to 25 cities.",
                            locale: locale
                        ),
                        locale: locale,
                        listPreviewMaximumCount
                    )
                )
            }

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
        .frame(width: dateSwitcherWidth)
    }

    /// Clamps and applies a generated-list count change, then refreshes its preview.
    private func changeListPreviewCityCount(by delta: Int) {
        let updatedCount = min(max(listPreviewState.cityCount + delta, 1), listPreviewMaximumCount)
        guard updatedCount != listPreviewState.cityCount else { return }
        Haptics.lightImpact()
        withAnimation(.smooth(duration: 0.18)) {
            listPreviewState.cityCount = updatedCount
        }
    }

}
