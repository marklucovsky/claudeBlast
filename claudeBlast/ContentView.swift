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
    @AppStorage(AppSettingsKey.devShowNav) private var devShowNav: Bool = false

    @State private var hamburgerVisible = false
    @State private var hideTask: Task<Void, Never>?
    @State private var showMenuSheet = false
    @State private var activeDestination: Destination?

    private enum Destination: Identifiable {
        case admin, tileScript
        var id: Self { self }
    }

    private var isHamburgerShown: Bool { hamburgerVisible || devShowNav }

    var body: some View {
        TileGridView()
            .overlay(alignment: .topLeading) {
                hamburgerOverlay
                    .padding(.top, 4)
                    .padding(.leading, 8)
            }
            .sheet(isPresented: $showMenuSheet) {
                menuSheet
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(item: $activeDestination) { dest in
                switch dest {
                case .admin:
                    AdminView()
                case .tileScript:
                    TileScriptView()
                }
            }
            .onAppear {
                scriptRunner.onSwitchToHome = {
                    activeDestination = nil
                    showMenuSheet = false
                }
                scriptRecorder.onSwitchToHome = {
                    activeDestination = nil
                    showMenuSheet = false
                }
                scriptRecorder.onSwitchToScript = {
                    activeDestination = .tileScript
                }
            }
    }

    // MARK: - Hamburger overlay

    @ViewBuilder
    private var hamburgerOverlay: some View {
        ZStack(alignment: .topLeading) {
            // Invisible triple-tap target — always present, reveals hamburger
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    if !hamburgerVisible {
                        hamburgerVisible = true
                        startAutoHide()
                    }
                }

            // Visible hamburger button — fades in/out
            if isHamburgerShown {
                Button {
                    showMenuSheet = true
                    resetAutoHide()
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isHamburgerShown)
    }

    // MARK: - Menu sheet

    private var menuSheet: some View {
        NavigationStack {
            List {
                Button {
                    showMenuSheet = false
                    // Small delay so the sheet dismisses before the cover presents
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeDestination = .admin
                    }
                } label: {
                    Label("Admin", systemImage: "lock.fill")
                }

                Button {
                    showMenuSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeDestination = .tileScript
                    }
                } label: {
                    Label("TileScript", systemImage: "play.rectangle.fill")
                }

                Button(role: .destructive) {
                    hamburgerVisible = false
                    hideTask?.cancel()
                    hideTask = nil
                    showMenuSheet = false
                } label: {
                    Label("Hide Menu", systemImage: "eye.slash")
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showMenuSheet = false }
                }
            }
        }
    }

    // MARK: - Hamburger visibility

    private func startAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            hamburgerVisible = false
        }
    }

    private func resetAutoHide() {
        guard !devShowNav else { return }
        startAutoHide()
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
