//
//  LibraryScanner.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import Foundation
import AVFoundation
import CryptoKit
import SQLite
import UniformTypeIdentifiers

class LibraryScanner: ObservableObject {
    @Published var isScanning = false
    @Published var scanProgress: Double = 0.0
    @Published var currentFile = ""
    @Published var totalFiles = 0
    @Published var processedFiles = 0
    
    private let databaseManager: DatabaseManager
    private let supportedExtensions = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "ogg", "wma"])
    private let supportedImageExtensions = Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"])
    private let commonArtworkFilenames = ["cover", "folder", "albumart", "front", "album", "artwork"]
    
    private var artworkCachePath: String?
    
    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
        self.setupArtworkCache()
    }
    
    // MARK: - Public Methods
    
    func scanLibrary(at path: String) async throws {
        await MainActor.run {
            self.isScanning = true
            self.scanProgress = 0.0
            self.processedFiles = 0
            self.currentFile = ""
        }
        
        defer {
            Task { @MainActor in
                self.isScanning = false
                self.currentFile = ""
            }
        }
        
        // Execute entire scan in a single transaction for complete atomicity
        try await databaseManager.withTransaction { db in
            
            // Step 1: Discover all audio files
            print("LibraryScanner: Starting file discovery in: \(path)")
            let audioFiles = try await self.discoverAudioFiles(in: path)
            
            await MainActor.run {
                self.totalFiles = audioFiles.count
            }
            
            print("LibraryScanner: Found \(audioFiles.count) audio files")
            for (index, file) in audioFiles.enumerated() {
                print("  \(index + 1): \(file)")
            }
            
            guard !audioFiles.isEmpty else {
                print("No audio files found in library")
                return
            }
            
            // Step 2: Process each audio file
            for (index, filePath) in audioFiles.enumerated() {
                print("\n=== Processing file \(index + 1)/\(audioFiles.count): \(filePath) ===")
                do {
                    try await self.processAudioFile(db: db, filePath: filePath)
                    print("✅ Successfully processed: \(URL(fileURLWithPath: filePath).lastPathComponent)")
                } catch {
                    print("❌ Failed to process \(filePath): \(error)")
                    // If any file fails, the transaction will be automatically rolled back
                    throw error
                }
                
                await MainActor.run {
                    self.processedFiles = index + 1
                    self.scanProgress = Double(index + 1) / Double(audioFiles.count)
                }
            }
            
            // Step 3: Update scan metadata
            try self.databaseManager.setLibraryMetadata(db: db, key: "last_scan", value: ISO8601DateFormatter().string(from: Date()))
            let finalTrackCount = try self.databaseManager.getTrackCount(db: db)
            try self.databaseManager.setLibraryMetadata(db: db, key: "total_tracks", value: String(finalTrackCount))
            
            print("Library scan completed: \(audioFiles.count) files processed")
            print("Final database track count: \(finalTrackCount)")
        }
    }
    
    // MARK: - File Discovery
    
    private func discoverAudioFiles(in rootPath: String) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let audioFiles = try self.findAudioFilesRecursively(in: rootPath)
                    continuation.resume(returning: audioFiles)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func findAudioFilesRecursively(in path: String) throws -> [String] {
        var audioFiles: [String] = []
        let fileManager = FileManager.default
        
        let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path),
                                               includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                print("Scanning file \(fileURL.path)")
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile == true {
                    let fileExtension = fileURL.pathExtension.lowercased()
                    if supportedExtensions.contains(fileExtension) {
                        audioFiles.append(fileURL.path)
                    }
                }
            } catch {
                print("Error checking file \(fileURL.path): \(error)")
            }
        }
        
        return audioFiles
    }
    
    // MARK: - File Processing
    
    private func processAudioFile(db: SQLite.Connection, filePath: String) async throws {
        await MainActor.run {
            self.currentFile = URL(fileURLWithPath: filePath).lastPathComponent
        }
        
        print("Processing: \(filePath)")
        
        // Calculate file hash
        print("Calculating file hash...")
        let fileHash = try calculateFileHash(filePath)
        print("File hash: \(fileHash)")
        
        // Check if track already exists by hash
        if let existingTrackId = try databaseManager.findTrackByHash(db: db, hash: fileHash) {
            // Convert absolute path to relative path for database storage
            guard let libraryPath = LibraryManager.shared.currentLibraryPath else {
                print("❌ Cannot store relative track path - no library path available")
                return
            }
            let libraryURL = URL(fileURLWithPath: libraryPath)
            let fileURL = URL(fileURLWithPath: filePath)
            let relativeFilePath = fileURL.relativePath(from: libraryURL)
            
            // Update file path only
            try databaseManager.updateTrackFilePath(db: db, trackIdValue: existingTrackId, newPath: relativeFilePath)
            print("Updated path for existing track (ID: \(existingTrackId)): \(relativeFilePath)")
            return
        }
        
        print("Track not found in database, creating new entry...")
        
        // Extract metadata
        print("Extracting metadata from: \(filePath)")
        let metadata = try await extractMetadata(from: filePath)
        
        // Debug metadata values
        print("Extracted metadata:")
        print("  - title: '\(metadata.title ?? "nil")'")
        print("  - artist: '\(metadata.artist ?? "nil")'") 
        print("  - album: '\(metadata.album ?? "nil")'")
        print("  - albumArtist: '\(metadata.albumArtist ?? "nil")'")
        print("  - genre: '\(metadata.genre ?? "nil")'")
        print("  - year: \(metadata.year?.description ?? "nil")")
        print("  - trackNumber: \(metadata.trackNumber?.description ?? "nil")")
        print("  - duration: \(metadata.duration?.description ?? "nil")")
        
        // Get or create artist
        let artistName = metadata.artist?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? metadata.artist! : "Unknown Artist"
        print("Using artist name: '\(artistName)'")
        let artistId = try getOrCreateArtist(db: db, name: artistName)
        
        // Get or create release
        let releaseTitle = metadata.album?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? metadata.album! : "Unknown Album"
        print("Using release title: '\(releaseTitle)'")
        let releaseId = try getOrCreateRelease(
            db: db,
            title: releaseTitle,
            artist: artistName,
            year: metadata.year,
            genre: metadata.genre
        )
        
        // Insert new track
        let trackName = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? metadata.title! : URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        print("Inserting track: '\(trackName)' with releaseId: \(releaseId)")
        
        // Convert absolute path to relative path for database storage
        guard let libraryPath = LibraryManager.shared.currentLibraryPath else {
            print("❌ Cannot store relative track path - no library path available")
            throw DatabaseError.notInitialized
        }
        let libraryURL = URL(fileURLWithPath: libraryPath)
        let fileURL = URL(fileURLWithPath: filePath)
        let relativeFilePath = fileURL.relativePath(from: libraryURL)
        
        let trackId = try databaseManager.insertTrack(
            db: db,
            name: trackName,
            trackNumberValue: metadata.trackNumber,
            discNumberValue: metadata.discNumber,
            filePathValue: relativeFilePath,
            fileHashValue: fileHash,
            releaseIdValue: releaseId,
            durationValue: metadata.duration
        )
        print("Track inserted with ID: \(trackId)")
        
        // Link artist to track (primary role)
        print("Linking artist \(artistId) to track \(trackId)")
        try databaseManager.linkArtistToTrack(db: db, artistIdValue: artistId, trackIdValue: trackId, role: "primary")
        
        // If album artist is different from track artist, link album artist to release
        if let albumArtist = metadata.albumArtist, albumArtist != artistName {
            print("Found different album artist: '\(albumArtist)'")
            let albumArtistId = try getOrCreateArtist(db: db, name: albumArtist)
            try databaseManager.linkArtistToRelease(db: db, artistIdValue: albumArtistId, releaseIdValue: releaseId, role: "primary")
        } else {
            // Link primary artist to release
            print("Linking artist \(artistId) to release \(releaseId)")
            try databaseManager.linkArtistToRelease(db: db, artistIdValue: artistId, releaseIdValue: releaseId, role: "primary")
        }
        
        // Process artwork for this release
        try processArtworkForRelease(db: db, releaseId: releaseId, metadata: metadata, filePath: filePath)
        
        print("✅ Successfully added track: '\(trackName)' (ID: \(trackId))")
    }
    
    // MARK: - Hash Calculation
    
    private func calculateFileHash(_ filePath: String) throws -> String {
        let fileURL = URL(fileURLWithPath: filePath)
        let fileData = try Data(contentsOf: fileURL)
        let hash = SHA256.hash(data: fileData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Metadata Extraction
    
    
    private func extractMetadata(from filePath: String) async throws -> AudioMetadata {
        return try await withCheckedThrowingContinuation { continuation in
            let asset = AVAsset(url: URL(fileURLWithPath: filePath))
            
            Task {
                do {
                    let metadata = try await asset.load(.metadata)
                    
                    var title: String?
                    var artist: String?
                    var album: String?
                    var albumArtist: String?
                    var genre: String?
                    var year: Int?
                    var trackNumber: Int?
                    var discNumber: Int?
                    var duration: Double?
                    var artwork: Data?
                    
                    print("Found \(metadata.count) metadata items for: \(URL(fileURLWithPath: filePath).lastPathComponent)")
                    
                    for item in metadata {
                        if let key = item.commonKey?.rawValue {
                            let value = try await item.load(.value)
                            print("Metadata key: \(key), value: \(String(describing: value))")
                            
                            switch key {
                            case AVMetadataKey.commonKeyTitle.rawValue:
                                title = value as? String
                            case AVMetadataKey.commonKeyArtist.rawValue:
                                artist = value as? String
                            case AVMetadataKey.commonKeyAlbumName.rawValue:
                                album = value as? String
                            case AVMetadataKey.commonKeyCreator.rawValue:
                                // Sometimes artist is stored as creator
                                if artist == nil {
                                    artist = value as? String
                                }
                            case AVMetadataKey.commonKeyType.rawValue:
                                genre = value as? String
                            case AVMetadataKey.commonKeyCreationDate.rawValue:
                                if let dateString = value as? String {
                                    year = extractYearFromDate(dateString)
                                }
                            default:
                                break
                            }
                        } else if let keySpace = item.keySpace, let key = item.key {
                            // Handle format-specific keys
                            let value = try await item.load(.value)
                            let keyString = "\(key)"
                            print("Format-specific key: \(keySpace.rawValue).\(keyString), value: \(String(describing: value))")
                            
                            // Handle Vorbis Comments (FLAC, OGG)
                            if keySpace.rawValue == "vorb" {
                                switch keyString {
                                case "TRACKNUMBER":
                                    if let trackString = value as? String {
                                        trackNumber = Int(trackString.components(separatedBy: "/").first ?? "")
                                        print("Found Vorbis track number: \(trackNumber ?? -1)")
                                    }
                                case "ALBUMARTIST":
                                    if albumArtist == nil {
                                        albumArtist = value as? String
                                        print("Found Vorbis album artist: \(albumArtist ?? "nil")")
                                    }
                                case "GENRE":
                                    if genre == nil {
                                        genre = value as? String
                                        print("Found Vorbis genre: \(genre ?? "nil")")
                                    }
                                case "DATE":
                                    if year == nil, let yearString = value as? String {
                                        year = extractYearFromDate(yearString)
                                        print("Found Vorbis year: \(year ?? -1)")
                                    }
                                case "DISCNUMBER":
                                    if let discString = value as? String {
                                        discNumber = Int(discString.components(separatedBy: "/").first ?? "")
                                        print("Found Vorbis disc number: \(discNumber ?? -1)")
                                    }
                                default:
                                    break
                                }
                            }
                            // Handle iTunes/ID3 specific keys
                            else if keySpace == .id3 {
                                switch keyString {
                                case "TPE1": // Lead artist
                                    if artist == nil {
                                        artist = value as? String
                                    }
                                case "TALB": // Album
                                    if album == nil {
                                        album = value as? String
                                    }
                                case "TIT2": // Title
                                    if title == nil {
                                        title = value as? String
                                    }
                                case "TCON": // Genre
                                    if genre == nil {
                                        genre = value as? String
                                    }
                                case "TYER", "TDRC": // Year
                                    if year == nil, let yearString = value as? String {
                                        year = extractYearFromDate(yearString)
                                    }
                                case "TRCK": // Track number
                                    if let trackString = value as? String {
                                        trackNumber = Int(trackString.components(separatedBy: "/").first ?? "")
                                    }
                                case "TPOS": // Disc number
                                    if let discString = value as? String {
                                        discNumber = Int(discString.components(separatedBy: "/").first ?? "")
                                        print("Found ID3 disc number: \(discNumber ?? -1)")
                                    }
                                default:
                                    break
                                }
                            } else if keySpace == .iTunes {
                                switch keyString {
                                case "©nam": // Title
                                    if title == nil {
                                        title = value as? String
                                    }
                                case "©ART": // Artist
                                    if artist == nil {
                                        artist = value as? String
                                    }
                                case "©alb": // Album
                                    if album == nil {
                                        album = value as? String
                                    }
                                case "©gen": // Genre
                                    if genre == nil {
                                        genre = value as? String
                                    }
                                case "©day": // Year
                                    if year == nil, let yearString = value as? String {
                                        year = extractYearFromDate(yearString)
                                    }
                                case "trkn": // Track number
                                    if let data = value as? Data, data.count >= 8 {
                                        trackNumber = Int(data[3])
                                    }
                                case "disk": // Disc number
                                    if let data = value as? Data, data.count >= 6 {
                                        discNumber = Int(data[3])
                                        print("Found iTunes disc number: \(discNumber ?? -1)")
                                    }
                                default:
                                    break
                                }
                            }
                        }
                    }
                    
                    // Get duration
                    let durationTime = try await asset.load(.duration)
                    if durationTime.isValid {
                        duration = CMTimeGetSeconds(durationTime)
                    }
                    
                    print("Extracted metadata - Title: '\(title ?? "nil")', Artist: '\(artist ?? "nil")', Album: '\(album ?? "nil")'")
                    
                    let audioMetadata = AudioMetadata(
                        title: title,
                        artist: artist,
                        album: album,
                        albumArtist: albumArtist,
                        genre: genre,
                        year: year,
                        trackNumber: trackNumber,
                        discNumber: discNumber,
                        duration: duration,
                        bitrate: nil,
                        sampleRate: nil,
                        artwork: artwork
                    )
                    
                    continuation.resume(returning: audioMetadata)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func extractYearFromDate(_ dateString: String) -> Int? {
        // Try to extract year from various date formats
        if let year = Int(String(dateString.prefix(4))), year > 1900 && year <= Calendar.current.component(.year, from: Date()) {
            return year
        }
        return nil
    }
    
    // MARK: - Database Helpers
    
    private func getOrCreateArtist(db: SQLite.Connection, name: String) throws -> Int64 {
        print("Looking for artist: '\(name)'")
        if let existingId = try databaseManager.findArtistByName(db: db, name: name) {
            print("Found existing artist with ID: \(existingId)")
            return existingId
        }
        print("Creating new artist: '\(name)'")
        let newId = try databaseManager.insertArtist(db: db, name: name)
        print("Created artist with ID: \(newId)")
        return newId
    }
    
    private func getOrCreateRelease(db: SQLite.Connection, title: String, artist: String, year: Int?, genre: String?) throws -> Int64 {
        // Try to find existing release by title and primary artist
        if let existingId = try databaseManager.findReleaseByTitleAndArtist(db: db, title: title, artist: artist) {
            return existingId
        }
        
        // Create new release
        return try databaseManager.insertRelease(
            db: db,
            title: title,
            year: year,
            genre: genre
        )
    }
    
    // MARK: - Artwork Cache Setup
    
    private func setupArtworkCache() {
        guard let cratePath = LibraryManager.shared.getCratePath() else {
            print("LibraryScanner: Could not get crate path for artwork cache")
            return
        }
        
        let artworkPath = URL(fileURLWithPath: cratePath).appendingPathComponent("artwork").path
        
        do {
            if !FileManager.default.fileExists(atPath: artworkPath) {
                try FileManager.default.createDirectory(atPath: artworkPath, withIntermediateDirectories: true)
                print("LibraryScanner: Created artwork cache directory at: \(artworkPath)")
            }
            self.artworkCachePath = artworkPath
        } catch {
            print("LibraryScanner: Failed to create artwork cache directory: \(error)")
        }
    }
    
    // MARK: - Artwork Processing
    
    private func processArtworkForRelease(db: SQLite.Connection, releaseId: Int64, metadata: AudioMetadata, filePath: String) throws {
        guard let artworkCachePath = artworkCachePath else {
            print("Artwork cache not available, skipping artwork processing")
            return
        }
        
        // Check if release already has artwork
        if let existingRelativeArtworkPath = try databaseManager.getReleaseArtworkPath(db: db, releaseId: releaseId) {
            // Convert relative path to absolute path for existence check
            guard let libraryPath = LibraryManager.shared.currentLibraryPath else {
                print("Cannot resolve artwork path - no library path available")
                return
            }
            let absoluteArtworkPath = URL(fileURLWithPath: libraryPath).appendingPathComponent(existingRelativeArtworkPath).path
            
            if FileManager.default.fileExists(atPath: absoluteArtworkPath) {
                print("Release \(releaseId) already has artwork: \(existingRelativeArtworkPath)")
                return
            } else {
                print("Artwork file missing, will replace: \(existingRelativeArtworkPath)")
            }
        }
        
        var artworkData: Data?
        var artworkSource = "none"
        
        // Priority 1: Try embedded artwork from metadata
        if let embeddedArtwork = metadata.artwork {
            artworkData = embeddedArtwork
            artworkSource = "embedded"
            print("Found embedded artwork (\(embeddedArtwork.count) bytes)")
        }
        // Priority 2: Look for artwork files in the same directory
        else if let directoryArtwork = findDirectoryArtwork(near: filePath) {
            artworkData = directoryArtwork
            artworkSource = "directory"
            print("Found directory artwork")
        }
        
        guard let artwork = artworkData else {
            print("No artwork found for release \(releaseId)")
            return
        }
        
        // Save artwork to cache
        do {
            // Generate hash of the artwork for the filename
            let artworkHash = SHA256.hash(data: artwork)
            let hashString = artworkHash.compactMap { String(format: "%02x", $0) }.joined()
            let artworkFileName = "\(hashString).jpg"
            let artworkFilePath = URL(fileURLWithPath: artworkCachePath).appendingPathComponent(artworkFileName).path
            
            // Only write if file doesn't already exist (deduplication)
            if !FileManager.default.fileExists(atPath: artworkFilePath) {
                try artwork.write(to: URL(fileURLWithPath: artworkFilePath))
                print("✅ Saved new \(artworkSource) artwork: \(artworkFileName)")
            } else {
                print("ℹ️ Artwork already exists in cache: \(artworkFileName)")
            }
            
            // Convert absolute path to relative path for database storage
            guard let libraryPath = LibraryManager.shared.currentLibraryPath else {
                print("❌ Cannot store relative artwork path - no library path available")
                return
            }
            
            let libraryURL = URL(fileURLWithPath: libraryPath)
            let artworkURL = URL(fileURLWithPath: artworkFilePath)
            let relativeArtworkPath = artworkURL.relativePath(from: libraryURL)
            
            // Update database with relative artwork path
            try databaseManager.updateReleaseArtworkPath(db: db, releaseId: releaseId, artworkPath: relativeArtworkPath)
            
            print("✅ Linked \(artworkSource) artwork to release \(releaseId): \(relativeArtworkPath)")
        } catch {
            print("❌ Failed to save artwork for release \(releaseId): \(error)")
        }
    }
    
    private func findDirectoryArtwork(near audioFilePath: String) -> Data? {
        let audioURL = URL(fileURLWithPath: audioFilePath)
        let directory = audioURL.deletingLastPathComponent()
        
        print("Looking for artwork in directory: \(directory.path)")
        
        // Get all files in the directory
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            print("Could not read directory contents")
            return nil
        }
        
        // Look for common artwork filenames
        for filename in commonArtworkFilenames {
            for file in files {
                let fileBaseName = file.deletingPathExtension().lastPathComponent.lowercased()
                let fileExtension = file.pathExtension.lowercased()
                
                if fileBaseName == filename && supportedImageExtensions.contains(fileExtension) {
                    print("Found potential artwork file: \(file.lastPathComponent)")
                    
                    do {
                        let imageData = try Data(contentsOf: file)
                        
                        // Basic validation - check if it's actually an image
                        if isValidImageData(imageData) {
                            print("✅ Valid artwork found: \(file.lastPathComponent) (\(imageData.count) bytes)")
                            return imageData
                        } else {
                            print("⚠️ File \(file.lastPathComponent) is not a valid image")
                        }
                    } catch {
                        print("❌ Could not read artwork file \(file.lastPathComponent): \(error)")
                    }
                }
            }
        }
        
        print("No artwork files found in directory")
        return nil
    }
    
    private func isValidImageData(_ data: Data) -> Bool {
        // Check for common image file signatures
        guard data.count >= 4 else { return false }
        
        let bytes = data.prefix(4)
        let signature = bytes.map { $0 }
        
        // JPEG: FF D8 FF
        if signature[0] == 0xFF && signature[1] == 0xD8 && signature[2] == 0xFF {
            return true
        }
        
        // PNG: 89 50 4E 47
        if signature[0] == 0x89 && signature[1] == 0x50 && signature[2] == 0x4E && signature[3] == 0x47 {
            return true
        }
        
        // GIF: 47 49 46 38 or 47 49 46 39
        if signature[0] == 0x47 && signature[1] == 0x49 && signature[2] == 0x46 && (signature[3] == 0x38 || signature[3] == 0x39) {
            return true
        }
        
        // BMP: 42 4D
        if signature[0] == 0x42 && signature[1] == 0x4D {
            return true
        }
        
        return false
    }
}

// MARK: - URL Extensions

extension URL {
    func relativePath(from base: URL) -> String {
        // Get standardized paths
        let basePath = base.standardized.path
        let targetPath = self.standardized.path
        
        // If target doesn't start with base path, return absolute path
        guard targetPath.hasPrefix(basePath) else {
            return targetPath
        }
        
        // Remove base path and leading slash
        let relativePath = String(targetPath.dropFirst(basePath.count))
        return relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
    }
}
