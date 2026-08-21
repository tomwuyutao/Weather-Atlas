//
//  Tutorial.swift
//  Weather
//
//  Purpose: Owns Weather Atlas's first-run tutorial, mandatory location
//  selection, contextual feature tips, and their self-contained Xcode previews.
//

import CoreLocation
import Foundation
import Observation
import SwiftUI

// MARK: - First-Run Tutorial

/// Two-step tutorial shown before the normal tab shell is mounted. A person
/// must choose either their current location or a permanent home location.
struct TutorialFlow: View {
    let model: WeatherModel
    let complete: () -> Void

    @Environment(\.locale) private var locale

    @State private var step: TutorialStep = .welcome
    @State private var isBouncingSun = false
    @State private var isSunExpanded = false
    @State private var showsWelcome = false
    @State private var isRequestingDeviceLocation = false
    @State private var deviceLocationMessage: LocalizedStringKey?
    @State private var showsHomeLocationPicker = false

    var body: some View {
        ZStack {
            AppPalette.light.background
                .ignoresSafeArea()

            Circle()
                .fill(AppPalette.light.dotSun)
                .frame(width: 58, height: 58)
                .offset(y: isBouncingSun ? -24 : 0)
                .scaleEffect(isSunExpanded ? 36 : 1)
                .opacity(showsWelcome ? 0 : 1)


            AppPalette.light.dotSun
                .ignoresSafeArea()
                .opacity(isSunExpanded ? 1 : 0)

            if showsWelcome {
                tutorialContent
                    .transition(.opacity)
            }
        }
        .task {
            await playLaunchAnimation()
        }
        .task(id: model.locationProvider.hasUsableCoordinate) {
            guard step == .location,
                  isRequestingDeviceLocation,
                  model.locationProvider.hasUsableCoordinate else {
                return
            }
            complete()
        }
        .onChange(of: model.locationProvider.status) { _, status in
            handleLocationStatus(status)
        }
        .sheet(isPresented: $showsHomeLocationPicker) {
            TutorialHomeLocationPicker { city in
                model.setHomeLocation(city)
                complete()
            }
        }
        // The tutorial intentionally uses its bright light presentation even
        // if the rest of the app is configured for a dark appearance.
        .preferredColorScheme(.light)
    }

    private var tutorialContent: some View {
        TabView(selection: $step) {
            TutorialWelcomeStage {
                advanceToLocation()
            }
            .tag(TutorialStep.welcome)

            TutorialLocationStage(
                isRequestingDeviceLocation: isRequestingDeviceLocation,
                deviceLocationMessage: deviceLocationMessage,
                useCurrentLocation: useCurrentLocation,
                chooseHomeLocation: {
                    deviceLocationMessage = nil
                    showsHomeLocationPicker = true
                }
            )
            .tag(TutorialStep.location)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func advanceToLocation() {
        withAnimation(.smooth) {
            step = .location
        }
    }

    private func playLaunchAnimation() async {
        for _ in 0..<2 {
            withAnimation(.easeOut(duration: 0.18)) {
                isBouncingSun = true
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }

            withAnimation(.easeIn(duration: 0.2)) {
                isBouncingSun = false
            }
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return
            }
        }

        withAnimation(.easeIn(duration: 0.48)) {
            isSunExpanded = true
        }
        do {
            try await Task.sleep(for: .milliseconds(360))
        } catch {
            return
        }
        withAnimation(.easeOut(duration: 0.22)) {
            showsWelcome = true
        }
    }

    private func useCurrentLocation() {
        deviceLocationMessage = nil
        isRequestingDeviceLocation = true
        model.useCurrentLocation(preferredLocale: locale)
    }

    private func handleLocationStatus(_ status: LocationProviderStatus) {
        guard isRequestingDeviceLocation else { return }

        switch status {
        case .denied:
            isRequestingDeviceLocation = false
            deviceLocationMessage = "Location access is off. Choose a home location instead."
        case .restricted, .servicesDisabled:
            isRequestingDeviceLocation = false
            deviceLocationMessage = "Current location is unavailable on this device. Choose a home location instead."
        case .failed:
            isRequestingDeviceLocation = false
            deviceLocationMessage = "We could not find your location. Try again or choose a home location."
        case .idle, .checkingAvailability, .requestingAuthorization, .locating,
             .resolvingPlace, .ready, .readyWithoutMetadata:
            break
        }
    }
}

private enum TutorialStep: Hashable {
    case welcome
    case location
}

/// The bright first tutorial page. It has no dependency on live app state so
/// it can be previewed exactly as it appears after the launch animation.
struct TutorialWelcomeStage: View {
    let continueAction: () -> Void

    var body: some View {
        TutorialStageLayout {
            tutorialWelcomeIntro
        } actions: {
            Button("Continue", action: continueAction)
                .buttonStyle(TutorialPrimaryButtonStyle())

        }
    }

    private var tutorialWelcomeIntro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome!")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(AppPalette.light.titleText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Here are the three ways to find sun using Weather Atlas:")
                .font(.title3)
                .foregroundStyle(AppPalette.light.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            TutorialFindSunSteps()
                .padding(.top, 4)
        }
    }
}

/// Reuses the original tutorial's numbered-card treatment to introduce the
/// three levels of Find Sun before the person chooses their location.
private struct TutorialFindSunSteps: View {
    private let steps: [TutorialFindSunStep] = [
        .init(
            number: 1,
            title: "Find Sun Near You",
            subtitle: "See nearby sunny places from Your Location."
        ),
        .init(
            number: 2,
            title: "Track Your Saved Places",
            subtitle: "Compare the cities you care about in Saved Places."
        ),
        .init(
            number: 3,
            title: "Explore the Map",
            subtitle: "Search new areas and discover sunny places."
        )
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(steps) { step in
                TutorialFindSunStepCard(step: step)
            }
        }
    }
}

private struct TutorialFindSunStep: Identifiable {
    let number: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var id: Int { number }
}

/// Original three-card tutorial styling, adapted for the current light
/// onboarding presentation.
private struct TutorialFindSunStepCard: View {
    let step: TutorialFindSunStep

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(step.number, format: .number)
                .font(.callout.weight(.bold))
                .foregroundStyle(AppPalette.light.titleText)
                .frame(width: 34, height: 34)
                .background(
                    AppPalette.light.titleText.opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppPalette.light.titleText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.subtitle)
                    .font(.body)
                    .foregroundStyle(AppPalette.light.titleText.opacity(0.64))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            AppPalette.light.titleText.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppPalette.light.titleText.opacity(0.14), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The required location page. It is parameterised by state owned by
/// `TutorialFlow`, keeping the visual stage independently previewable.
struct TutorialLocationStage: View {
    let isRequestingDeviceLocation: Bool
    let deviceLocationMessage: LocalizedStringKey?
    let useCurrentLocation: () -> Void
    let chooseHomeLocation: () -> Void

    var body: some View {
        TutorialStageLayout {
            tutorialLocationIntro
        } actions: {
            VStack(spacing: 12) {
                Button(action: useCurrentLocation) {
                    HStack(spacing: 10) {
                        if isRequestingDeviceLocation {
                            ProgressView()
                                .tint(AppPalette.light.background)

                        } else {
                            Image(systemName: "location.fill")

                        }
                        Text(
                            isRequestingDeviceLocation
                                ? "Finding your location…"
                                : "Use Current Location"
                        )
                    }
                }
                .buttonStyle(TutorialPrimaryButtonStyle())
                .disabled(isRequestingDeviceLocation)

                Button(action: chooseHomeLocation) {
                    Label("Choose Home Location", systemImage: "house.fill")
                }
                .buttonStyle(TutorialSecondaryButtonStyle())
                .disabled(isRequestingDeviceLocation)
            }
        }
    }

    private var tutorialLocationIntro: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set your location")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(AppPalette.light.titleText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use your current location, or choose a home location to keep using every time you open Weather Atlas.")
                .font(.title3)
                .foregroundStyle(AppPalette.light.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let deviceLocationMessage {
                Label(deviceLocationMessage, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.light.titleText)
                    .padding(.top, 4)

            }
        }
    }
}

/// Both full-screen stages share one elevated intro anchor. Actions remain
/// pinned to the bottom, leaving the welcome cards room without shifting the
/// location choices upward with them.
private struct TutorialStageLayout<Intro: View, Actions: View>: View {
    @ViewBuilder let intro: () -> Intro
    @ViewBuilder let actions: () -> Actions

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                intro()
                    .padding(.top, max(24, geometry.size.height * 0.10))

                Spacer(minLength: 32)

                actions()
            }
            .padding(28)
            .frame(maxWidth: contentWidth(for: geometry.size))
            .frame(maxWidth: .infinity)
        }
    }

    /// Match the focused 640-point content column used throughout the app in
    /// landscape on iPad. Phone and portrait onboarding retain their existing
    /// edge-to-edge stage layout.
    private func contentWidth(for size: CGSize) -> CGFloat {
        AppContentLayout.maximumWidth(
            for: size,
            horizontalSizeClass: horizontalSizeClass,
            standardMaximumWidth: .infinity
        )
    }
}

// MARK: - Home Location Search

/// A focused city search used only to establish the persistent home location.
/// It resolves provider results before accepting them, so tutorial setup never
/// stores an incomplete place or a free-form string as geographic data.
private struct TutorialHomeLocationPicker: View {
    let onSelect: (City) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    @State private var searchManager = CitySearchManager()
    @State private var query = ""
    @State private var isSettled = true
    @State private var selectionTask: Task<Void, Never>?
    /// Cancellation can race a provider completion. A generation also blocks
    /// stale results when the person changes then restores the same query.
    @State private var selectionGeneration = 0
    @State private var loadingID: CitySearchResult.ID?
    @State private var selectionMessage: String?

    var body: some View {
        NavigationStack {
            pickerContent
                .weatherContentColumn(standardMaximumWidth: .infinity)
                .weatherScreenBackground()
                .navigationTitle("Choose Home Location")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, prompt: "Search cities")
                .task(id: "\(normalizedQuery)|\(locale.identifier)") {
                    await updateSearch()
                }
                .onChange(of: query) { _, _ in
                    invalidateSelection()
                }
                .onDisappear {
                    invalidateSelection()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var pickerContent: some View {
        if normalizedQuery.isEmpty {
            ContentUnavailableView(
                "Search for your home location",
                systemImage: "house",
                description: Text("Choose a city to use as your location in Weather Atlas.")
            )
        } else if isSearching && hasNoResults {
            ProgressView("Searching…")
        } else if !isSearching && hasNoResults && !hasProviderError {
            ContentUnavailableView.search(text: normalizedQuery)
        } else {
            List {
                if let selectionMessage {
                    Section {
                        Label(selectionMessage, systemImage: "exclamationmark.circle")
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .listRowBackground(theme.colors.settingsRowFill)
                }

                resultSection(
                    "Apple Maps",
                    results: searchManager.appleResults,
                    isSearching: searchManager.isAppleSearching,
                    errorMessage: searchManager.appleErrorMessage
                )
                resultSection(
                    "Open-Meteo",
                    results: searchManager.openMeteoResults,
                    isSearching: searchManager.isOpenMeteoSearching,
                    errorMessage: searchManager.openMeteoErrorMessage
                )
            }
            .listStyle(.insetGrouped)
            .weatherScrollableBackground()
        }
    }

    @ViewBuilder
    private func resultSection(
        _ title: LocalizedStringKey,
        results: [CitySearchResult],
        isSearching: Bool,
        errorMessage: String?
    ) -> some View {
        if !results.isEmpty || isSearching || errorMessage != nil {
            Section(title) {
                ForEach(results) { result in
                    Button {
                        select(result)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title)
                                    .font(.body)
                                    .foregroundStyle(theme.colors.primaryText)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(
                                            theme.colors.secondaryText
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if loadingID == result.id {
                                ProgressView()
                                    .controlSize(.small)

                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(loadingID != nil)

                }

                if isSearching {
                    HStack(spacing: 10) {
                        ProgressView()

                        Text("Searching…")
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                } else if errorMessage != nil {
                    providerUnavailableRow
                }
            }
            .listRowBackground(theme.colors.settingsRowFill)
        }
    }

    /// Mirrors the main Search screen: a failed provider stays distinct from
    /// an ordinary empty search and can retry the current query in place.
    private var providerUnavailableRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Search Unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(theme.colors.primaryText)

            Text("This provider could not return results. Try again.")
                .font(.subheadline)
                .foregroundStyle(theme.colors.secondaryText)

            Button("Try Again", systemImage: "arrow.clockwise") {
                retryCitySearch()
            }
            .buttonStyle(.bordered)
            .tint(theme.colors.accent)
        }
        .padding(.vertical, 4)
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNoResults: Bool {
        searchManager.appleResults.isEmpty && searchManager.openMeteoResults.isEmpty
    }

    private var isSearching: Bool {
        !isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching
    }

    private var hasProviderError: Bool {
        searchManager.appleErrorMessage != nil
            || searchManager.openMeteoErrorMessage != nil
    }

    private func updateSearch() async {
        guard !normalizedQuery.isEmpty else {
            searchManager.search(query: "", locale: locale)
            isSettled = true
            return
        }

        isSettled = false
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        let submittedQuery = normalizedQuery
        searchManager.search(query: submittedQuery, locale: locale)
        guard !Task.isCancelled, normalizedQuery == submittedQuery else { return }
        isSettled = true
    }

    /// Restarts both providers for the current query, matching the main Search
    /// screen's recovery behavior.
    @MainActor
    private func retryCitySearch() {
        guard !normalizedQuery.isEmpty else { return }
        invalidateSelection()
        isSettled = true
        searchManager.search(query: normalizedQuery, locale: locale)
    }

    @MainActor
    private func invalidateSelection() {
        selectionGeneration &+= 1
        selectionTask?.cancel()
        selectionTask = nil
        loadingID = nil
        selectionMessage = nil
    }

    @MainActor
    private func select(_ result: CitySearchResult) {
        invalidateSelection()
        let generation = selectionGeneration
        let submittedQuery = normalizedQuery
        selectionTask = Task { @MainActor in
            loadingID = result.id
            selectionMessage = nil
            defer {
                if selectionGeneration == generation {
                    loadingID = nil
                    selectionTask = nil
                }
            }

            do {
                let resolved = try await searchManager.resolvePlace(for: result)
                guard !Task.isCancelled,
                      selectionGeneration == generation,
                      normalizedQuery == submittedQuery else {
                    return
                }
                let city = City(
                    name: resolved.cityName,
                    country: resolved.country,
                    latitude: resolved.coordinate.latitude,
                    longitude: resolved.coordinate.longitude,
                    timeZoneIdentifier: resolved.timeZoneIdentifier
                )
                onSelect(city)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      selectionGeneration == generation,
                      normalizedQuery == submittedQuery else {
                    return
                }
                selectionMessage = "We could not set that location. Try another result."
            }
        }
    }
}

// MARK: - Contextual Feature Tips

/// A tip shown after the first visit to its corresponding tab.
enum TutorialFeatureTip: Equatable {
    case savedPlaces
    case map

    var tab: AppTab {
        switch self {
        case .savedPlaces: .savedPlaces
        case .map: .map
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .savedPlaces: "Keep places you care about"
        case .map: "Explore Sun on a Map"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .savedPlaces:
            "Save prospective holiday destinations, and Weather Atlas will find the best dates and best places for each date."
        case .map:
            "Tap anywhere on the map to search that area. Or use the Find Sun button to search more broadly."
        }
    }

}

/// Centered instructional surface with the same single-action affordance on
/// both contextual tutorial screens. It deliberately avoids `Alert`, but uses
/// the same focused, modal visual hierarchy: a dimmed background, a dark/light
/// inverse panel, and one Done button.
struct TutorialFeatureTipCard: View {
    let tip: TutorialFeatureTip
    let dismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var panelPalette: AppPalette.Values {
        colorScheme == .light ? AppPalette.dark : AppPalette.light
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tip.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(panelPalette.titleText)

            Text(tip.message)
                .font(.body)
                .foregroundStyle(panelPalette.titleText.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: dismiss) {
                Text("Done")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppPalette.light.titleText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        AppPalette.light.dotSun,
                        in: RoundedRectangle(
                            cornerRadius: 16,
                            style: .continuous
                        )
                    )
                    // The visible background belongs to the label, so this
                    // shape makes the entire yellow control tappable rather
                    // than only the word “Done”.
                    .contentShape(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: 360)
        .background(
            panelPalette.background,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
    }
}

/// Displays a contextual tip only in its associated selected tab. Moving away
/// hides the card without marking it seen, so it returns on the next visit.
struct TutorialFeatureTipOverlay: View {
    let tip: TutorialFeatureTip?
    let tab: AppTab
    let isSelected: Bool
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            if let tip, tip.tab == tab, isSelected {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()

                TutorialFeatureTipCard(tip: tip, dismiss: dismiss)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: isSelected)
        .animation(.smooth, value: tip)
    }
}

// MARK: - Tutorial Presentation State

/// Shared app-level state for first-run completion, tutorial replay, and the
/// one-time Saved Places and Map explanations. Persisting here keeps all
/// tutorial behaviour in one file while `ContentView` remains a thin host.
@MainActor
@Observable
final class TutorialPresentationState {
    private enum StorageKey {
        static let completed = "hasCompletedOnboarding"
        static let replay = "shouldReplayTutorial"
        static let savedPlacesTipSeen = "hasSeenSavedPlacesTutorialTip"
        static let mapTipSeen = "hasSeenMapTutorialTip"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var hasCompleted: Bool
    private var isReplaying: Bool
    private(set) var hasSeenSavedPlacesTip: Bool
    private(set) var hasSeenMapTip: Bool
    private(set) var activeFeatureTip: TutorialFeatureTip?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompleted = defaults.object(forKey: StorageKey.completed) as? Bool ?? false
        isReplaying = defaults.object(forKey: StorageKey.replay) as? Bool ?? false
        hasSeenSavedPlacesTip = defaults.object(
            forKey: StorageKey.savedPlacesTipSeen
        ) as? Bool ?? false
        hasSeenMapTip = defaults.object(forKey: StorageKey.mapTipSeen) as? Bool ?? false
    }

    var shouldPresent: Bool {
        !hasCompleted || isReplaying
    }

    /// Reveals the app after the required location choice succeeds.
    func complete() {
        hasCompleted = true
        isReplaying = false
        defaults.set(true, forKey: StorageKey.completed)
        defaults.set(false, forKey: StorageKey.replay)
    }

    /// Makes the full flow and both contextual tips eligible again without
    /// changing saved places, weather data, or other app preferences.
    func replay() {
        activeFeatureTip = nil
        isReplaying = true
        hasSeenSavedPlacesTip = false
        hasSeenMapTip = false
        defaults.set(true, forKey: StorageKey.replay)
        defaults.set(false, forKey: StorageKey.savedPlacesTipSeen)
        defaults.set(false, forKey: StorageKey.mapTipSeen)
    }

    /// Clears only tutorial presentation state during a full app reset. The
    /// model reset separately removes the persisted home location.
    func resetForFullAppReset() {
        activeFeatureTip = nil
        hasCompleted = false
        isReplaying = false
        hasSeenSavedPlacesTip = false
        hasSeenMapTip = false
        defaults.set(false, forKey: StorageKey.completed)
        defaults.set(false, forKey: StorageKey.replay)
        defaults.set(false, forKey: StorageKey.savedPlacesTipSeen)
        defaults.set(false, forKey: StorageKey.mapTipSeen)
    }

    /// Schedules the tip for a just-opened tab only when no native data alert
    /// is visible. This prevents instructional copy from being obscured.
    func presentFeatureTipIfNeeded(
        for tab: AppTab,
        hasActiveNativeAlert: Bool
    ) {
        // A card belongs only to the tab that introduced it. Switching tabs
        // hides it without recording a dismissal, so returning to that tab
        // shows the same explanation again until the person taps Got it.
        if let currentTip = activeFeatureTip, currentTip.tab != tab {
            activeFeatureTip = nil
        }

        guard activeFeatureTip == nil,
              !shouldPresent,
              !hasActiveNativeAlert else {
            return
        }

        switch tab {
        case .savedPlaces where !hasSeenSavedPlacesTip:
            activeFeatureTip = .savedPlaces
        case .map where !hasSeenMapTip:
            activeFeatureTip = .map
        case .yourLocation, .search, .savedPlaces, .map:
            break
        }
    }

    /// Dismisses the visible card and remembers only its corresponding tab.
    func dismissActiveFeatureTip() {
        switch activeFeatureTip {
        case .savedPlaces:
            hasSeenSavedPlacesTip = true
            defaults.set(true, forKey: StorageKey.savedPlacesTipSeen)
        case .map:
            hasSeenMapTip = true
            defaults.set(true, forKey: StorageKey.mapTipSeen)
        case nil:
            break
        }
        activeFeatureTip = nil
    }

}

// MARK: - Tutorial Styling

private struct TutorialPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppPalette.light.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(AppPalette.light.titleText, in: .rect(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth, value: configuration.isPressed)
    }
}

private struct TutorialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppPalette.light.titleText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(AppPalette.light.background.opacity(0.55), in: .rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(AppPalette.light.titleText.opacity(0.18), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth, value: configuration.isPressed)
    }
}

// MARK: - Xcode Previews

#Preview("Tutorial – Welcome", traits: .fixedLayout(width: 390, height: 844)) {
    TutorialWelcomeStage(continueAction: {})
        .background(AppPalette.light.dotSun)
        .preferredColorScheme(.light)
}

#Preview("Tutorial – Select Location", traits: .fixedLayout(width: 390, height: 844)) {
    TutorialLocationStage(
        isRequestingDeviceLocation: false,
        deviceLocationMessage: nil,
        useCurrentLocation: {},
        chooseHomeLocation: {}
    )
    .background(AppPalette.light.dotSun)
    .preferredColorScheme(.light)
}

#Preview("Tutorial – Saved Places Tip") {
    TutorialSavedPlacesTipPreview()
}

#Preview("Tutorial – Map Tip") {
    TutorialMapTipPreview()
}

/// Recreates the Saved Places tab with a self-contained, empty in-memory
/// model, then lays the exact first-visit tip over its normal tab position.
@MainActor
private struct TutorialSavedPlacesTipPreview: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var previewState = TutorialPreviewState()

    var body: some View {
        NavigationStack {
            SavedPlacesView(
                model: previewState.model,
                router: previewState.router,
                selectedDate: $selectedDate
            )
        }
        .environment(previewState.missingDataAlerts)
        .environment(previewState.networkConnectivity)
        .overlay(alignment: .bottom) {
            TutorialFeatureTipCard(tip: .savedPlaces, dismiss: {})
        }
    }
}

/// Recreates the Map tab with the same self-contained state and shows the
/// Map-specific explanation above the bottom safe area.
@MainActor
private struct TutorialMapTipPreview: View {
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var previewState = TutorialPreviewState()

    var body: some View {
        NavigationStack {
            MapView(
                model: previewState.model,
                router: previewState.router,
                selectedDate: $selectedDate
            )
        }
        .environment(previewState.missingDataAlerts)
        .environment(previewState.networkConnectivity)
        .overlay {
            TutorialFeatureTipOverlay(
                tip: .map,
                tab: .map,
                isSelected: true,
                dismiss: {}
            )
        }
    }
}

/// Preview-only dependency bundle. Its stores are entirely in memory and the
/// empty place library means neither tab has any weather requests to make.
@MainActor
@Observable
private final class TutorialPreviewState {
    let networkConnectivity = NetworkConnectivity()
    let missingDataAlerts = MissingDataAlertCenter()
    let router = AppNavigation()
    let model: WeatherModel

    init() {
        let placesStore = SavedPlacesStore(inMemoryDocument: .empty)
        let weatherStore = SavedPlacesWeatherStore.preview(
            networkConnectivity: networkConnectivity
        )
        model = WeatherModel(
            placesStore: placesStore,
            weatherStore: weatherStore,
            locationProvider: LocationProvider(),
            initialHomeLocation: nil
        )
    }
}
