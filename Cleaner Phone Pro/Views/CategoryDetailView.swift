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
    @Environment(\.dismiss) private var dismiss

    /// Get the current category data from the viewModel (to get updated thumbnails)
    private var currentCategoryData: CategoryData {
        viewModel.categories.first { $0.category == categoryData.category } ?? categoryData
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if categoryData.category.hasSimilarGroups {
                similarPhotosView
            } else {
                regularGridView
            }

            if isLoadingThumbnails {
                loadingThumbnailsOverlay
            }
        }
        .navigationTitle(categoryData.category.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .fullScreenCover(isPresented: $showFullAccordion) {
            ItemsAccordionView(items: currentCategoryData.items, selectedItems: $selectedItems)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    // View detail button for non-similar categories
                    if !categoryData.category.hasSimilarGroups && !currentCategoryData.items.isEmpty {
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
            // Load thumbnails when entering the view
            await viewModel.loadThumbnailsForCategory(categoryData.category)
            isLoadingThumbnails = false
        }
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
                ForEach(currentCategoryData.items) { item in
                    SelectablePhotoCell(
                        item: item,
                        isSelected: selectedItems.contains(item),
                        onSelect: { toggleSelection(item) }
                    )
                }
            }
            .padding(2)
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

                // View detail button
                Button(action: { showAccordion = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption)
                        Text("Voir détail")
                            .font(.caption)
                    }
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
                }
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
}

// MARK: - Vertical Accordion View

struct VerticalAccordionView: View {
    let group: SimilarGroup
    @Binding var selectedItems: Set<MediaItem>
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var hdImages: [String: UIImage] = [:] // Cache des images HD par ID
    @State private var isPlayingVideo = false
    @State private var videoPlayer: AVPlayer?
    @StateObject private var videoLoader = VideoLoader()
    @State private var hdLoadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(Array(group.items.enumerated().reversed()), id: \.element.id) { index, item in
                        VerticalAccordionCard(
                            item: item,
                            highQualityImage: hdImages[item.id],
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
                    DragGesture()
                        .onChanged { value in
                            if !isPlayingVideo {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if isPlayingVideo { return }
                            let threshold: CGFloat = 60
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if value.translation.height > threshold && currentIndex < group.items.count - 1 {
                                    currentIndex += 1
                                    stopVideo()
                                } else if value.translation.height < -threshold && currentIndex > 0 {
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
        }
    }

    // MARK: - HD Preloading

    private func startHDPreloading() {
        hdLoadTask?.cancel()
        hdLoadTask = Task {
            // Preload current, next and previous items
            let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex - 1]
                .filter { $0 >= 0 && $0 < group.items.count }

            for index in indicesToLoad {
                let item = group.items[index]

                // Skip if already loaded or if it's a video
                if hdImages[item.id] != nil || item.asset.mediaType == .video {
                    continue
                }

                // Check if task was cancelled
                if Task.isCancelled { break }

                // Load HD image
                if let hdImage = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                    if !Task.isCancelled {
                        hdImages[item.id] = hdImage
                    }
                }
            }
        }
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
    @State private var hdImages: [String: UIImage] = [:] // Cache des images HD par ID
    @State private var isPlayingVideo = false
    @State private var videoPlayer: AVPlayer?
    @StateObject private var videoLoader = VideoLoader()
    @State private var hdLoadTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(Array(items.enumerated().reversed()), id: \.element.id) { index, item in
                        VerticalAccordionCard(
                            item: item,
                            highQualityImage: hdImages[item.id],
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
                    DragGesture()
                        .onChanged { value in
                            if !isPlayingVideo {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            if isPlayingVideo { return }
                            let threshold: CGFloat = 60
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if value.translation.height > threshold && currentIndex < items.count - 1 {
                                    currentIndex += 1
                                    stopVideo()
                                } else if value.translation.height < -threshold && currentIndex > 0 {
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
        }
    }

    // MARK: - HD Preloading

    private func startHDPreloading() {
        hdLoadTask?.cancel()
        hdLoadTask = Task {
            // Preload current, next and previous items
            let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex - 1]
                .filter { $0 >= 0 && $0 < items.count }

            for index in indicesToLoad {
                let item = items[index]

                // Skip if already loaded or if it's a video
                if hdImages[item.id] != nil || item.asset.mediaType == .video {
                    continue
                }

                // Check if task was cancelled
                if Task.isCancelled { break }

                // Load HD image
                if let hdImage = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                    if !Task.isCancelled {
                        hdImages[item.id] = hdImage
                    }
                }
            }
        }
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
                    Group {
                        if let image = highQualityImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else if let thumbnail = item.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray4))
                                .overlay(ProgressView())
                        }
                    }
                    .frame(width: screenSize.width - 24, height: screenSize.height * 0.80)
                    .clipped()

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
                    .fill(Color.white)
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
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Suppression en cours...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(.systemGray6))
            .cornerRadius(16)
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
