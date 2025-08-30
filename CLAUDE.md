# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MilkCrate is a macOS music library management application built with SwiftUI. It provides a user interface for organizing and browsing music collections with database-backed storage.

## Build and Development Commands

### Building the Project
- Open `milkcrate.xcodeproj` in Xcode
- Build using Xcode's build system (⌘B)
- Run the app with ⌘R

### Project Structure
The project follows a standard Xcode project structure:
- `milkcrate/` - Main source directory containing Swift files
- `milkcrate.xcodeproj/` - Xcode project configuration

## Architecture

### Core Components

**Application Entry Point:**
- `milkcrateApp.swift` - Main app entry point with SwiftUI App lifecycle
- Handles app termination cleanup for security-scoped resources

**User Interface:**
- `ContentView.swift` - Main application interface using NavigationSplitView
- Implements sidebar navigation with Recently Added, Artists, Albums, Tracks
- Includes file picker for library selection

**Data Models (`Models.swift`):**
- `Track` - Individual music track with metadata and file information
- `Release` - Album/release information with artwork support
- `Artist` - Artist information with roles (primary, featured, etc.)
- `Playlist` - User-created playlists
- Various relationship models for many-to-many associations
- Combined models for UI display (e.g., `TrackWithArtistsAndRelease`)

**Database Layer:**
- `DatabaseManager.swift` - SQLite database operations using SQLite.swift library
- **CRITICAL**: All database operations MUST be performed within transactions using `withTransaction()`
- Supports both sync and async transaction patterns
- Automatic cleanup of orphaned records

**Library Management:**
- `LibraryManager.swift` - Singleton managing library state and operations
- Handles library creation, opening, and closing
- Integrates with SecurityBookmarkManager for sandboxed file access

**Security and File Access:**
- `SecurityBookmarkManager.swift` - Manages macOS security-scoped bookmarks
- Required for sandboxed app to access user-selected directories
- Handles bookmark storage in UserDefaults

**Media Processing:**
- `LibraryScanner.swift` - Scans directories for audio files and extracts metadata
- Supports multiple audio formats: mp3, m4a, aac, flac, wav, aiff, ogg, wma
- Uses AVFoundation for metadata extraction from various formats (ID3, Vorbis, iTunes)
- Processes embedded and directory artwork
- Calculates SHA256 hashes for duplicate detection

### Key Dependencies

The project uses these external libraries:
- **SQLite.swift** - Type-safe SQLite database interface
- **AVFoundation** - Audio metadata extraction
- **CryptoKit** - File hashing (SHA256)

### Library Structure

Each music library consists of:
- A user-selected root directory containing audio files
- A hidden `.crate/` directory for metadata storage
- `library.db` - SQLite database in the .crate directory
- `artwork/` subdirectory for cached album artwork

### Important Patterns

**Database Transactions:**
```swift
// All database operations must use this pattern
try await databaseManager.withTransaction { db in
    // Perform database operations here
}
```

**Security-Scoped Resource Management:**
- All file access outside the app bundle requires security-scoped bookmarks
- Resources must be properly started/stopped via SecurityBookmarkManager
- Cleanup happens automatically on app termination

**Relative Path Storage:**
- File paths in the database are stored relative to the library root
- Resolved to absolute paths when needed using library path context

## Sandbox Configuration

The app runs in macOS App Sandbox with these entitlements:
- `com.apple.security.app-sandbox` - Enable App Sandbox
- `com.apple.security.files.user-selected.read-write` - Access user-selected files/folders

## Development Notes

- The app uses ObservableObject pattern for state management
- UI updates are handled via @Published properties and MainActor
- Error handling uses localized errors throughout
- Extensive logging for debugging database and file operations