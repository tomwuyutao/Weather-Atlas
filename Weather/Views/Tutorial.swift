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
    let onToggleContinentList: (CityListID) -> Void
    let onFinish: () -> Void
    var onCancel: (() -> Void)?

    @Environment(\.appTheme) private var theme
    @Environment(\.locale) private var locale
    @State private var page = 0

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
                    continentSelectionPage
                        .tag(2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack {
                Spacer()
                tutorialFooter
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
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
        86
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
                        .frame(height: proxy.size.height * 0.62)

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
                    subtitle: localizedString("Add the places you’re thinking about visiting.", locale: locale)
                )
                tutorialStep(
                    number: 2,
                    title: localizedString("See when each place shines", locale: locale),
                    subtitle: localizedString("Stop opening forecasts one by one.", locale: locale)
                )
                tutorialStep(
                    number: 3,
                    title: localizedString("Spot sunshine instantly", locale: locale),
                    subtitle: localizedString("See weather patterns across your saved places.", locale: locale)
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
        VStack(alignment: .leading, spacing: 20) {
            tutorialHeaderInset

            Text(localizedString("Choose something to start with", locale: locale))
                .font(tutorialTitle)
                .foregroundStyle(introColors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                ForEach(continentLists) { listID in
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            onToggleContinentList(listID)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            continentSelectionMarker(isSelected: selectedContinentListIDs.contains(listID.rawValue))

                            Text(listID.localizedDisplayName(locale: locale))
                                .font(.avenir(.body, weight: .bold))
                                .foregroundStyle(introColors.primaryText)

                            Spacer()
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 20)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if listID.rawValue != continentLists.last?.rawValue {
                        Divider()
                            .overlay(introColors.mapBorder.opacity(0.34))
                            .padding(.leading, 64)
                    }
                }
            }
            .background(introColors.listCardFill.opacity(0.78), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(introColors.mapBorder.opacity(0.28), lineWidth: 1)
            )

            Spacer(minLength: 92)
        }
        .padding(.horizontal, tutorialHorizontalPadding)
    }

    private func continentSelectionMarker(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? primaryButtonColor : .clear)
                .frame(width: 24, height: 24)

            Circle()
                .stroke(isSelected ? primaryButtonColor : introColors.mapBorder, lineWidth: 2.2)
                .frame(width: 24, height: 24)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 36, height: 24)
        .animation(.smooth(duration: 0.18), value: isSelected)
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
                .disabled(includesContinentSelection && page == 2 && selectedContinentListIDs.isEmpty)
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
}

// MARK: - Preview

#Preview("Tutorial") {
    @Previewable @State var selectedIDs: Set<String> = [CityListID.europe.rawValue]

    TutorialView(
        includesContinentSelection: true,
        continentLists: CityListID.builtInLists,
        selectedContinentListIDs: $selectedIDs,
        onToggleContinentList: { listID in
            if selectedIDs.contains(listID.rawValue) {
                selectedIDs.remove(listID.rawValue)
            } else {
                selectedIDs.insert(listID.rawValue)
            }
        },
        onFinish: {},
        onCancel: nil
    )
    .environment(\.appTheme, AppTheme.shared)
}
