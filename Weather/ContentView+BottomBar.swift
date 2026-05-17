//
//  ContentView+BottomBar.swift
//  Weather
//
//  Extracted from ContentView.swift
//

import SwiftUI

extension ContentView {

    @ViewBuilder
    var mapBottomToolbar: some View {
        HStack(spacing: 14) {
            Button {
                PlatformFeedback.lightImpact()
                #if os(iOS)
                if shouldUseIPadLayout {
                    iPadPreferredCompactColumn = .sidebar
                    iPadSidebarVisibility = .all
                } else {
                    showingMapSidebar = true
                }
                #else
                showingMapSidebar = true
                #endif
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 4) {
                Button {
                    PlatformFeedback.lightImpact()
                    recenterOnAllCities = false
                    DispatchQueue.main.async {
                        recenterOnAllCities = true
                    }
                } label: {
                    Image(systemName: "dot.squareshape.split.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                mapOverlayMenu
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .tint(theme.colors.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())

                if filterSunny {
                    Button {
                        withAnimation {
                            filterSunny = false
                        }
                    } label: {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                iOSNativeMenu
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(3)
            .themedGlass(in: .capsule)
            .contentShape(Capsule())

            Spacer()

            Button {
                activateInlineSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .themedGlass(in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }


    // MARK: - Bottom Bar State Views

    @ViewBuilder
    private func bottomBarCountryConfirmState(pending: String) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                Task {
                    await weatherService.deleteCurrentList()
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    pendingCountryList = nil
                    isLoadingPendingCountry = false
                    recenterOnAllCities = true
                }
            }

        Text(pending)
            .font(.avenir(.subheadline, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 14)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
            .themedGlass(in: .capsule)
            .glassEffectID("bottomBarCenter", in: bottomBarNS)
            .contentShape(Capsule())

        if isLoadingPendingCountry {
            ProgressView()
                .frame(width: 36, height: 36)
                .padding(6)
                .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        } else {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingCountrySearch = false
                    pendingCountryList = nil
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            .glassEffectID("bottomBarRight", in: bottomBarNS)
            .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomBarCountrySearchState: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField(localizedString("Search for a country", locale: locale), text: $countrySearchText)
                .textFieldStyle(.plain)
                .font(.avenir(.subheadline, weight: .medium))
                .autocorrectionDisabled()
                .focused($countrySearchFocused)
            if !countrySearchText.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 14, weight: .medium))
                    .contentShape(Circle())
                    .onTapGesture { countrySearchText = "" }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .themedGlass(in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: countrySearchText.isEmpty)

        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarRight", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showingCountrySearch = false
                    countrySearchText = ""
                    countrySearchFocused = false
                    pendingCountryList = nil
                }
            }
    }

    @ViewBuilder
    private var bottomBarPreviewExpandedState: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    previewCity = nil
                    recenterOnAllCities = true
                }
            }

        Text(toolbarTitle)
            .font(.avenir(.subheadline, weight: .semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 14)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
            .themedGlass(in: .capsule)
            .glassEffectID("bottomBarCenter", in: bottomBarNS)
            .contentShape(Capsule())
            .onTapGesture {
                showingListSwitcher = true
            }

        addCityButton(dismissExpanded: true)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
    }

    @ViewBuilder
    private var bottomBarPreviewSearchState: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .padding(6)
            .matchedGeometryEffect(id: "bottomBarLeft", in: bottomBarNS)
            .themedGlass(in: .circle)
            .glassEffectID("bottomBarLeft", in: bottomBarNS)
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingMapExpandedCard = false
                    previewCity = nil
                    recenterOnAllCities = true
                }
            }

        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(previewSearchText)
                .font(.avenir(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .themedGlass(in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showingInlineSearch = true
                inlineSearchText = previewSearchText
            }
        }

        addCityButton(dismissExpanded: false)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
    }

    @ViewBuilder
    private var bottomBarNormalState: some View {
        HStack(spacing: 2) {
            bottomTabButton(title: localizedString("Map", locale: locale), systemImage: "map", tab: 1)
            bottomTabButton(title: localizedString("List", locale: locale), systemImage: isGridView ? "square.grid.2x2" : "list.bullet", tab: 0)
        }
        .padding(6)
        .matchedGeometryEffect(id: "bottomBarCenter", in: bottomBarNS)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("bottomBarCenter", in: bottomBarNS)

        Button {
            PlatformFeedback.lightImpact()
            activateInlineSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 58, height: 58)
        }
        .buttonStyle(.plain)
        .matchedGeometryEffect(id: "bottomBarRight", in: bottomBarNS)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID("bottomBarRight", in: bottomBarNS)
        .contentShape(Circle())
    }

    private func bottomTabButton(title: String, systemImage: String, tab: Int) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            PlatformFeedback.lightImpact()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.primaryText)
            .frame(width: 82, height: 50)
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(selectedTab == tab)
    }

    // MARK: - Unified Bottom Bar (morphs between toolbar and search)

    var iOSUnifiedBottomBar: some View {
        GlassEffectContainer(spacing: 12) {
        HStack(spacing: 12) {
            if showingCountrySearch, let pending = pendingCountryList {
                bottomBarCountryConfirmState(pending: pending)
            } else if showingCountrySearch {
                bottomBarCountrySearchState
            } else if previewCity != nil, showingMapExpandedCard {
                bottomBarPreviewExpandedState
            } else if previewCity != nil {
                bottomBarPreviewSearchState
            } else {
                bottomBarNormalState
            }
        }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .padding(.top, previewCity != nil ? 0 : 20)
        .background {
            if previewCity == nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { }
            }
        }
        .onChange(of: showingCountrySearch) { _, newValue in
            if newValue {
                if allCountries.isEmpty {
                    allCountries = WorldCitiesParser.countriesWithEnoughCities()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    countrySearchFocused = true
                }
            } else {
                countrySearchFocused = false
            }
        }
        .onChange(of: showingRenameAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    renameAlertFocused = true
                }
            } else {
                renameAlertFocused = false
            }
        }
        .onChange(of: showingCityRenameAlert) { _, isShowing in
            if isShowing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    cityRenameFocused = true
                }
            } else {
                cityRenameFocused = false
            }
        }
        .alert(localizedString("Rename", locale: locale), isPresented: $showingRenameAlert) {
            TextField(localizedString("Name", locale: locale), text: $renameAlertText)
                .focused($renameAlertFocused)
            Button(localizedString("Cancel", locale: locale), role: .cancel) { }
            Button(localizedString("OK", locale: locale)) {
                let trimmed = renameAlertText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if let listToRenameID {
                        weatherService.renameList(listToRenameID, to: trimmed)
                    } else {
                        weatherService.renameCurrentList(to: trimmed)
                    }
                }
                listToRenameID = nil
            }
        }
        .alert(localizedString("Rename", locale: locale), isPresented: $showingCityRenameAlert) {
            TextField(localizedString("Name", locale: locale), text: $cityRenameText)
                .focused($cityRenameFocused)
            Button(localizedString("Cancel", locale: locale), role: .cancel) { }
            Button(localizedString("OK", locale: locale)) {
                let trimmed = cityRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let city = cityToRename {
                    if let cityToRenameListID {
                        weatherService.renameCity(city, in: cityToRenameListID, to: trimmed)
                    } else {
                        weatherService.renameCity(city, to: trimmed)
                    }
                }
                cityToRenameListID = nil
            }
        }
    }


}
