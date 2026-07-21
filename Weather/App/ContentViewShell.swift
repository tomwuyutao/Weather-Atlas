//
//  ContentViewShell.swift
//  Weather
//
//  Purpose: Composes the root navigation stack, lifecycle observers, sheets,
//  alerts, and transient app-wide overlays around ContentView's stored state.
//

import SwiftUI

// MARK: - View Entry Point

extension ContentView {
    var body: some View {
        viewAlerts
    }
}

// MARK: - App Shell

extension ContentView {
    private var viewLifecycle: some View {
        appNavigationStack
            .task {
                await onAppearLoad()
                publishWidgetCatalog()
            }
            .background {
                homeScreenShortcutReceiver
            }
            .onOpenURL(perform: handleWidgetURL)
            .onChange(of: weatherService.activeListID) { _, _ in
                scheduleDaytimeSunninessRefetch()
                publishWidgetCatalog()
            }
            .onChange(of: selectedForecastDate) { _, _ in
                scheduleDaytimeSunninessRefetch()
            }
            .onChange(of: availableForecastDates) { _, _ in
                normalizeSelectedForecastDate()
            }
            .onChange(of: weatherService.weatherDataByListID) { _, _ in
                publishWidgetCatalog()
            }
            .onChange(of: weatherService.availableLists) { _, _ in
                publishWidgetCatalog()
            }
            .onChange(of: locale.identifier) { _, _ in
                AppDelegate.updateHomeScreenShortcuts()
                publishWidgetCatalog()
            }
            .onChange(of: citySearchState.query) { _, newValue in
                scheduleCitySearch(for: newValue)
            }
            .onChange(of: weatherService.errorMessage) { _, message in
                if let message {
                    DeveloperWarningCenter.showMissingData(message: message, locale: locale)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                normalizeSelectedForecastDate()
                if isMapRoute {
                    centerMapOnDots(useListCoordinates: true)
                }
                guard !tutorialState.showsFirstLaunch, !tutorialState.showsReplay else { return }
                Task {
                    await weatherService.fetchWeatherForAllCities()
                    await refreshCitiesMissingDaytimeSunninessData()
                }
            }
    }

    private var viewStateObservers: some View {
        viewLifecycle
            .onChange(of: showingMapExpandedCard) { _, showing in
                if !showing, citySearchState.temporaryMapCity != nil {
                    citySearchState.temporaryMapCity = nil
                    centerMapOnDots(useListCoordinates: true)
                }
            }
            .onChange(of: filterSunny) { _, _ in
                dismissSelectedMapCardIfUnavailable()
            }
            .onChange(of: mapOverlayMode) { _, _ in
                dismissSelectedMapCardIfUnavailable()
            }
            .onChange(of: selectedForecastDate) { _, _ in
                dismissSelectedMapCardIfUnavailable()
            }
            .onChange(of: weatherService.weatherDataByListID) { _, _ in
                dismissSelectedMapCardIfUnavailable()
            }
    }

    private var viewSheetsAndOverlays: some View {
        viewStateObservers
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    weatherService: weatherService,
                    onReplayTutorial: {
                        showingSettings = false
                        tutorialState.showsReplay = true
                    }
                )
                // iPad: Use the native centred form presentation in regular-width
                // windows. Compact Split View keeps the existing phone-style sheet.
                .if(horizontalSizeClass == .regular) { view in
                    view.presentationSizing(.form)
                }
            }
            .fullScreenCover(isPresented: $tutorialState.showsFirstLaunch) {
                TutorialView(
                    includesListSelection: true,
                    continentLists: continentListTutorialLists,
                    creationProgress: weatherService.loadingProgress,
                    onSelectContinentList: finishTutorialWithContinentList,
                    onSelectCountryList: finishTutorialWithCountryList,
                    onFinish: applyTutorialListSelection,
                    onCancel: nil
                )
            }
            .fullScreenCover(isPresented: $tutorialState.showsReplay) {
                TutorialView(
                    includesListSelection: false,
                    continentLists: [],
                    creationProgress: 0,
                    onSelectContinentList: { _ in },
                    onSelectCountryList: { _ in },
                    onFinish: { tutorialState.showsReplay = false },
                    onCancel: nil
                )
            }
            .sheet(isPresented: Binding(
                get: { citySearchState.isPresented },
                set: { isPresented in
                    if !isPresented {
                        dismissNativeCitySearchAndRecenter()
                    }
                }
            )) {
                searchSheet
                    // iPad: A regular-width search is a native form sheet rather than
                    // an unnecessarily wide bottom sheet.
                    .if(horizontalSizeClass == .regular) { view in
                        view.presentationSizing(.form)
                    }
                    .if(horizontalSizeClass != .regular) { view in
                        view
                            .presentationDetents([.fraction(0.82), .large])
                            .presentationDragIndicator(.visible)
                    }
                    .presentationBackground(theme.colors.background)
            }
            .sheet(isPresented: $listManagementState.isPresented, onDismiss: performListManagementDismissAction) {
                listManagementSheet
                    // iPad: Keep this short navigation hierarchy in the system form
                    // size; narrow windows retain the existing draggable detents.
                    .if(horizontalSizeClass == .regular) { view in
                        view.presentationSizing(.form)
                    }
                    .if(horizontalSizeClass != .regular) { view in
                        view
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                    .presentationBackground(theme.colors.mapOcean)
            }
            .overlay {
                cityAddedConfirmationOverlay
            }
    }

    private var viewAlerts: some View {
        viewSheetsAndOverlays
            .alert(localizedString("Rename", locale: locale), isPresented: $showingCityRenameAlert) {
                TextField(localizedString("Name", locale: locale), text: $cityRenameText)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    cityToRename = nil
                }
                Button(localizedString("OK", locale: locale)) {
                    let trimmed = cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let cityToRename, !trimmed.isEmpty {
                        CityListID.saveCustomCityName(trimmed, for: cityToRename)
                    }
                    cityToRename = nil
                }
                .disabled(cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(localizedString("New List", locale: locale), isPresented: $showingAddListAlert) {
                TextField(localizedString("Name", locale: locale), text: $newListName)
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    newListName = ""
                }
                Button(localizedString("Add", locale: locale)) {
                    commitListManagerNewList()
                }
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert(developerWarning?.title ?? "Unexpected App Issue", isPresented: Binding(
                get: { developerWarning != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissDeveloperWarning()
                    }
                }
            )) {
                // SwiftUI updates the alert binding when this native cancel
                // button is tapped; the binding is the single queue owner.
                Button(localizedString("OK", locale: locale), role: .cancel) { }
            } message: {
                Text(developerWarning?.message ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: DeveloperWarningCenter.notification)) { notification in
                guard let warning = notification.object as? DeveloperWarning else { return }
                enqueueDeveloperWarning(warning)
            }
            .alert(localizedString("Delete List", locale: locale), isPresented: $showingDeleteListConfirmation) {
                Button(localizedString("Cancel", locale: locale), role: .cancel) {
                    listToDeleteID = nil
                }
                Button(localizedString("Delete", locale: locale), role: .destructive) {
                    if let listToDeleteID {
                        weatherService.deleteList(listToDeleteID)
                        refreshListOrder()
                    }
                    self.listToDeleteID = nil
                }
            } message: {
                Text(String(
                    format: localizedString("Are you sure you want to delete \"%@\"? This cannot be undone.", locale: locale),
                    (listToDeleteID ?? weatherService.activeListID).localizedDisplayName(locale: locale)
                ))
            }
            .toolbar {
                nativeBottomToolbarItems
            }
    }

    @ViewBuilder
    private var cityAddedConfirmationOverlay: some View {
        if let message = citySearchState.confirmation {
            CityAddedConfirmationView(message: message)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.86).combined(with: .opacity))
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: message)
        }
    }

    private func enqueueDeveloperWarning(_ warning: DeveloperWarning) {
        let isAlreadyPresented = developerWarning.map {
            $0.title == warning.title && $0.message == warning.message
        } ?? false
        let isAlreadyQueued = pendingDeveloperWarnings.contains {
            $0.title == warning.title && $0.message == warning.message
        }
        guard !isAlreadyPresented, !isAlreadyQueued else { return }

        if developerWarning == nil, !isDismissingDeveloperWarning {
            developerWarning = warning
        } else {
            pendingDeveloperWarnings.append(warning)
        }
    }

    private func dismissDeveloperWarning() {
        guard developerWarning != nil else { return }
        developerWarning = nil
        isDismissingDeveloperWarning = true
        Task { @MainActor in
            // Native alerts animate out after their binding becomes false. Wait
            // for that transition before assigning the next queued warning;
            // assigning it in the same run-loop turn can leave the state set
            // without presenting another alert.
            try? await Task.sleep(for: .milliseconds(350))
            isDismissingDeveloperWarning = false
            guard developerWarning == nil, !pendingDeveloperWarnings.isEmpty else { return }
            developerWarning = pendingDeveloperWarnings.removeFirst()
        }
    }

    func showCityAddedConfirmation(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            citySearchState.confirmation = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard citySearchState.confirmation == message else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                citySearchState.confirmation = nil
            }
        }
    }

    func cityAddedConfirmationMessage(cityName: String, listName: String) -> String {
        String(
            format: localizedString("%1$@ was added to %2$@.", locale: locale),
            locale: locale,
            cityName,
            listName
        )
    }

}

private struct CityAddedConfirmationView: View {
    let message: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 27, weight: .bold))
                .foregroundStyle(theme.colors.accent)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 300)
        .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: theme.colors.shadow.opacity(0.16), radius: 18, y: 8)
    }
}

#Preview("City Added Confirmation") {
    CityAddedConfirmationView(message: "Oxford was added to Europe.")
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColors.light.background)
        .environment(\.appTheme, AppTheme.shared)
}
