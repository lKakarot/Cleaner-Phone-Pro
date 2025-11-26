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
    
    private let photoService = PhotoLibraryService.shared
    
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
        
        async let screenshots = photoService.fetchScreenshots()
        async let largeVideos = photoService.fetchLargeVideos()
        async let allPhotos = photoService.fetchAllPhotos()
        async let allVideos = photoService.fetchAllVideos()
        
        let screenshotsResult = await screenshots
        let largeVideosResult = await largeVideos
        let allPhotosResult = await allPhotos
        let allVideosResult = await allVideos
        
        // For now, we'll use simple categorization
        // Similar photos/videos detection would require more complex algorithms
        let similarPhotos = findPotentialDuplicates(in: allPhotosResult)
        let similarVideos = findPotentialDuplicates(in: allVideosResult)
        
        // Others = photos that are not screenshots and not in similar
        let similarPhotoIds = Set(similarPhotos.map { $0.id })
        let others = allPhotosResult.filter { !similarPhotoIds.contains($0.id) }
        
        categories = [
            CategoryData(category: .similarPhotos, items: similarPhotos),
            CategoryData(category: .similarVideos, items: similarVideos),
            CategoryData(category: .screenshots, items: screenshotsResult),
            CategoryData(category: .largeVideos, items: largeVideosResult),
            CategoryData(category: .others, items: Array(others.prefix(50)))
        ]
        
        isLoading = false
    }
    
    private func findPotentialDuplicates(in items: [MediaItem]) -> [MediaItem] {
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
        
        // Return items that have potential duplicates (same minute)
        return grouped.values.filter { $0.count > 1 }.flatMap { $0 }
    }
}
