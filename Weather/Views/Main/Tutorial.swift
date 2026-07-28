//
//  Tutorial.swift
//  Weather
//
//  Purpose: Presents onboarding and owns the selection state and app actions
//  that turn first-run continent or country choices into persisted lists.
//

import SwiftUI
import UIKit

// MARK: - Presentation State

/// First-launch and replay selections owned by the tutorial flow.
struct TutorialPresentationState {
    /// Whether first-install onboarding covers the app.
    var showsFirstLaunch = false
    /// Whether the user explicitly replayed onboarding from Settings.
    var showsReplay = false
    /// Built-in continent sources selected during first-run setup.
    var selectedContinentIDs: Set<String> = []
    /// Reserved country selections for future multi-list onboarding.
    var selectedCountryIDs: Set<String> = []
}

// MARK: - Full-Screen Tutorial

/// Full-screen onboarding and replay flow with optional first-list creation.
struct TutorialView: View {
    /// Whether this run includes the first-list selection page.
    let includesListSelection: Bool
    /// Canonical continent sources offered during first-run setup.
    let continentLists: [CityListID]
    /// Fraction of initial list weather creation completed.
    let creationProgress: Double
    /// Async callback creating and selecting a continent list.
    let onSelectContinentList: (CityListID) async -> Void
    /// Async callback creating and selecting a country list.
    let onSelectCountryList: (CountryListOption) async -> Void
    /// Callback completing or dismissing the tutorial.
    let onFinish: () -> Void
    /// Optional replay-only cancel callback.
    var onCancel: (() -> Void)?
    /// Page seeded by previews and specialized presentations.
    var initialPage: Int = 0
    /// Whether previews should begin in creation-progress state.
    var initialIsCreatingList: Bool = false
    /// Optional list name shown by an initial creation state.
    var initialCreatingListName: String? = nil

    /// Active theme manager and semantic palette.
    @Environment(\.appTheme) private var theme
    /// Resolved appearance used by tutorial contrast choices.
    @Environment(\.colorScheme) private var colorScheme
    /// App-selected locale used throughout onboarding.
    @Environment(\.locale) private var locale
    /// Width class controlling phone/iPad layout.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Text category controlling reserved footer layout.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Contrast preference controlling page dots and surfaces.
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    /// Zero-based active tutorial page.
    @State private var page = 0
    /// Whether the continent picker is presented.
    @State private var showingContinentSearch = false
    /// Whether the country picker is presented.
    @State private var showingCountrySearch = false
    /// Query filtering countries inside the tutorial picker.
    @State private var countrySearchText = ""
    /// Whether list creation progress has replaced selection content.
    @State private var isCreatingList = false
    /// Name shown while the selected list is being created.
    @State private var creatingListName: String?
    /// Guards one-time application of preview/initial state.
    @State private var didApplyInitialState = false

    // MARK: Page State

    /// Total page count for onboarding or tutorial replay.
    private var pageCount: Int {
        includesListSelection ? 3 : 2
    }

    /// Builds paged content, modal pickers, and the persistent tutorial footer.
    var body: some View {
        ZStack {
            // Use the branded palette background on every tutorial page.
            introColors.background
                .ignoresSafeArea()

            tutorialPages
            .disabled(isCreatingList)

            // Keep the original overlay footer at compact text sizes. Larger text
            // reserves real layout space so the final onboarding row cannot sit
            // behind the page controls in a short landscape window.
            if !usesReservedFooterLayout {
                VStack {
                    Spacer()
                    tutorialFooter
                        .padding(.horizontal, 24)
                        .frame(maxWidth: tutorialContentMaxWidth)
                        .padding(.bottom, 28)
                }
            }
        }
        // Reserve real layout space for controls once text grows beyond the
        // default size, including the app's capped Extra Large setting.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesReservedFooterLayout {
                tutorialFooter
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .frame(maxWidth: tutorialContentMaxWidth)
                    .frame(maxWidth: .infinity)
                    .background(introColors.background)
            }
        }
        .sheet(isPresented: $showingContinentSearch) {
            tutorialPickerPresentation(
                ContinentListPickerContent(
                    lists: continentLists,
                    onSelect: { listID in
                        // Dismiss the picker and begin continent-list creation.
                        showingContinentSearch = false
                        creatingListName = listID.canonicalLocalizedDisplayName(locale: locale)
                        startCreatingList {
                            await onSelectContinentList(listID)
                        }
                    }
                )
            )
        }
        .sheet(isPresented: $showingCountrySearch) {
            let countries = CountryCityCatalog.countries(locale: locale)
            let query = countrySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            // Match localized and English names as well as ISO codes.
            let filteredCountries = query.isEmpty ? countries : countries.filter {
                $0.localizedName(locale: locale).localizedCaseInsensitiveContains(query)
                    || $0.englishName.localizedCaseInsensitiveContains(query)
                    || $0.iso2.localizedCaseInsensitiveContains(query)
            }
            tutorialPickerPresentation(
                CountryListPickerContent(
                    countries: filteredCountries,
                    searchBar: CountrySearchField(text: $countrySearchText),
                    onSelect: { country in
                        // Dismiss the picker and begin country-list creation.
                        showingCountrySearch = false
                        creatingListName = country.localizedName(locale: locale)
                        startCreatingList {
                            await onSelectCountryList(country)
                        }
                    }
                )
                .onAppear {
                    countrySearchText = ""
                }
            )
        }
        .interactiveDismissDisabled(isCreatingList)
        .onAppear {
            // Apply preview/test seed values only once.
            guard !didApplyInitialState else { return }
            didApplyInitialState = true
            page = min(max(initialPage, 0), pageCount - 1)
            isCreatingList = initialIsCreatingList
            creatingListName = initialCreatingListName
        }
    }

    /// Whether larger text requires content space reserved above the footer.
    private var usesReservedFooterLayout: Bool {
        dynamicTypeSize > .large
    }

    // MARK: Page Routing

    @ViewBuilder
    /// Builds the non-scrollable horizontal page container.
    private var tutorialPages: some View {
        if dynamicTypeSize > .large {
            // UIPageViewController's horizontal pan gesture can prevent the nested
            // vertical ScrollView from moving on large-text iPad layouts. The footer
            // already provides explicit paging, so use a direct page container here.
            currentTutorialPage
                .id(page)
                .transition(.opacity)
        } else {
            TabView(selection: $page) {
                welcomePage
                    .tag(0)

                stepsPage
                    .tag(1)

                if includesListSelection {
                    listSelectionPage
                        .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    @ViewBuilder
    /// Selects welcome, feature steps, or first-list setup for the active index.
    private var currentTutorialPage: some View {
        switch page {
        case 0:
            welcomePage
        case 1:
            stepsPage
        default:
            if includesListSelection {
                listSelectionPage
            } else {
                stepsPage
            }
        }
    }

    // MARK: Adaptive Layout

    /// Whether device-specific tutorial spacing should use iPad values.
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Main action fill selected for the active tutorial page.
    private var primaryButtonColor: Color {
        introColors.sunIconColor
    }

    /// Foreground guaranteed legible on the primary button fill.
    private var primaryButtonTextColor: Color {
        colorScheme == .dark ? introColors.background : introColors.primaryText
    }

    // MARK: Picker Presentation

    /// Presents a picker as an adaptive sheet with tutorial theme treatment.
    private func tutorialPickerPresentation<Content: View>(
        _ content: Content
    ) -> some View {
        content
            // iPad: Use form sizing in regular-width windows and phone detents elsewhere.
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

    /// Semantic palette used over the branded intro background.
    private var introColors: ThemeColors {
        theme.colors
    }

    /// Page horizontal inset adapted to device width.
    private var tutorialHorizontalPadding: CGFloat {
        28
    }

    // iPad: Keep onboarding copy and controls comfortably readable without
    // shrinking the full-screen artwork behind them.
    /// Maximum readable width for tutorial copy and controls.
    private var tutorialContentMaxWidth: CGFloat {
        680
    }

    // The normal footer overlays the pages, so scrollable page content reserves
    // enough space beneath its last meaningful element. Larger text uses a
    // safe-area footer and therefore needs only a small breathing space.
    /// Reserved vertical space preventing content from entering the footer.
    private var tutorialFooterClearance: CGFloat {
        usesReservedFooterLayout ? 24 : 128
    }

    /// Display font selected for current device and text category.
    private var tutorialTitle: Font {
        .system(.largeTitle, design: .serif, weight: .bold)
    }

    // The page footer is an overlay at normal Dynamic Type sizes. Limit the
    // iPad scene's downward shift in shorter windows so the subtitle always
    // clears the page indicator instead of scrolling beneath it.
    /// Positions the welcome illustration within varying safe-area heights.
    private func welcomeSceneOffset(for size: CGSize) -> CGFloat {
        guard isIPad else { return 0 }

        let preferredOffset: CGFloat = 150
        let minimumSubtitleToPagerGap: CGFloat = 36
        let pagerTop = size.height - 107
        let subtitleBottomBeforeOffset = (size.height * 0.58) + 94
        let availableOffset = pagerTop - subtitleBottomBeforeOffset - minimumSubtitleToPagerGap

        return min(preferredOffset, max(0, availableOffset))
    }

    // MARK: Welcome Page

    /// Builds branded illustration and introductory copy.
    private var welcomePage: some View {
        GeometryReader { proxy in
            let usesCompactIPadArtworkPosition = isIPad
                && max(proxy.size.width, proxy.size.height) < 1_250
            let artworkVerticalOffset: CGFloat = usesCompactIPadArtworkPosition ? 36 : 28
            let usesIPadLandscapeArtwork = isIPad && proxy.size.width > proxy.size.height
            let introGraphicName = usesIPadLandscapeArtwork
                ? "IntroGraphicsLandscape"
                : "IntroGraphics"
            let sceneOffset = welcomeSceneOffset(for: proxy.size)

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    Group {
                        if isIPad {
                            // Keep the same fill scale. The compact-iPad nudge keeps
                            // the globe's rounded top below the landscape viewport edge.
                            ZStack {
                                Image(introGraphicName)
                                    .resizable()
                                    .frame(
                                        width: proxy.size.width,
                                        // Preserve the welcome illustration's native ratio.
                                        height: proxy.size.width / (1_179.0 / 2_556.0)
                                    )
                                    .offset(y: artworkVerticalOffset)
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        } else {
                            Image("IntroGraphics")
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .clipped()
                        }
                    }
                    .ignoresSafeArea()

                    // iPad: Keep the standard artwork composition, but make the copy
                    // scrollable when a landscape or resized window is too short.
                    ScrollView {
                        welcomePageText(
                            topSpacing: proxy.size.height * 0.58
                        )
                        .frame(minHeight: proxy.size.height, alignment: .top)
                        .frame(maxWidth: tutorialContentMaxWidth)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
                // iPad: Shift the complete welcome scene so its artwork and copy keep
                // their intended relationship while moving down together. Shorter
                // windows use the largest safe offset before the pager.
                .offset(y: sceneOffset)

            }
        }
    }

    /// Builds the welcome title and subtitle with supplied scene clearance.
    private func welcomePageText(topSpacing: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: topSpacing)

            Text(localizedString("Welcome to Weather Atlas", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 28)

            Text(
                "\(localizedString("Find sunny destinations and", locale: locale)) \(localizedString("plan ahead for your next holiday.", locale: locale))"
            )
            .font(.title3)
            .foregroundStyle(introColors.primaryText.opacity(0.64))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.top, 24)

            Spacer(minLength: tutorialFooterClearance)
        }
    }

    // MARK: Steps Page

    /// Builds the feature explanation page in narrow or wide layout.
    private var stepsPage: some View {
        GeometryReader { proxy in
            // On iPad, the page retains its portrait composition
            // whenever it fits and becomes vertically scrollable in short windows.
            ScrollView(.vertical) {
                stepsPageContent(
                    usesWideStepLayout: isIPad
                        && proxy.size.width > proxy.size.height
                        && dynamicTypeSize > .large
                )
                    // Force the scroll view to measure every wrapped step at its
                    // full intrinsic height before applying the viewport minimum.
                    // Without this, the page-style TabView can compress the final
                    // step out of the visible/scrollable area in short iPad windows.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                    .frame(maxWidth: tutorialContentMaxWidth)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            .defaultScrollAnchor(.top)
        }
    }

    /// Composes tutorial feature steps for stacked or side-by-side presentation.
    private func stepsPageContent(usesWideStepLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            // Preserve room above the page for the optional cancel control.
            Color.clear
                .frame(height: 62)

            Text(localizedString("How Weather Atlas Works", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if usesWideStepLayout {
                    HStack(alignment: .top, spacing: 14) {
                        tutorialStep(
                            number: 1,
                            title: localizedString("Build your travel list", locale: locale),
                            subtitle: localizedString("Add the places you are planning to visit.", locale: locale)
                        )
                        tutorialStep(
                            number: 2,
                            title: localizedString("See when each place shines", locale: locale),
                            subtitle: localizedString("Stop opening forecasts one by one.", locale: locale)
                        )
                        tutorialStep(
                            number: 3,
                            title: localizedString("Visualise weather on a map", locale: locale),
                            subtitle: localizedString("Discover weather patterns across your saved places.", locale: locale)
                        )
                    }
                } else {
                    VStack(spacing: 22) {
                        tutorialStep(
                            number: 1,
                            title: localizedString("Build your travel list", locale: locale),
                            subtitle: localizedString("Add the places you are planning to visit.", locale: locale)
                        )
                        tutorialStep(
                            number: 2,
                            title: localizedString("See when each place shines", locale: locale),
                            subtitle: localizedString("Stop opening forecasts one by one.", locale: locale)
                        )
                        tutorialStep(
                            number: 3,
                            title: localizedString("Visualise weather on a map", locale: locale),
                            subtitle: localizedString("Discover weather patterns across your saved places.", locale: locale)
                        )
                    }
                }
            }
            .padding(.top, 12)

            Spacer()
            Spacer(minLength: tutorialFooterClearance)
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    /// Builds one numbered feature explanation row/card.
    private func tutorialStep(number: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                // Keep step numbers legible on the bright button fill in both
                // light and dark Increased Contrast appearances.
                .foregroundStyle(primaryButtonTextColor)
                .frame(width: 34, height: 34)
                .background(primaryButtonColor, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(introColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(introColors.primaryText.opacity(0.62))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(introColors.listCardFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(introColors.secondaryText.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: List Selection Pages

    @ViewBuilder
    /// Selects list-creation progress or the first-list source picker.
    private var listSelectionPage: some View {
        if isCreatingList {
            creatingListPage
        } else {
            GeometryReader { proxy in
                // The selection remains usable in iPad landscape,
                // Split View, and large text without changing the normal hierarchy.
                ScrollView {
                    listSelectionPageContent
                        .frame(minHeight: proxy.size.height, alignment: .top)
                        .frame(maxWidth: tutorialContentMaxWidth)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// Composes introductory copy and continent/country source cards.
    private var listSelectionPageContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Preserve room above the page for the optional cancel control.
            Color.clear
                .frame(height: 62)

            Text(localizedString("Let's add your first city list", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

            (
                Text(localizedString("Pick a place and we'll create a list of ", locale: locale))
                    + Text(localizedString("15 largest cities", locale: locale))
                        .fontWeight(.bold)
                        .underline(color: introColors.dotSun)
                    + Text(localizedString(" for you.", locale: locale))
            )
            .font(.body)
            .foregroundStyle(introColors.primaryText.opacity(0.64))
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 18)

            VStack(spacing: 16) {
                tutorialNewListOptionCard(
                    title: localizedString("Pick a Continent", locale: locale),
                    systemImage: "globe.europe.africa"
                ) {
                    showingContinentSearch = true
                }

                tutorialNewListOptionCard(
                    title: localizedString("Pick a Country", locale: locale),
                    systemImage: "flag"
                ) {
                    countrySearchText = ""
                    showingCountrySearch = true
                }
            }

            Spacer(minLength: tutorialFooterClearance)
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    /// Builds a sunny-colored first-list source card.
    private func tutorialNewListOptionCard(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        NewOptionButton(
            title: title,
            subtitle: nil,
            systemImage: systemImage,
            titleWeight: .medium,
            titleColor: primaryButtonTextColor,
            showsIconBackground: false,
            iconColor: primaryButtonTextColor,
            action: action
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(introColors.dotSun, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                // Increase Contrast gives these primary actions a stronger outline.
                .stroke(
                    introColors.secondaryText.opacity(colorSchemeContrast == .increased ? 1 : 0.24),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 1
                )
        }
    }

    // MARK: List Creation Progress

    /// Builds progress feedback while the initial list and weather are created.
    private var creatingListPage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    // iPad: Flexible spacers replace the former fixed 260-point
                    // offset, keeping progress centred across portrait, landscape,
                    // Split View, and larger text sizes.
                    Spacer(minLength: 40)

                    VStack(spacing: 18) {
                        // Incorporate the selected list name when one is available.
                        Text(
                            creatingListName.map {
                                "\(localizedString("Creating a list of 15 cities in", locale: locale)) \($0)"
                            } ?? localizedString("Creating a list of 15 cities", locale: locale)
                        )
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(introColors.primaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)

                        ProgressView(value: min(max(creationProgress, 0), 1))
                            .tint(primaryButtonColor)
                            .frame(width: 240)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, tutorialHorizontalPadding)
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: tutorialContentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Footer

    /// Builds the pinned page dots and primary/cancel controls.
    private var tutorialFooter: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        // Full opacity meets the increased-contrast non-text threshold.
                        .fill(
                            index == page
                                ? primaryButtonColor
                                : introColors.secondaryText.opacity(colorSchemeContrast == .increased ? 1 : 0.7)
                        )
                        .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
                        .animation(.smooth(duration: 0.18), value: page)
                }
            }

            if !isCreatingList {
                tutorialFooterButtons
            }
        }
    }

    /// Builds the context-sensitive tutorial action buttons.
    private var tutorialFooterButtons: some View {
        HStack(spacing: 12) {
            if let onCancel {
                Button(localizedString("Cancel", locale: locale)) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(introColors.accent)
                .foregroundStyle(introColors.primaryText)
                .controlSize(.large)
            }

            if !(includesListSelection && page == pageCount - 1) {
                Button {
                    // Advance one page or complete the final tutorial page.
                    if page < pageCount - 1 {
                        withAnimation(.smooth(duration: 0.2)) {
                            page += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(
                        page < pageCount - 1
                            ? localizedString("Continue", locale: locale)
                            : localizedString("Done", locale: locale)
                    )
                        .font(.body.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryButtonColor)
                .foregroundStyle(primaryButtonTextColor)
                .controlSize(.large)
            }
        }
    }

    // MARK: Tutorial Actions

    /// Enters progress state, runs creation, then completes onboarding.
    private func startCreatingList(_ action: @escaping () async -> Void) {
        guard !isCreatingList else { return }
        isCreatingList = true
        withAnimation(.smooth(duration: 0.22)) {
            page = 2
        }

        Task {
            await action()
            await MainActor.run {
                isCreatingList = false
            }
        }
    }

}

// MARK: - Tutorial List Selection

extension ContentView {
    /// Replaces the built-in list selection, creates any selected country
    /// lists, and performs the first weather load before dismissing onboarding.
    func applyTutorialListSelectionAndLoad() async {
        let selectedContinentIDs = tutorialState.selectedContinentIDs
        let selectedCountryIDs = tutorialState.selectedCountryIDs
        guard !selectedContinentIDs.isEmpty || !selectedCountryIDs.isEmpty else { return }
        let selectedLists = CityListID.builtInLists.filter { selectedContinentIDs.contains($0.rawValue) }

        CityListID.keepBuiltInLists(withRawValues: selectedContinentIDs)
        refreshListOrder()
        navigationPath = []

        var firstList = selectedLists.first
        let selectedCountries = CountryCityCatalog.countries(locale: locale).filter {
            selectedCountryIDs.contains($0.id)
        }

        for country in selectedCountries {
            let identity = CityListID.availableGeneratedListIdentity(
                for: .country(iso2: country.iso2, duplicateIndex: nil),
                locale: locale
            )
            let listID = await weatherService.createCustomList(
                name: identity.displayName,
                cities: CountryCityCatalog.topCities(for: country),
                nameSource: identity.nameSource
            )
            if firstList == nil {
                firstList = listID
            }
        }

        if let firstList {
            if firstList.rawValue == weatherService.activeListID.rawValue {
                await weatherService.fetchWeatherForAllCities()
            } else {
                await switchToList(firstList)
            }
        }

        refreshListOrder()
        centerMapOnDots()

        if !mapCities.isEmpty {
            await refreshCitiesMissingDaytimeSunninessData()
        }

        hasCompletedInitialWeatherLoad = true
        hasLaunchedBefore = true
        tutorialState.showsFirstLaunch = false
    }
}

// MARK: - Preview Support

/// Lightweight wrapper configuring tutorial-only Xcode previews.
private struct TutorialPreviewContent: View {
    /// Whether the preview starts on list-creation progress.
    let startsCreatingList: Bool

    /// Creates a normal or progress-state tutorial preview.
    init(startsCreatingList: Bool = false) {
        self.startsCreatingList = startsCreatingList
    }

    /// Builds a self-contained tutorial preview.
    var body: some View {
        TutorialView(
            includesListSelection: true,
            continentLists: CityListID.builtInLists,
            creationProgress: 0.42,
            onSelectContinentList: { _ in },
            onSelectCountryList: { _ in },
            onFinish: {},
            onCancel: nil,
            initialPage: startsCreatingList ? 2 : 0,
            initialIsCreatingList: startsCreatingList,
            initialCreatingListName: startsCreatingList
                ? CityListID.europe.localizedDisplayName()
                : nil
        )
        .environment(\.appTheme, AppTheme.shared)
    }
}

// MARK: - Previews

#Preview("Tutorial") {
    TutorialPreviewContent()
}

// Dedicated iPad welcome-page previews make the full-screen artwork and footer
// easy to inspect in both supported orientations without entering onboarding.
#Preview("Tutorial — iPad Portrait", traits: .fixedLayout(width: 834, height: 1_194)) {
    TutorialPreviewContent()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Tutorial — iPad Landscape", traits: .fixedLayout(width: 1_194, height: 834)) {
    TutorialPreviewContent()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("Tutorial Creating List") {
    TutorialPreviewContent(startsCreatingList: true)
}
