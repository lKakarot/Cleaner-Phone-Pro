//
//  CacheService.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos

/// Lightweight cached data for a category (no thumbnails, just IDs and sizes)
struct CachedMediaItem: Codable {
    let id: String
    let fileSize: Int64
    let creationDate: Date?
}

struct CachedSimilarGroup: Codable {
    let dateKey: String
    let itemIds: [String]
}

struct CachedCategoryData: Codable {
    let categoryRawValue: String
    let itemIds: [String]
    let itemSizes: [String: Int64]
    let similarGroups: [CachedSimilarGroup]
}

struct LibraryCache: Codable {
    let photoCount: Int
    let videoCount: Int
    let lastModified: Date
    let categories: [CachedCategoryData]
}

class CacheService {
    static let shared = CacheService()

    private let cacheKey = "libraryCache"
    private let defaults = UserDefaults.standard

    /// Save categories to cache
    func saveCache(categories: [CategoryData], photoCount: Int, videoCount: Int) {
        let cachedCategories = categories.map { category -> CachedCategoryData in
            let itemIds = category.items.map { $0.id }
            var itemSizes: [String: Int64] = [:]
            for item in category.items {
                itemSizes[item.id] = item.fileSize
            }

            let cachedGroups = category.similarGroups.map { group in
                CachedSimilarGroup(dateKey: group.dateKey, itemIds: group.items.map { $0.id })
            }

            return CachedCategoryData(
                categoryRawValue: category.category.rawValue,
                itemIds: itemIds,
                itemSizes: itemSizes,
                similarGroups: cachedGroups
            )
        }

        let cache = LibraryCache(
            photoCount: photoCount,
            videoCount: videoCount,
            lastModified: Date(),
            categories: cachedCategories
        )

        if let data = try? JSONEncoder().encode(cache) {
            defaults.set(data, forKey: cacheKey)
        }
    }

    /// Load cache if valid (library hasn't changed)
    func loadCacheIfValid() -> LibraryCache? {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(LibraryCache.self, from: data) else {
            return nil
        }

        // Check if library has changed by comparing counts
        let currentPhotoCount = getPhotoCount()
        let currentVideoCount = getVideoCount()

        if cache.photoCount == currentPhotoCount && cache.videoCount == currentVideoCount {
            return cache
        }

        // Library changed, cache is invalid
        return nil
    }

    /// Get current photo count from library
    private func getPhotoCount() -> Int {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        return PHAsset.fetchAssets(with: .image, options: options).count
    }

    /// Get current video count from library
    private func getVideoCount() -> Int {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
        return PHAsset.fetchAssets(with: .video, options: options).count
    }

    /// Clear the cache
    func clearCache() {
        defaults.removeObject(forKey: cacheKey)
    }
}
