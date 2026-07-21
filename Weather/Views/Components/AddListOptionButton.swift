//
//  AddListOptionButton.swift
//  Weather
//
//  Purpose: Defines the reusable icon, title, subtitle, and disclosure row
//  shared by list creation and tutorial selection screens.
//

import SwiftUI

// MARK: - Add-List Option Row

struct AddListOptionButton: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var titleWeight: Font.Weight = .semibold
    var titleColor: Color? = nil
    var showsIconBackground: Bool = true
    var iconColor: Color? = nil
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                addListOptionIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(titleWeight))
                        .foregroundStyle(titleColor ?? theme.colors.primaryText)

                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 22, alignment: .trailing)
            }
            .padding(.vertical, 16)
            .frame(minHeight: subtitle == nil ? 82 : 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var addListOptionIcon: some View {
        if showsIconBackground {
            Image(systemName: systemImage)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(iconColor ?? theme.colors.accent)
                .frame(width: 58, height: 58)
                .detailTranslucentCard(colorScheme: colorScheme, in: .rect(cornerRadius: 14))
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 33, weight: .regular))
                .foregroundStyle(iconColor ?? theme.colors.primaryText)
                .frame(width: 58, height: 58)
        }
    }
}
