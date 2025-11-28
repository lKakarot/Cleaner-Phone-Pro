//
//  CategoryDetailView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos
import AVKit

struct CategoryDetailView: View {
    @ObservedObject var viewModel: CleanerViewModel
    let categoryData: CategoryData
    @State private var selectedItems: Set<MediaItem> = []
    @State private var isLoadingThumbnails = true
    @State private var showFullAccordion = false
    @State private var showSwipeMode = false
    @State private var loadedThumbnails: [String: UIImage] = [:] // Local thumbnail storage
    @State private var visibleItemRange: Range<Int> = 0..<20 // Track visible items
    @State private var thumbnailLoadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    /// Get the current category data from the viewModel (to get updated thumbnails)
    private var currentCategoryData: CategoryData {
        viewModel.categories.first { $0.category == categoryData.category } ?? categoryData
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea(edges: .bottom)

            if categoryData.category.hasSimilarGroups {
                similarPhotosView
            } else {
                regularGridView
            }

            if isLoadingThumbnails {
                loadingThumbnailsOverlay
            }
        }
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .fullScreenCover(isPresented: $showFullAccordion) {
            ItemsAccordionView(items: currentCategoryData.items, selectedItems: $selectedItems)
        }
        .fullScreenCover(isPresented: $showSwipeMode) {
            CategorySwipeModeView(
                items: currentCategoryData.items,
                categoryName: categoryData.category.rawValue,
                viewModel: viewModel
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // Swipe mode button for non-similar categories
                    if !categoryData.category.hasSimilarGroups && !currentCategoryData.items.isEmpty {
                        Button(action: { showSwipeMode = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.draw")
                                Text("Trier")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                        }

                        // View detail button
                        Button(action: { showFullAccordion = true }) {
                            Image(systemName: "rectangle.stack")
                        }
                    }

                    // Delete button - iOS will show its own confirmation
                    if !selectedItems.isEmpty {
                        Button(action: {
                            Task {
                                let itemsToDelete = Array(selectedItems)
                                let success = await viewModel.deleteItems(itemsToDelete)
                                if success {
                                    selectedItems.removeAll()
                                    if currentCategoryData.items.isEmpty {
                                        dismiss()
                                    }
                                }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("\(selectedItems.count)")
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .overlay {
            if viewModel.isDeleting {
                DeletingOverlay()
            }
        }
        .task {
            // OPTIMIZATION: Load only initial visible thumbnails, not all
            await loadInitialThumbnails()
            isLoadingThumbnails = false
        }
        .onDisappear {
            thumbnailLoadTask?.cancel()
            loadedThumbnails.removeAll() // Free memory
        }
    }

    // OPTIMIZATION: Load thumbnails progressively instead of all at once
    private func loadInitialThumbnails() async {
        if categoryData.category.hasSimilarGroups {
            // For similar groups, load first group's thumbnails
            await viewModel.loadThumbnailsForCategory(categoryData.category)
        } else {
            // For regular grid, load only first ~30 items
            let items = currentCategoryData.items
            let initialCount = min(30, items.count)
            let initialItems = Array(items.prefix(initialCount))

            let loadedItems = await PhotoLibraryService.shared.loadThumbnailsBatch(for: initialItems, quality: .detail)
            for (index, item) in loadedItems.enumerated() where index < initialCount {
                if let thumbnail = item.thumbnail {
                    loadedThumbnails[item.id] = thumbnail
                }
            }
        }
    }

    // Called when scroll position changes to load more thumbnails
    private func loadThumbnailsForVisibleRange(_ range: Range<Int>) {
        thumbnailLoadTask?.cancel()
        thumbnailLoadTask = Task {
            await PhotoLibraryService.shared.loadThumbnailsProgressive(
                for: currentCategoryData.items,
                visibleRange: range,
                quality: .detail
            ) { index, thumbnail in
                let item = currentCategoryData.items[index]
                loadedThumbnails[item.id] = thumbnail
            }
        }
    }

    // Helper to get thumbnail for an item
    private func getThumbnail(for item: MediaItem) -> UIImage? {
        return item.thumbnail ?? loadedThumbnails[item.id]
    }

    private var loadingThumbnailsOverlay: some View {
        VStack {
            Spacer()
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Chargement...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .cornerRadius(20)
            .shadow(radius: 4)
            .padding(.bottom, 20)
        }
    }

    private var similarPhotosView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(currentCategoryData.similarGroups) { group in
                    SimilarGroupView(
                        group: group,
                        selectedItems: $selectedItems
                    )
                }
            }
            .padding()
        }
    }

    private var regularGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ], spacing: 2) {
                ForEach(Array(currentCategoryData.items.enumerated()), id: \.element.id) { index, item in
                    LazyThumbnailCell(
                        item: item,
                        thumbnail: getThumbnail(for: item),
                        isSelected: selectedItems.contains(item),
                        onSelect: { toggleSelection(item) },
                        onAppear: {
                            // Load thumbnail on demand when cell appears
                            if getThumbnail(for: item) == nil {
                                loadThumbnailOnDemand(for: item, at: index)
                            }
                        }
                    )
                }
            }
            .padding(2)
        }
    }

    // Load single thumbnail on demand
    private func loadThumbnailOnDemand(for item: MediaItem, at index: Int) {
        Task {
            if let thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail) {
                await MainActor.run {
                    loadedThumbnails[item.id] = thumbnail
                }
            }
        }
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }
}

struct SimilarGroupView: View {
    let group: SimilarGroup
    @Binding var selectedItems: Set<MediaItem>
    @State private var showAccordion = false

    // Check if all items in this group are selected
    private var allSelected: Bool {
        group.items.allSatisfy { selectedItems.contains($0) }
    }

    // Count of selected items in this group
    private var selectedCountInGroup: Int {
        group.items.filter { selectedItems.contains($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.items.count) photos similaires")
                        .font(.headline)

                    Text(group.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Select all button (icon only for compact display)
                Button(action: { toggleSelectAll() }) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(allSelected ? .blue : .secondary)
                }
                .frame(width: 36, height: 36)

                // View detail button
                Button(action: { showAccordion = true }) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                .frame(width: 36, height: 36)
                .background(Color(.systemGray5))
                .cornerRadius(8)
            }

            // Photos grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(group.items) { item in
                    SelectablePhotoCell(
                        item: item,
                        isSelected: selectedItems.contains(item),
                        onSelect: { toggleSelection(item) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .fullScreenCover(isPresented: $showAccordion) {
            VerticalAccordionView(group: group, selectedItems: $selectedItems)
        }
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            // Deselect all items in this group
            for item in group.items {
                selectedItems.remove(item)
            }
        } else {
            // Select all items in this group
            for item in group.items {
                selectedItems.insert(item)
            }
        }
    }
}

// MARK: - LRU Cache for HD Images (optimized memory management)

@MainActor
final class HDImageCache: ObservableObject {
    static let shared = HDImageCache()

    private var cache: [String: UIImage] = [:]
    private var accessOrder: [String] = []
    private let maxSize = 8 // Keep only 8 HD images in memory max

    func get(_ id: String) -> UIImage? {
        if let image = cache[id] {
            // Move to end (most recently used)
            accessOrder.removeAll { $0 == id }
            accessOrder.append(id)
            return image
        }
        return nil
    }

    func set(_ image: UIImage, for id: String) {
        // Evict oldest if at capacity
        while cache.count >= maxSize && !accessOrder.isEmpty {
            let oldest = accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[id] = image
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    func clear() {
        cache.removeAll()
        accessOrder.removeAll()
    }
}

// MARK: - Vertical Accordion View

struct VerticalAccordionView: View {
    let group: SimilarGroup
    @Binding var selectedItems: Set<MediaItem>
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @StateObject private var hdCache = HDImageCache()
    @State private var localHDImages: [String: UIImage] = [:] // Local cache for current session
    @State private var isPlayingVideo = false
    @State private var videoPlayer: AVPlayer?
    @StateObject private var videoLoader = VideoLoader()
    @State private var hdLoadTask: Task<Void, Never>?

    // OPTIMIZATION: Only render items within visible window (±2 from current)
    private var visibleIndices: [Int] {
        let start = max(0, currentIndex - 2)
        let end = min(group.items.count - 1, currentIndex + 2)
        guard start <= end else { return [] }
        return Array(start...end)
    }

    private func getHDImage(for id: String) -> UIImage? {
        return localHDImages[id] ?? hdCache.get(id)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    // OPTIMIZATION: Only create views for visible items (5 max instead of ALL)
                    ForEach(visibleIndices.reversed(), id: \.self) { index in
                        let item = group.items[index]
                        VerticalAccordionCard(
                            item: item,
                            highQualityImage: getHDImage(for: item.id),
                            isSelected: selectedItems.contains(item),
                            index: index,
                            currentIndex: currentIndex,
                            totalCount: group.items.count,
                            screenSize: geometry.size,
                            dragOffset: index == currentIndex ? dragOffset : 0,
                            onSelect: { toggleSelection(item) },
                            isPlayingVideo: $isPlayingVideo,
                            videoPlayer: $videoPlayer
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if !isPlayingVideo {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if isPlayingVideo { return }
                            // Use both threshold and velocity for better UX
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            let shouldScrollDown = value.translation.height > threshold || velocity > 200
                            let shouldScrollUp = value.translation.height < -threshold || velocity < -200

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if shouldScrollDown && currentIndex < group.items.count - 1 {
                                    currentIndex += 1
                                    stopVideo()
                                } else if shouldScrollUp && currentIndex > 0 {
                                    currentIndex -= 1
                                    stopVideo()
                                }
                                dragOffset = 0
                            }
                        }
                )
            }

            // UI Overlay
            VStack {
                // Header
                HStack {
                    Button(action: {
                        stopVideo()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(group.items.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)

                    Spacer()

                    let selectedCount = group.items.filter { selectedItems.contains($0) }.count
                    Text("\(selectedCount) sél.")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCount > 0 ? Color.blue : Color.black.opacity(0.5))
                        .cornerRadius(20)
                }
                .padding()

                Spacer()

                // Bottom controls
                if let currentItem = group.items[safe: currentIndex] {
                    VStack(spacing: 12) {
                        // iCloud download progress indicator
                        if case .downloadingFromCloud(let progress) = videoLoader.state {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .frame(width: 50, height: 50)
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "icloud.and.arrow.down")
                                    Text("Téléchargement iCloud...")
                                }
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.bottom, 8)
                        }

                        // Action buttons row (only for videos)
                        if currentItem.asset.mediaType == .video {
                            Button(action: {
                                if isPlayingVideo {
                                    stopVideo()
                                } else {
                                    playVideo(for: currentItem.asset)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if case .loading = videoLoader.state {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: isPlayingVideo ? "stop.fill" : "play.fill")
                                    }
                                    Text(isPlayingVideo ? "Stop" : "Lire")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(isPlayingVideo ? Color.red : Color.green)
                                .cornerRadius(25)
                            }
                            .disabled(isVideoLoading)
                        }

                        // Select button
                        Button(action: { toggleSelection(currentItem) }) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedItems.contains(currentItem) ? "checkmark.circle.fill" : "circle")
                                Text(selectedItems.contains(currentItem) ? "Sélectionnée" : "Sélectionner")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(selectedItems.contains(currentItem) ? Color.blue : Color.black.opacity(0.6))
                            .cornerRadius(30)
                        }

                        // Info
                        HStack(spacing: 6) {
                            Text(ByteCountFormatter.string(fromByteCount: currentItem.fileSize, countStyle: .file))
                                .fontWeight(.medium)
                            Text("•")
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                            Text("Glissez vers le bas")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .onAppear {
            startHDPreloading()
        }
        .onChange(of: currentIndex) { _ in
            startHDPreloading()
            cleanupDistantImages()
        }
        .onChange(of: videoLoader.state) { newState in
            if case .ready(let playerItem) = newState {
                let player = AVPlayer(playerItem: playerItem)
                self.videoPlayer = player
                self.isPlayingVideo = true
                player.play()
            }
        }
        .onDisappear {
            stopVideo()
            hdLoadTask?.cancel()
            localHDImages.removeAll() // Free memory on dismiss
        }
    }

    // MARK: - HD Preloading (Optimized)

    private func startHDPreloading() {
        hdLoadTask?.cancel()
        hdLoadTask = Task {
            // Preload current and next 2 items (3 total)
            let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex + 2]
                .filter { $0 >= 0 && $0 < group.items.count }

            for index in indicesToLoad {
                let item = group.items[index]

                // Skip if already loaded
                if localHDImages[item.id] != nil || hdCache.get(item.id) != nil {
                    continue
                }

                // Check if task was cancelled
                if Task.isCancelled { break }

                if item.asset.mediaType == .video {
                    // For videos: load high-quality thumbnail (.swipe quality = 900x900)
                    if let thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .swipe) {
                        if !Task.isCancelled {
                            localHDImages[item.id] = thumbnail
                            hdCache.set(thumbnail, for: item.id)
                        }
                    }
                } else {
                    // For photos: load full HD image
                    if let hdImage = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                        if !Task.isCancelled {
                            localHDImages[item.id] = hdImage
                            hdCache.set(hdImage, for: item.id)
                        }
                    }
                }
            }
        }
    }

    // OPTIMIZATION: Remove HD images that are far from current view to free memory
    private func cleanupDistantImages() {
        let keepIndices = Set((max(0, currentIndex - 3)...min(group.items.count - 1, currentIndex + 3)))
        let keepIds = Set(keepIndices.map { group.items[$0].id })

        localHDImages = localHDImages.filter { keepIds.contains($0.key) }
    }

    private var isVideoLoading: Bool {
        switch videoLoader.state {
        case .loading, .downloadingFromCloud:
            return true
        default:
            return false
        }
    }

    private func playVideo(for asset: PHAsset) {
        videoLoader.load(asset: asset)
    }

    private func stopVideo() {
        videoPlayer?.pause()
        videoPlayer = nil
        isPlayingVideo = false
        videoLoader.cancel()
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }
}

// MARK: - Items Accordion View (for non-similar categories)

struct ItemsAccordionView: View {
    let items: [MediaItem]
    @Binding var selectedItems: Set<MediaItem>
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @StateObject private var hdCache = HDImageCache()
    @State private var localHDImages: [String: UIImage] = [:] // Local cache for current session
    @State private var isPlayingVideo = false
    @State private var videoPlayer: AVPlayer?
    @StateObject private var videoLoader = VideoLoader()
    @State private var hdLoadTask: Task<Void, Never>?

    // OPTIMIZATION: Only render items within visible window (±2 from current)
    private var visibleIndices: [Int] {
        let start = max(0, currentIndex - 2)
        let end = min(items.count - 1, currentIndex + 2)
        guard start <= end else { return [] }
        return Array(start...end)
    }

    private func getHDImage(for id: String) -> UIImage? {
        return localHDImages[id] ?? hdCache.get(id)
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    // OPTIMIZATION: Only create views for visible items (5 max instead of ALL)
                    ForEach(visibleIndices.reversed(), id: \.self) { index in
                        let item = items[index]
                        VerticalAccordionCard(
                            item: item,
                            highQualityImage: getHDImage(for: item.id),
                            isSelected: selectedItems.contains(item),
                            index: index,
                            currentIndex: currentIndex,
                            totalCount: items.count,
                            screenSize: geometry.size,
                            dragOffset: index == currentIndex ? dragOffset : 0,
                            onSelect: { toggleSelection(item) },
                            isPlayingVideo: $isPlayingVideo,
                            videoPlayer: $videoPlayer
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if !isPlayingVideo {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if isPlayingVideo { return }
                            // Use both threshold and velocity for better UX
                            let threshold: CGFloat = 50
                            let velocity = value.predictedEndTranslation.height - value.translation.height
                            let shouldScrollDown = value.translation.height > threshold || velocity > 200
                            let shouldScrollUp = value.translation.height < -threshold || velocity < -200

                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                if shouldScrollDown && currentIndex < items.count - 1 {
                                    currentIndex += 1
                                    stopVideo()
                                } else if shouldScrollUp && currentIndex > 0 {
                                    currentIndex -= 1
                                    stopVideo()
                                }
                                dragOffset = 0
                            }
                        }
                )
            }

            // UI Overlay
            VStack {
                // Header
                HStack {
                    Button(action: {
                        stopVideo()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)

                    Spacer()

                    let selectedCount = items.filter { selectedItems.contains($0) }.count
                    Text("\(selectedCount) sél.")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCount > 0 ? Color.blue : Color.black.opacity(0.5))
                        .cornerRadius(20)
                }
                .padding()

                Spacer()

                // Bottom controls
                if let currentItem = items[safe: currentIndex] {
                    VStack(spacing: 12) {
                        // iCloud download progress indicator
                        if case .downloadingFromCloud(let progress) = videoLoader.state {
                            VStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                        .frame(width: 50, height: 50)
                                    Circle()
                                        .trim(from: 0, to: progress)
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                        .frame(width: 50, height: 50)
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                }
                                HStack(spacing: 4) {
                                    Image(systemName: "icloud.and.arrow.down")
                                    Text("Téléchargement iCloud...")
                                }
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.bottom, 8)
                        }

                        // Action buttons row (only for videos)
                        if currentItem.asset.mediaType == .video {
                            Button(action: {
                                if isPlayingVideo {
                                    stopVideo()
                                } else {
                                    playVideo(for: currentItem.asset)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    if case .loading = videoLoader.state {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: isPlayingVideo ? "stop.fill" : "play.fill")
                                    }
                                    Text(isPlayingVideo ? "Stop" : "Lire")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(isPlayingVideo ? Color.red : Color.green)
                                .cornerRadius(25)
                            }
                            .disabled(isVideoLoading)
                        }

                        // Select button
                        Button(action: { toggleSelection(currentItem) }) {
                            HStack(spacing: 8) {
                                Image(systemName: selectedItems.contains(currentItem) ? "checkmark.circle.fill" : "circle")
                                Text(selectedItems.contains(currentItem) ? "Sélectionnée" : "Sélectionner")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(selectedItems.contains(currentItem) ? Color.blue : Color.black.opacity(0.6))
                            .cornerRadius(30)
                        }

                        // Info
                        HStack(spacing: 6) {
                            Text(ByteCountFormatter.string(fromByteCount: currentItem.fileSize, countStyle: .file))
                                .fontWeight(.medium)
                            Text("•")
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                            Text("Glissez vers le bas")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .onAppear {
            startHDPreloading()
        }
        .onChange(of: currentIndex) { _ in
            startHDPreloading()
            cleanupDistantImages()
        }
        .onChange(of: videoLoader.state) { newState in
            if case .ready(let playerItem) = newState {
                let player = AVPlayer(playerItem: playerItem)
                self.videoPlayer = player
                self.isPlayingVideo = true
                player.play()
            }
        }
        .onDisappear {
            stopVideo()
            hdLoadTask?.cancel()
            localHDImages.removeAll() // Free memory on dismiss
        }
    }

    // MARK: - HD Preloading (Optimized for both photos and videos)

    private func startHDPreloading() {
        hdLoadTask?.cancel()
        hdLoadTask = Task {
            // Preload current and next 2 items (3 total)
            let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex + 2]
                .filter { $0 >= 0 && $0 < items.count }

            for index in indicesToLoad {
                let item = items[index]

                // Skip if already loaded
                if localHDImages[item.id] != nil || hdCache.get(item.id) != nil {
                    continue
                }

                // Check if task was cancelled
                if Task.isCancelled { break }

                if item.asset.mediaType == .video {
                    // For videos: load high-quality thumbnail (.swipe quality = 900x900)
                    if let thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .swipe) {
                        if !Task.isCancelled {
                            localHDImages[item.id] = thumbnail
                            hdCache.set(thumbnail, for: item.id)
                        }
                    }
                } else {
                    // For photos: load full HD image
                    if let hdImage = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                        if !Task.isCancelled {
                            localHDImages[item.id] = hdImage
                            hdCache.set(hdImage, for: item.id)
                        }
                    }
                }
            }
        }
    }

    // OPTIMIZATION: Remove HD images that are far from current view to free memory
    private func cleanupDistantImages() {
        let keepIndices = Set((max(0, currentIndex - 3)...min(items.count - 1, currentIndex + 3)))
        let keepIds = Set(keepIndices.map { items[$0].id })

        localHDImages = localHDImages.filter { keepIds.contains($0.key) }
    }

    private var isVideoLoading: Bool {
        switch videoLoader.state {
        case .loading, .downloadingFromCloud:
            return true
        default:
            return false
        }
    }

    private func playVideo(for asset: PHAsset) {
        videoLoader.load(asset: asset)
    }

    private func stopVideo() {
        videoPlayer?.pause()
        videoPlayer = nil
        isPlayingVideo = false
        videoLoader.cancel()
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
    }
}

struct VerticalAccordionCard: View {
    let item: MediaItem
    let highQualityImage: UIImage?
    let isSelected: Bool
    let index: Int
    let currentIndex: Int
    let totalCount: Int
    let screenSize: CGSize
    let dragOffset: CGFloat
    let onSelect: () -> Void
    @Binding var isPlayingVideo: Bool
    @Binding var videoPlayer: AVPlayer?

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    private var videoDuration: String {
        guard isVideo else { return "" }
        let duration = item.asset.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var relativeIndex: Int {
        index - currentIndex
    }

    private var offsetY: CGFloat {
        // Base position: cards aligned at bottom
        let bottomAlign = screenSize.height * 0.12

        if relativeIndex < 0 {
            // Cards that have been swiped away go down off screen
            return screenSize.height + dragOffset
        }
        if relativeIndex == 0 {
            // Current card at bottom, follows drag
            return bottomAlign + dragOffset
        }
        // Cards behind: stacked ABOVE with decreasing offset (visible at top)
        return bottomAlign - CGFloat(relativeIndex) * 50
    }

    private var scale: CGFloat {
        if relativeIndex < 0 { return 1.0 }
        if relativeIndex == 0 { return 1.0 }
        // Cards behind are slightly smaller
        return max(0.92, 1.0 - CGFloat(relativeIndex) * 0.02)
    }

    private var opacity: Double {
        if relativeIndex < 0 { return 0 }
        if relativeIndex > 6 { return 0 }
        return 1.0
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Photo/Video with border frame
            ZStack(alignment: .topLeading) {
                // Show video player if playing, otherwise show thumbnail
                if isPlayingVideo && relativeIndex == 0, let player = videoPlayer {
                    VideoPlayer(player: player)
                        .frame(width: screenSize.width - 24, height: screenSize.height * 0.80)
                } else {
                    // Background for letterboxing
                    Color(.systemGray6)
                        .frame(width: screenSize.width - 24, height: screenSize.height * 0.80)

                    Group {
                        if let image = highQualityImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if let thumbnail = item.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .overlay(ProgressView())
                        }
                    }
                    .frame(maxWidth: screenSize.width - 24, maxHeight: screenSize.height * 0.80)

                    // Video badge (only when not playing)
                    if isVideo && relativeIndex == 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text(videoDuration)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(16)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .scaleEffect(scale, anchor: .bottom)
        .offset(y: offsetY)
        .opacity(opacity)
        .zIndex(Double(totalCount - index))
        .shadow(color: .black.opacity(0.2), radius: 12, y: relativeIndex > 0 ? 8 : 0)
        .overlay(
            // Selection indicator
            Group {
                if isSelected && relativeIndex >= 0 {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                                .background(Circle().fill(.white).frame(width: 24, height: 24))
                                .shadow(radius: 4)
                                .padding(20)
                        }
                        Spacer()
                    }
                    .offset(y: offsetY + 10)
                }
            }
        )
        .onTapGesture {
            if relativeIndex == 0 {
                onSelect()
            }
        }
    }
}

// Safe array subscript
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// OPTIMIZATION: Lazy loading cell with onAppear callback
struct LazyThumbnailCell: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onAppear: () -> Void

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    private var videoDuration: String {
        guard isVideo else { return "" }
        let duration = item.asset.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo/Video thumbnail - tap to select
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }

            // Video indicator (top left)
            if isVideo {
                VStack {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(videoDuration)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)

                        Spacer()
                    }
                    Spacer()
                }
            }

            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.black.opacity(0.3))
                    .frame(width: 26, height: 26)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(6)

            // File size label
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
        .onTapGesture {
            onSelect()
        }
        .onAppear {
            onAppear()
        }
    }
}

struct SelectablePhotoCell: View {
    let item: MediaItem
    let isSelected: Bool
    let onSelect: () -> Void

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    private var videoDuration: String {
        guard isVideo else { return "" }
        let duration = item.asset.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo/Video thumbnail - tap to select
            if let thumbnail = item.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }

            // Video indicator (top left)
            if isVideo {
                VStack {
                    HStack {
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(videoDuration)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .padding(4)

                        Spacer()
                    }
                    Spacer()
                }
            }

            // Selection indicator
            ZStack {
                Circle()
                    .fill(isSelected ? Color.blue : Color.black.opacity(0.3))
                    .frame(width: 26, height: 26)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(6)

            // File size label
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
        .onTapGesture {
            onSelect()
        }
    }
}

struct DeletingOverlay: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Fond semi-transparent avec blur
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Card centrale
            VStack(spacing: 20) {
                // Icône animée
                ZStack {
                    // Cercle extérieur qui pulse
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.red.opacity(0.3), .orange.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .opacity(isAnimating ? 0.3 : 0.8)

                    // Cercle qui tourne
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))

                    // Icône centrale
                    Image(systemName: "trash.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.red, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(spacing: 8) {
                    Text("Suppression en cours")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(.label))

                    Text("Veuillez patienter...")
                        .font(.subheadline)
                        .foregroundColor(Color(.secondaryLabel))
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Category Swipe Mode View

struct CategorySwipeModeView: View {
    let items: [MediaItem]
    let categoryName: String
    @ObservedObject var viewModel: CleanerViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var toKeep: [MediaItem] = []
    @State private var toDelete: [MediaItem] = []
    @State private var hdImage: UIImage?
    @State private var loadedThumbnails: [String: UIImage] = [:]
    @State private var hdLoadTask: Task<Void, Never>?
    @State private var showResults = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if showResults {
                CategorySwipeResultsView(
                    categoryName: categoryName,
                    toKeep: toKeep,
                    toDelete: toDelete,
                    onDeleteConfirmed: deleteSelectedItems,
                    onReset: resetSwipe,
                    onDismiss: { dismiss() }
                )
            } else if currentIndex >= items.count {
                // All done
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("Tri terminé !")
                        .font(.title2)
                        .fontWeight(.bold)

                    Button(action: { showResults = true }) {
                        Text("Voir le résumé")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(25)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(10)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }

                        Spacer()

                        VStack(spacing: 2) {
                            Text(categoryName)
                                .font(.headline)
                            Text("\(currentIndex + 1) / \(items.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { showResults = true }) {
                            Text("Terminer")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Stats
                    HStack(spacing: 30) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("\(toDelete.count)")
                        }
                        .foregroundColor(.red)

                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                            Text("\(toKeep.count)")
                        }
                        .foregroundColor(.green)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.top, 8)

                    Spacer()

                    // Card
                    ZStack {
                        // Background cards - reversed so next card is on top
                        ForEach((0..<min(2, items.count - currentIndex - 1)).reversed(), id: \.self) { i in
                            let index = currentIndex + i + 1
                            if index < items.count {
                                CategorySwipeCardBackground(
                                    item: items[index],
                                    thumbnail: getThumbnail(for: items[index]),
                                    offset: CGFloat(i)
                                )
                            }
                        }

                        // Current card
                        CategorySwipeCard(
                            item: items[currentIndex],
                            thumbnail: getThumbnail(for: items[currentIndex]),
                            hdImage: hdImage,
                            offset: offset
                        )
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 20)))
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    offset = gesture.translation
                                }
                                .onEnded { gesture in
                                    handleGestureEnd(gesture)
                                }
                        )
                    }
                    .padding()

                    Spacer()

                    // Action buttons
                    HStack(spacing: 30) {
                        Button(action: { swipeLeft() }) {
                            Image(systemName: "xmark")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 65, height: 65)
                                .background(Color.red)
                                .clipShape(Circle())
                        }

                        Button(action: { undoSwipe() }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 50, height: 50)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                        .disabled(currentIndex == 0 && toKeep.isEmpty && toDelete.isEmpty)
                        .opacity(currentIndex == 0 && toKeep.isEmpty && toDelete.isEmpty ? 0.4 : 1)

                        Button(action: { swipeRight() }) {
                            Image(systemName: "heart.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 65, height: 65)
                                .background(Color.green)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.bottom, 30)

                    // Instructions
                    HStack(spacing: 30) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Supprimer")
                        }
                        .foregroundColor(.red)

                        HStack(spacing: 4) {
                            Text("Garder")
                            Image(systemName: "arrow.right")
                        }
                        .foregroundColor(.green)
                    }
                    .font(.caption)
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            loadVisibleItems()
        }
        .onChange(of: currentIndex) { _ in
            loadVisibleItems()
        }
        .onDisappear {
            hdLoadTask?.cancel()
        }
    }

    private func getThumbnail(for item: MediaItem) -> UIImage? {
        return item.thumbnail ?? loadedThumbnails[item.id]
    }

    private func loadVisibleItems() {
        hdImage = nil

        // Keep some thumbnails in cache
        if !items.isEmpty && currentIndex < items.count {
            let validEnd = min(items.count - 1, currentIndex + 3)
            let validStart = max(0, currentIndex - 1)
            if validStart <= validEnd {
                let indicesToKeep = Set((validStart...validEnd).map { items[$0].id })
                loadedThumbnails = loadedThumbnails.filter { indicesToKeep.contains($0.key) }
            }
        }

        let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex + 2]
            .filter { $0 >= 0 && $0 < items.count }

        for index in indicesToLoad {
            let item = items[index]
            if item.thumbnail == nil && loadedThumbnails[item.id] == nil {
                Task {
                    if let thumb = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .swipe) {
                        await MainActor.run {
                            loadedThumbnails[item.id] = thumb
                        }
                    }
                }
            }
        }

        loadHDForCurrentItem()
    }

    private func loadHDForCurrentItem() {
        hdLoadTask?.cancel()
        guard currentIndex < items.count else { return }
        let item = items[currentIndex]
        guard item.asset.mediaType == .image else {
            hdImage = nil
            return
        }

        hdLoadTask = Task {
            if let image = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                if !Task.isCancelled {
                    await MainActor.run {
                        hdImage = image
                    }
                }
            }
        }
    }

    private func handleGestureEnd(_ gesture: DragGesture.Value) {
        let threshold: CGFloat = 100
        if gesture.translation.width < -threshold {
            swipeLeft()
        } else if gesture.translation.width > threshold {
            swipeRight()
        } else {
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }

    private func swipeLeft() {
        let item = items[currentIndex]
        withAnimation(.spring()) {
            offset = CGSize(width: -500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            toDelete.append(item)
            currentIndex += 1
            offset = .zero
        }
    }

    private func swipeRight() {
        let item = items[currentIndex]
        withAnimation(.spring()) {
            offset = CGSize(width: 500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            toKeep.append(item)
            currentIndex += 1
            offset = .zero
        }
    }

    private func undoSwipe() {
        guard currentIndex > 0 || !toKeep.isEmpty || !toDelete.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        }
        if let last = toKeep.last, last.id == items[currentIndex].id {
            toKeep.removeLast()
        } else if let last = toDelete.last, last.id == items[currentIndex].id {
            toDelete.removeLast()
        }
    }

    private func resetSwipe() {
        currentIndex = 0
        toKeep = []
        toDelete = []
        hdImage = nil
        showResults = false
    }

    private func deleteSelectedItems() {
        Task {
            let _ = await viewModel.deleteItems(toDelete)
            await MainActor.run {
                dismiss()
            }
        }
    }
}

// MARK: - Category Swipe Card

struct CategorySwipeCard: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let hdImage: UIImage?
    let offset: CGSize

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGray6)

                if let image = hdImage ?? thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                } else {
                    ProgressView()
                }

                // Video badge
                if isVideo {
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12))
                                Text(formatDuration(item.asset.duration))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(12)
                            Spacer()
                        }
                        Spacer()
                    }
                }

                // Swipe indicators
                VStack {
                    Spacer()
                    HStack {
                        if offset.width < -20 {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.red)
                                .opacity(min(1, Double(-offset.width) / 100))
                        }
                        Spacer()
                        if offset.width > 20 {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.green)
                                .opacity(min(1, Double(offset.width) / 100))
                        }
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                }

                // File info
                VStack {
                    Spacer()
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let date = item.asset.creationDate {
                            Text(date, style: .date)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
        .aspectRatio(0.7, contentMode: .fit)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Category Swipe Card Background

struct CategorySwipeCardBackground: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let offset: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGray6)
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                } else {
                    ProgressView().scaleEffect(0.8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .scaleEffect(1 - (offset + 1) * 0.05)
            .offset(y: (offset + 1) * 10)
            .opacity(0.7 - offset * 0.2)
        }
        .aspectRatio(0.7, contentMode: .fit)
    }
}

// MARK: - Category Swipe Results View

struct CategorySwipeResultsView: View {
    let categoryName: String
    let toKeep: [MediaItem]
    let toDelete: [MediaItem]
    let onDeleteConfirmed: () -> Void
    let onReset: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
                Spacer()
                Text("Résumé")
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal)

            // Stats
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .font(.title)
                        .foregroundColor(.green)
                    Text("\(toKeep.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("À garder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.title)
                        .foregroundColor(.red)
                    Text("\(toDelete.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("À supprimer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical)

            // Space to free
            if !toDelete.isEmpty {
                let totalSize = toDelete.reduce(0) { $0 + $1.fileSize }
                Text("Espace à libérer: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                    .font(.headline)
                    .foregroundColor(.green)
            }

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                if !toDelete.isEmpty {
                    Button(action: onDeleteConfirmed) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Supprimer \(toDelete.count) éléments")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                }

                Button(action: onReset) {
                    Text("Recommencer")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(14)
                }

                Button(action: onDismiss) {
                    Text("Fermer")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            viewModel: CleanerViewModel(),
            categoryData: CategoryData(
                category: .screenshots,
                items: []
            )
        )
    }
}
