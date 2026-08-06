//
//  TutorialView.swift
//  Weather
//
//  Purpose: Presents the branded first-launch and replay tutorial. First launch
//  can add a geographic set of starting cities directly to Saved Places.
//

import SwiftUI
import UIKit

/// Distinguishes first-run setup from the explanatory replay in Settings.
enum WeatherAtlasTutorialMode: String, Identifiable {
    case firstLaunch
    case replay

    var id: Self { self }

    var includesStartingCities: Bool {
        self == .firstLaunch
    }
}

/// Branded, adaptive Weather Atlas onboarding restored around the place-owned
/// app model rather than list creation.
struct WeatherAtlasTutorialView: View {
    let mode: WeatherAtlasTutorialMode
    let importProgress: Double
    let onAddStartingCities: ([City]) async throws -> Void
    let onFinish: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @State private var page = 0
    @State private var showsContinentPicker = false
    @State private var showsCountryPicker = false
    @State private var isImporting = false
    @State private var importSourceName: String?
    @State private var pendingImport: TutorialStartingCitiesSelection?
    @State private var presentedError: TutorialPresentedError?

    private var pageCount: Int {
        mode.includesStartingCities ? 3 : 2
    }

    private var usesReservedFooterLayout: Bool {
        dynamicTypeSize > .large
    }

    private var primaryButtonColor: Color {
        theme.colors.dotSun
    }

    private var primaryButtonTextColor: Color {
        colorScheme == .dark
            ? theme.colors.background
            : theme.colors.primaryText
    }

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            tutorialPages
                .disabled(isImporting)

            if !usesReservedFooterLayout {
                VStack {
                    Spacer()
                    tutorialFooter
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 680)
                        .padding(.bottom, 28)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if usesReservedFooterLayout {
                tutorialFooter
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .background(theme.colors.background)
            }
        }
        .sheet(
            isPresented: $showsContinentPicker,
            onDismiss: beginPendingImportIfNeeded
        ) {
            tutorialPickerPresentation(
                TutorialContinentPicker { continent in
                    pendingImport = TutorialStartingCitiesSelection(
                        sourceName: continent.localizedName(locale: locale),
                        cities: CountryCityCatalog.topCities(for: continent)
                    )
                    showsContinentPicker = false
                }
            )
        }
        .sheet(
            isPresented: $showsCountryPicker,
            onDismiss: beginPendingImportIfNeeded
        ) {
            tutorialPickerPresentation(
                TutorialCountryPicker { country in
                    pendingImport = TutorialStartingCitiesSelection(
                        sourceName: country.localizedName(locale: locale),
                        cities: CountryCityCatalog.topCities(for: country)
                    )
                    showsCountryPicker = false
                }
            )
        }
        .alert(
            "Starting Cities Could Not Be Added",
            isPresented: presentedErrorIsPresented,
            presenting: presentedError
        ) { _ in
            Button("OK") {
                presentedError = nil
            }
        } message: { error in
            Text(error.message)
        }
        .interactiveDismissDisabled(mode == .firstLaunch || isImporting)
    }

    @ViewBuilder
    private var tutorialPages: some View {
        if dynamicTypeSize > .large {
            currentTutorialPage
                .id(page)
                .transition(.opacity)
        } else {
            TabView(selection: $page) {
                TutorialWelcomePage()
                    .tag(0)

                TutorialStepsPage()
                    .tag(1)

                if mode.includesStartingCities {
                    startingCitiesPage
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
            TutorialWelcomePage()
        case 1:
            TutorialStepsPage()
        default:
            startingCitiesPage
        }
    }

    @ViewBuilder
    private var startingCitiesPage: some View {
        if isImporting {
            TutorialImportProgressPage(
                sourceName: importSourceName,
                progress: importProgress
            )
        } else {
            TutorialStartingCitiesPage(
                chooseContinent: { showsContinentPicker = true },
                chooseCountry: { showsCountryPicker = true },
                primaryButtonColor: primaryButtonColor,
                primaryButtonTextColor: primaryButtonTextColor
            )
        }
    }

    private var tutorialFooter: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(
                            index == page
                                ? primaryButtonColor
                                : theme.colors.secondaryText.opacity(
                                    colorSchemeContrast == .increased ? 1 : 0.7
                                )
                        )
                        .frame(
                            width: index == page ? 9 : 7,
                            height: index == page ? 9 : 7
                        )
                        .animation(.smooth(duration: 0.18), value: page)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tutorial progress")
            .accessibilityValue("Page \(page + 1) of \(pageCount)")

            if !isImporting,
               !(mode.includesStartingCities && page == pageCount - 1) {
                Button {
                    if page < pageCount - 1 {
                        withAnimation(.smooth(duration: 0.2)) {
                            page += 1
                        }
                    } else {
                        onFinish()
                    }
                } label: {
                    footerButtonLabel
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

    @ViewBuilder
    private var footerButtonLabel: some View {
        if page < pageCount - 1 {
            Text("Continue")
        } else {
            Text("Done")
        }
    }

    private func beginImport(sourceName: String, cities: [City]) {
        guard !isImporting else { return }
        guard !cities.isEmpty else {
            presentedError = TutorialPresentedError(
                message: localizedString(
                    "Starting cities are unavailable for this selection.",
                    locale: locale
                )
            )
            return
        }
        importSourceName = sourceName
        isImporting = true
        withAnimation(.smooth(duration: 0.22)) {
            page = 2
        }

        Task {
            do {
                try await onAddStartingCities(cities)
                onFinish()
            } catch {
                isImporting = false
                presentedError = TutorialPresentedError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
    }

    private func beginPendingImportIfNeeded() {
        guard let pendingImport else { return }
        self.pendingImport = nil
        beginImport(
            sourceName: pendingImport.sourceName,
            cities: pendingImport.cities
        )
    }

    private var presentedErrorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    @ViewBuilder
    private func tutorialPickerPresentation<Content: View>(
        _ content: Content
    ) -> some View {
        if horizontalSizeClass == .regular {
            content
                .presentationSizing(.form)
                .presentationBackground(theme.colors.background)
        } else {
            content
                .presentationDetents([.fraction(0.82), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.colors.background)
        }
    }
}

// MARK: - Tutorial Pages

private struct TutorialWelcomePage: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            let landscape = isPad && proxy.size.width > proxy.size.height
            let artworkName = usesBlackArtwork
                ? "IntroGraphicsBlack"
                : (landscape ? "IntroGraphicsLandscape" : "IntroGraphics")
            let compactPad = isPad
                && max(proxy.size.width, proxy.size.height) < 1_250
            let artworkOffset: CGFloat = compactPad ? 36 : 28
            let sceneOffset = welcomeSceneOffset(
                for: proxy.size,
                isPad: isPad
            )

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
                    Group {
                        if isPad {
                            ZStack {
                                Image(artworkName)
                                    .resizable()
                                    .frame(
                                        width: proxy.size.width,
                                        height: proxy.size.width
                                            / (1_179.0 / 2_556.0)
                                    )
                                    .offset(y: artworkOffset)
                            }
                            .frame(
                                width: proxy.size.width,
                                height: proxy.size.height
                            )
                        } else {
                            Image(artworkName)
                                .resizable()
                                .scaledToFill()
                                .frame(
                                    width: proxy.size.width,
                                    height: proxy.size.height
                                )
                                .clipped()
                        }
                    }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                    ScrollView {
                        welcomeCopy(topSpacing: proxy.size.height * 0.58)
                            .frame(
                                minHeight: proxy.size.height,
                                alignment: .top
                            )
                            .frame(maxWidth: 680)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
                .offset(y: sceneOffset)
            }
        }
    }

    private func welcomeCopy(topSpacing: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: topSpacing)

            Text("Welcome to Weather Atlas")
                .font(.system(.largeTitle, design: .serif).weight(.bold))
                .foregroundStyle(theme.colors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 28)

            Text(
                "Find sunny destinations and plan ahead for your next holiday."
            )
            .font(.title3)
            .foregroundStyle(theme.colors.primaryText.opacity(0.64))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 36)
            .padding(.top, 24)

            Spacer(minLength: 128)
        }
    }

    private func welcomeSceneOffset(for size: CGSize, isPad: Bool) -> CGFloat {
        guard isPad else { return 0 }

        let preferredOffset: CGFloat = 150
        let minimumSubtitleToPagerGap: CGFloat = 36
        let pagerTop = size.height - 107
        let subtitleBottomBeforeOffset = (size.height * 0.58) + 94
        let availableOffset = pagerTop
            - subtitleBottomBeforeOffset
            - minimumSubtitleToPagerGap

        return min(preferredOffset, max(0, availableOffset))
    }

    private var usesBlackArtwork: Bool {
        theme.style == .black
            || (theme.style == .automaticBlack && colorScheme == .dark)
    }
}

private struct TutorialStepsPage: View {
    private let steps: [TutorialStep] = [
        TutorialStep(
            number: 1,
            title: "Save the places you care about",
            subtitle: "Keep every city together in Saved Places."
        ),
        TutorialStep(
            number: 2,
            title: "Choose the best date",
            subtitle: "Compare your places and see which ones have the sunniest conditions."
        ),
        TutorialStep(
            number: 3,
            title: "See when a city is sunny",
            subtitle: "Open a place to find its best sunny window and detailed forecast."
        )
    ]

    @Environment(\.appTheme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Color.clear
                        .frame(height: 62)

                    Text("How Weather Atlas Works")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(theme.colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if usesWideLayout(for: proxy.size) {
                        HStack(alignment: .top, spacing: 14) {
                            stepCards
                        }
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 22) {
                            stepCards
                        }
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 128)
                }
                .padding(.horizontal, 28)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always)
            .defaultScrollAnchor(.top)
        }
    }

    @ViewBuilder
    private var stepCards: some View {
        ForEach(steps) { step in
            TutorialStepCard(step: step)
        }
    }

    private func usesWideLayout(for size: CGSize) -> Bool {
        horizontalSizeClass == .regular
            && size.width > size.height
            && dynamicTypeSize > .large
    }
}

private struct TutorialStartingCitiesPage: View {
    let chooseContinent: () -> Void
    let chooseCountry: () -> Void
    let primaryButtonColor: Color
    let primaryButtonTextColor: Color

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear
                        .frame(height: 62)

                    Text("Choose your starting cities")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                        .foregroundStyle(theme.colors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "Pick a country or continent and Weather Atlas will add its 15 largest cities directly to Saved Places."
                    )
                    .font(.body)
                    .foregroundStyle(theme.colors.primaryText.opacity(0.64))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 18)

                    VStack(spacing: 16) {
                        TutorialSourceButton(
                            title: "Pick a Continent",
                            systemImage: "globe.europe.africa",
                            fill: primaryButtonColor,
                            foreground: primaryButtonTextColor,
                            action: chooseContinent
                        )

                        TutorialSourceButton(
                            title: "Pick a Country",
                            systemImage: "flag",
                            fill: primaryButtonColor,
                            foreground: primaryButtonTextColor,
                            action: chooseCountry
                        )
                    }

                    Spacer(minLength: 128)
                }
                .padding(.horizontal, 28)
                .frame(minHeight: proxy.size.height, alignment: .top)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct TutorialImportProgressPage: View {
    let sourceName: String?
    let progress: Double

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)

                    VStack(spacing: 18) {
                        if let sourceName {
                            Text("Adding starting cities from \(sourceName)")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Adding starting cities")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(theme.colors.primaryText)
                        }

                        ProgressView(value: min(max(progress, 0), 1))
                            .tint(theme.colors.dotSun)
                            .frame(maxWidth: 240)

                        Text("Saving your places and loading their forecasts…")
                            .font(.callout)
                            .foregroundStyle(theme.colors.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.horizontal, 28)
                .frame(minHeight: proxy.size.height)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Tutorial Components

private struct TutorialStep: Identifiable {
    let number: Int
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var id: Int { number }
}

private struct TutorialStepCard: View {
    let step: TutorialStep

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var numberForeground: Color {
        colorScheme == .dark
            ? theme.colors.background
            : theme.colors.primaryText
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(step.number, format: .number)
                .font(.callout.weight(.bold))
                .foregroundStyle(numberForeground)
                .frame(width: 34, height: 34)
                .background(theme.colors.dotSun, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(step.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.subtitle)
                    .font(.body)
                    .foregroundStyle(theme.colors.primaryText.opacity(0.62))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .background(
            theme.colors.background.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    theme.colors.secondaryText.opacity(0.28),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TutorialSourceButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let fill: Color
    let foreground: Color
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.system(size: 33, weight: .regular))
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .frame(width: 22, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .frame(minHeight: 102)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            fill,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    theme.colors.secondaryText.opacity(
                        colorSchemeContrast == .increased ? 1 : 0.24
                    ),
                    lineWidth: colorSchemeContrast == .increased ? 1.25 : 1
                )
        }
    }
}

// MARK: - Starting City Pickers

private struct TutorialContinentPicker: View {
    let onSelect: (ContinentPlacesOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            List(ContinentPlacesOption.allCases) { continent in
                Button {
                    onSelect(continent)
                } label: {
                    TutorialSourceRow(
                        title: continent.localizedName(locale: locale)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.colors.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .navigationTitle("Pick a Continent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TutorialCountryPicker: View {
    let onSelect: (CountryPlacesOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.appTheme) private var theme
    @State private var query = ""

    private var countries: [CountryPlacesOption] {
        CountryCityCatalog.countries(locale: locale)
    }

    private var filteredCountries: [CountryPlacesOption] {
        let normalizedQuery = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedQuery.isEmpty else { return countries }
        return countries.filter { country in
            country.localizedName(locale: locale)
                .localizedStandardContains(normalizedQuery)
                || country.englishName.localizedStandardContains(
                    normalizedQuery
                )
                || country.iso2.localizedStandardContains(normalizedQuery)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredCountries.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List(filteredCountries) { country in
                        Button {
                            onSelect(country)
                        } label: {
                            TutorialSourceRow(
                                title: country.localizedName(locale: locale)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.colors.background)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(theme.colors.background)
            .navigationTitle("Pick a Country")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search for a country")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TutorialSourceRow: View {
    let title: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

private struct TutorialPresentedError: Identifiable {
    let id = UUID()
    let message: String
}

private struct TutorialStartingCitiesSelection {
    let sourceName: String
    let cities: [City]
}

#Preview("Tutorial — First Launch") {
    WeatherAtlasTutorialView(
        mode: .firstLaunch,
        importProgress: 0.42,
        onAddStartingCities: { _ in },
        onFinish: {}
    )
    .environment(\.appTheme, AppTheme.shared)
}

#Preview("Tutorial — Replay") {
    WeatherAtlasTutorialView(
        mode: .replay,
        importProgress: 0,
        onAddStartingCities: { _ in },
        onFinish: {}
    )
    .environment(\.appTheme, AppTheme.shared)
}
