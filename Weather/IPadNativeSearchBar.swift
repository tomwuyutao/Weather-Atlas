//
//  IPadNativeSearchBar.swift
//  Weather
//
//  Native UIKit search field used in the iPad toolbar.
//

#if os(iOS)
import SwiftUI
import UIKit

struct IPadNativeSearchBar: UIViewRepresentable {
    @Binding var text: String
    @Binding var isPresented: Bool
    let placeholder: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isPresented: $isPresented, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.delegate = context.coordinator
        searchBar.placeholder = placeholder
        searchBar.searchBarStyle = .minimal
        searchBar.autocapitalizationType = .words
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .search
        searchBar.backgroundImage = UIImage()
        searchBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)
        searchBar.searchTextField.clearButtonMode = .whileEditing
        searchBar.searchTextField.borderStyle = .none
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isPresented = $isPresented
        context.coordinator.onSubmit = onSubmit

        if searchBar.text != text {
            searchBar.text = text
        }
        if searchBar.placeholder != placeholder {
            searchBar.placeholder = placeholder
        }
        if isPresented && !searchBar.isFirstResponder {
            searchBar.becomeFirstResponder()
        }
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var text: Binding<String>
        var isPresented: Binding<Bool>
        var onSubmit: () -> Void

        init(text: Binding<String>, isPresented: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.isPresented = isPresented
            self.onSubmit = onSubmit
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            isPresented.wrappedValue = true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            isPresented.wrappedValue = false
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text.wrappedValue = searchText
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            onSubmit()
            searchBar.resignFirstResponder()
        }
    }
}
#endif
