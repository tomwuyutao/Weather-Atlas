//
//  ManageCollectionsView.swift
//  Weather
//
//  Purpose: Provides native optional-collection management and many-to-many
//  membership editing without making collections a prerequisite for places.
//

import SwiftUI

/// Sheet wrapper used when collection management is presented modally.
struct ManageCollectionsSheet: View {
    let placesStore: PlacesStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ManageCollectionsView(placesStore: placesStore)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// Direct native creation flow used by the Places title menu and membership
/// editor. An optional place is included as part of the same verified write.
struct CreateCollectionSheet: View {
    let placesStore: PlacesStore
    let placeID: SavedPlace.ID?

    var body: some View {
        CollectionEditorSheet(
            placesStore: placesStore,
            request: .create(placeID: placeID)
        )
        .presentationSizing(.form)
    }
}

/// Native list for creating, renaming, reordering, and deleting optional
/// collections. Deleting a collection never deletes its saved places.
struct ManageCollectionsView: View {
    let placesStore: PlacesStore

    @State private var editorRequest: CollectionEditorRequest?
    @State private var pendingDeletion: PlaceCollection?
    @State private var presentedError: CollectionOperationError?

    var body: some View {
        Group {
            if placesStore.collections.isEmpty {
                ContentUnavailableView {
                    Label("No Collections", systemImage: "folder")
                } description: {
                    Text(
                        "Collections are optional. All saved places remain available in All Places."
                    )
                } actions: {
                    Button("New Collection", systemImage: "plus") {
                        editorRequest = .create(placeID: nil)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                collectionsList
            }
        }
        .weatherAtlasScreenBackground()
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !placesStore.collections.isEmpty {
                    EditButton()
                }

                Button("New Collection", systemImage: "plus") {
                    editorRequest = .create(placeID: nil)
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            CollectionEditorSheet(
                placesStore: placesStore,
                request: request
            )
            .presentationSizing(.form)
        }
        .confirmationDialog(
            pendingDeletion.map {
                localizedString(
                    "Delete “\($0.name)”?",
                    locale: locale
                )
            } ?? "",
            isPresented: deletionIsPresented,
            presenting: pendingDeletion
        ) { collection in
            Button("Delete", role: .destructive) {
                delete(collection)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The places in this collection will remain in All Places.")
        }
        .alert(
            "Couldn’t Update Collections",
            isPresented: errorIsPresented,
            presenting: presentedError
        ) { _ in
            Button("OK") {
                presentedError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    private var collectionsList: some View {
        List {
            Section {
                ForEach(placesStore.collections) { collection in
                    NavigationLink {
                        CollectionMembershipView(
                            placesStore: placesStore,
                            collectionID: collection.id
                        )
                    } label: {
                        CollectionSummaryLabel(
                            collection: collection,
                            placeCount: collection.placeIDs.count
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = collection
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editorRequest = .rename(collection.id)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            editorRequest = .rename(collection.id)
                        }

                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = collection
                        }
                    }
                }
                .onMove(perform: moveCollections)
            } footer: {
                Text(
                    "Deleting a collection removes only the grouping. Its places stay in All Places."
                )
            }
        }
        .listStyle(.insetGrouped)
        .weatherAtlasScrollableBackground()
    }

    private func moveCollections(
        from source: IndexSet,
        to destination: Int
    ) {
        var orderedIDs = placesStore.collections.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)

        do {
            try placesStore.setCollectionOrder(orderedIDs)
        } catch {
            presentedError = CollectionOperationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }

    @Environment(\.locale) private var locale

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private func delete(_ collection: PlaceCollection) {
        do {
            try placesStore.deleteCollection(id: collection.id)
            pendingDeletion = nil
        } catch {
            pendingDeletion = nil
            presentedError = CollectionOperationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }
}

/// Lets a user add or remove every saved place from one optional collection.
struct CollectionMembershipView: View {
    let placesStore: PlacesStore
    let collectionID: PlaceCollection.ID

    @State private var query = ""
    @State private var presentedError: CollectionOperationError?
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if collection == nil {
                ContentUnavailableView(
                    "Collection Unavailable",
                    systemImage: "folder.badge.questionmark",
                    description: Text("This collection no longer exists.")
                )
            } else if placesStore.allPlaces.isEmpty {
                ContentUnavailableView(
                    "No Saved Places",
                    systemImage: "mappin.slash",
                    description: Text(
                        "Save places first, then choose which ones belong in this collection."
                    )
                )
            } else if filteredPlaces.isEmpty {
                ContentUnavailableView.search(text: normalizedQuery)
            } else {
                List(filteredPlaces) { place in
                    Toggle(
                        isOn: membershipBinding(for: place.id)
                    ) {
                        SavedPlaceMembershipLabel(place: place)
                    }
                }
                .listStyle(.insetGrouped)
                .weatherAtlasScrollableBackground()
            }
        }
        .weatherAtlasScreenBackground()
        .navigationTitle(
            collection?.name
                ?? localizedString("Collection", locale: locale)
        )
        .searchable(text: $query, prompt: "Search places")
        .alert(
            "Couldn’t Update Collection",
            isPresented: errorIsPresented,
            presenting: presentedError
        ) { _ in
            Button("OK") {
                presentedError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    private var collection: PlaceCollection? {
        placesStore.collections.first { $0.id == collectionID }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredPlaces: [SavedPlace] {
        guard !normalizedQuery.isEmpty else {
            return placesStore.allPlaces
        }

        return placesStore.allPlaces.filter { place in
            place.displayName.localizedStandardContains(normalizedQuery)
                || place.city.country.localizedStandardContains(normalizedQuery)
        }
    }

    private func membershipBinding(
        for placeID: SavedPlace.ID
    ) -> Binding<Bool> {
        Binding {
            collection?.placeIDs.contains(placeID) == true
        } set: { isMember in
            do {
                try placesStore.setMembership(
                    of: placeID,
                    in: collectionID,
                    isMember: isMember
                )
            } catch {
                presentedError = CollectionOperationError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
    }
}

/// Lets a place-detail screen edit one place's many-to-many collection
/// memberships, and create a new collection containing that place.
struct PlaceCollectionsView: View {
    let placesStore: PlacesStore
    let placeID: SavedPlace.ID

    @State private var editorRequest: CollectionEditorRequest?
    @State private var presentedError: CollectionOperationError?
    @Environment(\.locale) private var locale

    var body: some View {
        Group {
            if placesStore.place(id: placeID) == nil {
                ContentUnavailableView(
                    "Place Unavailable",
                    systemImage: "mappin.slash",
                    description: Text("This saved place no longer exists.")
                )
            } else if placesStore.collections.isEmpty {
                ContentUnavailableView {
                    Label("No Collections", systemImage: "folder")
                } description: {
                    Text("Collections are optional ways to group saved places.")
                } actions: {
                    Button("New Collection", systemImage: "plus") {
                        editorRequest = .create(placeID: placeID)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(placesStore.collections) { collection in
                    Toggle(
                        isOn: membershipBinding(for: collection.id)
                    ) {
                        CollectionSummaryLabel(
                            collection: collection,
                            placeCount: collection.placeIDs.count
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .weatherAtlasScrollableBackground()
            }
        }
        .weatherAtlasScreenBackground()
        .navigationTitle("Collections")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Collection", systemImage: "plus") {
                    editorRequest = .create(placeID: placeID)
                }
            }
        }
        .sheet(item: $editorRequest) { request in
            CollectionEditorSheet(
                placesStore: placesStore,
                request: request
            )
            .presentationSizing(.form)
        }
        .alert(
            "Couldn’t Update Collections",
            isPresented: errorIsPresented,
            presenting: presentedError
        ) { _ in
            Button("OK") {
                presentedError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    private func membershipBinding(
        for collectionID: PlaceCollection.ID
    ) -> Binding<Bool> {
        Binding {
            placesStore.collections
                .first { $0.id == collectionID }?
                .placeIDs
                .contains(placeID) == true
        } set: { isMember in
            do {
                try placesStore.setMembership(
                    of: placeID,
                    in: collectionID,
                    isMember: isMember
                )
            } catch {
                presentedError = CollectionOperationError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }
}

/// Compact, Dynamic-Type-safe summary reused by collection lists and toggles.
private struct CollectionSummaryLabel: View {
    let collection: PlaceCollection
    let placeCount: Int

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)

                Text("\(placeCount) places")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.tint)
        }
    }
}

/// Dynamic-Type-safe saved-place label for membership toggles.
private struct SavedPlaceMembershipLabel: View {
    let place: SavedPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(place.displayName)

            if !place.city.country.isEmpty {
                Text(place.city.country)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Item-driven purpose for the native collection-name form.
private enum CollectionEditorRequest: Identifiable {
    case create(placeID: SavedPlace.ID?)
    case rename(PlaceCollection.ID)

    var id: String {
        switch self {
        case .create(let placeID):
            return "create-\(placeID?.uuidString ?? "empty")"
        case .rename(let collectionID):
            return "rename-\(collectionID)"
        }
    }
}

/// Small native form used for both collection creation and rename.
private struct CollectionEditorSheet: View {
    let placesStore: PlacesStore
    let request: CollectionEditorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var presentedError: CollectionOperationError?

    init(
        placesStore: PlacesStore,
        request: CollectionEditorRequest
    ) {
        self.placesStore = placesStore
        self.request = request

        let initialName: String
        switch request {
        case .create:
            initialName = ""
        case .rename(let collectionID):
            initialName = placesStore.collections
                .first { $0.id == collectionID }?
                .name ?? ""
        }
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit(save)
                } footer: {
                    Text(
                        "Collections organize saved places without removing them from All Places."
                    )
                }
            }
            .weatherAtlasScrollableBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(normalizedName.isEmpty)
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
        .alert(
            "Couldn’t Save Collection",
            isPresented: errorIsPresented,
            presenting: presentedError
        ) { _ in
            Button("OK") {
                presentedError = nil
            }
        } message: { error in
            Text(error.message)
        }
    }

    private var navigationTitle: String {
        switch request {
        case .create:
            return localizedString("New Collection", locale: locale)
        case .rename:
            return localizedString("Rename Collection", locale: locale)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    presentedError = nil
                }
            }
        )
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        do {
            switch request {
            case .create(let placeID):
                try placesStore.createCollection(
                    name: normalizedName,
                    placeIDs: placeID.map { [$0] } ?? []
                )
            case .rename(let collectionID):
                try placesStore.renameCollection(
                    id: collectionID,
                    to: normalizedName
                )
            }
            dismiss()
        } catch {
            presentedError = CollectionOperationError(
                message: localizedPlacesErrorDescription(
                    error,
                    locale: locale
                )
            )
        }
    }
}

/// Recoverable native alert payload for collection operations.
private struct CollectionOperationError: Identifiable {
    let id = UUID()
    let message: String
}
