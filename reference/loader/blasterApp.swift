//
//  blasterApp.swift
//  blaster
//
//  Created by MARK LUCOVSKY on 12/19/24.
//

import SwiftUI
import SwiftData

@main
struct blasterApp: App {
  private var modelContainer: ModelContainer
  @StateObject private var blaster: BlasterState = BlasterState()
  private var tiles: [TileModel] = []
  private var pages: [PageModel] = []
  
  
  
  
  init() {
    let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    let useMockData = true
    
    let schema = Schema([
      TileModel.self, BlasterCacheModel.self, PageModel.self
    ])
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [modelConfiguration])
    modelContainer = container
    
    if useMockData {
      (tiles, pages) = MockDataLoader.load(context: container.mainContext)
      

    }


  }
  
  var body: some Scene {
    WindowGroup {
      HomeView()
        .environmentObject(blaster)
        .onAppear() {
          blaster.setTiles(tiles: tiles)
          blaster.setPages(pages: pages)
          blaster.applyPageFilter()
        }
    }
    .modelContainer(modelContainer)
  }
  
}

enum MockDataLoader {
  static func load(context: ModelContext) -> ([TileModel], [PageModel]) {
    var allTiles: [TileModel] = []
    var allPages: [PageModel] = []
    
    guard let vocabularyUrl = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
      print("❌ Failed to locate vocabulary.json in bundle.")
      return ([], [])
    }
    
    guard let pagesUrl = Bundle.main.url(forResource: "pages", withExtension: "json") else {
      print("❌ Failed to locate pages.json in bundle.")
      return ([], [])
    }

    do {
      let tilesData = try Data(contentsOf: vocabularyUrl)
      let codableTiles = try JSONDecoder().decode([TileModelCodable].self, from: tilesData)
      allTiles = codableTiles.map {
        TileModel(from: $0)
      }
      
      let pagesData = try Data(contentsOf: pagesUrl)
      let codablePages = try JSONDecoder().decode([PageModelCodable].self, from: pagesData)
      

      
      allPages = codablePages.map {
        print("Tiles for page \($0.key): \($0.pageTiles)")
        
        var pageTiles: [PageTileModel] = []
        for ptc in $0.pageTiles {
  
          let tileKey = ptc.key
          
          if let tile: TileModel = allTiles.first(where: {$0.key == tileKey}) {
            
            let pageTile = PageTileModel(tile: tile, link: ptc.link, isAudible: ptc.isAudible)
            print("✅ Appending tile with key: \(tile.key)")
            pageTiles.append(pageTile)
          } else {
            print("❌ Tile not found for key: '\(tileKey)'")
          }
        }
        let tileOrder = pageTiles.map(\.id)
        let page = PageModel.make(displayName: $0.key, tiles: pageTiles, tileOrder: tileOrder)
        return page
      }

     

      // Perform one batch insert in a transaction
      try context.transaction {
        for tile in allTiles {
          context.insert(tile)
        }
        for page in allPages {
          context.insert(page)
        }
      }

    } catch {
      print("❌ Failed to load or decode dummy data: \(error)")
    }

    return (allTiles, allPages)
  }
}

