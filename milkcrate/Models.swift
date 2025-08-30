//
//  Models.swift
//  milkcrate
//
//  Created by Eoin Motherway on 30/8/2025.
//

import Foundation

// MARK: - Track Model

struct Track: Identifiable, Codable {
    let id: Int
    let name: String
    let trackNumber: Int?
    let discNumber: Int?
    let filePath: String
    let fileHash: String
    let releaseId: Int
    let duration: Double?
    let dateAdded: Date
    let dateModified: Date?
    let lastPlayed: Date?
    let playCount: Int
    let rating: Int
    
    var displayName: String {
        // filePath is now relative, but URL can still extract the filename properly
        return name.isEmpty ? URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent : name
    }
    
    var formattedDuration: String {
        guard let duration = duration else { return "--:--" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedTrackNumber: String {
        guard let trackNumber = trackNumber else { return "" }
        return String(trackNumber)
    }
    
    var formattedDiscNumber: String {
        guard let discNumber = discNumber else { return "" }
        return String(discNumber)
    }
    
    func resolvedFilePath(libraryPath: String) -> String {
        return URL(fileURLWithPath: libraryPath).appendingPathComponent(filePath).path
    }
}

// MARK: - Release Model

struct Release: Identifiable, Codable {
    let id: Int
    let title: String
    let year: Int?
    let genre: String?
    let artworkPath: String?
    let dateAdded: Date
    
    var displayTitle: String {
        return title.isEmpty ? "Unknown Release" : title
    }
    
    var displayYear: String {
        guard let year = year else { return "" }
        return String(year)
    }
    
    var displayGenre: String {
        return genre ?? "Unknown Genre"
    }
    
    func resolvedArtworkPath(libraryPath: String) -> String? {
        guard let artworkPath = artworkPath else { return nil }
        return URL(fileURLWithPath: libraryPath).appendingPathComponent(artworkPath).path
    }
}

// MARK: - Artist Model

enum ArtistRole: String, CaseIterable, Codable {
    case primary = "primary"
    case featured = "featured"
    case remixer = "remixer"
    case producer = "producer"
    case composer = "composer"
    
    var displayName: String {
        switch self {
        case .primary: return "Primary Artist"
        case .featured: return "Featured Artist"
        case .remixer: return "Remixer"
        case .producer: return "Producer"
        case .composer: return "Composer"
        }
    }
}

struct Artist: Identifiable, Codable {
    let id: Int
    let name: String
    let sortName: String?
    let dateAdded: Date
    
    var displayName: String {
        return name.isEmpty ? "Unknown Artist" : name
    }
    
    var sortableDisplayName: String {
        return sortName ?? name
    }
}

// MARK: - Playlist Model

struct Playlist: Identifiable, Codable {
    let id: Int
    let name: String
    let description: String?
    let dateCreated: Date
    let dateModified: Date
}

// MARK: - Playlist Track Model

struct PlaylistTrack: Identifiable, Codable {
    let id: Int
    let playlistId: Int
    let trackId: Int
    let position: Int
    let dateAdded: Date
}

// MARK: - Artist Relationship Models

struct ArtistRelease: Identifiable, Codable {
    let id: Int
    let artistId: Int
    let releaseId: Int
    let role: ArtistRole
    let dateAdded: Date
}

struct ArtistTrack: Identifiable, Codable {
    let id: Int
    let artistId: Int
    let trackId: Int
    let role: ArtistRole
    let dateAdded: Date
}

// MARK: - Combined Models for Display

struct TrackWithArtistsAndRelease: Identifiable {
    let track: Track
    let release: Release
    let artists: [Artist]
    let primaryArtists: [Artist]
    let featuredArtists: [Artist]
    
    var id: Int { track.id }
    
    var displayArtists: String {
        let primaryNames = primaryArtists.map { $0.displayName }
        let featuredNames = featuredArtists.map { $0.displayName }
        
        if primaryNames.isEmpty && featuredNames.isEmpty {
            return "Unknown Artist"
        }
        
        var result = primaryNames.joined(separator: ", ")
        if !featuredNames.isEmpty {
            result += " (feat. " + featuredNames.joined(separator: ", ") + ")"
        }
        
        return result
    }
}

struct ReleaseWithArtists: Identifiable {
    let release: Release
    let artists: [Artist]
    let primaryArtists: [Artist]
    
    var id: Int { release.id }
    
    var displayArtists: String {
        if primaryArtists.isEmpty {
            return "Unknown Artist"
        }
        return primaryArtists.map { $0.displayName }.joined(separator: ", ")
    }
}

// MARK: - Library Statistics

struct LibraryStatistics {
    let totalTracks: Int
    let totalReleases: Int
    let totalArtists: Int
    let totalGenres: Int
    let totalDuration: Double
    let totalFileSize: Int64
    let lastScanDate: Date?
    
    var formattedTotalDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        
        if hours > 0 {
            return String(format: "%d hours, %d minutes", hours, minutes)
        } else {
            return String(format: "%d minutes", minutes)
        }
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalFileSize)
    }
}

// MARK: - Search Results

struct SearchResults {
    let tracks: [TrackWithArtistsAndRelease]
    let releases: [ReleaseWithArtists]
    let artists: [Artist]
    let playlists: [Playlist]
    
    var isEmpty: Bool {
        return tracks.isEmpty && releases.isEmpty && artists.isEmpty && playlists.isEmpty
    }
    
    var totalCount: Int {
        return tracks.count + releases.count + artists.count + playlists.count
    }
}

// MARK: - Audio Metadata

struct AudioMetadata {
    let title: String?
    let artist: String?
    let album: String?
    let albumArtist: String?
    let genre: String?
    let year: Int?
    let trackNumber: Int?
    let discNumber: Int?
    let duration: Double?
    let bitrate: Int?
    let sampleRate: Int?
    let artwork: Data?
    
    static func empty() -> AudioMetadata {
        return AudioMetadata(
            title: nil,
            artist: nil,
            album: nil,
            albumArtist: nil,
            genre: nil,
            year: nil,
            trackNumber: nil,
            discNumber: nil,
            duration: nil,
            bitrate: nil,
            sampleRate: nil,
            artwork: nil
        )
    }
}
