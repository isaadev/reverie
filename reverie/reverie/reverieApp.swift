//
//  reverieApp.swift
//  reverie
//
//  Created by i on 4/17/26.
//

import SwiftUI
import CoreData

@main
struct reverieApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
