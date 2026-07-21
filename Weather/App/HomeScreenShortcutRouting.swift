//
//  HomeScreenShortcutRouting.swift
//  Weather
//
//  Purpose: Routes Home Screen quick actions and widget deep links into the
//  app's navigation and active-list state.
//

import SwiftUI

// MARK: - Shortcut Receiver

extension ContentView {
    var homeScreenShortcutReceiver: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .weatherOpenMainViewShortcut)) { notification in
                let notifiedDestination = (notification.object as? String)
                    .flatMap(HomeScreenShortcutDestination.init(rawValue:))
                guard let destination = AppDelegate.takePendingHomeScreenShortcut()
                    ?? notifiedDestination else { return }
                handleHomeScreenShortcut(destination)
            }
    }

    // MARK: External Destinations

    func handleOpenListShortcut(rawValue: String) {
        guard let listID = CityListID.allLists.first(where: { $0.rawValue == rawValue }) else { return }
        resetSelectedForecastDateToToday()
        showingSettings = false
        citySearchState.isPresented = false
        showingMapExpandedCard = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        clearGeneratedListPreview(playsHaptic: false)
        navigationPath = []

        Task {
            await switchToList(listID)
        }
    }

    func handleHomeScreenShortcut(_ destination: HomeScreenShortcutDestination) {
        resetSelectedForecastDateToToday()
        showingSettings = false
        citySearchState.isPresented = false
        showingMapExpandedCard = false
        selectedMapCity = nil
        citySearchState.temporaryMapCity = nil
        clearGeneratedListPreview(playsHaptic: false)

        switch destination {
        case .home:
            navigationPath = []
        case .map:
            navigationPath = [.map]
        case .list:
            navigationPath = [.list]
        }
    }

    func handleWidgetURL(_ url: URL) {
        guard url.scheme == "weatheratlas",
              url.host == "list",
              let rawValue = url.pathComponents.dropFirst().first,
              !rawValue.isEmpty else {
            return
        }
        handleOpenListShortcut(rawValue: rawValue)

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let kindValue = components.queryItems?.first(where: { $0.name == "missingKind" })?.value,
              let kind = WeatherDataIssue.Kind(rawValue: kindValue),
              let cityName = components.queryItems?.first(where: { $0.name == "city" })?.value else {
            return
        }
        let detail = components.queryItems?.first(where: { $0.name == "missingDetail" })?.value
        let issue = WeatherDataIssue(kind: kind, detail: detail)
        let message = weatherDataIssueMessage(issue, cityName: cityName, locale: locale)
        DeveloperWarningCenter.showMissingData(message: message, locale: locale)
    }
}
