// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CaregiverMenuCoordinator.swift
//  claudeBlast
//
//  Bridges the caregiver menu (opened by long-pressing Home in the tray, deep
//  in the view tree) up to ContentView, which owns the Admin/TileScript
//  presentation. The tray sets `requested`; ContentView observes it and drives
//  its fullScreenCover (AdminGate / TileScriptView). Replaces the old hidden
//  triple-tap → hamburger → menu entry chain.

import Foundation
import Observation

@MainActor
@Observable
final class CaregiverMenuCoordinator {
    /// A gated/admin destination the caregiver requested from the menu.
    enum Destination: Equatable {
        case admin       // presented behind AdminGate (Face ID / PIN)
        case tileScript
    }

    /// Set by the caregiver menu; observed and cleared by ContentView.
    var requested: Destination?
}
