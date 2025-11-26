//
//  MediaItem.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos
import UIKit

struct MediaItem: Identifiable, Hashable {
    let id: String
    let asset: PHAsset
    let creationDate: Date?
    let fileSize: Int64
    let mediaType: MediaType

    enum MediaType {
        case photo
        case video
        case screenshot
        case livePhoto
    }

    init(asset: PHAsset) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.creationDate = asset.creationDate
        self.fileSize = 0

        if asset.mediaType == .video {
            self.mediaType = .video
        } else if asset.mediaSubtypes.contains(.photoScreenshot) {
            self.mediaType = .screenshot
        } else if asset.mediaSubtypes.contains(.photoLive) {
            self.mediaType = .livePhoto
        } else {
            self.mediaType = .photo
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    var items: [MediaItem]
    var selectedForDeletion: Set<String> = []

    var potentialSavings: Int64 {
        items.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}

struct ScanResult {
    var duplicateGroups: [DuplicateGroup] = []
    var blurryPhotos: [MediaItem] = []
    var screenshots: [MediaItem] = []
    var largeVideos: [MediaItem] = []

    var totalDuplicates: Int {
        duplicateGroups.reduce(0) { $0 + $1.items.count - 1 }
    }
}
