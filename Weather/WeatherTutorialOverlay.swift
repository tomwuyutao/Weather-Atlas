//
//  WeatherTutorialOverlay.swift
//  Weather
//

import SwiftUI

#if os(iOS)
enum WeatherTutorialTarget: Hashable {
    case listSwitcher
    case dateSlider
    case listManager
    case search
}

enum WeatherTutorialStep: Int, CaseIterable {
    case intro
    case listSwitcher
    case dateSlider
    case listManager
    case search

    var target: WeatherTutorialTarget? {
        switch self {
        case .intro: return nil
        case .listSwitcher: return .listSwitcher
        case .dateSlider: return .dateSlider
        case .listManager: return .listManager
        case .search: return .search
        }
    }

    var title: String {
        switch self {
        case .intro: return "Welcome to Weather Atlas"
        case .listSwitcher: return "Switch lists"
        case .dateSlider: return "Change date"
        case .listManager: return "Manage lists"
        case .search: return "Search cities"
        }
    }

    var message: String {
        switch self {
        case .intro:
            return "Here is a quick tour of the main controls for lists, forecast dates, city management, and search."
        case .listSwitcher:
            return "Tap this to switch between your lists of tracked cities."
        case .dateSlider:
            return "Drag this up and down to change the forecast date."
        case .listManager:
            return "Tap this to manage cities within lists and create new lists."
        case .search:
            return "Find a city and add it to a list."
        }
    }

    var actionTitle: String {
        switch self {
        case .intro: return "Let's Start"
        case .search: return "OK"
        default: return "Okay"
        }
    }
}

struct WeatherTutorialTargetFramePreferenceKey: PreferenceKey {
    static var defaultValue: [WeatherTutorialTarget: CGRect] = [:]

    static func reduce(value: inout [WeatherTutorialTarget: CGRect], nextValue: () -> [WeatherTutorialTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func weatherTutorialTarget(_ target: WeatherTutorialTarget) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: WeatherTutorialTargetFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .global)]
                )
            }
        }
    }
}

struct WeatherTutorialOverlay: View {
    let step: WeatherTutorialStep
    let targetFrame: CGRect?
    let onAdvance: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geometry in
            let fallbackFrame = CGRect(
                x: geometry.size.width / 2 - 36,
                y: geometry.size.height / 2 - 36,
                width: 72,
                height: 72
            )
            let overlayOrigin = geometry.frame(in: .global).origin
            let normalizedTargetFrame = targetFrame.map { frame in
                frame.offsetBy(dx: -overlayOrigin.x, dy: -overlayOrigin.y)
            }
            let rawFocusFrame = clippedFocusFrame(normalizedTargetFrame ?? fallbackFrame, in: geometry.size)
            let usesCircularFocus = step == .listManager || step == .search
            let focusFrame = usesCircularFocus
                ? circularFocusFrame(centeredOn: rawFocusFrame, in: geometry.size)
                : rawFocusFrame
            let popupSize = CGSize(width: min(320, geometry.size.width - 32), height: 168)
            let popupCenter = step == .intro
                ? CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                : popupCenter(for: focusFrame, popupSize: popupSize, in: geometry.size)

            ZStack(alignment: .topLeading) {
                if step == .intro {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                } else {
                    TutorialDimShape(
                        cutout: focusFrame.insetBy(dx: -8, dy: -8),
                        cornerRadius: 22,
                        isCircle: usesCircularFocus
                    )
                    .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
                    .ignoresSafeArea()

                    if usesCircularFocus {
                        Circle()
                            .stroke(.white.opacity(0.95), lineWidth: 2)
                            .frame(width: focusFrame.width + 16, height: focusFrame.height + 16)
                            .position(x: focusFrame.midX, y: focusFrame.midY)
                            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                    } else {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.95), lineWidth: 2)
                            .frame(width: focusFrame.width + 16, height: focusFrame.height + 16)
                            .position(x: focusFrame.midX, y: focusFrame.midY)
                            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                    }
                }

                tutorialCard
                    .frame(width: popupSize.width)
                    .position(popupCenter)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
        .transition(.opacity)
        .zIndex(1000)
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.title)
                .font(.avenir(.headline, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            Text(step.message)
                .font(.avenir(.subheadline, weight: .regular))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onAdvance()
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text(step.actionTitle)
                        .font(.avenir(.body, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 4)
        }
        .padding(16)
        .background(theme.colors.listCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
    }

    private func clippedFocusFrame(_ frame: CGRect, in size: CGSize) -> CGRect {
        let safeFrame = frame.isNull || frame.isInfinite || frame.width <= 0 || frame.height <= 0
            ? CGRect(x: size.width / 2 - 36, y: size.height / 2 - 36, width: 72, height: 72)
            : frame
        return safeFrame.intersection(CGRect(origin: .zero, size: size)).isNull
            ? CGRect(x: size.width / 2 - 36, y: size.height / 2 - 36, width: 72, height: 72)
            : safeFrame.intersection(CGRect(origin: .zero, size: size))
    }

    private func circularFocusFrame(centeredOn frame: CGRect, in size: CGSize) -> CGRect {
        let diameter = min(max(frame.height, 44), 56)
        let proposed = CGRect(
            x: frame.midX - diameter / 2,
            y: frame.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
        return clippedFocusFrame(proposed, in: size)
    }

    private func popupCenter(for focusFrame: CGRect, popupSize: CGSize, in size: CGSize) -> CGPoint {
        let horizontalPadding: CGFloat = 16
        let verticalGap: CGFloat = 18
        let halfWidth = popupSize.width / 2
        let halfHeight = popupSize.height / 2
        let x = min(max(focusFrame.midX, horizontalPadding + halfWidth), size.width - horizontalPadding - halfWidth)

        let belowY = focusFrame.maxY + verticalGap + halfHeight
        let aboveY = focusFrame.minY - verticalGap - halfHeight
        let y: CGFloat
        if belowY + halfHeight <= size.height - horizontalPadding {
            y = belowY
        } else if aboveY - halfHeight >= horizontalPadding {
            y = aboveY
        } else {
            y = min(max(belowY, horizontalPadding + halfHeight), size.height - horizontalPadding - halfHeight)
        }

        return CGPoint(x: x, y: y)
    }
}

struct TutorialDimShape: Shape {
    let cutout: CGRect
    let cornerRadius: CGFloat
    let isCircle: Bool

    init(cutout: CGRect, cornerRadius: CGFloat, isCircle: Bool = false) {
        self.cutout = cutout
        self.cornerRadius = cornerRadius
        self.isCircle = isCircle
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if isCircle {
            path.addEllipse(in: cutout)
        } else {
            path.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }
        return path
    }
}

extension ContentView {
    func startWeatherTutorial() {
        selectedTab = 1
        showingInlineSearch = false
        inlineSearchFieldPresented = false
        inlineSearchText = ""
        showingCityDetail = false
        showingMapExpandedCard = false
        showingMapSidebar = false
        iPhoneNavigationPath = []
        if shouldUseIPadLayout {
            iPadSidebarVisibility = .all
        }
        iPadPreferredCompactColumn = .detail
        selectedDayOffset = -1
        sliderDragFraction = 0
        sliderDragStartDay = 0
        isDraggingDateSlider = false
        showDateSlider = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.2)) {
                tutorialStep = .intro
            }
        }
    }

    func advanceWeatherTutorial() {
        guard let currentStep = tutorialStep,
              let currentIndex = WeatherTutorialStep.allCases.firstIndex(of: currentStep) else {
            tutorialStep = nil
            return
        }

        let nextIndex = WeatherTutorialStep.allCases.index(after: currentIndex)
        if nextIndex < WeatherTutorialStep.allCases.endIndex {
            let nextStep = WeatherTutorialStep.allCases[nextIndex]
            if shouldUseIPadLayout, nextStep == .listManager {
                iPadSidebarVisibility = .all
            }
            withAnimation(.easeOut(duration: 0.2)) {
                tutorialStep = nextStep
            }
        } else {
            let shouldShowListPicker = shouldShowFirstLaunchListPickerAfterTutorial
            shouldShowFirstLaunchListPickerAfterTutorial = false
            withAnimation(.easeOut(duration: 0.2)) {
                tutorialStep = nil
            }
            if shouldShowListPicker {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        showingFirstLaunchListPicker = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    var weatherTutorialOverlay: some View {
        if let tutorialStep {
            WeatherTutorialOverlay(
                step: tutorialStep,
                targetFrame: tutorialStep.target.flatMap { tutorialTargetFrames[$0] },
                onAdvance: advanceWeatherTutorial
            )
        }
    }
}
#endif
