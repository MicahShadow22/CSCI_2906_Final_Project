//
//  RecipeImporter.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/9/26.
//

import Foundation

enum RecipeImporterError: LocalizedError {
    case invalidURL
    case network(Error)
    case noData
    case parseFailed
    case noStepsFound
    case noIngredientsFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The provided link is not a valid URL."
        case .network(let err):
            return "Network error: \(err.localizedDescription)"
        case .noData:
            return "No data was returned by the server."
        case .parseFailed:
            return "Could not parse the recipe from the page."
        case .noStepsFound:
            return "Couldn't find any steps on the page."
        case .noIngredientsFound:
            return "Couldn't find any ingredients on the page."
        }
    }
}

// MARK: - Importer

struct RecipeImporter {
    // MARK: - Public API

    static func importSteps(from url: URL) async throws -> [String] {
        let (data, _) : (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw RecipeImporterError.network(error)
        }
        guard !data.isEmpty else { throw RecipeImporterError.noData }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw RecipeImporterError.parseFailed
        }

        // Try JSON-LD first (schema.org Recipe)
        if let steps = extractStepsFromJSONLD(in: html), !steps.isEmpty {
            return steps
        }

        // Fallback: naive HTML list extraction
        let fallback = extractStepsFromHTMLLists(in: html)
        if !fallback.isEmpty { return fallback }

        throw RecipeImporterError.noStepsFound
    }

    static func importIngredients(from url: URL) async throws -> [IngredientItem] {
        let (data, _) : (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw RecipeImporterError.network(error)
        }
        guard !data.isEmpty else { throw RecipeImporterError.noData }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw RecipeImporterError.parseFailed
        }

        if let items = extractIngredientsFromJSONLD(in: html), !items.isEmpty {
            // JSON-LD rarely provides sections, so just return as is
            return items
        }

        let fallback = extractIngredientsFromHTML(in: html)
        if !fallback.isEmpty { return fallback }

        throw RecipeImporterError.noIngredientsFound
    }

    // MARK: - Ingredient Item

    struct IngredientItem: Equatable {
        var name: String
        var quantity: Double?
        var unit: String?
        var note: String?
        var section: String?
        var rawText: String?
    }

    // MARK: - JSON-LD parsing

    private static func extractStepsFromJSONLD(in html: String) -> [String]? {
        let scripts = jsonLDScriptBlocks(in: html)
        var allSteps: [String] = []
        for script in scripts {
            guard let data = script.data(using: .utf8) else { continue }
            // JSON-LD can be a single object or an array
            let jsonAny: Any
            do {
                jsonAny = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            } catch {
                continue
            }
            let candidates = findRecipeObjects(in: jsonAny)
            for obj in candidates {
                let steps = extractRecipeInstructions(from: obj)
                allSteps.append(contentsOf: steps)
            }
        }
        return allSteps.isEmpty ? nil : normalize(steps: allSteps)
    }

    private static func extractIngredientsFromJSONLD(in html: String) -> [IngredientItem]? {
        let scripts = jsonLDScriptBlocks(in: html)
        var all: [IngredientItem] = []
        for script in scripts {
            guard let data = script.data(using: .utf8) else { continue }
            let jsonAny: Any
            do { jsonAny = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) } catch { continue }
            let candidates = findRecipeObjects(in: jsonAny)
            for obj in candidates {
                if let arr = obj["recipeIngredient"] as? [Any] {
                    let items = arr.compactMap { any -> IngredientItem? in
                        if let s = any as? String {
                            var it = parseIngredientLine(s)
                            it?.rawText = s
                            return it
                        }
                        if let d = any as? [String: Any], let s = d["text"] as? String {
                            var it = parseIngredientLine(s)
                            it?.rawText = s
                            return it
                        }
                        return nil
                    }
                    all.append(contentsOf: items)
                }
            }
        }
        return all.isEmpty ? nil : all
    }

    private static func jsonLDScriptBlocks(in html: String) -> [String] {
        // Find <script type="application/ld+json"> ... </script>
        let pattern = "<script[^>]*type\\s*=\\s*\\\"application/ld\\+json\\\"[^>]*>([\\s\\S]*?)</script>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let range = match.range(at: 1)
            if range.location != NSNotFound { return ns.substring(with: range) }
            return nil
        }
    }

    private static func findRecipeObjects(in any: Any) -> [[String: Any]] {
        var results: [[String: Any]] = []
        if let dict = any as? [String: Any] {
            // If this dict itself is a Recipe or contains a graph
            if isRecipe(dict) { results.append(dict) }
            if let graph = dict["@graph"] { results.append(contentsOf: findRecipeObjects(in: graph)) }
            // Also check common nesting keys
            for (_, value) in dict { results.append(contentsOf: findRecipeObjects(in: value)) }
        } else if let array = any as? [Any] {
            for item in array { results.append(contentsOf: findRecipeObjects(in: item)) }
        }
        return results
    }

    private static func isRecipe(_ dict: [String: Any]) -> Bool {
        guard let type = dict["@type"] else { return false }
        if let s = type as? String { return s.lowercased().contains("recipe") }
        if let arr = type as? [Any] {
            return arr.contains { item in
                if let s = item as? String { return s.lowercased().contains("recipe") }
                return false
            }
        }
        return false
    }

    private static func extractRecipeInstructions(from dict: [String: Any]) -> [String] {
        guard let instructions = dict["recipeInstructions"] else { return [] }
        return extractInstructionValues(from: instructions)
    }

    private static func extractInstructionValues(from any: Any) -> [String] {
        var steps: [String] = []
        if let s = any as? String {
            // Split on newlines first, then fallback to periods
            let candidates = s.components(separatedBy: CharacterSet.newlines)
                .flatMap { $0.components(separatedBy: ". ") }
            steps.append(contentsOf: candidates)
        } else if let arr = any as? [Any] {
            for item in arr {
                if let s = item as? String {
                    steps.append(s)
                } else if let d = item as? [String: Any] {
                    // HowToStep or HowToSection
                    if let type = (d["@type"] as? String)?.lowercased(), type.contains("howtosection"), let inner = d["itemListElement"] {
                        steps.append(contentsOf: extractInstructionValues(from: inner))
                    } else if let text = d["text"] as? String {
                        steps.append(text)
                    } else if let name = d["name"] as? String, !name.isEmpty {
                        steps.append(name)
                    }
                }
            }
        } else if let dict = any as? [String: Any] {
            // Sometimes it's an object with itemListElement
            if let inner = dict["itemListElement"] { steps.append(contentsOf: extractInstructionValues(from: inner)) }
        }
        return normalize(steps: steps)
    }

    private static func normalize(steps: [String]) -> [String] {
        steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - HTML fallback parsing

    private static func extractStepsFromHTMLLists(in html: String) -> [String] {
        // Prefer lists that look like instructions/directions
        let patterns = [
            "<ol[^>]*class=\\\"[^\"]*(instruction|direction|step)[^\"]*\\\"[^>]*>([\\s\\S]*?)</ol>",
            "<ul[^>]*class=\\\"[^\"]*(instruction|direction|step)[^\"]*\\\"[^>]*>([\\s\\S]*?)</ul>",
            "<ol[^>]*>([\\s\\S]*?)</ol>"
        ]
        for pattern in patterns {
            if let steps = extractListItems(html: html, pattern: pattern), !steps.isEmpty {
                return steps
            }
        }
        return []
    }

    private static func extractListItems(html: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        let listRange = match.range(at: match.numberOfRanges - 1)
        guard listRange.location != NSNotFound else { return nil }
        let listHTML = ns.substring(with: listRange)

        // Extract <li>...</li>
        guard let liRegex = try? NSRegularExpression(pattern: "<li[^>]*>([\\s\\S]*?)</li>", options: [.caseInsensitive]) else { return nil }
        let liMatches = liRegex.matches(in: listHTML, options: [], range: NSRange(location: 0, length: (listHTML as NSString).length))
        var steps: [String] = []
        for li in liMatches {
            let r = li.range(at: 1)
            if r.location != NSNotFound {
                let raw = (listHTML as NSString).substring(with: r)
                let text = stripHTML(raw)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { steps.append(trimmed) }
            }
        }
        return steps
    }

    private static func stripHTML(_ s: String) -> String {
        // Remove tags
        let pattern = "<[^>]+>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        let noTags = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        // Collapse whitespace
        return noTags.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: - Ingredient HTML parsing

    private static func extractIngredientsFromHTML(in html: String) -> [IngredientItem] {
        // We will find all candidate lists and merge them in DOM order, with priority for <ol> that look like ingredients.
        // Priority tiers of patterns (searched independently, then merged preserving DOM order within each tier):
        // 1) <ol class~="ingredient">
        // 2) <ul class~="ingredient">
        // 3) generic <ol>
        // 4) generic <ul>
        let tiers: [String] = [
            "<ol[^>]*class=\\\"[^\"]*ingredient[^\"]*\\\"[^>]*>([\\s\\S]*?)</ol>",
            "<ul[^>]*class=\\\"[^\"]*ingredient[^\"]*\\\"[^>]*>([\\s\\S]*?)</ul>",
            "<ol[^>]*>([\\s\\S]*?)</ol>",
            "<ul[^>]*>([\\s\\S]*?)</ul>"
        ]

        let ns = html as NSString
        var collected: [(range: NSRange, items: [IngredientItem])] = []

        for pattern in tiers {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                let listRange = match.range(at: match.numberOfRanges - 1)
                guard listRange.location != NSNotFound else { continue }
                let listHTML = ns.substring(with: listRange)
                if let items = extractIngredientListItems(html: listHTML, pattern: "<li[^>]*>([\\s\\S]*?)</li>") {
                    if !items.isEmpty {
                        // Try to find a preceding section heading (e.g., <h2>, <h3>, or <p><strong>Heading</strong>)
                        let section = findSectionHeading(before: match.range, in: ns)
                        let annotated = items.map { item -> IngredientItem in
                            var it = item
                            if it.section == nil { it.section = section }
                            return it
                        }
                        collected.append((range: match.range, items: annotated))
                    }
                }
            }
            // Do not break; we want to gather across tiers and merge later.
        }

        // Sort by DOM order (range.location) so we preserve page order across all lists.
        collected.sort { $0.range.location < $1.range.location }

        // Merge items from all lists in order.
        var result: [IngredientItem] = []
        for entry in collected { result.append(contentsOf: entry.items) }
        return result
    }

    private static func extractIngredientListItems(html: String, pattern: String) -> [IngredientItem]? {
        guard let liRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        let liMatches = liRegex.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        var results: [IngredientItem] = []
        for li in liMatches {
            let r = li.range(at: 1)
            if r.location != NSNotFound {
                let raw = ns.substring(with: r)
                let text = stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, var item = parseIngredientLine(text) { item.rawText = text; results.append(item) }
            }
        }
        return results
    }

    private static func parseIngredientLine(_ line: String) -> IngredientItem? {
        // Very naive parser: try to split quantity, unit, and name
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Extract leading number or fraction
        let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var idx = 0
        var quantity: Double? = nil

        if idx < tokens.count, let q = parseQuantity(tokens[idx]) {
            quantity = q
            idx += 1
        }

        var unit: String? = nil
        if idx < tokens.count, looksLikeUnit(tokens[idx]) {
            unit = tokens[idx]
            idx += 1
        }

        let nameAndNote = tokens.dropFirst(idx).joined(separator: " ")
        var name = nameAndNote
        var note: String? = nil
        if let open = nameAndNote.firstIndex(of: "("), let close = nameAndNote.lastIndex(of: ")"), open < close {
            note = String(nameAndNote[nameAndNote.index(after: open)..<close])
            name = String(nameAndNote[..<open]).trimmingCharacters(in: .whitespaces)
        }

        return IngredientItem(name: name, quantity: quantity, unit: unit, note: note, section: nil, rawText: nil)
    }

    private static func parseQuantity(_ token: String) -> Double? {
        // Handle simple numbers and common unicode fractions
        let map: [String: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0/3.0, "⅔": 2.0/3.0, "⅛": 0.125]
        if let v = map[token] { return v }
        if let v = Double(token.replacingOccurrences(of: ",", with: ".")) { return v }
        // Handle e.g. 1/2
        if token.contains("/") {
            let parts = token.split(separator: "/").map(String.init)
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 { return n/d }
        }
        return nil
    }

    private static func looksLikeUnit(_ token: String) -> Bool {
        let units = ["tsp","tbsp","cup","cups","g","kg","mg","ml","l","oz","lb","lbs","teaspoon","tablespoon","clove","cloves","can","cans","stick","sticks"]
        return units.contains { $0.caseInsensitiveCompare(token) == .orderedSame }
    }

    private static func findSectionHeading(before range: NSRange, in ns: NSString) -> String? {
        // Look back a limited window for a heading tag
        let lookback = 2000
        let start = max(0, range.location - lookback)
        let length = min(lookback, range.location - start)
        guard length > 0 else { return nil }
        let windowRange = NSRange(location: start, length: length)
        let window = ns.substring(with: windowRange)

        // Search for the last occurrence of a heading-like pattern
        let patterns = [
            "<h[1-6][^>]*>([\\s\\S]*?)</h[1-6]>",
            "<p[^>]*>\\s*<strong[^>]*>([\\s\\S]*?)</strong>\\s*</p>"
        ]
        var found: (pos: Int, text: String)? = nil
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: window, options: [], range: NSRange(location: 0, length: (window as NSString).length))
            for m in matches {
                let r = m.range(at: 1)
                if r.location != NSNotFound {
                    let text = stripHTML((window as NSString).substring(with: r)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        let absPos = start + m.range.location
                        if found == nil || absPos > found!.pos {
                            found = (pos: absPos, text: text)
                        }
                    }
                }
            }
        }
        return found?.text
    }
}
