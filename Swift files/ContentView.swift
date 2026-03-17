//
//  ContentView.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import SwiftUI
import SwiftData

// Root split-view listing recipes with search, theming, and add/edit.

struct ContentView: View {
    // MARK: - Environment & Data
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Recipe.updatedAt, order: .reverse)]) private var recipes: [Recipe]

    // MARK: - UI State
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var pendingDeleteOffsets: IndexSet? = nil
    @State private var showingDeleteConfirm = false

    // MARK: - Theming
    @AppStorage("accentColorName") private var accentColorName = Accent.teal.rawValue
    @AppStorage("appearanceMode") private var appearanceMode = Appearance.system.rawValue
    @Environment(\.colorScheme) private var systemColorScheme

    // Convenience
    private var appearance: Appearance { Appearance(rawValue: appearanceMode) ?? .system }

    // MARK: - Constants
    private enum Accent: String, CaseIterable { case blue, teal, green, orange, pink, purple, red, indigo }
    private enum Appearance: String { case system, light, dark }

    private static let accentMap: [String: Color] = [
        Accent.blue.rawValue: .blue,
        Accent.teal.rawValue: .teal,
        Accent.green.rawValue: .green,
        Accent.orange.rawValue: .orange,
        Accent.pink.rawValue: .pink,
        Accent.purple.rawValue: .purple,
        Accent.red.rawValue: .red,
        Accent.indigo.rawValue: .indigo
    ]

    // MARK: - Derived Data
    /// Recipes filtered by the current search text.
    private var filteredRecipes: [Recipe] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return recipes }
        return recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(q) ||
            recipe.notes.localizedCaseInsensitiveContains(q)
        }
    }

    /// The current theme accent color.
    private var themeColor: Color {
        Self.accentMap[accentColorName] ?? .teal
    }

    /// The selected color scheme based on appearance mode setting.
    private var selectedColorScheme: ColorScheme? {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Background gradient that adapts to the theme color and system color scheme.
    private var backgroundGradient: LinearGradient {
        let start = themeColor.opacity(systemColorScheme == .dark ? 0.35 : 0.2)
        let end = themeColor.opacity(0.05)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Body
    var body: some View {
        NavigationSplitView {
            recipeList
                .navigationTitle("Recipes")
                .searchable(text: $searchText)
                .toolbar { toolbarContent }
                .confirmationDialog("Delete", isPresented: $showingDeleteConfirm, titleVisibility: .visible, presenting: pendingDeleteOffsets) { offsets in
                    Button("Delete", role: .destructive) {
                        deleteRecipes(offsets: offsets)
                        pendingDeleteOffsets = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDeleteOffsets = nil
                    }
                } message: { offsets in
                    Text(dynamicDeleteMessage(for: offsets))
                }
        } detail: {
            Text("Select a recipe")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundGradient.ignoresSafeArea())
        }
        .tint(themeColor)
        .preferredColorScheme(selectedColorScheme)
    }

    // MARK: - Subviews
    private var recipeList: some View {
        List {
            ForEach(filteredRecipes) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe)
                } label: {
                    recipeRow(for: recipe)
                }
                .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                pendingDeleteOffsets = offsets
                showingDeleteConfirm = true
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func recipeRow(for recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.title)
                .font(.headline)
            if !recipe.notes.isEmpty {
                Text(recipe.notes)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .appCardStyle(color: themeColor, isDark: systemColorScheme == .dark)
        .contentShape(Rectangle())
        .padding(12)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) { appearanceMenu }
        ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Recipe", systemImage: "plus")
            }
            .accessibilityHint("Create a new recipe")
            .accessibilityLabel("Add Recipe")
            .accessibilityAddTraits(.isButton)
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    RecipeEditorView()
                }
            }
        }
    }

    private var appearanceMenu: some View {
        Menu {
            accentSection
            appearanceSection
        } label: {
            Label("Appearance", systemImage: "paintpalette")
                .accessibilityLabel("Appearance")
        }
    }

    private var accentSection: some View {
        Section("Accent Color") {
            ForEach(Accent.allCases, id: \.self) { accent in
                let name = accent.rawValue
                let color = Self.accentMap[name] ?? .teal
                Button { accentColorName = name } label: {
                    HStack {
                        Circle().fill(color).frame(width: 14, height: 14)
                        Text(name.capitalized)
                        if accentColorName == name { Image(systemName: "checkmark") }
                    }
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            appearanceButton(.system, title: "System")
            appearanceButton(.light, title: "Light")
            appearanceButton(.dark, title: "Dark")
        }
    }

    private func appearanceButton(_ mode: Appearance, title: String) -> some View {
        Button { appearanceMode = mode.rawValue } label: {
            HStack {
                Text(title)
                if appearanceMode == mode.rawValue { Image(systemName: "checkmark") }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func dynamicDeleteMessage(for offsets: IndexSet?) -> String {
        guard let offsets, !offsets.isEmpty else { return "This action cannot be undone." }
        if offsets.count == 1, let index = offsets.first, filteredRecipes.indices.contains(index) {
            let title = filteredRecipes[index].title
            return "This will permanently remove \"\(title)\". This action cannot be undone."
        } else {
            return "This will permanently remove \(offsets.count) recipes. This action cannot be undone."
        }
    }

    // MARK: - Actions
    private func deleteRecipes(offsets: IndexSet) {
        withAnimation {
            for index in offsets.sorted(by: >) {
                guard filteredRecipes.indices.contains(index) else { continue }
                modelContext.delete(filteredRecipes[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Recipe.self, Ingredient.self, RecipeStep.self, Tag.self], inMemory: true)
}

