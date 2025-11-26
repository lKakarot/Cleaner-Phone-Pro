//
//  CleanerViewModel.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos
import SwiftUI

@MainActor
class CleanerViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scanPhase: String = ""
    @Published var hasCompletedScan = false

    @Published var allPhotos: [MediaItem] = []
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var blurryPhotos: [MediaItem] = []
    @Published var screenshots: [MediaItem] = []
    @Published var largeVideos: [(item: MediaItem, size: Int64, duration: TimeInterval)] = []
    @Published var burstGroups: [BurstGroup] = []

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined

    var totalIssuesCount: Int {
        let duplicatesCount = duplicateGroups.reduce(0) { $0 + $1.items.count - 1 }
        let burstsCount = burstGroups.reduce(0) { $0 + $1.items.count - 1 }
        return duplicatesCount + blurryPhotos.count + screenshots.count + largeVideos.count + burstsCount
    }

    var potentialSpaceSaved: Int64 {
        var total: Int64 = 0
        for video in largeVideos {
            total += video.size
        }
        return total
    }

    private let photoService = PhotoLibraryService.shared

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }

    func startFullScan() async {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        hasCompletedScan = false

        // Phase 1: Fetch all photos
        scanPhase = "Chargement des photos..."
        let photos = await photoService.fetchPhotosOnly()
        allPhotos = photos
        scanProgress = 0.1

        // Phase 2: Fetch videos
        scanPhase = "Chargement des vidéos..."
        let videos = await photoService.fetchVideosOnly()
        scanProgress = 0.2

        // Phase 3: Find screenshots
        scanPhase = "Identification des captures..."
        screenshots = photos.filter { $0.mediaType == .screenshot }
        scanProgress = 0.3

        // Phase 4: Find duplicates
        scanPhase = "Recherche des doublons..."
        duplicateGroups = await DuplicateDetectionService.shared.findDuplicates(in: photos) { progress in
            Task { @MainActor in
                self.scanProgress = 0.3 + progress * 0.3
            }
        }
        scanProgress = 0.6

        // Phase 5: Find blurry photos
        scanPhase = "Détection photos floues..."
        blurryPhotos = await BlurDetectionService.shared.findBlurryPhotos(in: photos) { progress in
            Task { @MainActor in
                self.scanProgress = 0.6 + progress * 0.25
            }
        }
        scanProgress = 0.85

        // Phase 6: Find large videos
        scanPhase = "Analyse des vidéos..."
        var videosWithSize: [(item: MediaItem, size: Int64, duration: TimeInterval)] = []
        for item in videos {
            let resources = PHAssetResource.assetResources(for: item.asset)
            var size: Int64 = 0
            for resource in resources {
                if let fileSize = resource.value(forKey: "fileSize") as? Int64 {
                    size += fileSize
                }
            }
            if size > 50_000_000 {
                videosWithSize.append((item, size, item.asset.duration))
            }
        }
        largeVideos = videosWithSize.sorted { $0.size > $1.size }
        scanProgress = 0.92

        // Phase 7: Find burst photos
        scanPhase = "Recherche des rafales..."
        burstGroups = findBurstPhotos(in: photos)

        scanProgress = 1.0
        scanPhase = "Terminé"
        isScanning = false
        hasCompletedScan = true
    }

    private func findBurstPhotos(in photos: [MediaItem]) -> [BurstGroup] {
        var burstDict: [String: [MediaItem]] = [:]

        for photo in photos {
            if let burstId = photo.asset.burstIdentifier {
                if burstDict[burstId] == nil {
                    burstDict[burstId] = []
                }
                burstDict[burstId]?.append(photo)
            }
        }

        // Ne garder que les groupes avec plus d'une photo
        return burstDict.compactMap { (burstId, items) in
            guard items.count > 1 else { return nil }
            // Trier par date
            let sortedItems = items.sorted {
                ($0.creationDate ?? Date.distantPast) < ($1.creationDate ?? Date.distantPast)
            }
            return BurstGroup(burstIdentifier: burstId, items: sortedItems)
        }.sorted { $0.items.count > $1.items.count }
    }

    func deleteItems(_ items: [MediaItem]) async -> Bool {
        let assets = items.map { $0.asset }
        return await photoService.deleteAssets(assets)
    }

    func removeFromDuplicates(_ itemIds: Set<String>) {
        for i in duplicateGroups.indices.reversed() {
            duplicateGroups[i].items.removeAll { itemIds.contains($0.id) }
            if duplicateGroups[i].items.count <= 1 {
                duplicateGroups.remove(at: i)
            }
        }
    }

    func removeFromBlurry(_ itemIds: Set<String>) {
        blurryPhotos.removeAll { itemIds.contains($0.id) }
    }

    func removeFromScreenshots(_ itemIds: Set<String>) {
        screenshots.removeAll { itemIds.contains($0.id) }
    }
}
