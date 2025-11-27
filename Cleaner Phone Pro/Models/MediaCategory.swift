//
//  MediaCategory.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

enum MediaCategory: String, CaseIterable, Identifiable {
    case similarPhotos = "Photos similaires"
    case similarVideos = "Vidéos similaires"
    case similarScreenshots = "Captures similaires"
    case screenshots = "Captures d'écran"
    case largeVideos = "Vidéos volumineuses"
    case others = "Autres"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .similarPhotos: return "photo.on.rectangle"
        case .similarVideos: return "video.badge.plus"
        case .similarScreenshots: return "rectangle.on.rectangle"
        case .screenshots: return "camera.viewfinder"
        case .largeVideos: return "film"
        case .others: return "photo.stack"
        }
    }

    var color: Color {
        switch self {
        case .similarPhotos: return .blue
        case .similarVideos: return .purple
        case .similarScreenshots: return .green
        case .screenshots: return .orange
        case .largeVideos: return .red
        case .others: return .gray
        }
    }

    var isVideo: Bool {
        switch self {
        case .similarVideos, .largeVideos: return true
        default: return false
        }
    }

    var hasSimilarGroups: Bool {
        switch self {
        case .similarPhotos, .similarVideos, .similarScreenshots: return true
        default: return false
        }
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    var thumbnail: UIImage?
    var fileSize: Int64

    init(asset: PHAsset, thumbnail: UIImage? = nil, fileSize: Int64 = 0) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.thumbnail = thumbnail
        self.fileSize = fileSize
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id && lhs.hasThumbnail == rhs.hasThumbnail
    }

    var hasThumbnail: Bool {
        thumbnail != nil
    }
}

struct SimilarGroup: Identifiable {
    let id = UUID()
    let dateKey: String
    var items: [MediaItem]

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

struct CategoryData: Identifiable {
    let id = UUID()
    let category: MediaCategory
    var items: [MediaItem]
    var similarGroups: [SimilarGroup]

    init(category: MediaCategory, items: [MediaItem], similarGroups: [SimilarGroup] = []) {
        self.category = category
        self.items = items
        self.similarGroups = similarGroups
    }

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var previewItems: [MediaItem] {
        Array(items.prefix(3))
    }
}
