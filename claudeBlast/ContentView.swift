// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ContentView.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TileScriptRunner.self) private var scriptRunner
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TileGridView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            AdminView()
                .tabItem {
                    Label("Admin", systemImage: "lock.fill")
                }
                .tag(1)
            TileScriptView()
                .tabItem {
                    Label("TileScript", systemImage: "play.rectangle.fill")
                }
                .tag(2)
        }
        .onAppear {
            scriptRunner.onSwitchToHome = { selectedTab = 0 }
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
