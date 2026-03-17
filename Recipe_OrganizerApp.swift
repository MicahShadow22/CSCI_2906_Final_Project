//
//  Recipe_OrganizerApp.swift
//  Recipe Organizer
//
//  Created by Micah Sillyman-Weeks on 3/6/26.
//

import SwiftUI
import SwiftData

@main
struct Recipe_OrganizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Recipe.self, Ingredient.self, RecipeStep.self, Tag.self])
    }
}

  
