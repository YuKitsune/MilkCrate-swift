//
//  DatabaseManager.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import Foundation
import SQLite

class DatabaseManager {
    private let db: Connection
    private let databasePath: String
    
    // MARK: - Table Definitions
    
    // Tables
    private let tracks = Table("tracks")
    private let releases = Table("releases")
    private let artists = Table("artists")
    private let artistRelease = Table("artist_release")
    private let artistTrack = Table("artist_track")
    private let playlists = Table("playlists")
    private let playlistTracks = Table("playlist_tracks")
    private let libraryMetadata = Table("library_metadata")
    
    // Tracks table columns
    private let trackId = Expression<Int64>("id")
    private let trackName = Expression<String>("name")
    private let trackNumber = Expression<Int?>("track_number")
    private let discNumber = Expression<Int?>("disc_number")
    private let filePath = Expression<String>("file_path")
    private let fileHash = Expression<String>("file_hash")
    private let releaseId = Expression<Int64>("release_id")
    private let duration = Expression<Double?>("duration")
    private let dateAdded = Expression<Date>("date_added")
    private let dateModified = Expression<Date?>("date_modified")
    private let lastPlayed = Expression<Date?>("last_played")
    private let playCount = Expression<Int>("play_count")
    private let rating = Expression<Int>("rating")
    
    // Releases table columns
    private let releaseIdCol = Expression<Int64>("id")
    private let releaseTitle = Expression<String>("title")
    private let releaseYear = Expression<Int?>("year")
    private let releaseGenre = Expression<String?>("genre")
    private let artworkPath = Expression<String?>("artwork_path")
    private let releaseDateAdded = Expression<Date>("date_added")
    
    // Artists table columns
    private let artistIdCol = Expression<Int64>("id")
    private let artistName = Expression<String>("name")
    private let sortName = Expression<String?>("sort_name")
    private let artistDateAdded = Expression<Date>("date_added")
    
    // Artist-Release relationship columns
    private let arId = Expression<Int64>("id")
    private let arArtistId = Expression<Int64>("artist_id")
    private let arReleaseId = Expression<Int64>("release_id")
    private let arRole = Expression<String>("role")
    private let arDateAdded = Expression<Date>("date_added")
    
    // Artist-Track relationship columns
    private let atId = Expression<Int64>("id")
    private let atArtistId = Expression<Int64>("artist_id")
    private let atTrackId = Expression<Int64>("track_id")
    private let atRole = Expression<String>("role")
    private let atDateAdded = Expression<Date>("date_added")
    
    // Library metadata columns
    private let metadataKey = Expression<String>("key")
    private let metadataValue = Expression<String?>("value")
    private let metadataDateModified = Expression<Date>("date_modified")
    
    init(databasePath: String) throws {
        self.databasePath = databasePath
        self.db = try Connection(databasePath)
        
        // Configure SQLite for better performance and safety
        try db.execute("PRAGMA foreign_keys = ON")
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = NORMAL")
        try db.execute("PRAGMA temp_store = MEMORY")
        try db.execute("PRAGMA mmap_size = 268435456") // 256MB
    }
    
    deinit {
        // SQLite.swift handles connection cleanup automatically
    }
    
    // MARK: - Transaction-Enforced Database Access
    
    /// Execute database operations within a transaction
    /// This is the ONLY way to access the database - ensures all operations are transactional
    func withTransaction<T>(_ operation: @escaping (Connection) throws -> T) throws -> T {
        print("DatabaseManager: Beginning transaction")
        var result: T!
        try db.transaction {
            result = try operation(db)
            print("DatabaseManager: Transaction committed")
        }
        return result
    }
    
    /// Execute async database operations within a transaction
    /// Note: This creates a manual transaction since SQLite.swift's transaction API doesn't support async
    func withTransaction<T>(_ operation: @escaping (Connection) async throws -> T) async throws -> T {
        print("DatabaseManager: Beginning async transaction")
        
        // Start transaction manually
        try db.execute("BEGIN IMMEDIATE")
        
        do {
            let result = try await operation(db)
            try db.execute("COMMIT")
            print("DatabaseManager: Async transaction committed")
            return result
        } catch {
            try db.execute("ROLLBACK")
            print("DatabaseManager: Async transaction rolled back: \(error)")
            throw error
        }
    }
    
    // MARK: - Database Initialization
    
    func initializeDatabase() throws {
        try withTransaction { db in
            try self.createTables(db: db)
            try self.insertInitialData(db: db)
        }
    }
    
    private func createTables(db: Connection) throws {
        // Create tracks table
        try db.run(tracks.create(ifNotExists: true) { t in
            t.column(trackId, primaryKey: .autoincrement)
            t.column(trackName)
            t.column(trackNumber)
            t.column(discNumber)
            t.column(filePath, unique: true)
            t.column(fileHash)
            t.column(releaseId)
            t.column(duration)
            t.column(dateAdded, defaultValue: Date())
            t.column(dateModified)
            t.column(lastPlayed)
            t.column(playCount, defaultValue: 0)
            t.column(rating, defaultValue: 0)
            t.foreignKey(releaseId, references: releases, releaseIdCol, delete: .cascade)
        })
        
        // Create releases table
        try db.run(releases.create(ifNotExists: true) { t in
            t.column(releaseIdCol, primaryKey: .autoincrement)
            t.column(releaseTitle)
            t.column(releaseYear)
            t.column(releaseGenre)
            t.column(artworkPath)
            t.column(releaseDateAdded, defaultValue: Date())
        })
        
        // Create artists table
        try db.run(artists.create(ifNotExists: true) { t in
            t.column(artistIdCol, primaryKey: .autoincrement)
            t.column(artistName, unique: true)
            t.column(sortName)
            t.column(artistDateAdded, defaultValue: Date())
        })
        
        // Create artist-release relationship table
        try db.run(artistRelease.create(ifNotExists: true) { t in
            t.column(arArtistId)
            t.column(arReleaseId)
            t.column(arRole, defaultValue: "primary")
            t.column(arDateAdded, defaultValue: Date())
            t.primaryKey(arArtistId, arReleaseId)
            t.foreignKey(arArtistId, references: artists, artistIdCol, delete: .cascade)
            t.foreignKey(arReleaseId, references: releases, releaseIdCol, delete: .cascade)
            t.unique([arArtistId, arReleaseId, arRole])
            t.check([
                "primary", "featured", "remixer", "producer", "composer"
            ].contains(arRole))
        })
        
        // Create artist-track relationship table
        try db.run(artistTrack.create(ifNotExists: true) { t in
            t.column(atArtistId)
            t.column(atTrackId)
            t.column(atRole, defaultValue: "primary")
            t.column(atDateAdded, defaultValue: Date())
            
            t.primaryKey(arArtistId, atTrackId)
            t.foreignKey(atArtistId, references: artists, artistIdCol, delete: .cascade)
            t.foreignKey(atTrackId, references: tracks, trackId, delete: .cascade)
            t.unique([atArtistId, atTrackId, atRole])
            t.check([
                "primary", "featured", "remixer", "producer", "composer"
            ].contains(atRole))
        })
        
        // Create library metadata table
        try db.run(libraryMetadata.create(ifNotExists: true) { t in
            t.column(metadataKey, primaryKey: true)
            t.column(metadataValue)
            t.column(metadataDateModified, defaultValue: Date())
        })
        
        // Create indexes for better performance
        try db.run(tracks.createIndex(releaseId, ifNotExists: true))
        try db.run(tracks.createIndex(filePath, ifNotExists: true))
        try db.run(tracks.createIndex(fileHash, ifNotExists: true))
        try db.run(tracks.createIndex(trackName, ifNotExists: true))
        try db.run(releases.createIndex(releaseTitle, ifNotExists: true))
        try db.run(releases.createIndex(releaseYear, ifNotExists: true))
        try db.run(artists.createIndex(artistName, ifNotExists: true))
        try db.run(artistRelease.createIndex(arArtistId, ifNotExists: true))
        try db.run(artistRelease.createIndex(arReleaseId, ifNotExists: true))
        try db.run(artistTrack.createIndex(atArtistId, ifNotExists: true))
        try db.run(artistTrack.createIndex(atTrackId, ifNotExists: true))
        
        print("DatabaseManager: Created tables and indexes")
    }
    
    private func insertInitialData(db: Connection) throws {
        let metadata = [
            ("version", "1.0"),
            ("created_date", ISO8601DateFormatter().string(from: Date())),
            ("last_scan", ""),
            ("total_tracks", "0")
        ]
        
        for (key, value) in metadata {
            try db.run(libraryMetadata.insert(or: .ignore,
                metadataKey <- key,
                metadataValue <- value
            ))
        }
        
        print("DatabaseManager: Inserted initial metadata")
    }
    
    // MARK: - Database Operations (All require transactions)
    
    private func cleanupOrphanedRecords(db: Connection) throws {
        // Clean up artist_track relationships for non-existent tracks
        let existingTrackIds = Array(try db.prepare(tracks.select(trackId))).map { $0[trackId] }
        try db.run(artistTrack.filter(!existingTrackIds.contains(atTrackId)).delete())
        
        // Clean up artist_release relationships for releases with no tracks
        let releasesWithTracks = Array(try db.prepare(tracks.select(releaseId.distinct))).map { $0[releaseId] }
        try db.run(artistRelease.filter(!releasesWithTracks.contains(arReleaseId)).delete())
        
        // Clean up releases with no tracks
        try db.run(releases.filter(!releasesWithTracks.contains(releaseIdCol)).delete())
        
        // Clean up artists with no relationships
        let artistsInTracks = Array(try db.prepare(artistTrack.select(atArtistId.distinct))).map { $0[atArtistId] }
        let artistsInReleases = Array(try db.prepare(artistRelease.select(arArtistId.distinct))).map { $0[arArtistId] }
        let allRelatedArtists = Set(artistsInTracks + artistsInReleases)
        
        try db.run(artists.filter(!Array(allRelatedArtists).contains(artistIdCol)).delete())
        
        print("DatabaseManager: Cleaned up orphaned records")
    }
    
    func findTrackByHash(db: Connection, hash: String) throws -> Int64? {
        print("DatabaseManager: Looking for track with hash: \(hash)")
        
        if let track = try db.pluck(tracks.filter(fileHash == hash)) {
            let foundId = track[trackId]
            let foundHash = track[fileHash]
            print("DatabaseManager: Found existing track ID \(foundId) with hash: \(foundHash)")
            return foundId
        } else {
            print("DatabaseManager: No track found with hash: \(hash)")
            return nil
        }
    }
    
    func updateTrackFilePath(db: Connection, trackIdValue: Int64, newPath: String) throws {
        print("DatabaseManager: Updating track \(trackIdValue) file path to: \(newPath)")
        
        try db.run(tracks.filter(trackId == trackIdValue).update(
            filePath <- newPath,
            dateModified <- Date()
        ))
        
        print("DatabaseManager: Successfully updated track file path")
    }
    
    func insertArtist(db: Connection, name: String, sortNameValue: String? = nil) throws -> Int64 {
        print("DatabaseManager: Inserting artist: '\(name)' (sortName: \(sortNameValue ?? "nil"))")
        
        let artistId = try db.run(artists.insert(
            artistName <- name,
            sortName <- sortNameValue
        ))
        
        print("DatabaseManager: Successfully inserted artist with ID: \(artistId)")
        return artistId
    }
    
    func findArtistByName(db: Connection, name: String) throws -> Int64? {
        if let artist = try db.pluck(artists.filter(artistName == name)) {
            return artist[artistIdCol]
        }
        return nil
    }
    
    func insertRelease(db: Connection, title: String, year: Int? = nil, genre: String? = nil) throws -> Int64 {
        print("DatabaseManager: Inserting release: '\(title)' (year: \(year?.description ?? "nil"), genre: \(genre ?? "nil"))")
        
        let releaseIdValue = try db.run(releases.insert(
            releaseTitle <- title,
            releaseYear <- year,
            releaseGenre <- genre
        ))
        
        print("DatabaseManager: Successfully inserted release with ID: \(releaseIdValue)")
        return releaseIdValue
    }
    
    func findReleaseByTitleAndArtist(db: Connection, title: String, artist: String) throws -> Int64? {
        let query = releases
            .join(artistRelease, on: releases[releaseIdCol] == artistRelease[arReleaseId])
            .join(artists, on: artists[artistIdCol] == artistRelease[arArtistId])
            .filter(releases[releaseTitle] == title && artists[artistName] == artist && artistRelease[arRole] == "primary")
            .limit(1)
        
        if let release = try db.pluck(query) {
            return release[releases[releaseIdCol]]
        }
        return nil
    }
    
    func insertTrack(db: Connection, name: String, trackNumberValue: Int? = nil, discNumberValue: Int? = nil, filePathValue: String, fileHashValue: String, releaseIdValue: Int64, durationValue: Double? = nil) throws -> Int64 {
        print("DatabaseManager: Inserting track: '\(name)' (trackNumber: \(trackNumberValue?.description ?? "nil"), discNumber: \(discNumberValue?.description ?? "nil"), releaseId: \(releaseIdValue), duration: \(durationValue?.description ?? "nil"))")
        
        let trackIdValue = try db.run(tracks.insert(
            trackName <- name,
            trackNumber <- trackNumberValue,
            discNumber <- discNumberValue,
            filePath <- filePathValue,
            fileHash <- fileHashValue,
            releaseId <- releaseIdValue,
            duration <- durationValue
        ))
        
        print("DatabaseManager: Successfully inserted track with ID: \(trackIdValue)")
        return trackIdValue
    }
    
    func linkArtistToRelease(db: Connection, artistIdValue: Int64, releaseIdValue: Int64, role: String = "primary") throws {
        try db.run(artistRelease.insert(or: .ignore,
            arArtistId <- artistIdValue,
            arReleaseId <- releaseIdValue,
            arRole <- role
        ))
        print("DatabaseManager: Linked artist \(artistIdValue) to release \(releaseIdValue) with role '\(role)'")
    }
    
    func linkArtistToTrack(db: Connection, artistIdValue: Int64, trackIdValue: Int64, role: String = "primary") throws {
        try db.run(artistTrack.insert(or: .ignore,
            atArtistId <- artistIdValue,
            atTrackId <- trackIdValue,
            atRole <- role
        ))
        print("DatabaseManager: Linked artist \(artistIdValue) to track \(trackIdValue) with role '\(role)'")
    }
    
    func setLibraryMetadata(db: Connection, key: String, value: String) throws {
        try db.run(libraryMetadata.insert(or: .replace,
            metadataKey <- key,
            metadataValue <- value,
            metadataDateModified <- Date()
        ))
    }
    
    func getLibraryMetadata(db: Connection, key: String) throws -> String? {
        if let row = try db.pluck(libraryMetadata.filter(metadataKey == key)) {
            return row[metadataValue]
        }
        return nil
    }
    
    func getTrackCount(db: Connection) throws -> Int {
        return try db.scalar(tracks.count)
    }
    
    func getReleaseArtworkPath(db: Connection, releaseId: Int64) throws -> String? {
        if let release = try db.pluck(releases.filter(releaseIdCol == releaseId)) {
            return release[artworkPath]
        }
        return nil
    }
    
    func updateReleaseArtworkPath(db: Connection, releaseId: Int64, artworkPath artworkPathValue: String) throws {
        print("DatabaseManager: Updating release \(releaseId) artwork path to: \(artworkPathValue)")
        
        try db.run(releases.filter(releaseIdCol == releaseId).update(
            artworkPath <- artworkPathValue
        ))
        
        print("DatabaseManager: Successfully updated release artwork path")
    }
}

// MARK: - Error Types

enum DatabaseError: LocalizedError {
    case connectionFailed
    case sqlError(String)
    case notInitialized
    case transactionRequired
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to database"
        case .sqlError(let message):
            return "Database error: \(message)"
        case .notInitialized:
            return "Database not initialized"
        case .transactionRequired:
            return "Database operation must be performed within a transaction"
        }
    }
}
