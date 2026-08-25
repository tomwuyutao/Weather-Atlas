//
//  FindSunButton.swift
//  Weather
//
//  Purpose: The compact Map Find Sun control and its complete native menu.
//

import CoreLocation
import SwiftUI
import UIKit

// MARK: - Find Sun Menu

/// A single compact control for all Find Sun entry points. Immediate searches
/// stay in the menu, while the country and continent catalogs open in a
/// dedicated picker that floats on iPad and remains full screen on iPhone.
struct FindSunButton: View {
    // MARK: - Inputs

    let currentLocationCoordinate: CLLocationCoordinate2D?
    let locale: Locale
    /// Parent-owned Map generation. Clear, a replacement query, and an
    /// external Map hand-off all advance it before a stale deferred action can
    /// mutate the newly established session.
    let sessionGeneration: Int
    let findSunHere: () -> Void
    let findSunNearMe: () -> Void
    let findSunInCountry: (CountryPlacesOption) -> Void
    let findSunInContinent: (ContinentPlacesOption) -> Void

    // MARK: - Deferred Selection State

    @State private var presentedPicker: GeographicPicker?
    @State private var pendingCommitTask: Task<Void, Never>?
    @State private var pendingCommitID = 0
    @State private var latestSessionGeneration = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Presentation

    var body: some View {
        pickerPresentation
            .onAppear {
                latestSessionGeneration = sessionGeneration
            }
            .onChange(of: sessionGeneration) { _, newGeneration in
                latestSessionGeneration = newGeneration
                presentedPicker = nil
                cancelPendingCommit()
            }
            .onDisappear {
                cancelPendingCommit()
            }
    }

    /// Full-screen presentation remains a focused phone experience. On iPad,
    /// native sheets are centered floating panels that keep the map visible
    /// behind the country or continent catalog.
    @ViewBuilder
    private var pickerPresentation: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            findSunMenu
                .sheet(item: $presentedPicker) { picker in
                    geographicPicker(for: picker)
                }
        } else {
            findSunMenu
                .fullScreenCover(item: $presentedPicker) { picker in
                    geographicPicker(for: picker)
                }
        }
    }

    private var findSunMenu: some View {
        Menu {
            Button(action: { runAfterMenuDismissal(findSunHere) }) {
                MapContextMenuLabel(
                    "This Area",
                    systemImage: thisAreaSystemImage
                )
            }
            Button(action: { runAfterMenuDismissal(findSunNearMe) }) {
                MapContextMenuLabel(
                    "Near Me",
                    systemImage: "location"
                )
            }

            Divider()

            Button {
                cancelPendingCommit()
                presentedPicker = .country
            } label: {
                MapContextMenuLabel("Country", systemImage: "flag")
            }

            Button {
                cancelPendingCommit()
                presentedPicker = .continent
            } label: {
                MapContextMenuLabel(
                    "Continent",
                    systemImage: "globe.europe.africa"
                )
            }
        } label: {
            Label("Find Sun", systemImage: "magnifyingglass")
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private func geographicPicker(
        for picker: GeographicPicker
    ) -> FindSunGeographicSearchSheet {
        FindSunGeographicSearchSheet(
            picker: picker,
            currentLocationCoordinate: currentLocationCoordinate,
            locale: locale,
            sessionGeneration: sessionGeneration,
            isSessionCurrent: isSessionCurrent,
            findSunInCountry: findSunInCountry,
            findSunInContinent: findSunInContinent
        )
    }

    private var thisAreaSystemImage: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    // MARK: - Deferred Menu Actions

    /// A system `Menu` finishes its collapse animation after its action has
    /// been invoked. Publishing the loading state in that same transaction
    /// briefly places the shrinking menu over the replacement MapCard. Yield
    /// until the menu is gone so the compact surface changes cleanly once.
    private func runAfterMenuDismissal(_ action: @escaping () -> Void) {
        cancelPendingCommit()
        let scheduledGeneration = sessionGeneration
        pendingCommitID &+= 1
        let commitID = pendingCommitID
        pendingCommitTask = Task { @MainActor in
            if reduceMotion {
                await Task.yield()
            } else {
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  commitID == pendingCommitID,
                  scheduledGeneration == latestSessionGeneration else {
                return
            }
            pendingCommitTask = nil
            action()
        }
    }

    private func cancelPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        pendingCommitID &+= 1
    }

    private func isSessionCurrent(_ generation: Int) -> Bool {
        generation == latestSessionGeneration
    }
}

// MARK: - Native Menu Labels

/// Native menus choose their own width. Force each descriptive label into one
/// compact line so unusually long localized place names never create a tall
/// context menu item.
struct MapContextMenuLabel: View {
    private let title: Text
    let systemImage: String

    /// Keeps literal menu titles as catalog keys instead of eagerly converting
    /// them to `String`, which would make `Text` render the English source.
    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    /// Dynamic city, country, and continent names have already been resolved
    /// for the active locale by their caller and must not be looked up again.
    init(resolved title: String, systemImage: String) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            title
                .lineLimit(1)
                .truncationMode(.tail)
                // Let UIKit measure the complete single-line title when it
                // chooses the native menu width; otherwise it can wrap this
                // label before the menu gets a chance to expand for it.
                .fixedSize(horizontal: true, vertical: false)
        } icon: {
            Image(systemName: systemImage)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Geographic Picker

/// The two catalog surfaces use dedicated navigation instead of nested menus:
/// countries can be searched, and both lists stay usable at every Dynamic Type
/// size.
private enum GeographicPicker: String, Identifiable {
    case country
    case continent

    var id: String { rawValue }
}

/// Catalog picker for broad Find Sun searches.
private struct FindSunGeographicSearchSheet: View {
    let picker: GeographicPicker
    let currentLocationCoordinate: CLLocationCoordinate2D?
    let locale: Locale
    let sessionGeneration: Int
    let isSessionCurrent: (Int) -> Bool
    let findSunInCountry: (CountryPlacesOption) -> Void
    let findSunInContinent: (ContinentPlacesOption) -> Void

    @State private var query = ""
    /// A row selection should start dismissal before it changes the Map's
    /// bottom surface. This prevents the presenting Find Sun control from
    /// being replaced while the catalog is still on screen.
    @State private var isCommittingSelection = false

    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var countries: [CountryPlacesOption] {
        let allCountries = CountryCityCatalog.countries(
            near: currentLocationCoordinate,
            locale: locale
        )
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return allCountries }
        return allCountries.filter {
            $0.localizedName(locale: locale)
                .localizedCaseInsensitiveContains(trimmedQuery)
                || $0.englishName.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                switch picker {
                case .country:
                    ForEach(countries) { country in
                        Button {
                            select(country)
                        } label: {
                            geographicPickerRow(
                                title: country.localizedName(locale: locale)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(theme.colors.settingsRowFill)
                case .continent:
                    ForEach(ContinentPlacesOption.allCases) { continent in
                        Button {
                            select(continent)
                        } label: {
                            geographicPickerRow(
                                title: continent.localizedName(locale: locale)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(theme.colors.settingsRowFill)
                }
            }
            .listStyle(.insetGrouped)
            .weatherScrollableBackground()
            .weatherContentColumn(standardMaximumWidth: .infinity)
            .weatherScreenBackground()
            .tint(theme.colors.accent)
            .navigationTitle(
                picker == .country
                    ? "Find Sun in a Country"
                    : "Find Sun in a Continent"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .modifier(CountrySearchModifier(isEnabled: picker == .country, query: $query))
        }
    }

    /// Broad geographic rows open the same result surface as their Search-tab
    /// counterparts, so they retain the standard trailing disclosure affordance.
    private func geographicPickerRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
        }
        .contentShape(.rect)
    }

    /// Begin native dismissal synchronously, then start the Map query on the
    /// following main-actor turn. The selector therefore leaves immediately,
    /// while Map receives its loading state before the dismissal reveals it.
    private func select(_ country: CountryPlacesOption) {
        guard !isCommittingSelection else { return }
        isCommittingSelection = true
        let committingGeneration = sessionGeneration
        dismiss()
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  isSessionCurrent(committingGeneration) else {
                return
            }
            findSunInCountry(country)
        }
    }

    private func select(_ continent: ContinentPlacesOption) {
        guard !isCommittingSelection else { return }
        isCommittingSelection = true
        let committingGeneration = sessionGeneration
        dismiss()
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  isSessionCurrent(committingGeneration) else {
                return
            }
            findSunInContinent(continent)
        }
    }
}

/// Keeps continent selection direct: its short fixed list should not display
/// a search field that cannot add useful filtering.
private struct CountrySearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, prompt: "Search countries")
        } else {
            content
        }
    }
}

#if DEBUG

// MARK: - Preview

#Preview("Find Sun Button", traits: .sizeThatFitsLayout) {
    FindSunButton(
        currentLocationCoordinate: CLLocationCoordinate2D(
            latitude: 51.5072,
            longitude: -0.1276
        ),
        locale: .current,
        sessionGeneration: 0,
        findSunHere: {},
        findSunNearMe: {},
        findSunInCountry: { _ in },
        findSunInContinent: { _ in }
    )
    .padding()
    .environment(\.appTheme, .shared)
}
#endif
