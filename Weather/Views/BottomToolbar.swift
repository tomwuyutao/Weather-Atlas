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

    /// Activates and fetches a list, then fits the map to its available cities.
    func switchToList(_ listID: CityListID) async {
        guard listID.rawValue != weatherService.activeListID.rawValue else { return }
        await weatherService.switchList(to: listID)
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
                    listManagementState.isPresented = true
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
                bottomMoreButton
            case .some(.map):
                mapMoreMenu
            case .some(.cityDetail(let city)):
                if let sourceListID = detailSourceListID(for: city) {
                    detailCityMoreMenu(for: city, sourceListID: sourceListID)
                } else {
                    bottomMoreButton
                }
            case .some(.listPreview):
                // A preview without initialized draft state still cancels natively.
                Button(localizedString("Cancel", locale: locale), systemImage: "xmark") {
                    cancelGeneratedListPreview()
                }
            case nil:
                bottomMoreButton
            }
        }
    }

    @ViewBuilder
    /// Selects the date switcher or generated-list city-count control.
    var bottomCenterToolbarControl: some View {
        if isListPreviewActive {
            listPreviewCountPickerControl
        } else if !dateSwitcherAvailableForecastDates.contains(where: {
            Calendar.current.isDate($0, inSameDayAs: dateSwitcherSelectedForecastDate)
        }) {
            // Keep the toolbar stable when the selected date is absent from its source.
            Color.clear
                .frame(width: dateSwitcherWidth, height: 44)
        } else {
            dateSwitcherControl
        }
    }

    @ViewBuilder
    /// Selects the global Add menu or generated-list preview confirmation.
    var bottomTrailingToolbarControl: some View {
        if isListPreviewActive {
            // Save the currently generated list preview.
            Button(localizedString("Add", locale: locale), systemImage: "plus") {
                confirmGeneratedListPreview()
            }
            .disabled(listPreviewCities.isEmpty)
        } else {
            Menu(localizedString("Add", locale: locale), systemImage: "plus") {
                Menu {
                    ForEach(managedLists) { listID in
                        Button {
                            presentAddCitySearch(to: listID)
                        } label: {
                            primaryMenuLabel(
                                listID.localizedDisplayName(locale: locale),
                                systemImage: "list.bullet"
                            )
                        }
                    }
                } label: {
                    primaryMenuLabel(
                        localizedString("Add City to List", locale: locale),
                        systemImage: "building.2"
                    )
                }

                Button {
                    addListState.isPresented = true
                } label: {
                    primaryMenuLabel(
                        localizedString("Add List", locale: locale),
                        systemImage: "list.bullet"
                    )
                }
            }
            .menuOrder(.fixed)
            .tint(theme.colors.accent)
        }
    }

    /// Renders previous, calendar, and next controls for the selected date source.
    var dateSwitcherControl: some View {
        HStack(spacing: 6) {
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
                in: firstDate...lastDate,
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

    /// Keeps the shared refresh and Settings actions at the bottom of every More menu.
    @ViewBuilder
    var globalMoreMenuFooter: some View {
        Divider()

        Button {
            refreshWeather()
        } label: {
            primaryMenuLabel(
                localizedString("Refresh", locale: locale)
                    + (timeSinceRefreshText().isEmpty ? "" : " (\(timeSinceRefreshText()))"),
                systemImage: "arrow.clockwise"
            )
        }
        .disabled(weatherService.isLoading)

        Button {
            showingSettings = true
        } label: {
            primaryMenuLabel(localizedString("Settings", locale: locale), systemImage: "gearshape")
        }
    }

    /// Hosts the shared More-menu footer on screens with no additional actions.
    var bottomMoreButton: some View {
        Menu(localizedString("Menu", locale: locale), systemImage: "ellipsis") {
            globalMoreMenuFooter
        }
        .menuIndicator(.hidden)
        .menuOrder(.fixed)
        .tint(theme.colors.accent)
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
