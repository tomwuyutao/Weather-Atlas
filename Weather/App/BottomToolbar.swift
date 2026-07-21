//
//  BottomToolbar.swift
//  Weather
//
//  Purpose: Defines the native floating bottom toolbar used by Home, List,
//  Detail, Map, search results, and generated-list previews.
//

import SwiftUI

// MARK: - Native Bottom Toolbar

extension ContentView {
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
            Color.clear
                .frame(width: bottomCenterToolbarWidth, height: 44)
                .accessibilityHidden(true)
        } else {
            dateSwitcherControl
        }
    }

    private var dateSwitcherHasSelectedDate: Bool {
        dateSwitcherAvailableForecastDates.contains {
            Calendar.current.isDate($0, inSameDayAs: dateSwitcherSelectedForecastDate)
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
            EmptyView()
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
