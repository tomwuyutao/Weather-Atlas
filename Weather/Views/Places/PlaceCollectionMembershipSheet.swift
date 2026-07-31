//
//  PlaceCollectionMembershipSheet.swift
//  Weather
//
//  Purpose: Edits optional many-to-many collection membership with a native
//  list. Saving a place never requires choosing a collection.
//

import SwiftUI

struct PlaceCollectionMembershipSheet: View {
    let place: SavedPlace
    let placesStore: PlacesStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var presentedError: CollectionMembershipError?
    @State private var isCreatingCollection = false

    private var collectionIDs: Set<PlaceCollection.ID> {
        Set(placesStore.collections(containing: place.id).map(\.id))
    }

    var body: some View {
        NavigationStack {
            Group {
                if placesStore.collections.isEmpty {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "folder")
                    } description: {
                        Text(
                            "Collections are optional. Create one when you want to group places."
                        )
                    } actions: {
                        Button(
                            "New Collection",
                            systemImage: "folder.badge.plus",
                            action: {
                                isCreatingCollection = true
                            }
                        )
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(placesStore.collections) { collection in
                        Toggle(
                            isOn: membershipBinding(for: collection)
                        ) {
                            Label(collection.name, systemImage: "folder")
                        }
                    }
                    .weatherAtlasScrollableBackground()
                }
            }
            .weatherAtlasScreenBackground()
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Unable to Update Collection",
                isPresented: errorIsPresented,
                presenting: presentedError
            ) { _ in
                Button("OK") {
                    presentedError = nil
                }
            } message: { error in
                Text(error.message)
            }
            .sheet(isPresented: $isCreatingCollection) {
                CreateCollectionSheet(
                    placesStore: placesStore,
                    placeID: place.id
                )
            }
        }
        .presentationSizing(.form)
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

    private func membershipBinding(
        for collection: PlaceCollection
    ) -> Binding<Bool> {
        Binding {
            collectionIDs.contains(collection.id)
        } set: { isMember in
            do {
                try placesStore.setMembership(
                    of: place.id,
                    in: collection.id,
                    isMember: isMember
                )
            } catch {
                presentedError = CollectionMembershipError(
                    message: localizedPlacesErrorDescription(
                        error,
                        locale: locale
                    )
                )
            }
        }
    }
}

private struct CollectionMembershipError: Identifiable {
    let id = UUID()
    let message: String
}
