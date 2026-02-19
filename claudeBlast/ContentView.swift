//
//  ContentView.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            TileGridView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            AdminView()
                .tabItem {
                    Label("Admin", systemImage: "lock.fill")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self, BlasterScene.self],
            inMemory: true
        )
}
