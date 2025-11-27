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
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var analysisMessage = ""
    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isDeleting = false
    @Published var totalPhotoCount = 0
    @Published var totalVideoCount = 0
    @Published var diagnostics: LibraryDiagnostics?
    @Published var showDiagnostics = false
    @Published var dataVersion: Int = 0  // Incremented when data changes (for UI refresh)

    private let photoService = PhotoLibraryService.shared
    private let cacheService = CacheService.shared
    private let hashService = ImageHashService.shared

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
        // Sync authorization status (important when called from onboarding preloader)
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        // Start with progress bar immediately
        isAnalyzing = true
        analysisProgress = 0
        analysisMessage = "Récupération des médias..."

        // Run diagnostics
        let diag = photoService.getLibraryDiagnostics()
        diagnostics = diag

        analysisProgress = 0.05
        analysisMessage = "Chargement photos..."

        // Phase 1: Fast metadata scan (no thumbnails)
        async let screenshots = photoService.fetchScreenshots()
        async let largeVideos = photoService.fetchLargeVideos()
        async let allPhotos = photoService.fetchAllPhotos()
        async let allVideos = photoService.fetchAllVideos()

        let screenshotsResult = await screenshots
        analysisProgress = 0.10

        let largeVideosResult = await largeVideos
        analysisProgress = 0.12

        let allPhotosResult = await allPhotos
        analysisProgress = 0.18

        let allVideosResult = await allVideos
        analysisProgress = 0.20
        analysisMessage = "Organisation..."

        // Store total counts for display
        totalPhotoCount = allPhotosResult.count + screenshotsResult.count
        totalVideoCount = allVideosResult.count

        // Videos: keep date-based grouping (can't hash videos easily)
        let (similarVideos, videoGroups) = findPotentialDuplicatesWithGroups(in: allVideosResult)

        // Set initial categories with date-based grouping (fast)
        let (initialSimilarPhotos, initialPhotoGroups) = findPotentialDuplicatesWithGroups(in: allPhotosResult)
        let (initialSimilarScreenshots, initialScreenshotGroups) = findPotentialDuplicatesWithGroups(in: screenshotsResult)

        let initialSimilarScreenshotIds = Set(initialSimilarScreenshots.map { $0.id })
        let initialUniqueScreenshots = screenshotsResult.filter { !initialSimilarScreenshotIds.contains($0.id) }
        let initialSimilarPhotoIds = Set(initialSimilarPhotos.map { $0.id })
        let initialOthers = allPhotosResult.filter { !initialSimilarPhotoIds.contains($0.id) }

        analysisProgress = 0.25

        // Show categories immediately (user can start browsing)
        categories = [
            CategoryData(category: .similarPhotos, items: initialSimilarPhotos, similarGroups: initialPhotoGroups),
            CategoryData(category: .similarVideos, items: similarVideos, similarGroups: videoGroups),
            CategoryData(category: .similarScreenshots, items: initialSimilarScreenshots, similarGroups: initialScreenshotGroups),
            CategoryData(category: .screenshots, items: initialUniqueScreenshots),
            CategoryData(category: .largeVideos, items: largeVideosResult),
            CategoryData(category: .others, items: initialOthers)
        ]

        // Load preview thumbnails (in parallel with analysis)
        Task {
            await loadPreviewThumbnails()
        }

        // Phase 2: Run similarity analysis
        analysisMessage = "Analyse des similarités..."

        // Compute hashes for photos
        let photosToAnalyze = Array(allPhotosResult.prefix(2000))
        let photoHashes = await hashService.computeHashes(for: photosToAnalyze) { progress in
            self.analysisProgress = 0.25 + progress * 0.35 // 25-60%
            self.analysisMessage = "Analyse photos..."
        }

        // Compute hashes for screenshots
        let screenshotsToAnalyze = Array(screenshotsResult.prefix(1000))
        let screenshotHashes = await hashService.computeHashes(for: screenshotsToAnalyze) { progress in
            self.analysisProgress = 0.60 + progress * 0.30 // 60-90%
            self.analysisMessage = "Analyse screenshots..."
        }

        analysisProgress = 0.92
        analysisMessage = "Regroupement..."

        // Find similar photos using advanced perceptual hashing
        let photoSimilarGroups = hashService.groupBySimilarityAdvanced(
            items: photosToAnalyze,
            hashes: photoHashes,
            strictThreshold: 6,
            looseThreshold: 16,
            dayWindow: 30
        )

        // Find similar screenshots
        let screenshotSimilarGroups = hashService.groupBySimilarity(
            items: screenshotsToAnalyze,
            hashes: screenshotHashes,
            threshold: 10
        )

        analysisProgress = 0.96

        // Convert to SimilarGroup format
        let photoGroups = photoSimilarGroups.enumerated().map { index, items in
            SimilarGroup(dateKey: "group_\(index)", items: items)
        }
        let similarPhotos = photoGroups.flatMap { $0.items }

        let screenshotGroups = screenshotSimilarGroups.enumerated().map { index, items in
            SimilarGroup(dateKey: "group_\(index)", items: items)
        }
        let similarScreenshots = screenshotGroups.flatMap { $0.items }

        // Update categories with better similarity detection
        let similarScreenshotIds = Set(similarScreenshots.map { $0.id })
        let uniqueScreenshots = screenshotsResult.filter { !similarScreenshotIds.contains($0.id) }
        let similarPhotoIds = Set(similarPhotos.map { $0.id })
        let others = allPhotosResult.filter { !similarPhotoIds.contains($0.id) }

        // Update categories with improved results
        categories = [
            CategoryData(category: .similarPhotos, items: similarPhotos, similarGroups: photoGroups),
            CategoryData(category: .similarVideos, items: similarVideos, similarGroups: videoGroups),
            CategoryData(category: .similarScreenshots, items: similarScreenshots, similarGroups: screenshotGroups),
            CategoryData(category: .screenshots, items: uniqueScreenshots),
            CategoryData(category: .largeVideos, items: largeVideosResult),
            CategoryData(category: .others, items: others)
        ]

        analysisProgress = 1.0
        analysisMessage = "Terminé"

        // Small delay to show 100% before hiding
        try? await Task.sleep(nanoseconds: 300_000_000)
        isAnalyzing = false

        // Reload preview thumbnails for updated categories
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
        guard !items.isEmpty else { return true }

        isDeleting = true
        defer { isDeleting = false }

        let assets = items.map { $0.asset }
        let deletedIds = Set(items.map { $0.id })

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSFastEnumeration)
            }

            // Update local state immediately (no need to reload everything!)
            removeItemsFromCategories(ids: deletedIds)

            // Clear cache since library changed
            cacheService.clearCache()

            // Increment version to trigger UI refresh
            dataVersion += 1

            return true
        } catch {
            print("Error deleting items: \(error)")
            return false
        }
    }

    /// Remove items from all categories by their IDs (fast local update)
    private func removeItemsFromCategories(ids: Set<String>) {
        for index in categories.indices {
            // Remove from flat items list
            categories[index].items.removeAll { ids.contains($0.id) }

            // Remove from similar groups if applicable
            if categories[index].category.hasSimilarGroups {
                for groupIndex in categories[index].similarGroups.indices {
                    categories[index].similarGroups[groupIndex].items.removeAll { ids.contains($0.id) }
                }
                // Remove empty groups
                categories[index].similarGroups.removeAll { $0.items.isEmpty }
            }
        }

        // Update counts
        totalPhotoCount = categories.reduce(0) { count, cat in
            count + cat.items.filter { $0.asset.mediaType == .image }.count
        }
        totalVideoCount = categories.reduce(0) { count, cat in
            count + cat.items.filter { $0.asset.mediaType == .video }.count
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
