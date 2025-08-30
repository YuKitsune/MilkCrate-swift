//
//  milkcrateApp.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import SwiftUI

@main
struct milkcrateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        .defaultSize(width: 1200, height: 800)
    }
    
    init() {
        // Setup app termination handler
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Clean up security-scoped resources
            SecurityBookmarkManager.shared.stopAccessingAllPaths()
            LibraryManager.shared.closeLibrary()
        }
    }
}
