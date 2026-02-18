//
//  claudeBlastApp.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

@main
struct claudeBlastApp: App {
    private let modelContainer: ModelContainer
    private let loadDuration: TimeInterval

    init() {
        let schema = Schema([
            TileModel.self,
            PageModel.self,
            PageTileModel.self,
            SentenceCache.self,
            BlasterScene.self,
            MetricEvent.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        self.modelContainer = container
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
        self.loadDuration = result.duration
    }

    var body: some Scene {
        WindowGroup {
            ContentView(loadDuration: loadDuration)
        }
        .modelContainer(modelContainer)
    }
}
