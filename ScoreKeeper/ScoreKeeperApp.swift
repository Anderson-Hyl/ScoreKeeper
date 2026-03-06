//
//  ScoreKeeperApp.swift
//  ScoreKeeper
//
//  Created by anderson on 2026/3/6.
//

import SQLiteData
import SwiftUI

@main
struct ScoreKeeperApp: App {
    init() {
        try! prepareDependencies {
            try $0.bootstrapDatabase()
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                GamesView()
            }
        }
    }
}
