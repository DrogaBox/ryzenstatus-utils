// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 RyzenStatus

import SwiftUI

extension View {
    /// Lets the whole header of a `DisclosureGroup` open and close it. On
    /// macOS only the small chevron does, which is hard to hit. Buttons and
    /// toggles inside the header keep their own clicks.
    func disclosureHeader(isExpanded: Binding<Bool>) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.wrappedValue.toggle() }
            }
    }
}

/// A `DisclosureGroup` whose whole header opens and closes it, for the
/// places that have no expansion state of their own or only a text title.
struct HeaderDisclosureGroup<Header: View, Content: View>: View {
    private let isExpanded: Binding<Bool>?
    @State private var ownExpanded = false
    private let content: () -> Content
    private let header: () -> Header

    init(isExpanded: Binding<Bool>? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> Header) {
        self.isExpanded = isExpanded
        self.content = content
        self.header = label
    }

    var body: some View {
        let expanded = isExpanded ?? $ownExpanded
        DisclosureGroup(isExpanded: expanded, content: content) {
            header().disclosureHeader(isExpanded: expanded)
        }
    }
}

extension HeaderDisclosureGroup where Header == Text {
    init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>? = nil,
                            @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }
}
