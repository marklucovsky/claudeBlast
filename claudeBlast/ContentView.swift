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
        TileGridView()
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [TileModel.self, PageModel.self, PageTileModel.self],
            inMemory: true
        )
}
