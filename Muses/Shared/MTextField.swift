//
//  MusesTextField.swift
//  Muses
//
//  Created by 何纪栋 on 2026/9/13.
//
import SwiftUI

struct MTextField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        HStack(alignment: axis == .vertical ? .top : .center, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(MusesTheme.coral)
                .frame(width: 42, height: 42)
                .background(MusesTheme.coralSoft, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(MusesTheme.secondaryInk)
                TextField(placeholder, text: $text, axis: axis)
                    .font(.body.weight(.medium))
                    .lineLimit(axis == .vertical ? 2...4 : 1...1)
            }
        }
    }
}
