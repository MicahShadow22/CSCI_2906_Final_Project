import SwiftUI

/// A reusable card style with rounded background and subtle stroke that adapts to theme and color scheme.
struct AppCardStyle: ViewModifier {
    let color: Color
    let isDark: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(isDark ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(isDark ? 0.35 : 0.25), lineWidth: 0.5)
            )
    }
}

extension View {
    /// Applies the standard card styling used throughout the app.
    /// - Parameters:
    ///   - color: The theme accent color to base the material on.
    ///   - isDark: Whether the current color scheme is dark.
    func appCardStyle(color: Color, isDark: Bool) -> some View {
        modifier(AppCardStyle(color: color, isDark: isDark))
    }
}
