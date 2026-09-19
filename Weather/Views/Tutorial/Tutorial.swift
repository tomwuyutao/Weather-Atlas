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

extension EnvironmentValues {
  /// Warm ivory onboarding palette resolved for the system contrast preference.
  @Entry fileprivate var tutorialPalette: AppPalette.Values = AppPalette.light
}

// MARK: - First-Run Tutorial

/// A welcome page precedes the required location choice. The normal
/// tab shell stays unmounted until current or home location is established.
struct TutorialFlow: View {
  // MARK: - Inputs and Flow State

  let model: WeatherModel
  let complete: () -> Void

  @Environment(\.locale) private var locale
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  @State private var step: TutorialStep = .welcome
  @State private var openingComplete = false
  @State private var isRequestingDeviceLocation = false
  @State private var deviceLocationMessage: LocalizedStringKey?
  @State private var showsHomeLocationPicker = false

  // MARK: - Presentation

  var body: some View {
    ZStack {
      (AppPalette.values(for: .light, contrast: colorSchemeContrast)).background
        .ignoresSafeArea()

      tutorialContent
    }
    .task(id: model.locationProvider.hasUsableCoordinate) {
      guard step == .location,
        isRequestingDeviceLocation,
        model.locationProvider.hasUsableCoordinate
      else {
        return
      }
      complete()
    }
    .onChange(of: model.locationProvider.status) { _, status in
      handleLocationStatus(status)
    }
    .sheet(isPresented: $showsHomeLocationPicker) {
      TutorialHomeLocationPicker { city in
        guard PlacesLibraryValidator.isValidCity(city) else { return }
        model.clearLocationState(keepingTransientCities: true)
        model.homeLocation = city
        if let data = try? JSONEncoder().encode(city) {
          UserDefaults.standard.set(
            data,
            forKey: "weatherAtlas.homeLocation"
          )
        }
        model.locationProvider.useHomeLocation(city)
        complete()
      }
    }
    // The tutorial intentionally uses its warm light presentation even
    // if the rest of the app is configured for a dark appearance.
    .environment(
      \.tutorialPalette,
      AppPalette.values(for: .light, contrast: colorSchemeContrast)
    )
    .tint((AppPalette.values(for: .light, contrast: colorSchemeContrast)).titleText)
    .preferredColorScheme(.light)
  }

  // MARK: - Stage Navigation

  private var tutorialContent: some View {
    TabView(selection: $step) {
      TutorialWelcomeStage(
        animatesEntrance: true,
        onEntranceComplete: { openingComplete = true }
      ) {
        withAnimation(reduceMotion ? nil : .smooth) {
          step = .location
        }
      }
      .tag(TutorialStep.welcome)

      TutorialLocationStage(
        isRequestingDeviceLocation: isRequestingDeviceLocation,
        deviceLocationMessage: deviceLocationMessage,
        useCurrentLocation: {
          deviceLocationMessage = nil
          isRequestingDeviceLocation = true
          model.homeLocation = nil
          UserDefaults.standard.removeObject(
            forKey: "weatherAtlas.homeLocation"
          )
          model.clearLocationState(keepingTransientCities: true)
          model.locationProvider.clearLocation()
          model.locationProvider.requestCurrentLocation(
            preferredLocale: locale
          )
        },
        chooseHomeLocation: {
          deviceLocationMessage = nil
          showsHomeLocationPicker = true
        }
      )
      .tag(TutorialStep.location)
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .allowsHitTesting(openingComplete || reduceMotion)
    .accessibilityHidden(!openingComplete && !reduceMotion)
    // Let each page's artwork reach the physical top edge behind the
    // status bar; the bottom safe area still protects the action buttons.
    .ignoresSafeArea(.container, edges: .top)
  }

  // MARK: - Location Choice

  private func handleLocationStatus(_ status: LocationProviderStatus) {
    guard isRequestingDeviceLocation else { return }

    switch status {
    case .denied:
      isRequestingDeviceLocation = false
      deviceLocationMessage = "Location access is off. Choose a home location instead."
    case .restricted, .servicesDisabled:
      isRequestingDeviceLocation = false
      deviceLocationMessage =
        "Current location is unavailable on this device. Choose a home location instead."
    case .failed:
      isRequestingDeviceLocation = false
      deviceLocationMessage =
        "We could not find your location. Try again or choose a home location."
    case .idle, .checkingAvailability, .requestingAuthorization, .locating,
      .resolvingPlace, .ready, .readyWithoutMetadata:
      break
    }
  }
}

// MARK: - Tutorial Stages

private enum TutorialStep: Int, CaseIterable, Identifiable {
  case welcome
  case location

  var id: Self { self }

  var message: LocalizedStringKey {
    switch self {
    case .welcome:
      "Let’s start finding sunshine for your holidays."
    case .location:
      "Use your current location, or choose a home location to keep using every time you open Weather Atlas."
    }
  }
}

struct TutorialWelcomeStage: View {
  var animatesEntrance = false
  var onEntranceComplete: () -> Void = {}
  let continueAction: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var openingPhase: TutorialOpeningPhase = .sun

  var body: some View {
    TutorialStageLayout(
      step: .welcome,
      openingPhase: animatesEntrance && !reduceMotion ? openingPhase : .complete
    ) {
      Button("Continue", action: continueAction)
        .buttonStyle(TutorialPrimaryButtonStyle())
    }
    .task(id: TutorialOpeningPlayback(reduceMotion: reduceMotion, scenePhase: scenePhase)) {
      guard animatesEntrance, openingPhase != .complete else { return }

      if reduceMotion {
        finishOpening()
        return
      }

      guard scenePhase == .active else {
        // Interruptions finish an in-flight entrance instead of
        // leaving navigation locked or replaying it on every resume.
        if openingPhase != .sun {
          finishOpening()
        }
        return
      }

      await playOpening()
    }
  }

  @MainActor
  private func playOpening() async {
    do {
      try await Task.sleep(for: .milliseconds(300))
      withAnimation(.spring(duration: 0.75, bounce: 0.30)) {
        openingPhase = .cursorArrived
      }
      try await Task.sleep(for: .milliseconds(910))

      withAnimation(.easeOut(duration: 0.12)) {
        openingPhase = .pressed
      }
      try await Task.sleep(for: .milliseconds(120))
      withAnimation(.spring(duration: 0.34, bounce: 0.42)) {
        openingPhase = .clicked
      }
      try await Task.sleep(for: .milliseconds(460))

      withAnimation(.spring(duration: 0.9, bounce: 0.14)) {
        openingPhase = .expanded
      }
      try await Task.sleep(for: .milliseconds(780))
      withAnimation(.easeOut(duration: 0.30)) {
        openingPhase = .revealed
      }
      try await Task.sleep(for: .milliseconds(300))
      finishOpening()
    } catch {
      // SwiftUI cancels this task on disappearance or a playback-context
      // change. The next context handles Reduce Motion / interruptions.
      return
    }
  }

  @MainActor
  private func finishOpening() {
    guard openingPhase != .complete else { return }
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      openingPhase = .complete
      onEntranceComplete()
    }
  }
}

// MARK: - Opening Animation

private struct TutorialOpeningPlayback: Equatable {
  let reduceMotion: Bool
  let scenePhase: ScenePhase
}

private enum TutorialOpeningPhase {
  case sun
  case cursorArrived
  case pressed
  case clicked
  case expanded
  case revealed
  case complete

}

/// The opening sun and the settled welcome artwork are the same view, with
/// the exact same destination geometry. Only the temporary cursor/ripple leave.
private struct TutorialWelcomeArtwork: View {
  let size: CGSize
  let finalRadius: CGFloat
  let phase: TutorialOpeningPhase

  @Environment(\.tutorialPalette) private var palette

  var body: some View {
    let initialRadius = min(46, size.width * 0.12)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let radius =
      (phase == .expanded || phase == .revealed || phase == .complete)
      ? finalRadius
      : initialRadius * (phase == .pressed ? 0.91 : 1)
    let sunCenter =
      (phase == .expanded || phase == .revealed || phase == .complete)
      ? CGPoint(x: size.width - finalRadius * 0.36, y: finalRadius * 0.42)
      : center

    ZStack(alignment: .topLeading) {
      Circle()
        .fill(palette.dotSun)
        .frame(width: radius * 2, height: radius * 2)
        .position(sunCenter)

      if phase != .complete {
        Circle()
          .stroke(palette.dotSun, lineWidth: 2)
          .frame(width: initialRadius * 2, height: initialRadius * 2)
          .scaleEffect(phase == .clicked ? 1.6 : 0.9)
          .opacity(phase == .pressed ? 0.5 : 0)
          .position(center)

        Image(systemName: "location.fill")
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(palette.titleText)
          .frame(width: initialRadius * 1.42, height: initialRadius * 1.42)
          // Scaling around its tip keeps the cursor on the sun as
          // it presses, matching the overlapping app-icon motif.
          .scaleEffect(phase == .pressed ? 0.84 : 1, anchor: .topTrailing)
          .rotationEffect(.degrees(phase == .sun ? -18 : 0))
          .position(
            phase == .sun
              ? CGPoint(x: -initialRadius * 2, y: size.height + initialRadius * 2)
              : CGPoint(x: center.x - initialRadius * 0.70, y: center.y + initialRadius * 0.72)
          )
          .opacity(
            phase == .sun
              || phase == .expanded
              || phase == .revealed
              || phase == .complete
              ? 0 : 1
          )
          .animation(
            .easeOut(duration: 0.16),
            value: phase == .expanded
              || phase == .revealed
              || phase == .complete
          )
      }
    }
    .frame(width: size.width, height: size.height)
  }
}

/// Location state remains owned by the flow, keeping this page previewable.
struct TutorialLocationStage: View {
  let isRequestingDeviceLocation: Bool
  let deviceLocationMessage: LocalizedStringKey?
  let useCurrentLocation: () -> Void
  let chooseHomeLocation: () -> Void

  @Environment(\.tutorialPalette) private var palette

  var body: some View {
    TutorialStageLayout(
      step: .location,
      deviceLocationMessage: deviceLocationMessage
    ) {
      VStack(spacing: 12) {
        Button("Choose Home Location", action: chooseHomeLocation)
          .buttonStyle(TutorialSecondaryButtonStyle())
          .disabled(isRequestingDeviceLocation)

        Button(action: useCurrentLocation) {
          HStack(spacing: 10) {
            if isRequestingDeviceLocation {
              ProgressView()
                .tint(palette.background)
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
      }
    }
  }
}

/// Both pages share the same upper artwork and text anchors. Footer height
/// does not move the introduction, and compact layouts scroll above the actions.
private struct TutorialStageLayout<Actions: View>: View {
  let step: TutorialStep
  var deviceLocationMessage: LocalizedStringKey?
  var openingPhase: TutorialOpeningPhase = .complete
  @ViewBuilder let actions: () -> Actions

  @Environment(\.tutorialPalette) private var palette
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    GeometryReader { geometry in
      let columnWidth =
        horizontalSizeClass == .regular
          && geometry.size.width > geometry.size.height
        ? min(480, AppContentLayout.landscapeIPadMaximumWidth)
        : 480
      // Keep the heading at the same height on both pages, reserving
      // room for the longer location copy and its two bottom actions.
      let textTop = min(
        geometry.size.height * 0.43,
        max(104, geometry.size.height - 410)
      )

      VStack(spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            titleSlot

            Text(step.message)
              .font(.body)
              .foregroundStyle(palette.secondaryText)
              .lineSpacing(4)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)

            if let deviceLocationMessage {
              Label(deviceLocationMessage, systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(palette.titleText)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.top, textTop)
          .padding(.horizontal, 32)
          .padding(.bottom, 20)
          .frame(maxWidth: columnWidth)
          .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)

        VStack(spacing: 24) {
          actions()
          pageProgress
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: columnWidth)
        .frame(maxWidth: .infinity)
      }
      .opacity(
        openingPhase == .revealed || openingPhase == .complete ? 1 : 0
      )
      .offset(
        y: openingPhase == .revealed || openingPhase == .complete
          ? 0
          : 14
      )
      .accessibilityHidden(
        openingPhase != .revealed && openingPhase != .complete
      )
      .background {
        GeometryReader { artworkGeometry in
          clippedArtwork(
            in: artworkGeometry.size,
            titleTop: textTop + geometry.safeAreaInsets.top
          )
        }
        .ignoresSafeArea()
      }
    }
    .background(palette.background.ignoresSafeArea())
  }

  /// Decorative artwork bleeds beyond the viewport instead of taking up a
  /// slot in the text layout. Compact screens reduce it to keep copy clear.
  private func clippedArtwork(in size: CGSize, titleTop: CGFloat) -> some View {
    let radius = min(size.width * 0.56, max(48, (titleTop - 48) / 1.42))

    return Group {
      switch step {
      case .welcome:
        TutorialWelcomeArtwork(size: size, finalRadius: radius, phase: openingPhase)
      case .location:
        Image(systemName: "location.fill")
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.monochrome)
          .foregroundStyle(palette.dotSun)
          .frame(width: radius * 1.6, height: radius * 1.6)
          .position(x: size.width - radius * 0.20, y: radius * 0.72)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .clipped()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Measure both localized titles so their body text begins on the same
  /// baseline, including when translations or Dynamic Type need more room.
  private var titleSlot: some View {
    ZStack(alignment: .topLeading) {
      ForEach(TutorialStep.allCases) { candidate in
        Text(
          candidate == .welcome
            ? "Welcome to Weather Atlas"
            : "Set your location"
        )
        .hidden()
        .accessibilityHidden(true)
      }

      Text(
        step == .welcome
          ? "Welcome to Weather Atlas"
          : "Set your location"
      )
      .foregroundStyle(palette.titleText)
      .accessibilityAddTraits(.isHeader)
    }
    .font(.system(.title, design: .serif).weight(.bold))
    .lineLimit(1)
    .minimumScaleFactor(0.68)
    .allowsTightening(true)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var pageProgress: some View {
    HStack(spacing: 12) {
      ForEach(TutorialStep.allCases) { candidate in
        Circle()
          .fill(candidate == step ? palette.titleText : palette.dotCloudy)
          .frame(width: 8, height: 8)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Tutorial progress")
    .accessibilityValue("Page \(step.rawValue + 1) of \(TutorialStep.allCases.count)")
  }
}

// MARK: - Home Location Search

/// A focused city search used only to establish the persistent home location.
/// It resolves provider results before accepting them, so tutorial setup never
/// stores an incomplete place or a free-form string as geographic data.
private struct TutorialHomeLocationPicker: View {
  // MARK: - Inputs and Search State

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
  /// A localization key is retained until display so the picker follows the
  /// app's in-view locale instead of treating the English source as verbatim.
  @State private var selectionMessage: LocalizedStringKey?

  // MARK: - Presentation

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
          ({ () -> Void in

            selectionGeneration &+= 1
            selectionTask?.cancel()
            selectionTask = nil
            loadingID = nil
            selectionMessage = nil
          })()
        }
        .onDisappear {
          ({ () -> Void in

            selectionGeneration &+= 1
            selectionTask?.cancel()
            selectionTask = nil
            loadingID = nil
            selectionMessage = nil
          })()
        }
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            CloseButton(action: dismiss.callAsFunction)
          }
        }
    }
  }

  // MARK: - Search Results

  @ViewBuilder
  private var pickerContent: some View {
    if normalizedQuery.isEmpty {
      ContentUnavailableView(
        "Search for your home location",
        systemImage: "house",
        description: Text("Choose a city to use as your location in Weather Atlas.")
      )
    } else if (!isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching)
      && (searchManager.appleResults.isEmpty && searchManager.openMeteoResults.isEmpty)
    {
      ProgressView("Searching…")
    } else if !(!isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching)
      && (searchManager.appleResults.isEmpty && searchManager.openMeteoResults.isEmpty)
      && searchManager.appleErrorMessage == nil
      && searchManager.openMeteoErrorMessage == nil
    {
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
    if !results.isEmpty
      || (!isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching)
      || errorMessage != nil
    {
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

        if !isSettled || searchManager.isAppleSearching || searchManager.isOpenMeteoSearching {
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
        ({ () -> Void in

          guard !normalizedQuery.isEmpty else { return }
          ({ () -> Void in

            selectionGeneration &+= 1
            selectionTask?.cancel()
            selectionTask = nil
            loadingID = nil
            selectionMessage = nil
          })()
          isSettled = true
          searchManager.search(query: normalizedQuery, locale: locale)
        })()
      }
      .buttonStyle(.bordered)
      .tint(theme.colors.accent)
    }
    .padding(.vertical, 4)
  }

  // MARK: - Search State

  private var normalizedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Search Lifecycle

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

  @MainActor
  private func select(_ result: CitySearchResult) {
    ({ () -> Void in

      selectionGeneration &+= 1
      selectionTask?.cancel()
      selectionTask = nil
      loadingID = nil
      selectionMessage = nil
    })()
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
          normalizedQuery == submittedQuery
        else {
          return
        }
        let city = City(
          name: resolved.cityName,
          country: resolved.country,
          countryISO2Code: resolved.countryISO2Code,
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
          normalizedQuery == submittedQuery
        else {
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

  var message: LocalizedStringKey {
    switch self {
    case .savedPlaces:
      "Save cities you care about to compare their weather in one place."
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
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(
        tip == .savedPlaces
          ? "Keep places you care about"
          : "Explore Sun on a Map"
      )
      .font(.title3.weight(.bold))
      .foregroundStyle(
        (AppPalette.values(
          for: colorScheme == .light ? .dark : .light,
          contrast: colorSchemeContrast
        )).titleText)

      Text(tip.message)
        .font(.body)
        .foregroundStyle(
          (AppPalette.values(
            for: colorScheme == .light ? .dark : .light,
            contrast: colorSchemeContrast
          )).titleText.opacity(0.84)
        )
        .fixedSize(horizontal: false, vertical: true)

      Button(action: dismiss) {
        Text("Done")
          .font(.headline.weight(.semibold))
          .foregroundStyle(
            colorSchemeContrast == .increased
              ? (AppPalette.values(for: .light, contrast: colorSchemeContrast)).background
              : (AppPalette.values(for: .light, contrast: colorSchemeContrast)).titleText
          )
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(
            colorSchemeContrast == .increased
              ? (AppPalette.values(for: .light, contrast: colorSchemeContrast)).titleText
              : (AppPalette.values(for: .light, contrast: colorSchemeContrast)).dotSun,
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
      (AppPalette.values(
        for: colorScheme == .light ? .dark : .light,
        contrast: colorSchemeContrast
      )).background,
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

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  var body: some View {
    ZStack {
      if let tip,
        (tip == .savedPlaces ? AppTab.savedPlaces : .map) == tab,
        isSelected
      {
        Color.black.opacity(
          reduceTransparency ? 0.72 : 0.28
        )
        .ignoresSafeArea()

        TutorialFeatureTipCard(tip: tip, dismiss: dismiss)
          .padding(.horizontal, 24)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(reduceMotion ? nil : .smooth, value: isSelected)
    .animation(reduceMotion ? nil : .smooth, value: tip)
  }
}

// MARK: - Tutorial Presentation State

/// Shared app-level state for first-run completion, tutorial replay, and the
/// one-time Saved Places and Map explanations. Persisting here keeps all
/// tutorial behaviour in one file while `ContentView` remains a thin host.
@MainActor
@Observable
final class TutorialPresentationState {
  // MARK: - Persistence Keys

  private enum StorageKey {
    static let completed = "hasCompletedOnboarding"
    static let replay = "shouldReplayTutorial"
    static let savedPlacesTipSeen = "hasSeenSavedPlacesTutorialTip"
    static let mapTipSeen = "hasSeenMapTutorialTip"
  }

  // MARK: - Persisted Presentation State

  @ObservationIgnored let defaults: UserDefaults

  var hasCompleted: Bool
  var isReplaying: Bool
  private(set) var hasSeenSavedPlacesTip: Bool
  private(set) var hasSeenMapTip: Bool
  private(set) var activeFeatureTip: TutorialFeatureTip?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    hasCompleted = defaults.object(forKey: StorageKey.completed) as? Bool ?? false
    isReplaying = defaults.object(forKey: StorageKey.replay) as? Bool ?? false
    hasSeenSavedPlacesTip =
      defaults.object(
        forKey: StorageKey.savedPlacesTipSeen
      ) as? Bool ?? false
    hasSeenMapTip = defaults.object(forKey: StorageKey.mapTipSeen) as? Bool ?? false
  }

  // MARK: - Full Tutorial Lifecycle

  var shouldPresent: Bool {
    !hasCompleted || isReplaying
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

  // MARK: - Contextual Tip Lifecycle

  /// Schedules the tip for a just-opened tab only when no native data alert
  /// is visible. This prevents instructional copy from being obscured.
  func presentFeatureTipIfNeeded(
    for tab: AppTab,
    hasActiveNativeAlert: Bool
  ) {
    // A card belongs only to the tab that introduced it. Switching tabs
    // hides it without recording a dismissal, so returning to that tab
    // shows the same explanation again until the person taps Done.
    if let currentTip = activeFeatureTip,
      (currentTip == .savedPlaces ? AppTab.savedPlaces : .map) != tab
    {
      activeFeatureTip = nil
    }

    guard activeFeatureTip == nil,
      !shouldPresent,
      !hasActiveNativeAlert
    else {
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
  @Environment(\.tutorialPalette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(palette.background)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 18)
      .background(palette.titleText, in: .rect(cornerRadius: 18))
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(
        reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1)
      )
      .animation(
        reduceMotion ? nil : .smooth,
        value: configuration.isPressed
      )
  }
}

private struct TutorialSecondaryButtonStyle: ButtonStyle {
  @Environment(\.tutorialPalette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accessibilityReduceTransparency)
  private var reduceTransparency

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(palette.titleText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 17)
      .background(
        reduceTransparency
          ? palette.background
          : palette.background.opacity(0.55),
        in: .rect(cornerRadius: 18)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .strokeBorder(
            palette.titleText.opacity(0.18),
            lineWidth: 1
          )
      }
      .opacity(configuration.isPressed ? 0.72 : 1)
      .scaleEffect(
        reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1)
      )
      .animation(
        reduceMotion ? nil : .smooth,
        value: configuration.isPressed
      )
  }
}

// MARK: - Xcode Previews

#if DEBUG

  // MARK: - Full-Screen Stages

  #Preview("Tutorial – Opening Animation", traits: .fixedLayout(width: 390, height: 844)) {
    TutorialWelcomeStage(animatesEntrance: true, continueAction: {})
      .preferredColorScheme(.light)
  }

  #Preview("Tutorial – Welcome", traits: .fixedLayout(width: 390, height: 844)) {
    TutorialWelcomeStage(continueAction: {})
      .preferredColorScheme(.light)
  }

  #Preview("Tutorial – Large Text", traits: .fixedLayout(width: 320, height: 568)) {
    TutorialWelcomeStage(continueAction: {})
      .dynamicTypeSize(.accessibility3)
      .preferredColorScheme(.light)
  }

  #Preview("Tutorial – Select Location", traits: .fixedLayout(width: 390, height: 844)) {
    TutorialLocationStage(
      isRequestingDeviceLocation: false,
      deviceLocationMessage: nil,
      useCurrentLocation: {},
      chooseHomeLocation: {}
    )
    .background(AppPalette.light.background)
    .preferredColorScheme(.light)
  }

  // MARK: - Contextual Tip Hosts

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

  // MARK: - Preview Dependencies

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
      let weatherStore = SavedPlacesWeatherStore(
        weatherService: WeatherService(),
        cache: PlaceWeatherSnapshotCache(fileURL: nil),
        networkConnectivity: networkConnectivity
      )
      model = WeatherModel(
        placesStore: placesStore,
        weatherStore: weatherStore,
        locationProvider: LocationProvider(),
        recentSearches: RecentSearchStore(inMemoryCities: []),
        initialHomeLocation: nil
      )
    }
  }
#endif
