//
//  Item.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import Foundation
import SwiftData

// MARK: - Models

/// Root recipe entity containing metadata, relationships, and optional photo.
@Model
final class Recipe {
    var title: String
    var notes: String
    var links: String
    var isFavorite: Bool
    var rating: Int
    var createdAt: Date
    var updatedAt: Date
    var photoData: Data?

    // Relationships
    @Relationship(deleteRule: .cascade)
    var ingredients: [Ingredient] = []

    @Relationship(deleteRule: .cascade)
    var steps: [RecipeStep] = []

    // Optional categorization
    @Relationship(deleteRule: .nullify)
    var tags: [Tag] = []

    init(
        title: String       = "",
        notes: String       = "",
        links: String       = "",
        isFavorite: Bool    = false,
        rating: Int         = 0,
        createdAt: Date     = .now,
        updatedAt: Date     = .now,
        photoData: Data?    = nil
    ) {
        self.title = title
        self.notes = notes
        self.links = links
        self.isFavorite = isFavorite
        self.rating = rating
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.photoData = photoData
    }
}

/// Ingredient for a recipe; can be structured or raw text.
@Model
final class Ingredient {
    var name: String
    var quantity: Double?
    var unit: String?
    var note: String?
    var rawText: String?
    var isChecked: Bool

    init(
        name: String = "",
        quantity: Double? = nil,
        unit: String? = nil,
        note: String? = nil,
        rawText: String? = nil,
        isChecked: Bool = false
    ) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.rawText = rawText
        self.isChecked = isChecked
    }
}

/// Ordered step within a recipe.
@Model
final class RecipeStep {
    var order: Int
    var text: String
    var durationSeconds: Int?
    var isCompleted: Bool

    init(order: Int = 0, text: String = "", durationSeconds: Int? = nil, isCompleted: Bool = false) {
        self.order = order
        self.text = text
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
    }
}

/// Lightweight tag for categorizing recipes.
@Model
final class Tag {
    var name: String

    init(name: String) {
        self.name = name
    }
}

