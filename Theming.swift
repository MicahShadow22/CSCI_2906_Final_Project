//
//  Theming.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/13/26.
//

import SwiftUI

// MARK: - Accent & Appearance

enum Accent: String, CaseIterable {
    case blue, teal, green, orange, pink, purple, red, indigo
}

enum Appearance: String {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Helpers

struct Theme {
    static let accentChoices: [(String, Color)] = [
        (Accent.blue.rawValue, .blue),
        (Accent.teal.rawValue, .teal),
        (Accent.green.rawValue, .green),
        (Accent.orange.rawValue, .orange),
        (Accent.pink.rawValue, .pink),
        (Accent.purple.rawValue, .purple),
        (Accent.red.rawValue, .red),
        (Accent.indigo.rawValue, .indigo)
    ]

    static func color(for name: String) -> Color {
        accentChoices.first(where: { $0.0 == name })?.1 ?? .teal
    }

    static func backgroundGradient(themeColor: Color, isDark: Bool) -> LinearGradient {
        let start = themeColor.opacity(isDark ? 0.35 : 0.2)
        let end = themeColor.opacity(0.05)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
