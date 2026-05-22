// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneMaterializerTests.swift
//  claudeBlastTests
//

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct SceneMaterializerTests {

    // Tiny test vocabulary — three classes, declaration order matters.
    static let testVocab: [TileModelCodable] = [
        .init(key: "eat",    wordClass: "actions"),
        .init(key: "drink",  wordClass: "actions"),
        .init(key: "stop",   wordClass: "actions"),
        .init(key: "mom",    wordClass: "people"),
        .init(key: "dad",    wordClass: "people"),
        .init(key: "sister", wordClass: "people"),
        .init(key: "apple",  wordClass: "food"),
        .init(key: "banana", wordClass: "food"),
    ]

    private func mat(_ pages: [PageJSON],
                     home: String = "home",
                     isDefault: Bool = true) throws -> SceneMaterializer.MaterializedScene {
        let scene = SceneJSON(
            key: "test", name: "Test",
            description: nil, homePageKey: home,
            isDefault: isDefault, pages: pages
        )
        return try SceneMaterializer.materialize(scene: scene, vocabulary: Self.testVocab)
    }

    @Test func selectAllActions_inVocabOrder() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectAll(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab)
        ])])
        let keys = m.pages[0].tiles.map(\.key)
        #expect(keys == ["eat","drink","stop"])
    }

    @Test func selectAllAlphabetical() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectAll(classes: ["actions"], exclude: [], limit: nil, orderBy: .name)
        ])])
        let keys = m.pages[0].tiles.map(\.key)
        #expect(keys == ["drink","eat","stop"])
    }

    @Test func selectAllMultiClass_keepsVocabOrderAcrossClasses() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectAll(classes: ["people","food"], exclude: [], limit: nil, orderBy: .vocab)
        ])])
        let keys = m.pages[0].tiles.map(\.key)
        // people block then food block (vocab order within the filter)
        #expect(keys == ["mom","dad","sister","apple","banana"])
    }

    @Test func selectAllWithExcludeAndLimit() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectAll(classes: ["people"], exclude: ["sister"], limit: 1, orderBy: .vocab)
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["mom"])
    }

    @Test func selectAllUnknownClass_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "home", tiles: [
                .selectAll(classes: ["nope"], exclude: [], limit: nil, orderBy: .vocab)
            ])])
        }
    }

    @Test func selectKeys_inOrder() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectKeys(["dad","apple","stop"])
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["dad","apple","stop"])
    }

    @Test func selectKeysUnknown_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "home", tiles: [
                .selectKeys(["bogus"])
            ])])
        }
    }

    @Test func makeLink_inserts_whenNotPresent() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .makeLink(key: "mom", link: "people", audible: false)
        ])])
        let t = m.pages[0].tiles[0]
        #expect(t.key == "mom")
        #expect(t.link == "people")
        #expect(t.isAudible == false)
    }

    @Test func makeLink_updatesInPlace_whenPresent() throws {
        // Place the tile first via selectKeys (audible=true, no link), then
        // makeLink should mutate the existing tile in its current position.
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectKeys(["eat","drink","mom"]),
            .makeLink(key: "drink", link: "drinks", audible: true),
        ])])
        let keys = m.pages[0].tiles.map(\.key)
        #expect(keys == ["eat","drink","mom"])  // position preserved
        let drink = m.pages[0].tiles[1]
        #expect(drink.link == "drinks")
        #expect(drink.isAudible == true)
    }

    @Test func deleteTile_removes() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectAll(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab),
            .deleteTile("stop"),
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["eat","drink"])
    }

    @Test func deleteTile_missing_isNoOp() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .selectKeys(["mom"]),
            .deleteTile("ghost"),
        ])])
        #expect(m.pages[0].tiles.map(\.key) == ["mom"])
    }

    @Test func mixedCommands_buildExpectedPage() throws {
        let m = try mat([PageJSON(key: "home", tiles: [
            .makeLink(key: "mom", link: "people", audible: false),  // [mom→link]
            .selectKeys(["eat","drink"]),                            // [mom→link, eat, drink]
            .makeLink(key: "eat", link: "food", audible: true),      // mutate eat
            .selectAll(classes: ["food"], exclude: [], limit: nil, orderBy: .vocab),
            .deleteTile("banana"),
        ])])
        let entries = m.pages[0].tiles
        #expect(entries.map(\.key) == ["mom","eat","drink","apple"])
        #expect(entries[0].link == "people"); #expect(entries[0].isAudible == false)
        #expect(entries[1].link == "food");   #expect(entries[1].isAudible == true)
        #expect(entries[2].link == "");       #expect(entries[2].isAudible == true)
    }

    @Test func homePageNotFound_throws() {
        #expect(throws: SceneMaterializer.MaterializeError.self) {
            _ = try mat([PageJSON(key: "actual_home", tiles: [.selectKeys(["mom"])])],
                        home: "wrong_home")
        }
    }

    @Test func metadataPassesThrough() throws {
        let m = try mat([PageJSON(key: "home", tiles: [.selectKeys(["mom"])])])
        #expect(m.name == "Test")
        #expect(m.homePageKey == "home")
        #expect(m.isDefault == true)
    }
}
