//
//  ContentView.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query var tiles: [TileModel]
    @Query var pages: [PageModel]
    let loadDuration: TimeInterval

    var body: some View {
        VStack(spacing: 20) {
            Text("Blaster")
                .font(.largeTitle)

            Text("Tiles loaded: \(tiles.count) (\(String(format: "%.3fs", loadDuration)))")
                .font(.title2)

            Text("Pages loaded: \(pages.count)")
                .font(.title2)

            if let homePage = pages.first(where: { $0.displayName == "home" }) {
                Text("Home page tiles: \(homePage.tiles.count)")
                    .font(.title3)
            }
        }
    }
}

#Preview {
    ContentView(loadDuration: 0)
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self],
            inMemory: true
        )
}
