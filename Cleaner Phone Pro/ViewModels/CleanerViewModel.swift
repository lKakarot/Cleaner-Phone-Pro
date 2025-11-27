//
//  CleanerViewModel.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

@MainActor
class CleanerViewModel: ObservableObject {
    @Published var categories: [CategoryData] = []
    @Published var isLoading = false
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isDeleting = false
    @Published var totalPhotoCount = 0
    @Published var totalVideoCount = 0
    @Published var diagnostics: LibraryDiagnostics?
    @Published var showDiagnostics = false

    private let photoService = PhotoLibraryService.shared
    private let cacheService = CacheService.shared

    init() {
        // Initialize with empty categories
        categories = MediaCategory.allCases.map { category in
            CategoryData(category: category, items: [])
        }
    }

    func requestAccess() async {
        authorizationStatus = await photoService.requestAuthorization()
        if authorizationStatus == .authorized || authorizationStatus == .limited {
            await loadAllCategories()
        }
    }

    func loadAllCategories() async {
        isLoading = true

        // Run diagnostics
        let diag = photoService.getLibraryDiagnostics()
        diagnostics = diag

        // Phase 1: Fast metadata scan (no thumbnails)
        async let screenshots = photoService.fetchScreenshots()
        async let largeVideos = photoService.fetchLargeVideos()
        async let allPhotos = photoService.fetchAllPhotos()
        async let allVideos = photoService.fetchAllVideos()

        let screenshotsResult = await screenshots
        let largeVideosResult = await largeVideos
        let allPhotosResult = await allPhotos
        let allVideosResult = await allVideos

        // Store total counts for display
        totalPhotoCount = allPhotosResult.count + screenshotsResult.count
        totalVideoCount = allVideosResult.count

        // Find similar photos/videos/screenshots with groups (sorted by most recent first)
        let (similarPhotos, photoGroups) = findPotentialDuplicatesWithGroups(in: allPhotosResult)
        let (similarVideos, videoGroups) = findPotentialDuplicatesWithGroups(in: allVideosResult)
        let (similarScreenshots, screenshotGroups) = findPotentialDuplicatesWithGroups(in: screenshotsResult)

        // Screenshots that are NOT similar
        let similarScreenshotIds = Set(similarScreenshots.map { $0.id })
        let uniqueScreenshots = screenshotsResult.filter { !similarScreenshotIds.contains($0.id) }

        // Others = photos that are not screenshots and not in similar
        let similarPhotoIds = Set(similarPhotos.map { $0.id })
        let others = allPhotosResult.filter { !similarPhotoIds.contains($0.id) }

        // Set categories immediately (without thumbnails) - NO LIMIT on others
        categories = [
            CategoryData(category: .similarPhotos, items: similarPhotos, similarGroups: photoGroups),
            CategoryData(category: .similarVideos, items: similarVideos, similarGroups: videoGroups),
            CategoryData(category: .similarScreenshots, items: similarScreenshots, similarGroups: screenshotGroups),
            CategoryData(category: .screenshots, items: uniqueScreenshots),
            CategoryData(category: .largeVideos, items: largeVideosResult),
            CategoryData(category: .others, items: others)
        ]

        isLoading = false

        // Phase 2: Load preview thumbnails (only first 3 of each category)
        await loadPreviewThumbnails()
    }

    /// Restore categories from cache by fetching assets by their IDs
    private func restoreFromCache(_ cache: LibraryCache) async {
        var restoredCategories: [CategoryData] = []

        for cachedCategory in cache.categories {
            guard let category = MediaCategory.allCases.first(where: { $0.rawValue == cachedCategory.categoryRawValue }) else {
                continue
            }

            // Fetch assets by IDs
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: cachedCategory.itemIds, options: nil)
            var items: [MediaItem] = []

            fetchResult.enumerateObjects { asset, _, _ in
                let fileSize = cachedCategory.itemSizes[asset.localIdentifier] ?? 0
                items.append(MediaItem(asset: asset, thumbnail: nil, fileSize: fileSize))
            }

            // Restore the order from cache
            let orderedItems = cachedCategory.itemIds.compactMap { id in
                items.first { $0.id == id }
            }

            // Restore similar groups if any
            var similarGroups: [SimilarGroup] = []
            for cachedGroup in cachedCategory.similarGroups {
                let groupItems = cachedGroup.itemIds.compactMap { id in
                    orderedItems.first { $0.id == id }
                }
                if !groupItems.isEmpty {
                    similarGroups.append(SimilarGroup(dateKey: cachedGroup.dateKey, items: groupItems))
                }
            }

            restoredCategories.append(CategoryData(
                category: category,
                items: orderedItems,
                similarGroups: similarGroups
            ))
        }

        categories = restoredCategories
    }

    /// Load high-quality thumbnails for the first 3 items of each category (in parallel)
    private func loadPreviewThumbnails() async {
        // Load all preview thumbnails in parallel for maximum speed
        await withTaskGroup(of: (Int, [MediaItem]).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    let updatedItems = await self.photoService.loadPreviewThumbnails(for: category.items)
                    return (index, updatedItems)
                }
            }

            // Update categories as soon as each one finishes
            for await (index, updatedItems) in group {
                categories[index].items = updatedItems
            }
        }
    }

    private func findPotentialDuplicatesWithGroups(in items: [MediaItem]) -> ([MediaItem], [SimilarGroup]) {
        // Group by date (photos taken within same minute could be duplicates)
        var grouped: [String: [MediaItem]] = [:]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for item in items {
            if let date = item.asset.creationDate {
                let key = formatter.string(from: date)
                grouped[key, default: []].append(item)
            }
        }

        // Filter groups with more than 1 item
        let duplicateGroups = grouped.filter { $0.value.count > 1 }

        // Create SimilarGroup objects, sorted by most recent date first
        let similarGroups = duplicateGroups.map { key, groupItems in
            // Sort items within each group by date (most recent first)
            let sortedItems = groupItems.sorted { item1, item2 in
                let date1 = item1.asset.creationDate ?? Date.distantPast
                let date2 = item2.asset.creationDate ?? Date.distantPast
                return date1 > date2
            }
            return SimilarGroup(dateKey: key, items: sortedItems)
        }.sorted { $0.dateKey > $1.dateKey } // Most recent groups first

        // Return all items that are duplicates (flattened, but maintaining order)
        let allDuplicates = similarGroups.flatMap { $0.items }
        return (allDuplicates, similarGroups)
    }

    /// Load thumbnails for items in a specific category (called when entering detail view)
    func loadThumbnailsForCategory(_ category: MediaCategory) async {
        guard let index = categories.firstIndex(where: { $0.category == category }) else { return }

        let categoryData = categories[index]

        if category.hasSimilarGroups {
            // Load thumbnails for all groups
            var updatedGroups = categoryData.similarGroups
            for groupIndex in updatedGroups.indices {
                let updatedItems = await photoService.loadThumbnailsBatch(
                    for: updatedGroups[groupIndex].items,
                    quality: .detail
                )
                updatedGroups[groupIndex].items = updatedItems
            }
            categories[index].similarGroups = updatedGroups
            // Also update the flat items list
            categories[index].items = updatedGroups.flatMap { $0.items }
        } else {
            // Load thumbnails for regular items
            let updatedItems = await photoService.loadThumbnailsBatch(
                for: categoryData.items,
                quality: .detail
            )
            categories[index].items = updatedItems
        }
    }

    func deleteItems(_ items: [MediaItem]) async -> Bool {
        isDeleting = true
        defer { isDeleting = false }

        let assets = items.map { $0.asset }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }

            // Clear cache since library changed
            cacheService.clearCache()

            // Reload categories after deletion
            await loadAllCategories()
            return true
        } catch {
            print("Error deleting items: \(error)")
            return false
        }
    }

    func deleteItemsFromCategory(_ items: [MediaItem], category: MediaCategory) {
        // Update local state immediately
        if let index = categories.firstIndex(where: { $0.category == category }) {
            let itemIds = Set(items.map { $0.id })
            categories[index].items.removeAll { itemIds.contains($0.id) }

            // Also update similar groups if applicable
            if category.hasSimilarGroups {
                for groupIndex in categories[index].similarGroups.indices {
                    categories[index].similarGroups[groupIndex].items.removeAll { itemIds.contains($0.id) }
                }
                // Remove empty groups
                categories[index].similarGroups.removeAll { $0.items.isEmpty }
            }
        }
    }
}
