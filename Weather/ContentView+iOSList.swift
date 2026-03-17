//
//  ContentView+iOSList.swift
//  Weather
//
//  iOS list view, grid view, list switcher, and list management.
//

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {

    // MARK: - List Switcher

    var iOSListSwitcher: some View {
        Group {
            if isEditingListName {
                TextField("List name", text: $editingListName)
                    .font(.avenir(.title, weight: .bold))
                    .multilineTextAlignment(.center)
                    .submitLabel(.done)
                    .focused($listNameFieldFocused)
                    .onSubmit { commitListNameEdit() }
                    .onChange(of: listNameFieldFocused) { _, focused in
                        if !focused { commitListNameEdit() }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear { listNameFieldFocused = true }
            } else {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showingListSidebar = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(weatherService.activeListID.localizedDisplayName(locale: locale))
                            .font(.avenir(.title, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Grid Cell

    @ViewBuilder
    func gridCell(for cityWeather: CityWeather) -> some View {
        let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
        let isNow = selectedDayOffset == -1
        let displayIcon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
        let displayTemp = isNow ? cityWeather.temperature : forecast.dailyHigh
        VStack(spacing: 8) {
            Image(systemName: displayIcon)
                .font(.title2)
                .weatherIconStyle(for: displayIcon)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(height: 30)

            Text(tempUnit.display(displayTemp))
                .font(.avenir(.title2, weight: .medium))
                .contentTransition(.numericText())

            Text(cityWeather.city.localizedName(locale: locale))
                .font(.avenir(.footnote, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background {
            if theme.colors.listCardFill == .clear {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(longPressedCity?.id == cityWeather.id ? Color.primary.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.listCardFill)
            }
        }
        .overlay(alignment: .topLeading) {
            if isEditMode {
                Button {
                    withAnimation {
                        weatherService.removeCity(cityWeather)
                        if selectedCity?.id == cityWeather.id {
                            selectedCity = nil
                        }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, theme.colors.destructive)
                }
                .offset(x: -6, y: -6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        
        .onTapGesture {
            if !isEditMode {
                detailOpenedFromList = true
                tappedCity = cityWeather
                showingCityDetail = true
            }
        }
        .scaleEffect(longPressedCity?.id == cityWeather.id ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.2), value: longPressedCity?.id)
        .onLongPressGesture {
            if !isEditMode {
                longPressedCity = cityWeather
            }
        }
        .if(isEditMode) {
            $0.onDrag {
                gridDragItem = cityWeather
                return NSItemProvider(object: cityWeather.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: GridDropDelegate(
                item: cityWeather,
                dragItem: $gridDragItem,
                cities: weatherService.cityWeatherData,
                moveCity: { from, to in
                    weatherService.moveCity(from: from, to: to)
                }
            ))
        }
        .popover(isPresented: Binding(
            get: { longPressedCity?.id == cityWeather.id },
            set: { if !$0 { longPressedCity = nil } }
        )) {
            VStack(alignment: .leading, spacing: 0) {
                menuRow(icon: "map", title: localizedString("Reveal on Map", locale: locale)) {
                    let revealCity = cityWeather
                    longPressedCity = nil
                    showingCityDetail = false
                    centerOnCityTrigger = nil
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedTab = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        centerOnCityTrigger = revealCity
                    }
                }

                Divider().padding(.horizontal, 12).padding(.vertical, 4)

                menuRow(icon: "trash", title: localizedString("Delete City", locale: locale)) {
                    longPressedCity = nil
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                }
                .foregroundStyle(theme.colors.destructive)
            }
            .padding(.vertical, 8)
            .frame(width: 220)
            .presentationCompactAdaptation(.popover)
            .themedPopoverBackground()
        }
    }

    // MARK: - List Management

    func startEditingListName() {
        editingListName = weatherService.activeListID.localizedDisplayName(locale: locale)
        isEditingListName = true
    }
    
    func startAddingNewList() {
        isAddingNewList = true
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await weatherService.addNewList(name: "")
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            editingListName = ""
            isEditingListName = true
        }
    }
    
    func deleteCurrentList() {
        withAnimation(.easeOut(duration: 0.15)) {
            listContentOpacity = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await weatherService.deleteCurrentList()
            withAnimation(.easeIn(duration: 0.2)) {
                listContentOpacity = 1
            }
            recenterOnAllCities = true
        }
    }
    
    func commitListNameEdit() {
        let name = editingListName.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isEditingListName = false
        }
        if name.isEmpty {
            // Empty name: use "New List" for new lists, keep existing name for renames
            if isAddingNewList {
                weatherService.renameCurrentList(to: localizedString("New List", locale: locale))
            }
        } else {
            weatherService.renameCurrentList(to: name)
        }
        isAddingNewList = false
    }

    // MARK: - Swipe Day Gesture

    func swipeDayGesture() -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                let maxDay = max(weatherService.forecastDays.count - 1, 0)
                if horizontal < 0 && selectedDayOffset < maxDay {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iOSPreviousDayOffset = selectedDayOffset
                        selectedDayOffset += 1
                    }
                } else if horizontal > 0 && selectedDayOffset > -1 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iOSPreviousDayOffset = selectedDayOffset
                        selectedDayOffset -= 1
                    }
                }
            }
    }

    // MARK: - Main List View

    @ViewBuilder
    var iOSListView: some View {
        Group {
            if weatherService.cityWeatherData.isEmpty {
                iOSListEmptyState
            } else if isGridView {
                iOSGridContent
            } else {
                iOSPlainListContent
            }
        }
        .opacity(listContentOpacity)
        .overlay {
            if weatherService.isLoading, listContentOpacity < 1 {
                GeometryReader { geo in
                    VStack(spacing: 20) {
                        Image(systemName: "cloud.sun.fill")
                            .font(.system(size: 56))
                            .weatherIconStyle(for: "cloud.sun.fill")
                        Text(localizedString("Loading Weather", locale: locale))
                            .font(.avenir(.title2, weight: .semibold))
                        Capsule()
                            .fill(theme.colors.primaryText.opacity(0.15))
                            .frame(width: 140, height: 4)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(theme.colors.primaryText)
                                    .frame(width: 140 * weatherService.loadingProgress, height: 4)
                            }
                    }
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var iOSListEmptyState: some View {
        if weatherService.isLoading {
            // First launch loading state
            GeometryReader { geo in
                VStack(spacing: 20) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 56))
                        .weatherIconStyle(for: "cloud.sun.fill")
                    Text(localizedString("Loading Weather", locale: locale))
                        .font(.avenir(.title2, weight: .semibold))
                    Capsule()
                        .fill(theme.colors.primaryText.opacity(0.15))
                        .frame(width: 140, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(theme.colors.primaryText)
                                .frame(width: 140 * weatherService.loadingProgress, height: 4)
                        }
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        } else if weatherService.hasSavedCities {
            VStack(spacing: 0) {
                iOSListSwitcher
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                Spacer()
                ContentUnavailableView(localizedString("Loading Weather", locale: locale), systemImage: "cloud.sun", description: Text(localizedString("Fetching forecasts for your cities…", locale: locale)))
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                iOSListSwitcher
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                Spacer()
                if !isEditingListName {
                    Button {
                        if isIPad {
                            showingAddCityView = true
                        } else {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                showingInlineSearch = true
                            }
                        }
                    } label: {
                        Label(localizedString("Search", locale: locale), systemImage: "magnifyingglass")
                            .font(.avenir(.body, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(theme.colors.accent, in: Capsule())
                            .themedGlass(in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 40)
                    .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Grid Content

    private var iOSGridContent: some View {
        ScrollView {
            iOSListSwitcher
                .padding(.top, 24)
                .padding(.bottom, 20)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(iOSFilteredCities) { cityWeather in
                    gridCell(for: cityWeather)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, isIPad ? 20 : 100)
        }
        .gesture(swipeDayGesture())
        .transition(.opacity)
    }

    // MARK: - Plain List Content

    private var iOSPlainListContent: some View {
        List {
            iOSListSwitcher
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                .padding(.top, 8)

            ForEach(iOSFilteredCities) { cityWeather in
                HStack(spacing: 0) {
                    if isEditMode {
                        Button {
                            withAnimation {
                                weatherService.removeCity(cityWeather)
                                if selectedCity?.id == cityWeather.id {
                                    selectedCity = nil
                                }
                            }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, theme.colors.destructive)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    let isNow = selectedDayOffset == -1
                    let forecast = cityWeather.forecast(for: max(0, selectedDayOffset))
                    let displayIcon = isNow ? cityWeather.weatherIcon : forecast.weatherIcon
                    let displayTemp = isNow ? cityWeather.temperature : forecast.dailyHigh
                    Text(cityWeather.city.localizedName(locale: locale))
                        .font(.avenir(.body, weight: .medium))
                    Spacer()
                    Text(tempUnit.display(displayTemp))
                        .font(.avenir(.title2, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .padding(.trailing, 4)
                    Image(systemName: displayIcon)
                        .font(.title3)
                        .weatherIconStyle(for: displayIcon)
                        .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                        .frame(width: 32)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 22)
                .background {
                    if theme.colors.listCardFill == .clear {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(longPressedCity?.id == cityWeather.id ? Color.primary.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                    }
                }
                .scaleEffect(longPressedCity?.id == cityWeather.id ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.2), value: longPressedCity?.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isEditMode {
                        detailOpenedFromList = true
                        tappedCity = cityWeather
                        showingCityDetail = true
                    }
                }
                .onLongPressGesture {
                    longPressedCity = cityWeather
                }
                .popover(isPresented: Binding(
                    get: { longPressedCity?.id == cityWeather.id },
                    set: { if !$0 { longPressedCity = nil } }
                )) {
                    VStack(alignment: .leading, spacing: 0) {
                        menuRow(icon: "map", title: localizedString("Reveal on Map", locale: locale)) {
                            let revealCity = cityWeather
                            longPressedCity = nil
                            showingCityDetail = false
                            centerOnCityTrigger = nil
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                centerOnCityTrigger = revealCity
                            }
                        }
                        
                        Divider().padding(.horizontal, 12).padding(.vertical, 4)
                        
                        menuRow(icon: "trash", title: localizedString("Delete City", locale: locale)) {
                            longPressedCity = nil
                            weatherService.removeCity(cityWeather)
                            if selectedCity?.id == cityWeather.id {
                                selectedCity = nil
                            }
                        }
                        .foregroundStyle(theme.colors.destructive)
                    }
                    .padding(.vertical, 8)
                    .frame(width: 220)
                    .presentationCompactAdaptation(.popover)
                    .themedPopoverBackground()
                }
            }
            .onMove(perform: isEditMode ? { source, destination in
                weatherService.moveCity(from: source, to: destination)
            } : nil)
            .listRowBackground(Color.clear)
            .listRowSeparator(theme.colors.listCardFill == .clear ? .hidden : .visible)
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 16 }
            .alignmentGuide(.listRowSeparatorTrailing) { d in d[.trailing] - 16 }
            .listRowInsets(EdgeInsets(top: theme.colors.listCardFill == .clear ? 4 : 0, leading: 16, bottom: theme.colors.listCardFill == .clear ? 4 : 0, trailing: 16))
        }
        .listStyle(.plain)
        .contentMargins(.bottom, isIPad ? 20 : 100)
        .environment(\.editMode, Binding(
            get: { isEditMode ? .active : .inactive },
            set: { newValue in isEditMode = (newValue == .active) }
        ))
        .gesture(swipeDayGesture())
        .transition(.opacity)
    }

    var iOSFilteredCities: [CityWeather] {
        var cities = weatherService.cityWeatherData
        if !searchText.isEmpty {
            cities = cities.filter {
                $0.city.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        if filterSunny {
            cities = cities.filter {
                let forecast = $0.forecast(for: max(0, selectedDayOffset))
                return forecast.condition == .clear
            }
        }
        return cities
    }
}

// MARK: - Grid Drop Delegate

struct GridDropDelegate: DropDelegate {
    let item: CityWeather
    @Binding var dragItem: CityWeather?
    let cities: [CityWeather]
    let moveCity: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        dragItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragItem,
              dragItem.id != item.id,
              let fromIndex = cities.firstIndex(where: { $0.id == dragItem.id }),
              let toIndex = cities.firstIndex(where: { $0.id == item.id }) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            moveCity(IndexSet(integer: fromIndex), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct CountrySearchSheet: View {
    let onSelect: (String) -> Void
    
    @State private var searchText: String = ""
    @State private var allCountries: [String] = []
    @Environment(\.dismiss) private var dismiss
    
    private var filteredCountries: [String] {
        if searchText.isEmpty {
            return allCountries
        }
        return allCountries.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredCountries, id: \.self) { country in
                Button {
                    onSelect(country)
                } label: {
                    Text(country)
                        .font(.avenir(.body, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Add Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if allCountries.isEmpty {
                allCountries = WorldCitiesParser.countriesWithEnoughCities()
            }
        }
    }
}

#Preview {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

