//
//  Tutorial.swift
//  Weather
//
//  Purpose: Presents first-launch onboarding, replayable app guidance, and the
//  final continent-list selection step used when the app is opened fresh.
//

import SwiftUI

// MARK: - Full-Screen Tutorial

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
    @State private var page = 0
    @State private var showingContinentSearch = false
    @State private var showingCountrySearch = false
    @State private var countrySearchText = ""
    @State private var isCreatingList = false
    @State private var creatingListName: String?
    @State private var didApplyInitialState = false

    private var pageCount: Int {
        includesContinentSelection ? 4 : 2
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
                    continentSelectionPage
                        .tag(2)

                    creatingListPage
                        .tag(3)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .disabled(isCreatingList)

            VStack {
                Spacer()
                tutorialFooter
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showingContinentSearch) {
            tutorialContinentSearchSheet
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.background)
        }
        .sheet(isPresented: $showingCountrySearch) {
            tutorialCountrySearchSheet
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.background)
        }
        .interactiveDismissDisabled(isCreatingList)
        .onAppear {
            applyInitialStateIfNeeded()
        }
    }

    private var tutorialBackground: Color {
        introColors.background
    }

    private var primaryButtonColor: Color {
        introColors.sunIconColor
    }

    private var primaryButtonTextColor: Color {
        introColors.primaryText
    }

    private var introColors: ThemeColors {
        .light
    }

    private var tutorialHorizontalPadding: CGFloat {
        28
    }

    private var tutorialTopSpacer: CGFloat {
        62
    }

    private var tutorialTitle: Font {
        .system(size: 34, weight: .bold, design: .serif)
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

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: proxy.size.height * 0.58)

                    Text(localizedString("Welcome to Weather Atlas", locale: locale))
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(introColors.primaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 28)

                    VStack(spacing: 8) {
                        Text(localizedString("Find sunny destinations and", locale: locale))
                        Text(localizedString("plan ahead for your next holiday.", locale: locale))
                    }
                    .font(.avenir(.title3, weight: .regular))
                    .foregroundStyle(introColors.primaryText.opacity(0.64))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(.horizontal, 36)
                    .padding(.top, 24)

                    Spacer()
                }
            }
        }
    }

    // MARK: Steps Page

    private var stepsPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            tutorialHeaderInset

            Text(localizedString("How Weather Atlas Works", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)

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
                .font(.avenir(.callout, weight: .bold))
                .foregroundStyle(introColors.primaryText)
                .frame(width: 34, height: 34)
                .background(primaryButtonColor, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.avenir(.headline, weight: .bold))
                    .foregroundStyle(introColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.avenir(.body, weight: .regular))
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

    // MARK: Continent Selection Page

    private var continentSelectionPage: some View {
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
                    + Text(localizedString("15 big cities", locale: locale)).fontWeight(.bold)
                    + Text(localizedString(" for you.", locale: locale))
            )
            .font(.avenir(.body, weight: .regular))
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
            action: action
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(introColors.listCardFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(introColors.mapBorder.opacity(0.24), lineWidth: 1)
        }
    }

    // MARK: Creating Page

    private var creatingListPage: some View {
        VStack(spacing: 22) {
            Spacer()
                .frame(height: 260)

            VStack(spacing: 18) {
                Text(creatingListTitle)
                    .font(.avenir(.title3, weight: .semibold))
                    .foregroundStyle(introColors.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)

                ProgressView(value: min(max(creationProgress, 0), 1))
                    .tint(primaryButtonColor)
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
                            .font(.avenir(.body, weight: .regular))
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

            TextField(localizedString("Search for a country", locale: locale), text: $countrySearchText)
                .font(.avenir(.body, weight: .regular))
                .foregroundStyle(.primary)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)

            if !countrySearchText.isEmpty {
                Button {
                    countrySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(theme.colors.listCardFill, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(colorScheme == .dark ? 0.16 : 0.38), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 18, y: 8)
    }

    private func tutorialContinentSearchRow(_ listID: CityListID) -> some View {
        HStack(spacing: 12) {
            Text(listID.localizedDisplayName(locale: locale))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func tutorialCountrySearchRow(_ country: CountryListOption) -> some View {
        HStack(spacing: 12) {
            Text(country.localizedName(locale: locale))
                .font(.avenir(.headline, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.accent)
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

            if !isCreatingList {
                HStack(spacing: 12) {
                    if let onCancel {
                        Button(localizedString("Cancel", locale: locale)) {
                            onCancel()
                        }
                        .buttonStyle(.bordered)
                        .tint(page < 2 ? introColors.primaryText : .white)
                        .foregroundStyle(page < 2 ? introColors.primaryText : .white)
                        .controlSize(.large)
                    }

                    Button {
                        advanceOrFinish()
                    } label: {
                        Text(primaryButtonTitle)
                            .font(.avenir(.body, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(primaryButtonColor)
                    .foregroundStyle(primaryButtonTextColor)
                    .controlSize(.large)
                    .disabled(includesContinentSelection && page == 2)
                }
            }
        }
    }

    private var inactivePageDotColor: Color {
        introColors.mapBorder.opacity(0.7)
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
            page = 3
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
        initialPage: 3,
        initialIsCreatingList: true,
        initialCreatingListName: CityListID.europe.localizedDisplayName()
    )
    .environment(\.appTheme, AppTheme.shared)
}
