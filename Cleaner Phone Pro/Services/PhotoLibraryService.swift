//
//  PhotoLibraryService.swift
//  Cleaner Phone Pro
//

import Photos
import UIKit

class PhotoLibraryService: ObservableObject {
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    
    static let shared = PhotoLibraryService()
    
    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 300, height: 300)
    
    func requestAuthorization() async -> PHAuthorizationStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status
    }
    
    func fetchScreenshots() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) != 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        return await fetchMediaItems(from: assets)
    }
    
    func fetchLargeVideos(minSizeMB: Int64 = 10) async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        var items = await fetchMediaItems(from: assets)

        let minSizeBytes = minSizeMB * 1024 * 1024
        items = items.filter { $0.fileSize >= minSizeBytes }

        return items.sorted { $0.fileSize > $1.fileSize }
    }
    
    func fetchAllPhotos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %d) == 0",
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        return await fetchMediaItems(from: assets)
    }

    func fetchAllVideos() async -> [MediaItem] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]

        let assets = PHAsset.fetchAssets(with: .video, options: options)
        return await fetchMediaItems(from: assets)
    }
    
    private func fetchMediaItems(from fetchResult: PHFetchResult<PHAsset>) async -> [MediaItem] {
        var items: [MediaItem] = []
        
        fetchResult.enumerateObjects { asset, _, _ in
            items.append(MediaItem(asset: asset))
        }
        
        var itemsWithData: [MediaItem] = []
        for var item in items {
            item.thumbnail = await self.loadThumbnail(for: item.asset)
            item.fileSize = self.getFileSize(for: item.asset)
            itemsWithData.append(item)
        }
        
        return itemsWithData
    }
    
    func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            imageManager.requestImage(
                for: asset,
                targetSize: thumbnailSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func getFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)

        // Try to get original resource first, then any available resource
        let targetTypes: [PHAssetResourceType] = [
            .video,
            .fullSizeVideo,
            .photo,
            .fullSizePhoto,
            .adjustmentBaseVideo,
            .adjustmentBasePhoto
        ]

        for targetType in targetTypes {
            if let resource = resources.first(where: { $0.type == targetType }),
               let fileSize = resource.value(forKey: "fileSize") as? Int64,
               fileSize > 0 {
                return fileSize
            }
        }

        // Fallback to first resource
        if let resource = resources.first,
           let fileSize = resource.value(forKey: "fileSize") as? Int64 {
            return fileSize
        }

        // Estimate size for videos based on duration (rough estimate: 10MB per minute for HD)
        if asset.mediaType == .video {
            let estimatedBytesPerSecond: Double = 170_000 // ~10MB/min
            return Int64(asset.duration * estimatedBytesPerSecond)
        }

        return 0
    }
}
