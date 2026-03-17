//
//  RecipeEditorView.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

// Editor for creating and updating recipes with photo, links, ingredients, and steps.

struct RecipeEditorView: View {
    // MARK: - Environment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    // MARK: - Theming
    private enum Appearance: String { case system, light, dark }
    @AppStorage("accentColorName") private var accentColorName = "teal"
    @AppStorage("appearanceMode") private var appearanceMode = Appearance.system.rawValue

    private let accentChoices: [(String, Color)] = [
        ("blue", .blue), ("teal", .teal), ("green", .green), ("orange", .orange),
        ("pink", .pink), ("purple", .purple), ("red", .red), ("indigo", .indigo)
    ]

    private var themeColor: Color { accentChoices.first(where: { $0.0 == accentColorName })?.1 ?? .teal }

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

    // MARK: - State
    @State private var draft: Recipe?
    @State private var pickerItem: PhotosPickerItem?
    @State private var titleText: String = ""
    @State private var linksText: String = ""
    @State private var importError: String?
    @State private var isImportingBoth = false
    @FocusState private var titleIsFocused: Bool

    @State private var ingredientsVersion: Int = 0

    private var trimmedLinksText: String { linksText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var recipeToEdit: Recipe?

    // MARK: - Body
    var body: some View {
        Group {
            if let draft {
                Form {
                    basicsSection(draft)
                    photoSection(draft)
                    ingredientsSection(draft)
                    stepsSection(draft)
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .navigationTitle(draft.title.isEmpty ? "New Recipe" : "Edit Recipe")
                .toolbar { editorToolbar }
                .tint(themeColor)
                .preferredColorScheme(selectedColorScheme)
                .background(backgroundGradient.ignoresSafeArea())
                .onAppear { if recipeToEdit == nil { titleIsFocused = true } }
            } else {
                ProgressView().task { initializeDraft() }
                    .tint(themeColor)
                    .preferredColorScheme(selectedColorScheme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(backgroundGradient.ignoresSafeArea())
            }
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancel() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(trimmedLinksText.isEmpty) }
    }

    // MARK: - Sections
    @ViewBuilder
    private func basicsSection(_ draft: Recipe) -> some View {
        Section {
            TextField("Title", text: $titleText)
                .font(.title3)
                .focused($titleIsFocused)
            TextField("Links", text: $linksText, axis: .vertical)
                .lineLimit(3, reservesSpace: true)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button { Task { await importBothIfPossible(draft) } } label: {
                    Label("Import Both", systemImage: "arrow.down.circle")
                        .labelStyle(.titleAndIcon)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeColor)
                .disabled(trimmedLinksText.isEmpty || isImportingBoth)

                if isImportingBoth { ProgressView() }
            }
            Text("This will import both Step to Step and Ingredients below")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let importError { Text(importError).font(.footnote).foregroundStyle(.red) }
        } header: { Text("Basics").foregroundStyle(themeColor) }
        .headerProminence(.increased)
    }

    @ViewBuilder
    private func photoSection(_ draft: Recipe) -> some View {
        Section {
            if let data = draft.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            PhotosPicker("Choose Photo", selection: $pickerItem, matching: .images)
                .onChange(of: pickerItem) { _, newValue in
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            await MainActor.run { draft.photoData = data }
                        }
                    }
                }
        } header: { Text("Photo").foregroundStyle(themeColor) }
        .headerProminence(.increased)
    }

    @ViewBuilder
    private func ingredientsSection(_ draft: Recipe) -> some View {
        Section("Ingredients") {
            ForEach(draft.ingredients.indices, id: \.self) { i in
                TextEditor(text: Binding<String>(
                    get: { draft.ingredients[i].rawText ?? "" },
                    set: { draft.ingredients[i].rawText = $0 }
                ))
                .frame(minHeight: 44)
            }
            .onDelete { indexes in
                indexes.map { draft.ingredients[$0] }.forEach { modelContext.delete($0) }
                draft.ingredients.remove(atOffsets: indexes)
            }
            Button { draft.ingredients.append(Ingredient(rawText: "")) } label: { Label("Add Ingredient", systemImage: "plus") }
        }
    }

    @ViewBuilder
    private func stepsSection(_ draft: Recipe) -> some View {
        Section {
            let sorted = draft.steps.sorted(by: { $0.order < $1.order })
            ForEach(sorted) { step in
                TextField("Step", text: binding(step, \.text), axis: .vertical)
                    .lineLimit(nil)
            }
            .onDelete { indexes in
                let sorted = draft.steps.sorted(by: { $0.order < $1.order })
                indexes.map { sorted[$0] }.forEach { step in
                    if let idx = draft.steps.firstIndex(where: { $0.id == step.id }) {
                        modelContext.delete(draft.steps[idx])
                        draft.steps.remove(at: idx)
                    }
                }
                renumberSteps()
            }
            Button {
                let nextOrder = (draft.steps.map(\.order).max() ?? -1) + 1
                draft.steps.append(RecipeStep(order: nextOrder, text: ""))
            } label: { Label("Add Step", systemImage: "plus") }
        } header: { Text("Steps").foregroundStyle(themeColor) }
        .headerProminence(.increased)
    }

    // MARK: - Lifecycle
    @MainActor private func initializeDraft() {
        if let recipeToEdit {
            draft = recipeToEdit
            titleText = recipeToEdit.title
            linksText = recipeToEdit.links
        } else {
            let recipe = Recipe(title: "")
            modelContext.insert(recipe)
            draft = recipe
            titleText = recipe.title
            linksText = recipe.links
        }
    }

    // MARK: - Import Helpers
    @MainActor
    private func importIngredientsIfPossible(_ draft: Recipe) async {
        importError = nil
        let link = trimmedLinksText
        guard !link.isEmpty else { return }
        guard let firstURL = link.components(separatedBy: CharacterSet.newlines).first, let url = URL(string: firstURL) else {
            importError = RecipeImporterError.invalidURL.localizedDescription
            return
        }
        defer {}
        do {
            let items = try await RecipeImporter.importIngredients(from: url)
            if items.isEmpty { throw RecipeImporterError.noIngredientsFound }

            let ensuredItems: [RecipeImporter.IngredientItem] = items.map { item in
                var it = item
                if (it.rawText == nil || it.rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                    var parts: [String] = []
                    if let q = it.quantity { parts.append(q.formatted()) }
                    if let u = it.unit, !u.isEmpty { parts.append(u) }
                    if !it.name.isEmpty { parts.append(it.name) }
                    if let n = it.note, !n.isEmpty { parts.append("(\(n))") }
                    let fallback = parts.joined(separator: " ")
                    if !fallback.isEmpty { it.rawText = fallback }
                }
                return it
            }

            DispatchQueue.main.async {
                for ing in draft.ingredients { modelContext.delete(ing) }
                draft.ingredients.removeAll()
                for item in ensuredItems {
                    let ing = Ingredient(name: item.name, quantity: item.quantity, unit: item.unit, note: item.note, rawText: item.rawText ?? "")
                    draft.ingredients.append(ing)
                }
                draft.updatedAt = .now
                ingredientsVersion &+= 1
            }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func importBothIfPossible(_ draft: Recipe) async {
        importError = nil
        let link = trimmedLinksText
        guard !link.isEmpty else { return }
        guard let firstURL = link.components(separatedBy: CharacterSet.newlines).first, let url = URL(string: firstURL) else {
            importError = RecipeImporterError.invalidURL.localizedDescription
            return
        }
        isImportingBoth = true
        defer { isImportingBoth = false }

        do {
            async let stepsTask: [String] = RecipeImporter.importSteps(from: url)
            async let ingredientsTask: [RecipeImporter.IngredientItem] = RecipeImporter.importIngredients(from: url)
            let (steps, ingredients) = try await (stepsTask, ingredientsTask)

            let ensuredIngredients: [RecipeImporter.IngredientItem] = ingredients.map { item in
                var it = item
                if (it.rawText == nil || it.rawText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true) {
                    var parts: [String] = []
                    if let q = it.quantity { parts.append(q.formatted()) }
                    if let u = it.unit, !u.isEmpty { parts.append(u) }
                    if !it.name.isEmpty { parts.append(it.name) }
                    if let n = it.note, !n.isEmpty { parts.append("(\(n))") }
                    let fallback = parts.joined(separator: " ")
                    if !fallback.isEmpty { it.rawText = fallback }
                }
                return it
            }

            DispatchQueue.main.async {
                for ing in draft.ingredients { modelContext.delete(ing) }
                draft.ingredients.removeAll()
                for item in ensuredIngredients {
                    let ing = Ingredient(name: item.name, quantity: item.quantity, unit: item.unit, note: item.note, rawText: item.rawText ?? "")
                    draft.ingredients.append(ing)
                }
                for step in draft.steps { modelContext.delete(step) }
                draft.steps.removeAll()
                for (idx, text) in steps.enumerated() { draft.steps.append(RecipeStep(order: idx, text: text)) }
                draft.updatedAt = .now
                ingredientsVersion &+= 1
            }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func importStepsIfPossible(_ draft: Recipe) async {
        importError = nil
        let link = trimmedLinksText
        guard !link.isEmpty else { return }
        guard let firstURL = link.components(separatedBy: CharacterSet.newlines).first, let url = URL(string: firstURL) else {
            importError = RecipeImporterError.invalidURL.localizedDescription
            return
        }
        defer {}
        do {
            let steps = try await RecipeImporter.importSteps(from: url)
            if steps.isEmpty { throw RecipeImporterError.noStepsFound }
            for step in draft.steps { modelContext.delete(step) }
            draft.steps.removeAll()
            for (idx, text) in steps.enumerated() { draft.steps.append(RecipeStep(order: idx, text: text)) }
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Utilities
    private func renumberSteps() {
        guard let draft else { return }
        for (idx, step) in draft.steps.sorted(by: { $0.order < $1.order }).enumerated() { step.order = idx }
    }

    private func normalizeLinksText(_ text: String) -> String {
        let urls = extractURLs(from: text)
        var seen = Set<String>()
        var unique: [String] = []
        for url in urls { let s = url.absoluteString; if !seen.contains(s) { seen.insert(s); unique.append(s) } }
        return unique.joined(separator: "\n")
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
            if let url = normalizedURL(from: token) { let key = url.absoluteString; if !seen.contains(key) { results.append(url); seen.insert(key) } }
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

    private func save() {
        if let draft {
            draft.title = titleText
            draft.links = normalizeLinksText(linksText)
            draft.updatedAt = .now
        }
        dismiss()
    }

    private func cancel() {
        if let draft, recipeToEdit == nil { modelContext.delete(draft) }
        dismiss()
    }

    // MARK: - Binding helpers
    private func binding(_ keyPath: WritableKeyPath<Recipe, String>) -> Binding<String> {
        Binding { draft?[keyPath: keyPath] ?? "" } set: { newValue in draft?[keyPath: keyPath] = newValue }
    }

    private func binding(_ keyPath: WritableKeyPath<Recipe, Bool>) -> Binding<Bool> {
        Binding { draft?[keyPath: keyPath] ?? false } set: { newValue in draft?[keyPath: keyPath] = newValue }
    }

    private func binding(_ keyPath: WritableKeyPath<Recipe, Int>) -> Binding<Int> {
        Binding { draft?[keyPath: keyPath] ?? 0 } set: { newValue in draft?[keyPath: keyPath] = newValue }
    }

    private func binding<T: AnyObject, V>(_ object: T, _ keyPath: ReferenceWritableKeyPath<T, V>) -> Binding<V> {
        Binding { object[keyPath: keyPath] } set: { newValue in object[keyPath: keyPath] = newValue }
    }

    private func binding<T: AnyObject, V>(for object: T, _ keyPath: ReferenceWritableKeyPath<T, V?>) -> Binding<V?> {
        Binding { object[keyPath: keyPath] } set: { newValue in object[keyPath: keyPath] = newValue }
    }

    private func optionalDoubleStringBinding(for ingredient: Ingredient, _ keyPath: ReferenceWritableKeyPath<Ingredient, Double?>) -> Binding<String> {
        Binding<String> {
            if let value = ingredient[keyPath: keyPath] { return String(value) } else { return "" }
        } set: { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { ingredient[keyPath: keyPath] = nil }
            else if let number = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { ingredient[keyPath: keyPath] = number }
        }
    }
}

private extension Binding where Value == String? {
    func `default`(_ value: String) -> Binding<String> {
        Binding<String>(get: { self.wrappedValue ?? value }, set: { self.wrappedValue = $0 })
    }
}

