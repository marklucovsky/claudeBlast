// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NavigationCoordinator.swift
//  claudeBlast
//

import SwiftUI

/// Shared navigation state extracted from TileGridView so that both the grid
/// and TileScriptRunner can read/write the current page and breadcrumb path.
@Observable
@MainActor
final class NavigationCoordinator {
    var currentPageKey: String?
    var navigationPath: [String] = []

    /// Reset navigation to the home page of the given scene.
    func navigateHome(homePageKey: String) {
        currentPageKey = nil
        navigationPath = [homePageKey]
    }

    /// Navigate to a specific page key, updating the breadcrumb path.
    func navigate(to pageKey: String) {
        if let idx = navigationPath.firstIndex(of: pageKey) {
            navigationPath = Array(navigationPath.prefix(idx + 1))
        } else {
            navigationPath.append(pageKey)
        }
        currentPageKey = pageKey
    }

    /// Navigate home (nil key) — pops breadcrumb to root.
    func navigateToRoot() {
        if let home = navigationPath.first {
            navigationPath = [home]
        }
        currentPageKey = nil
    }
}
