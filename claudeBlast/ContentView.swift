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
    @Environment(TileScriptRecorder.self) private var scriptRecorder
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(CaregiverMenuCoordinator.self) private var caregiverMenu

    @Query private var deviceProfiles: [DeviceProfile]

    @State private var activeDestination: Destination?
    @State private var pendingImportSheet: ImportSheetURL?

    private enum Destination: Identifiable {
        case admin, tileScript
        var id: Self { self }
    }

    /// True when the device hasn't gone through onboarding yet — either no
    /// DeviceProfile exists or its onboardingCompleted flag is false.
    /// ProfileMigration always materializes a placeholder before any view
    /// appears, so the "no DeviceProfile" branch is just defensive.
    private var needsOnboarding: Bool {
        guard let device = deviceProfiles.first else { return true }
        return !device.onboardingCompleted
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else {
                mainContent
            }
        }
        .onChange(of: needsOnboarding) { _, isNeeded in
            // Defensive reset when transitioning out of onboarding.
            // activeDestination is @State on ContentView and survives data
            // wipes (Factory Reset clears SwiftData but not @State). Without
            // this, a session that had Admin open before a reset would
            // instantly re-present AdminGate the moment mainContent mounts,
            // because $activeDestination's binding is still .admin.
            if !isNeeded {
                activeDestination = nil
                pendingImportSheet = nil
            }
        }
    }

    private var mainContent: some View {
        TileGridView()
            .fullScreenCover(item: $activeDestination) { dest in
                switch dest {
                case .admin:
                    AdminGate { AdminView() }
                case .tileScript:
                    TileScriptView()
                }
            }
            // The caregiver menu (long-press Home in the tray) requests a gated
            // destination; present it here, where the cover lives. Admin is
            // wrapped in AdminGate (Face ID / PIN), so the menu itself is open.
            .onChange(of: caregiverMenu.requested) { _, requested in
                guard let requested else { return }
                caregiverMenu.requested = nil
                switch requested {
                case .admin:      activeDestination = .admin
                case .tileScript: activeDestination = .tileScript
                }
            }
            .onAppear {
                scriptRunner.onSwitchToHome = { activeDestination = nil }
                scriptRecorder.onSwitchToHome = { activeDestination = nil }
                scriptRecorder.onSwitchToScript = { activeDestination = .tileScript }
            }
            .onChange(of: importCoordinator.pendingURL) { _, url in
                guard let url else { return }
                importCoordinator.pendingURL = nil
                // Dismiss any active fullScreenCover first, then present import
                if activeDestination != nil {
                    activeDestination = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        pendingImportSheet = ImportSheetURL(url: url)
                    }
                } else {
                    pendingImportSheet = ImportSheetURL(url: url)
                }
            }
            .sheet(item: $pendingImportSheet) { wrapper in
                SceneImportSheet(url: wrapper.url) {
                    pendingImportSheet = nil
                }
            }
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
