//
//  Tutorial.swift
//  Weather
//
//  Purpose: Presents first-launch onboarding, replayable app guidance, and the
//  final continent-list selection step used when the app is opened fresh.
//

import SwiftUI

// MARK: - Full-Screen Tutorial

// Accessibility: Stable focus destinations let VoiceOver follow onboarding page
// changes instead of remaining on a footer button whose surrounding page changed.
private enum TutorialAccessibilityFocus: Hashable {
    case welcome
    case steps
    case listSelection
    case creatingList
}

struct TutorialView: View {
    let includesContinentSelection: Bool
    let continentLists: [CityListID]
    @Binding var selectedContinentListIDs: Set<String>
    @Binding var selectedCountryListIDs: Set<String>
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var page = 0
    @State private var showingContinentSearch = false
    @State private var showingCountrySearch = false
    @State private var countrySearchText = ""
    @State private var isCreatingList = false
    @State private var creatingListName: String?
    @State private var didApplyInitialState = false
    @AccessibilityFocusState private var accessibilityFocus: TutorialAccessibilityFocus?

    private var pageCount: Int {
        includesContinentSelection ? 3 : 2
    }

    var body: some View {
        ZStack {
            tutorialBackground
                .ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage
                    .tag(0)

                stepsPage
                    .tag(1)

                if includesContinentSelection {
                    tutorialListSelectionPage
                        .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(isCreatingList)

            // Accessibility: Keep the original overlay footer at normal sizes; large
            // accessibility text uses the safe-area footer below to avoid content overlap.
            if !dynamicTypeSize.isAccessibilitySize {
                VStack {
                    Spacer()
                    tutorialFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
            }
        }
        // Accessibility: Reserve real layout space for controls at accessibility text sizes.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                tutorialFooter
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(tutorialBackground)
            }
        }
        .sheet(isPresented: $showingContinentSearch) {
            tutorialContinentSearchSheet
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.background)
                // Accessibility: The picker has no visual Cancel button, so expose the
                // standard modal escape action without altering its normal appearance.
                .accessibilityAction(.escape) {
                    showingContinentSearch = false
                }
        }
        .sheet(isPresented: $showingCountrySearch) {
            tutorialCountrySearchSheet
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.background)
                // Accessibility: Let VoiceOver and Voice Control leave the picker
                // without depending on a drag gesture.
                .accessibilityAction(.escape) {
                    showingCountrySearch = false
                }
        }
        .interactiveDismissDisabled(isCreatingList)
        // Accessibility: Onboarding pages can always be traversed backward with the
        // standard escape gesture; a supplied cancel action is used from the first page.
        .accessibilityAction(.escape) {
            if page > 0, !isCreatingList {
                withAnimation(.smooth(duration: 0.2)) {
                    page -= 1
                }
            } else if page == 0 {
                if let onCancel {
                    onCancel()
                } else if !includesContinentSelection {
                    // Accessibility: A replay can be dismissed from its first page even
                    // though first-launch onboarding intentionally remains mandatory.
                    onFinish()
                }
            }
        }
        .onAppear {
            applyInitialStateIfNeeded()
            focusCurrentTutorialPage()
        }
        .onChange(of: page) { _, _ in
            focusCurrentTutorialPage()
        }
        .onChange(of: isCreatingList) { _, _ in
            focusCurrentTutorialPage()
        }
    }

    private var tutorialBackground: Color {
        introColors.background
    }

    private var primaryButtonColor: Color {
        introColors.sunIconColor
    }

    private var primaryButtonTextColor: Color {
        colorScheme == .dark ? introColors.background : introColors.primaryText
    }

    private var introColors: ThemeColors {
        theme.colors
    }

    private var tutorialHorizontalPadding: CGFloat {
        28
    }

    private var tutorialTopSpacer: CGFloat {
        62
    }

    private var tutorialTitle: Font {
        .system(.largeTitle, design: .serif, weight: .bold)
    }

    private var tutorialHeaderInset: some View {
        Color.clear
            .frame(height: tutorialTopSpacer)
    }

    // MARK: Welcome Page

    private var welcomePage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Image("IntroGraphics")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .ignoresSafeArea()
                    // Accessibility: Remove decorative artwork visually at very large text sizes
                    // so the scrollable welcome copy receives the available space.
                    .opacity(dynamicTypeSize.isAccessibilitySize ? 0 : 1)
                    .accessibilityHidden(true)

                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        welcomePageText(topSpacing: 24)
                            .padding(.bottom, 180)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    welcomePageText(topSpacing: proxy.size.height * 0.58)
                }
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 28)
                .accessibilityAddTraits(.isHeader)
                // Accessibility: This is the first reading destination on page one.
                .accessibilityFocused($accessibilityFocus, equals: .welcome)

            VStack(spacing: 8) {
                Text(localizedString("Find sunny destinations and", locale: locale))
                Text(localizedString("plan ahead for your next holiday.", locale: locale))
            }
            .font(.title3)
            .foregroundStyle(introColors.primaryText.opacity(0.64))
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .accessibilityElement(children: .combine)

            Spacer()
        }
    }

    // MARK: Steps Page

    @ViewBuilder
    private var stepsPage: some View {
        // Accessibility: Long onboarding copy becomes scrollable instead of clipping.
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                stepsPageContent
                    .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
        } else {
            stepsPageContent
        }
    }

    private var stepsPageContent: some View {
        VStack(alignment: .leading, spacing: 26) {
            tutorialHeaderInset

            Text(localizedString("How Weather Atlas Works", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                // Accessibility: Continue moves VoiceOver to the newly displayed heading.
                .accessibilityFocused($accessibilityFocus, equals: .steps)

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
            .padding(.top, 12)

            Spacer()
            Spacer(minLength: 72)
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    private func tutorialStep(number: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                // Accessibility: Keep step numbers legible on the bright button fill
                // in both light and dark Increased Contrast appearances.
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
        // Accessibility: Expose the visually grouped number, title, and explanation once.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(number). \(title)")
        .accessibilityValue(subtitle)
    }

    // MARK: Continent Selection Page

    @ViewBuilder
    private var continentSelectionPage: some View {
        // Accessibility: The selection page also scrolls when Dynamic Type needs more height.
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                continentSelectionPageContent
                    .padding(.bottom, 170)
            }
            .scrollIndicators(.hidden)
        } else {
            continentSelectionPageContent
        }
    }

    private var continentSelectionPageContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            tutorialHeaderInset

            Text(localizedString("Let's add your first city list", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                // Accessibility: Focus the required list-selection task when it appears.
                .accessibilityFocused($accessibilityFocus, equals: .listSelection)

            (
                Text(localizedString("Pick a place and we'll create a list of ", locale: locale))
                    + Text(localizedString("15 big cities", locale: locale)).fontWeight(.bold)
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    @ViewBuilder
    private var tutorialListSelectionPage: some View {
        if isCreatingList {
            creatingListPage
        } else {
            continentSelectionPage
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
            titleColor: introColors.primaryText,
            showsIconBackground: false,
            iconColor: introColors.accent,
            action: action
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(introColors.listCardFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                // Accessibility: These cards are primary onboarding actions, so
                // Increase Contrast gives their full boundary a 3:1+ outline.
                .stroke(
                    introColors.mapBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.24),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 1
                )
        }
    }

    // MARK: Creating Page

    private var creatingListPage: some View {
        VStack(spacing: 22) {
            Spacer()
                .frame(height: 260)

            VStack(spacing: 18) {
                Text(creatingListTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(introColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityAddTraits(.isHeader)
                    // Accessibility: Creation replaces the picker page, so announce its
                    // status heading as the new focus destination.
                    .accessibilityFocused($accessibilityFocus, equals: .creatingList)

                ProgressView(value: min(max(creationProgress, 0), 1))
                    .tint(primaryButtonColor)
                    .frame(width: 240)
                    .accessibilityLabel(creatingListTitle)
                    .accessibilityValue(
                        min(max(creationProgress, 0), 1).formatted(.percent.precision(.fractionLength(0)))
                    )
            }

            Spacer()
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    private var creatingListTitle: String {
        guard let creatingListName else {
            return localizedString("Creating a list of 15 cities", locale: locale)
        }
        return "\(localizedString("Creating a list of 15 cities in", locale: locale)) \(creatingListName)"
    }

    private var tutorialContinentSearchSheet: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(continentLists) { listID in
                    Button {
                        beginCreatingContinentList(listID)
                    } label: {
                        tutorialContinentSearchRow(listID)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(listID.localizedDisplayName(locale: locale))

                    if listID != continentLists.last {
                        Divider()
                            .background(theme.colors.secondaryText.opacity(0.20))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 18)
        .padding(.bottom, 28)
        .background(theme.colors.background.ignoresSafeArea())
    }

    private var tutorialCountrySearchSheet: some View {
        VStack(spacing: 18) {
            tutorialCountrySearchBar

            ScrollView {
                VStack(spacing: 0) {
                    let countries = filteredTutorialCountryOptions
                    if countries.isEmpty {
                        Text(localizedString("No countries found.", locale: locale))
                            .font(.body)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(countries) { country in
                            Button {
                                beginCreatingCountryList(country)
                            } label: {
                                tutorialCountrySearchRow(country)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(country.localizedName(locale: locale))

                            if country.id != countries.last?.id {
                                Divider()
                                    .background(theme.colors.secondaryText.opacity(0.20))
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 28)
        .background(theme.colors.background.ignoresSafeArea())
        .onAppear {
            countrySearchText = ""
        }
    }

    private var tutorialCountrySearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)

            TextField(localizedString("Search for a country", locale: locale), text: $countrySearchText)
                .font(.body)
                .foregroundStyle(theme.colors.primaryText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .accessibilityLabel(localizedString("Search for a country", locale: locale))

            if !countrySearchText.isEmpty {
                Button {
                    countrySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Accessibility: The 44-point clear target preserves the compact search capsule
                // because its extra label space is compensated by negative padding.
                .padding(-13)
                .accessibilityLabel(localizedString("Clear", locale: locale))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .background(theme.colors.listCardFill, in: Capsule())
        .overlay {
            Capsule()
                // Accessibility: Make the custom search-field boundary sufficiently
                // distinct only when Increase Contrast is enabled.
                .stroke(
                    theme.colors.primaryText.opacity(
                        colorSchemeContrast == .increased
                            ? 1
                            : (colorScheme == .dark ? 0.16 : 0.12)
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 0.8
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
    }

    private func tutorialContinentSearchRow(_ listID: CityListID) -> some View {
        HStack(spacing: 12) {
            Text(listID.localizedDisplayName(locale: locale))
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func tutorialCountrySearchRow(_ country: CountryListOption) -> some View {
        HStack(spacing: 12) {
            Text(country.localizedName(locale: locale))
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
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
            // Accessibility: Announce page position without focusing each decorative dot.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(currentTutorialPageTitle)
            .accessibilityValue("\(page + 1) / \(pageCount)")

            if !isCreatingList {
                tutorialFooterButtons
            }
        }
    }

    private var tutorialFooterButtons: some View {
        // Accessibility: Stack footer actions when horizontal labels no longer fit comfortably.
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))

        return layout {
            if let onCancel {
                Button(localizedString("Cancel", locale: locale)) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .tint(introColors.accent)
                .foregroundStyle(introColors.primaryText)
                .controlSize(.large)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            }

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
            .disabled(includesContinentSelection && page == 2)
        }
    }

    // MARK: - Accessibility - Page Descriptions

    private var currentTutorialPageTitle: String {
        switch page {
        case 0:
            localizedString("Welcome to Weather Atlas", locale: locale)
        case 1:
            localizedString("How Weather Atlas Works", locale: locale)
        default:
            isCreatingList
                ? creatingListTitle
                : localizedString("Let's add your first city list", locale: locale)
        }
    }

    // MARK: - Footer Styling

    private var inactivePageDotColor: Color {
        // Accessibility: Full opacity clears the 3:1 non-text threshold in the
        // increased-contrast light palette; standard mode remains unchanged.
        introColors.mapBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.7)
    }

    private var primaryButtonTitle: String {
        if page < pageCount - 1 {
            return localizedString("Continue", locale: locale)
        }
        return includesContinentSelection ? localizedString("Start", locale: locale) : localizedString("Done", locale: locale)
    }

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
        creatingListName = listID.localizedDisplayName(locale: locale)
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

    // MARK: - Accessibility - Onboarding Focus

    private func focusCurrentTutorialPage() {
        // Accessibility: Clearing first makes repeated visits to the same page announce
        // consistently after SwiftUI finishes the page transition.
        accessibilityFocus = nil
        DispatchQueue.main.async {
            if isCreatingList {
                accessibilityFocus = .creatingList
            } else {
                switch page {
                case 0: accessibilityFocus = .welcome
                case 1: accessibilityFocus = .steps
                default: accessibilityFocus = .listSelection
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Tutorial") {
    @Previewable @State var selectedIDs: Set<String> = []

    TutorialView(
        includesContinentSelection: true,
        continentLists: CityListID.builtInLists,
        selectedContinentListIDs: $selectedIDs,
        selectedCountryListIDs: .constant([]),
        creationProgress: 0.42,
        onSelectContinentList: { _ in },
        onSelectCountryList: { _ in },
        onFinish: {},
        onCancel: nil
    )
    .environment(\.appTheme, AppTheme.shared)
}

#Preview("Tutorial Creating List") {
    @Previewable @State var selectedIDs: Set<String> = [CityListID.europe.rawValue]

    TutorialView(
        includesContinentSelection: true,
        continentLists: CityListID.builtInLists,
        selectedContinentListIDs: $selectedIDs,
        selectedCountryListIDs: .constant([]),
        creationProgress: 0.42,
        onSelectContinentList: { _ in },
        onSelectCountryList: { _ in },
        onFinish: {},
        onCancel: nil,
        initialPage: 2,
        initialIsCreatingList: true,
        initialCreatingListName: CityListID.europe.localizedDisplayName()
    )
    .environment(\.appTheme, AppTheme.shared)
}
