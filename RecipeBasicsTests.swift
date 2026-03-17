#if canImport(Testing)
//
//  RecipeBasicsTests.swift
//  Recipe Organizer Tests
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import Testing
import SwiftData
@testable import Recipe_Organizer

@Suite("Recipe basics")
struct RecipeBasicsTests {
    @Test("Default values")
    @MainActor
    func defaultRecipe() {
        let r = Recipe()
        #expect(r.title == "")
        #expect(r.notes == "")
        #expect(r.isFavorite == false)
        #expect(r.rating == 0)
        #expect(r.ingredients.isEmpty)
        #expect(r.steps.isEmpty)
        #expect(r.tags.isEmpty)
    }

    @Test("Add ingredients and steps in memory")
    @MainActor
    func addIngredientsAndSteps() throws {
        let r = Recipe(title: "Test")
        r.ingredients.append(Ingredient(name: "Flour", quantity: 2, unit: "cups"))
        r.steps.append(RecipeStep(order: 0, text: "Mix"))

        #expect(r.ingredients.count == 1)
        #expect(r.steps.count == 1)

        let firstIng = try #require(r.ingredients.first)
        #expect(firstIng.name == "Flour")

        let firstStep = try #require(r.steps.first)
        #expect(firstStep.order == 0)
        #expect(firstStep.text == "Mix")
    }
}

@Suite("SwiftData persistence")
struct RecipePersistenceTests {
    private func makeInMemoryContainer() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([Recipe.self, Ingredient.self, RecipeStep.self, Tag.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return (container, container.mainContext)
    }

    @Test("Cascade delete removes children")
    @MainActor
    func cascadeDeleteRemovesChildren() throws {
        let (_, context) = try makeInMemoryContainer()

        let recipe = Recipe(title: "Soup")
        let ing = Ingredient(name: "Salt")
        let step = RecipeStep(order: 0, text: "Boil")

        context.insert(recipe)
        context.insert(ing)
        context.insert(step)

        recipe.ingredients.append(ing)
        recipe.steps.append(step)

        try context.save()

        let ingCountBefore = try context.fetch(FetchDescriptor<Ingredient>()).count
        let stepCountBefore = try context.fetch(FetchDescriptor<RecipeStep>()).count
        #expect(ingCountBefore == 1)
        #expect(stepCountBefore == 1)

        context.delete(recipe)
        try context.save()

        let ingsAfter = try context.fetch(FetchDescriptor<Ingredient>())
        let stepsAfter = try context.fetch(FetchDescriptor<RecipeStep>())
        #expect(ingsAfter.isEmpty)
        #expect(stepsAfter.isEmpty)
    }

    @Test("Deleting recipe doesn't delete tags")
    @MainActor
    func deletingRecipeDoesNotDeleteTags() throws {
        let (_, context) = try makeInMemoryContainer()

        let recipe = Recipe(title: "Salad")
        let tag = Tag(name: "Vegan")

        context.insert(recipe)
        context.insert(tag)

        recipe.tags.append(tag)

        try context.save()

        context.delete(recipe)
        try context.save()

        let tags = try context.fetch(FetchDescriptor<Tag>())
        #expect(tags.count == 1)
        #expect(tags.first?.name == "Vegan")
    }
}
#endif
