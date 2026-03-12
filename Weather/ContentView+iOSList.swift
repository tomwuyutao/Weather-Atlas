//
//  ContentView+iOSList.swift
//  Weather
//
//  iOS list view, grid view, list switcher, and list management.
//

import SwiftUI
import UniformTypeIdentifiers

#if !os(macOS)
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
                    showingListSwitcher = true
                } label: {
                    Text(weatherService.activeListID.localizedDisplayName(locale: locale))
                        .font(.avenir(.title, weight: .bold))
                        .overlay(alignment: .trailing) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .offset(x: 20)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingListSwitcher) {
                    iOSListSwitcherMenu
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
    }

    var iOSListSwitcherMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isReorderingLists {
                // Reorder mode: drag handle items
                let rowHeight: CGFloat = 44
                ForEach(Array(reorderableLists.enumerated()), id: \.element.id) { index, listID in
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .opacity(draggingListID == listID ? 0.5 : 1.0)
                    .offset(y: draggingListID == listID ? dragOffset : 0)
                    .zIndex(draggingListID == listID ? 1 : 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if draggingListID == nil {
                                    draggingListID = listID
                                }
                                guard draggingListID == listID else { return }
                                dragOffset = value.translation.height
                                
                                guard let fromIndex = reorderableLists.firstIndex(of: listID) else { return }
                                let proposedOffset = Int(round(value.translation.height / rowHeight))
                                let toIndex = min(max(fromIndex + proposedOffset, 0), reorderableLists.count - 1)
                                if toIndex != fromIndex {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        reorderableLists.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
                                    }
                                    // Reset offset after move so it stays near the finger
                                    let moved = toIndex - fromIndex
                                    dragOffset -= CGFloat(moved) * rowHeight
                                }
                            }
                            .onEnded { _ in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    dragOffset = 0
                                    draggingListID = nil
                                }
                            }
                    )
                }
                
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                
                // Done button
                Button {
                    CityListID.saveListOrder(reorderableLists)
                    isReorderingLists = false
                } label: {
                    HStack(spacing: 12) {
                        Text("Done")
                            .font(.avenir(.body, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Normal mode: tappable list items
                ForEach(CityListID.allLists) { listID in
                    Button {
                        showingListSwitcher = false
                        guard listID != weatherService.activeListID else { return }
                        mapHasInitialized = false
                        recenterOnAllCities = false
                        withAnimation(.easeOut(duration: 0.15)) {
                            listContentOpacity = 0
                        }
                        Task {
                            try? await Task.sleep(for: .milliseconds(150))
                            await weatherService.switchList(to: listID)
                            withAnimation(.easeIn(duration: 0.2)) {
                                listContentOpacity = 1
                            }
                            recenterOnAllCities = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text(listID.localizedDisplayName(locale: locale))
                                .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if listID == weatherService.activeListID {
                                Circle()
                                    .fill(theme.colors.accent)
                                    .frame(width: 6, height: 6)
                                    .frame(width: 13)
                            }
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 16)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                
                Button {
                    showingListSwitcher = false
                    startAddingNewList()
                } label: {
                    HStack(spacing: 12) {
                        Text("Add List")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    showingListSwitcher = false
                    startEditingListName()
                } label: {
                    HStack(spacing: 12) {
                        Text("Rename List")
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    reorderableLists = CityListID.allLists
                    isReorderingLists = true
                } label: {
                    HStack(spacing: 12) {
                        Text("Reorder Lists")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Button {
                    showingListSwitcher = false
                    showingDeleteListConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Text(localizedString("Delete List", locale: locale))
                            .font(.avenir(.body, weight: .medium))
                            .foregroundStyle(theme.colors.destructive)
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.destructive)
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
        .onChange(of: showingListSwitcher) { _, showing in
            if !showing {
                isReorderingLists = false
                draggingListID = nil
                dragOffset = 0
            }
        }
    }
    
    var iOSListSwitcherMenuListsOnly: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(CityListID.allLists) { listID in
                Button {
                    showingListSwitcher = false
                    guard listID != weatherService.activeListID else { return }
                    mapHasInitialized = false
                    recenterOnAllCities = false
                    withAnimation(.easeOut(duration: 0.15)) {
                        listContentOpacity = 0
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        await weatherService.switchList(to: listID)
                        withAnimation(.easeIn(duration: 0.2)) {
                            listContentOpacity = 1
                        }
                        recenterOnAllCities = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(listID.localizedDisplayName(locale: locale))
                            .font(.avenir(.body, weight: listID == weatherService.activeListID ? .bold : .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        if listID == weatherService.activeListID {
                            Circle()
                                .fill(theme.colors.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.leading, 24)
                    .padding(.trailing, 16)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 210)
        .themedPopoverBackground()
    }

    // MARK: - Grid Cell

    @ViewBuilder
    func gridCell(for cityWeather: CityWeather) -> some View {
        let forecast = cityWeather.forecast(for: selectedDayOffset)
        VStack(spacing: 8) {
            Image(systemName: forecast.weatherIcon)
                .font(.title2)
                .weatherIconStyle(for: forecast.weatherIcon)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .replace)))
                .frame(height: 30)

            Text(tempUnit.display(forecast.daytimeHigh))
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
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
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
        .onDrag {
            if isEditMode {
                gridDragItem = cityWeather
                return NSItemProvider(object: cityWeather.id.uuidString as NSString)
            }
            return NSItemProvider()
        }
        .onDrop(of: [.text], delegate: GridDropDelegate(
            item: cityWeather,
            dragItem: $gridDragItem,
            cities: weatherService.cityWeatherData,
            moveCity: { from, to in
                weatherService.moveCity(from: from, to: to)
            }
        ))
        .contextMenu {
            if !isEditMode {
                Button(role: .destructive) {
                    weatherService.removeCity(cityWeather)
                    if selectedCity?.id == cityWeather.id {
                        selectedCity = nil
                    }
                } label: {
                    Label(localizedString("Delete", locale: locale), systemImage: "trash")
                }
            }
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
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
                } else if horizontal > 0 && selectedDayOffset > 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        iOSPreviousDayOffset = selectedDayOffset
                        selectedDayOffset -= 1
                    }
                }
            }
    }

    // MARK: - Main List View

    var iOSListView: some View {
        Group {
            if weatherService.cityWeatherData.isEmpty && weatherService.isLoading {
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
            } else if weatherService.cityWeatherData.isEmpty && weatherService.hasSavedCities {
                VStack(spacing: 0) {
                    iOSListSwitcher
                        .padding(.top, 24)
                        .padding(.bottom, 20)
                    Spacer()
                    ContentUnavailableView(localizedString("Loading Weather", locale: locale), systemImage: "cloud.sun", description: Text(localizedString("Fetching forecasts for your cities…", locale: locale)))
                    Spacer()
                }
            } else if weatherService.cityWeatherData.isEmpty {
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
            } else if isGridView {
                ScrollView {
                    iOSListSwitcher
                        .padding(.top, 24)
                        .padding(.bottom, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(iOSFilteredCities) { cityWeather in
                            gridCell(for: cityWeather)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, isIPad ? 20 : 100)
                }
                .gesture(swipeDayGesture())
                .transition(.opacity)
            } else {
                List {
                    iOSListSwitcher
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 20, trailing: 16))
                        .padding(.top, 8)

                    ForEach(iOSFilteredCities) { cityWeather in
                        HStack {
                            Text(cityWeather.city.localizedName(locale: locale))
                                .font(.avenir(.body, weight: .medium))
                            Spacer()
                            Text(tempUnit.display(cityWeather.forecast(for: selectedDayOffset).daytimeHigh))
                                .font(.avenir(.title2, weight: .medium))
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .padding(.trailing, 4)
                            Image(systemName: cityWeather.forecast(for: selectedDayOffset).weatherIcon)
                                .font(.title3)
                                .weatherIconStyle(for: cityWeather.forecast(for: selectedDayOffset).weatherIcon)
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
                    .onDelete(perform: isEditMode ? { indexSet in
                        for index in indexSet {
                            let cityToDelete = iOSFilteredCities[index]
                            weatherService.removeCity(cityToDelete)
                            if selectedCity?.id == cityToDelete.id {
                                selectedCity = nil
                            }
                        }
                    } : nil)
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
        }
        .opacity(listContentOpacity)
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
                let forecast = $0.forecast(for: selectedDayOffset)
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
#endif
#Preview {
    let _ = UserDefaults.standard.set(false, forKey: "isGridView")
    let _ = UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    ContentView()
}

