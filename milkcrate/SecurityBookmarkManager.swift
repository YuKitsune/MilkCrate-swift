//
//  SecurityBookmarkManager.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import Foundation

class SecurityBookmarkManager {
    static let shared = SecurityBookmarkManager()
    
    private var activeURLs: [String: URL] = [:]
    
    private init() {}
    
    // MARK: - Bookmark Management
    
    func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope,
                                      includingResourceValuesForKeys: nil,
                                      relativeTo: nil)
        } catch {
            print("Failed to create security bookmark: \(error)")
            return nil
        }
    }
    
    func resolveBookmark(from data: Data) -> URL? {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: data,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale)
            
            if isStale {
                print("Bookmark is stale - need to recreate bookmark")
                // Remove the stale bookmark
                return nil
            }
            
            return url
        } catch {
            print("Failed to resolve security bookmark: \(error)")
            return nil
        }
    }
    
    // MARK: - Access Management
    
    func registerActiveURL(_ url: URL) {
        activeURLs[url.path] = url
        print("Registered active URL: \(url.path)")
    }
    
    func startAccessingPath(_ path: String) -> Bool {
        print("SecurityBookmarkManager: Attempting to access path: \(path)")
        
        // Check if we already have access to this path
        if activeURLs[path] != nil {
            print("SecurityBookmarkManager: Already have access to path: \(path)")
            return true
        }
        
        // First try to use an already active URL for this path
        let url = URL(fileURLWithPath: path)
        
        // Try to get URL from stored bookmark
        let bookmarkKey = "library_bookmark_\(path.hash)"
        print("SecurityBookmarkManager: Looking for bookmark with key: \(bookmarkKey)")
        
        if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
            print("SecurityBookmarkManager: Found bookmark data, attempting to resolve")
            if let bookmarkURL = resolveBookmark(from: bookmarkData) {
                print("SecurityBookmarkManager: Bookmark resolved to: \(bookmarkURL.path)")
                
                // Start accessing the security-scoped resource
                if bookmarkURL.startAccessingSecurityScopedResource() {
                    // Store the active URL
                    activeURLs[path] = bookmarkURL
                    print("Successfully started accessing path via bookmark: \(path)")
                    return true
                } else {
                    print("SecurityBookmarkManager: Failed to start accessing via bookmark")
                }
            } else {
                print("SecurityBookmarkManager: Failed to resolve bookmark or bookmark is stale")
                // Remove stale bookmark
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
            }
        } else {
            print("SecurityBookmarkManager: No bookmark data found")
        }
        
        // If bookmark doesn't work, try direct URL access (might work if user just selected it)
        print("SecurityBookmarkManager: Trying direct URL access")
        if url.startAccessingSecurityScopedResource() {
            activeURLs[path] = url
            print("Successfully started accessing path directly: \(path)")
            return true
        }
        
        print("Failed to start accessing security-scoped resource: \(path)")
        return false
    }
    
    func stopAccessingPath(_ path: String) {
        guard let url = activeURLs[path] else {
            return
        }
        
        url.stopAccessingSecurityScopedResource()
        activeURLs.removeValue(forKey: path)
        print("Stopped accessing path: \(path)")
    }
    
    func stopAccessingAllPaths() {
        for (path, url) in activeURLs {
            url.stopAccessingSecurityScopedResource()
            print("Stopped accessing path: \(path)")
        }
        activeURLs.removeAll()
    }
    
    // MARK: - Bookmark Storage
    
    func storeBookmark(for url: URL) {
        guard let bookmarkData = createBookmark(for: url) else {
            print("Failed to create bookmark for: \(url.path)")
            return
        }
        
        let bookmarkKey = "library_bookmark_\(url.path.hash)"
        UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        print("Stored bookmark for: \(url.path)")
    }
    
    func hasBookmark(for path: String) -> Bool {
        let bookmarkKey = "library_bookmark_\(path.hash)"
        return UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }
    
    func removeBookmark(for path: String) {
        let bookmarkKey = "library_bookmark_\(path.hash)"
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        print("Removed bookmark for: \(path)")
    }
    
    // MARK: - Utility Methods
    
    func isAccessingPath(_ path: String) -> Bool {
        return activeURLs[path] != nil
    }
    
    func getAccessiblePaths() -> [String] {
        return Array(activeURLs.keys)
    }
    
    func getActiveURL(for path: String) -> URL? {
        return activeURLs[path]
    }
}