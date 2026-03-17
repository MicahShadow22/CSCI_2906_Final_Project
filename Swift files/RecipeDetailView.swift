//
//  RecipeDetailView.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

// Detail view for a single recipe with photo, links, ingredients, and steps.

struct RecipeDetailView: View {
    // MARK: - Environment & State
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var showingEditor = false
    @State private var showResetConfirm = false

    let recipe: Recipe

    // MARK: - Theming
    private enum Appearance: String { case system, light, dark }

    @AppStorage("accentColorName") private var accentColorName = "teal"
    @AppStorage("appearanceMode") private var appearanceMode = Appearance.system.rawValue

    private let accentChoices: [(String, Color)] = [
        ("blue", .blue), ("teal", .teal), ("green", .green), ("orange", .orange),
        ("pink", .pink), ("purple", .purple), ("red", .red), ("indigo", .indigo)
    ]

    private var themeColor: Color {
        accentChoices.first(where: { $0.0 == accentColorName })?.1 ?? .teal
    }

    private var selectedColorScheme: ColorScheme? {
        switch Appearance(rawValue: appearanceMode) ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private var backgroundGradient: LinearGradient {
        let start = themeColor.opacity(systemColorScheme == .dark ? 0.35 : 0.2)
        let end = themeColor.opacity(0.05)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !recipe.notes.isEmpty { notesSection }
                linksSection
                ingredientsSection
                stepsSection
            }
            .padding()
        }
        .navigationTitle(recipe.title.isEmpty ? "Untitled Recipe" : recipe.title)
        .toolbar { editToolbar }
        .sheet(isPresented: $showingEditor) { NavigationStack { RecipeEditorView(recipeToEdit: recipe) } }
        .tint(themeColor)
        .preferredColorScheme(selectedColorScheme)
        .background(backgroundGradient.ignoresSafeArea())
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var editToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingEditor = true } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    // MARK: - Sections
    @ViewBuilder
    private var notesSection: some View {
        Text(recipe.notes)
            .font(.body)
            .padding(.vertical, 4)
    }

    /// Header showing the photo (if any) and quick meta like favorite and rating.
    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let data = recipe.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                if recipe.isFavorite { Image(systemName: "heart.fill").foregroundStyle(themeColor) }
                if recipe.rating > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<recipe.rating, id: \.self) { _ in Image(systemName: "star.fill") }
                    }
                    .foregroundStyle(.yellow)
                }
            }
        }
        .padding(12)
        .appCardStyle(color: themeColor, isDark: systemColorScheme == .dark)
    }

    /// Card displaying the list of ingredients if present.
    @ViewBuilder
    private var ingredientsSection: some View {
        if !recipe.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ingredients").font(.title3).bold().foregroundStyle(themeColor)
                ForEach(recipe.ingredients) { ing in
                    Text(ingredientDisplayLine(ing))
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .lineSpacing(2)
            .padding(14)
            .appCardStyle(color: themeColor, isDark: systemColorScheme == .dark)
        }
    }

    /// Card displaying ordered cooking steps if present.
    @ViewBuilder
    private var stepsSection: some View {
        if !recipe.steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Steps").font(.title3).bold().foregroundStyle(themeColor)
                    Spacer()
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(themeColor)
                            .accessibilityLabel("Reset all steps")
                    }
                    .buttonStyle(.plain)
                }

                let sorted = recipe.steps.sorted(by: { $0.order < $1.order })
                ForEach(sorted.indices, id: \.self) { i in
                    let step = sorted[i]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.caption).bold()
                                .foregroundStyle(step.isCompleted ? .secondary : themeColor)
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle().fill((step.isCompleted ? themeColor.opacity(0.12) : themeColor.opacity(0.2)))
                                )
                                .overlay(
                                    Circle().strokeBorder(themeColor.opacity(step.isCompleted ? 0.25 : 0.4), lineWidth: 0.5)
                                )
                                .padding(.top, 2)

                            Text(step.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(step.isCompleted ? .secondary : .primary)
                                .strikethrough(step.isCompleted, pattern: .solid, color: .secondary)
                        }
                        if i < sorted.count - 1 { Divider().opacity(0.15) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { step.isCompleted.toggle() } }
                }
            }
            .lineSpacing(2)
            .padding(16)
            .appCardStyle(color: themeColor, isDark: systemColorScheme == .dark)
            .alert("Reset all steps?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.2)) { for s in recipe.steps { s.isCompleted = false } }
                }
            } message: { Text("This will clear completion for all steps.") }
        }
    }

    /// Card showing normalized links extracted from the recipe's links text.
    @ViewBuilder
    private var linksSection: some View {
        if !recipe.links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Links").font(.title3).bold().foregroundStyle(themeColor)
                let urls = extractURLs(from: recipe.links)
                if urls.isEmpty {
                    Text(recipe.links)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    ForEach(urls, id: \.self) { url in
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text(url.absoluteString)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .lineSpacing(2)
            .padding(14)
            .appCardStyle(color: themeColor, isDark: systemColorScheme == .dark)
        }
    }

    // MARK: - Helpers
    private func ingredientDisplayLine(_ ing: Ingredient) -> String {
        if let raw = ing.rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return raw }
        var parts: [String] = []
        if let q = ing.quantity { parts.append(q.formatted()) }
        if let unit = ing.unit, !unit.isEmpty { parts.append(unit) }
        if !ing.name.isEmpty { parts.append(ing.name) }
        if let note = ing.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            if let colon = note.firstIndex(of: ":") {
                let after = note.index(after: colon)
                let remainder = String(note[after...]).trimmingCharacters(in: .whitespaces)
                if !remainder.isEmpty { parts.append("(\(remainder))") }
            } else {
                parts.append("(\(note))")
            }
        }
        return parts.joined(separator: " ")
    }

    private func extractURLs(from text: String) -> [URL] {
        var results: [URL] = []
        var seen = Set<String>()
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let nsText = text as NSString
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches { if let url = match.url { let key = url.absoluteString; if !seen.contains(key) { results.append(url); seen.insert(key) } } }
        }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;|"))
        let tokens = text.components(separatedBy: separators).filter { !$0.isEmpty }
        let trimChars = CharacterSet(charactersIn: "()[]{}<>.,!?\'\"")
        for raw in tokens {
            let token = raw.trimmingCharacters(in: trimChars)
            if let url = normalizedURL(from: token) {
                let key = url.absoluteString
                if !seen.contains(key) { results.append(url); seen.insert(key) }
            }
        }
        return results
    }

    private func normalizedURL(from token: String) -> URL? {
        if token.contains("@") { return nil }
        if let url = URL(string: token), url.scheme != nil { return url }
        if token.hasPrefix("//"), let url = URL(string: "https:" + token) { return url }
        let hasDot = token.contains(".")
        let hasSpaces = token.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if hasDot && !hasSpaces { return URL(string: "https://" + token) }
        return nil
    }
}

