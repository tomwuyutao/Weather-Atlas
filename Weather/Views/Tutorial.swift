//
//  Tutorial.swift
//  Weather
//
//  Purpose: Presents first-launch onboarding, replayable app guidance, and the
//  continent-or-country list selection used when the app is opened fresh.
//

import SwiftUI
import UIKit

// MARK: - Full-Screen Tutorial

struct TutorialView: View {
    let includesListSelection: Bool
    let continentLists: [CityListID]
    let creationProgress: Double
    let onSelectContinentList: (CityListID) async -> Void
    let onSelectCountryList: (CountryListOption) async -> Void
    let onFinish: () -> Void
    var onCancel: (() -> Void)?
    var initialPage: Int = 0
    var initialIsCreatingList: Bool = false
    var initialCreatingListName: String? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var page = 0
    @State private var showingContinentSearch = false
    @State private var showingCountrySearch = false
    @State private var countrySearchText = ""
    @State private var isCreatingList = false
    @State private var creatingListName: String?
    @State private var didApplyInitialState = false

    // MARK: Page State

    private var pageCount: Int {
        includesListSelection ? 3 : 2
    }

    var body: some View {
        ZStack {
            tutorialBackground
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
                    .background(tutorialBackground)
            }
        }
        .sheet(isPresented: $showingContinentSearch) {
            tutorialPickerPresentation(tutorialContinentSearchSheet)
        }
        .sheet(isPresented: $showingCountrySearch) {
            tutorialPickerPresentation(tutorialCountrySearchSheet)
        }
        .interactiveDismissDisabled(isCreatingList)
        .onAppear {
            applyInitialStateIfNeeded()
        }
    }

    private var tutorialBackground: Color {
        introColors.background
    }

    private var usesReservedFooterLayout: Bool {
        dynamicTypeSize > .large
    }

    // MARK: Page Routing

    @ViewBuilder
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
                    tutorialListSelectionPage
                        .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    @ViewBuilder
    private var currentTutorialPage: some View {
        switch page {
        case 0:
            welcomePage
        case 1:
            stepsPage
        default:
            if includesListSelection {
                tutorialListSelectionPage
            } else {
                stepsPage
            }
        }
    }

    // MARK: Adaptive Layout

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var primaryButtonColor: Color {
        introColors.sunIconColor
    }

    private var primaryButtonTextColor: Color {
        colorScheme == .dark ? introColors.background : introColors.primaryText
    }

    // MARK: Picker Presentation

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

    private var introColors: ThemeColors {
        theme.colors
    }

    private var tutorialHorizontalPadding: CGFloat {
        28
    }

    // iPad: Keep onboarding copy and controls comfortably readable without
    // shrinking the full-screen artwork behind them.
    private var tutorialContentMaxWidth: CGFloat {
        680
    }

    // The normal footer overlays the pages, so scrollable page content reserves
    // enough space beneath its last meaningful element. Larger text uses a
    // safe-area footer and therefore needs only a small breathing space.
    private var tutorialFooterClearance: CGFloat {
        usesReservedFooterLayout ? 24 : 128
    }

    private var tutorialTopSpacer: CGFloat {
        62
    }

    private var tutorialTitle: Font {
        .system(.largeTitle, design: .serif, weight: .bold)
    }

    private let introGraphicsAspectRatio: CGFloat = 1_179.0 / 2_556.0

    // The page footer is an overlay at normal Dynamic Type sizes. Limit the
    // iPad scene's downward shift in shorter windows so the subtitle always
    // clears the page indicator instead of scrolling beneath it.
    private func welcomeSceneOffset(for size: CGSize) -> CGFloat {
        guard isIPad else { return 0 }

        let preferredOffset: CGFloat = 150
        let minimumSubtitleToPagerGap: CGFloat = 36
        let pagerTop = size.height - 107
        let subtitleBottomBeforeOffset = (size.height * 0.58) + 94
        let availableOffset = pagerTop - subtitleBottomBeforeOffset - minimumSubtitleToPagerGap

        return min(preferredOffset, max(0, availableOffset))
    }

    private var tutorialHeaderInset: some View {
        Color.clear
            .frame(height: tutorialTopSpacer)
    }

    // MARK: Welcome Page

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
                                        height: proxy.size.width / introGraphicsAspectRatio
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

    private func stepsPageContent(usesWideStepLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 26) {
            tutorialHeaderInset

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
                .stroke(introColors.mapBorder.opacity(0.28), lineWidth: 1)
        )
    }

    // MARK: List Selection Pages

    private var listSelectionPage: some View {
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

    private var listSelectionPageContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            tutorialHeaderInset

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
                tutorialAddListOptionCard(
                    title: localizedString("Pick a Continent", locale: locale),
                    systemImage: "globe.europe.africa"
                ) {
                    showingContinentSearch = true
                }

                tutorialAddListOptionCard(
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

    @ViewBuilder
    private var tutorialListSelectionPage: some View {
        if isCreatingList {
            creatingListPage
        } else {
            listSelectionPage
        }
    }

    private var filteredTutorialCountryOptions: [CountryListOption] {
        let countries = CountryCityCatalog.countries(locale: locale)
        let query = countrySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return countries }
        return countries.filter {
            $0.localizedName(locale: locale).localizedCaseInsensitiveContains(query)
                || $0.englishName.localizedCaseInsensitiveContains(query)
                || $0.iso2.localizedCaseInsensitiveContains(query)
        }
    }

    private func tutorialAddListOptionCard(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        AddListOptionButton(
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
                    introColors.mapBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.24),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 1
                )
        }
    }

    // MARK: List Creation Progress

    private var creatingListPage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    // iPad: Flexible spacers replace the former fixed 260-point
                    // offset, keeping progress centred across portrait, landscape,
                    // Split View, and larger text sizes.
                    Spacer(minLength: 40)

                    VStack(spacing: 18) {
                        Text(creatingListTitle)
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

    private var creatingListTitle: String {
        guard let creatingListName else {
            return localizedString("Creating a list of 15 cities", locale: locale)
        }
        return "\(localizedString("Creating a list of 15 cities in", locale: locale)) \(creatingListName)"
    }

    // MARK: Picker Sheets

    private var tutorialContinentSearchSheet: some View {
        ContinentListPickerContent(
            lists: continentLists,
            onSelect: beginCreatingContinentList
        )
    }

    private var tutorialCountrySearchSheet: some View {
        CountryListPickerContent(
            countries: filteredTutorialCountryOptions,
            searchBar: CountrySearchField(
                text: $countrySearchText
            ),
            onSelect: beginCreatingCountryList
        )
        .onAppear {
            countrySearchText = ""
        }
    }

    // MARK: Footer

    private var tutorialFooter: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? primaryButtonColor : inactivePageDotColor)
                        .frame(width: index == page ? 9 : 7, height: index == page ? 9 : 7)
                        .animation(.smooth(duration: 0.18), value: page)
                }
            }

            if !isCreatingList {
                tutorialFooterButtons
            }
        }
    }

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
                    advanceOrFinish()
                } label: {
                    Text(primaryButtonTitle)
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

    // MARK: - Footer Styling

    private var inactivePageDotColor: Color {
        // Full opacity clears the 3:1 non-text threshold in the
        // increased-contrast light palette; standard mode remains unchanged.
        introColors.mapBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.7)
    }

    private var primaryButtonTitle: String {
        if page < pageCount - 1 {
            return localizedString("Continue", locale: locale)
        }
        return localizedString("Done", locale: locale)
    }

    // MARK: Tutorial Actions

    private func advanceOrFinish() {
        if page < pageCount - 1 {
            withAnimation(.smooth(duration: 0.2)) {
                page += 1
            }
        } else {
            onFinish()
        }
    }

    private func beginCreatingContinentList(_ listID: CityListID) {
        showingContinentSearch = false
        creatingListName = listID.canonicalLocalizedDisplayName(locale: locale)
        startCreatingList {
            await onSelectContinentList(listID)
        }
    }

    private func beginCreatingCountryList(_ country: CountryListOption) {
        showingCountrySearch = false
        creatingListName = country.localizedName(locale: locale)
        startCreatingList {
            await onSelectCountryList(country)
        }
    }

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

    private func applyInitialStateIfNeeded() {
        guard !didApplyInitialState else { return }
        didApplyInitialState = true
        page = min(max(initialPage, 0), pageCount - 1)
        isCreatingList = initialIsCreatingList
        creatingListName = initialCreatingListName
    }

}

// MARK: - Preview Support

private struct TutorialPreviewContent: View {
    let startsCreatingList: Bool

    init(startsCreatingList: Bool = false) {
        self.startsCreatingList = startsCreatingList
    }

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
