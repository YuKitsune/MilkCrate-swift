//
//  ContentView.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var libraryManager = LibraryManager.shared
    @State private var showingLibraryPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedSidebarItem: SidebarItem? = .recentlyAdded
    @State private var isHoveringPlaylistButton = false
    
    var body: some View {
        Group {
            if libraryManager.isLibraryOpen {
                NavigationSplitView {
                    // Sidebar content
                    List(selection: $selectedSidebarItem) {
                        Section("Library") {
                            Label("Recently Added", systemImage: "clock")
                                .tag(SidebarItem.recentlyAdded)
                            
                            Label("Artists", systemImage: "person.2")
                                .tag(SidebarItem.artists)
                            
                            Label("Albums", systemImage: "square.stack")
                                .tag(SidebarItem.albums)
                            
                            Label("Tracks", systemImage: "music.note")
                                .tag(SidebarItem.tracks)
                        }
                        
                        Section {
                            Text("No playlists")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } header: {
                            HStack {
                                Text("Playlists")
                                
                                Spacer()
                                
                                Button(action: createNewPlaylist) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .frame(width: 20, height: 20)
                                .background(
                                    Circle()
                                        .stroke(Color.secondary.opacity(isHoveringPlaylistButton ? 1.0 : 0.0), lineWidth: 1)
                                )
                                .onHover { hovering in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isHoveringPlaylistButton = hovering
                                    }
                                }
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
                } detail: {
                    // Main content area
                    VStack {
                        if let libraryPath = libraryManager.currentLibraryPath {
                            Text("Library: \(URL(fileURLWithPath: libraryPath).lastPathComponent)")
                                .font(.title2)
                                .padding()
                            
                            Text("Main content area will be implemented here")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            } else {
                VStack {
                    Text("No library selected")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
                .onAppear {
                    showingLibraryPicker = true
                }
            }
        }
        .fileImporter(
            isPresented: $showingLibraryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    handleLibrarySelection(url: url)
                }
            case .failure(let error):
                showError("Failed to select library: \(error.localizedDescription)")
            }
        }
        .alert("Library Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func createNewPlaylist() {
        print("Create new playlist")
    }
    
    private func handleLibrarySelection(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            showError("Failed to access the selected folder")
            return
        }
        
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            let bookmarkKey = "library_bookmark_\(url.path.hash)"
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
            
            SecurityBookmarkManager.shared.registerActiveURL(url)
            
            Task {
                do {
                    try await libraryManager.openLibrary(at: url.path)
                } catch {
                    await MainActor.run {
                        showError(error.localizedDescription)
                    }
                }
            }
        } catch {
            url.stopAccessingSecurityScopedResource()
            showError("Failed to save access permissions: \(error.localizedDescription)")
        }
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

enum SidebarItem: String, CaseIterable {
    case recentlyAdded = "recently_added"
    case artists = "artists"
    case albums = "albums"
    case tracks = "tracks"
}

#Preview {
    ContentView()
}
