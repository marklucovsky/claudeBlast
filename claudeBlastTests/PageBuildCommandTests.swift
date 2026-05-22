// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageBuildCommandTests.swift
//  claudeBlastTests
//
//  Round-trip tests for the JSON DSL shape — guards against regressions
//  as the on-disk scene files start to ride on this encoding.
//

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct PageBuildCommandTests {

    @Test func selectAllSingleClass_decodesString() throws {
        let json = #"{"selectAll": "actions"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .selectAll(let classes, let exclude, let limit, let orderBy) = cmd else {
            Issue.record("expected selectAll"); return
        }
        #expect(classes == ["actions"])
        #expect(exclude == [])
        #expect(limit == nil)
        #expect(orderBy == .vocab)
    }

    @Test func selectAllMultiClass_decodesArray() throws {
        let json = #"{"selectAll": ["food","drinks"], "exclude": ["pizza"], "limit": 8, "orderBy": "name"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .selectAll(let classes, let exclude, let limit, let orderBy) = cmd else {
            Issue.record("expected selectAll"); return
        }
        #expect(classes == ["food","drinks"])
        #expect(exclude == ["pizza"])
        #expect(limit == 8)
        #expect(orderBy == .name)
    }

    @Test func selectKeys_decodes() throws {
        let json = #"{"selectKeys": ["i","me","you"]}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .selectKeys(let keys) = cmd else { Issue.record("expected selectKeys"); return }
        #expect(keys == ["i","me","you"])
    }

    @Test func makeLink_decodes() throws {
        let json = #"{"makeLink": "people", "link": "people", "audible": false}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .makeLink(let key, let link, let audible) = cmd else {
            Issue.record("expected makeLink"); return
        }
        #expect(key == "people")
        #expect(link == "people")
        #expect(audible == false)
    }

    @Test func deleteTile_decodes() throws {
        let json = #"{"deleteTile": "stop"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .deleteTile(let key) = cmd else { Issue.record("expected deleteTile"); return }
        #expect(key == "stop")
    }

    @Test func unknownCommand_throws() {
        let json = #"{"bogus": "x"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        }
    }

    @Test func roundTrip_selectAllSingle() throws {
        let original = PageBuildCommand.selectAll(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_selectAllMultiWithOptions() throws {
        let original = PageBuildCommand.selectAll(
            classes: ["food","drinks"], exclude: ["pizza"], limit: 8, orderBy: .name)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_makeLink() throws {
        let original = PageBuildCommand.makeLink(key: "eat", link: "<home>", audible: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_fullPage() throws {
        let page = PageJSON(key: "home", tiles: [
            .makeLink(key: "people", link: "people", audible: false),
            .selectKeys(["i","me","you","my","your","it"]),
            .selectAll(classes: ["actions"], exclude: ["eat"], limit: nil, orderBy: .vocab),
            .deleteTile("stop"),
        ])
        let data = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(PageJSON.self, from: data)
        #expect(decoded.key == "home")
        #expect(decoded.tiles.count == 4)
        #expect(decoded.tiles == page.tiles)
    }
}
