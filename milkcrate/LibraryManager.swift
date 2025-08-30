//
//  LibraryManager.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import Foundation

class LibraryManager: ObservableObject {
    static let shared = LibraryManager()
    
    private let crateDirectoryName = ".crate"
    private let databaseFileName = "library.db"
    
    @Published var currentLibraryPath: String?
    @Published var isLibraryOpen = false
    @Published var scanner: LibraryScanner?
    
    private var databaseManager: DatabaseManager?
    
    private init() {}
    
    // MARK: - Library Operations
    
    func openLibrary(at path: String) async throws {
        let libraryURL = URL(fileURLWithPath: path)
        
        // Verify the directory exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw LibraryError.directoryNotFound
        }
        
        // Start accessing security-scoped resource
        guard SecurityBookmarkManager.shared.startAccessingPath(path) else {
            print("LibraryManager (openLibrary): Failed to start accessing path: \(path)")
            throw LibraryError.permissionDenied
        }
        
        print("LibraryManager (openLibrary): Successfully started accessing path: \(path)")
        
        // Get the actual security-scoped URL
        guard let secureLibraryURL = SecurityBookmarkManager.shared.getActiveURL(for: path) else {
            print("LibraryManager (openLibrary): Failed to get active URL for path: \(path)")
            throw LibraryError.permissionDenied
        }
        
        let crateURL = secureLibraryURL.appendingPathComponent(crateDirectoryName)
        
        // Check if .crate directory exists
        if FileManager.default.fileExists(atPath: crateURL.path) {
            try openExistingLibrary(libraryPath: path, cratePath: crateURL.path)
        } else {
            try createLibraryStructure(libraryPath: path, crateURL: crateURL)
        }
        
        await MainActor.run {
            currentLibraryPath = path
            isLibraryOpen = true
            
            // Initialize scanner
            if let dbManager = databaseManager {
                scanner = LibraryScanner(databaseManager: dbManager)
            }
        }
        
        // Automatically scan library
        do {
            try await scanLibrary()
        } catch {
            print("Warning: Library scan failed: \(error.localizedDescription)")
            // Don't throw here - library is still usable even if scan fails
        }
    }
    
    func createNewLibrary(at path: String) async throws {
        // Start accessing security-scoped resource
        guard SecurityBookmarkManager.shared.startAccessingPath(path) else {
            print("LibraryManager (createNewLibrary): Failed to start accessing path: \(path)")
            throw LibraryError.permissionDenied
        }
        
        print("LibraryManager (createNewLibrary): Successfully started accessing path: \(path)")
        
        // Get the actual security-scoped URL
        guard let libraryURL = SecurityBookmarkManager.shared.getActiveURL(for: path) else {
            print("LibraryManager (createNewLibrary): Failed to get active URL for path: \(path)")
            throw LibraryError.permissionDenied
        }
        
        // Create the library directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            } catch {
                throw LibraryError.permissionDenied
            }
        }
        
        let crateURL = libraryURL.appendingPathComponent(crateDirectoryName)
        try createLibraryStructure(libraryPath: path, crateURL: crateURL)
        
        await MainActor.run {
            currentLibraryPath = path
            isLibraryOpen = true
            
            // Initialize scanner
            if let dbManager = databaseManager {
                scanner = LibraryScanner(databaseManager: dbManager)
            }
        }
        
        // Automatically scan library
        do {
            try await scanLibrary()
        } catch {
            print("Warning: Library scan failed: \(error.localizedDescription)")
            // Don't throw here - library is still usable even if scan fails
        }
    }
    
    func closeLibrary() {
        // Stop accessing security-scoped resource
        if let path = currentLibraryPath {
            SecurityBookmarkManager.shared.stopAccessingPath(path)
        }
        
        databaseManager = nil
        
        Task { @MainActor in
            scanner = nil
            currentLibraryPath = nil
            isLibraryOpen = false
        }
    }
    
    // MARK: - Scanning Operations
    
    func scanLibrary() async throws {
        guard let libraryPath = currentLibraryPath,
              let scanner = scanner else {
            throw LibraryError.libraryNotOpen
        }
        
        try await scanner.scanLibrary(at: libraryPath)
    }
    
    // MARK: - Private Methods
    
    private func openExistingLibrary(libraryPath: String, cratePath: String) throws {
        let databasePath = URL(fileURLWithPath: cratePath).appendingPathComponent(databaseFileName).path
        
        // Verify database exists
        guard FileManager.default.fileExists(atPath: databasePath) else {
            throw LibraryError.databaseNotFound
        }
        
        // Initialize database manager
        databaseManager = try DatabaseManager(databasePath: databasePath)
        
        print("Opened existing library at: \(libraryPath)")
    }
    
    private func createLibraryStructure(libraryPath: String, crateURL: URL) throws {
        // Create .crate directory using security-scoped URL
        do {
            print("Creating .crate directory at: \(crateURL.path)")
            try FileManager.default.createDirectory(at: crateURL, withIntermediateDirectories: true)
            print("Successfully created .crate directory")
        } catch {
            print("Failed to create .crate directory: \(error)")
            throw LibraryError.permissionDenied
        }
        
        // Hide the .crate directory on macOS
        do {
            var crateURLMutable = crateURL
            var resourceValues = URLResourceValues()
            resourceValues.isHidden = true
            try crateURLMutable.setResourceValues(resourceValues)
        } catch {
            // Hiding the directory is not critical, continue anyway
            print("Warning: Could not hide .crate directory")
        }
        
        // Create and initialize database
        let databasePath = crateURL.appendingPathComponent(databaseFileName).path
        do {
            databaseManager = try DatabaseManager(databasePath: databasePath)
            try databaseManager?.initializeDatabase()
        } catch {
            throw LibraryError.databaseInitializationFailed
        }
        
        print("Created new library at: \(libraryPath)")
    }
    
    // MARK: - Database Access
    
    func getDatabaseManager() -> DatabaseManager? {
        return databaseManager
    }
    
    // MARK: - Utility Methods
    
    func isValidLibrary(at path: String) -> Bool {
        let dataURL = URL(fileURLWithPath: path).appendingPathComponent(crateDirectoryName)
        let databaseURL = dataURL.appendingPathComponent(databaseFileName)
        
        return FileManager.default.fileExists(atPath: dataURL.path) &&
               FileManager.default.fileExists(atPath: databaseURL.path)
    }
    
    func getCratePath() -> String? {
        guard let libraryPath = currentLibraryPath else { return nil }
        return URL(fileURLWithPath: libraryPath).appendingPathComponent(crateDirectoryName).path
    }
    
    func getDatabasePath() -> String? {
        guard let cratePath = getCratePath() else { return nil }
        return URL(fileURLWithPath: cratePath).appendingPathComponent(databaseFileName).path
    }
}

// MARK: - Error Types

enum LibraryError: LocalizedError {
    case directoryNotFound
    case databaseNotFound
    case creationFailed
    case databaseInitializationFailed
    case libraryNotOpen
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "The selected directory does not exist"
        case .databaseNotFound:
            return "Library database not found in .crate directory"
        case .creationFailed:
            return "Failed to create library structure"
        case .databaseInitializationFailed:
            return "Failed to initialize library database"
        case .libraryNotOpen:
            return "No library is currently open"
        case .permissionDenied:
            return "Permission denied. Please select a folder you have write access to, or try selecting a folder in your Documents, Music, or Desktop directory."
        }
    }
}
