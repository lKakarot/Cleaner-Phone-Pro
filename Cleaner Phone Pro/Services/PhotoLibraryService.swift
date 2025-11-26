//
//  PhotoLibraryService.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos
import UIKit

@MainActor
class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var allPhotos: [MediaItem] = []
    @Published var isLoading = false

    static let shared = PhotoLibraryService()

    private init() {
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
        return status == .authorized || status == .limited
    }

    func fetchAllPhotos() async {
        // Vérifier le statut actuel (pas le cache)
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .authorized || currentStatus == .limited else {
            return
        }

        isLoading = true

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var items: [MediaItem] = []

        assets.enumerateObjects { asset, _, _ in
            items.append(MediaItem(asset: asset))
        }

        allPhotos = items
        isLoading = false
    }

    func fetchPhotosOnly() async -> [MediaItem] {
        // Vérifier le statut actuel (pas le cache)
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .authorized || currentStatus == .limited else {
            return []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var items: [MediaItem] = []

        assets.enumerateObjects { asset, _, _ in
            items.append(MediaItem(asset: asset))
        }

        return items
    }

    func fetchVideosOnly() async -> [MediaItem] {
        // Vérifier le statut actuel (pas le cache)
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard currentStatus == .authorized || currentStatus == .limited else {
            return []
        }

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)

        let assets = PHAsset.fetchAssets(with: fetchOptions)
        var items: [MediaItem] = []

        assets.enumerateObjects { asset, _, _ in
            items.append(MediaItem(asset: asset))
        }

        return items
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            } completionHandler: { success, error in
                if let error = error {
                    print("Error deleting assets: \(error.localizedDescription)")
                }
                continuation.resume(returning: success)
            }
        }
    }

    func getStorageInfo() -> (used: Int64, total: Int64) {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let totalSize = attributes[.systemSize] as? Int64,
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return (0, 0)
        }
        return (totalSize - freeSize, totalSize)
    }
}
