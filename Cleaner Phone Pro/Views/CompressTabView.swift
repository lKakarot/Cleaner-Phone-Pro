//
//  CompressTabView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos
import AVKit

// MARK: - Compress Tab View

struct CompressTabView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @State private var selectedItem: MediaItem?
    @State private var selectedItems: Set<String> = []
    @State private var isSelectionMode = false
    @State private var showCompressionSheet = false
    @State private var showBatchCompressionSheet = false
    @State private var selectedTab = 0
    @State private var loadedThumbnails: [String: UIImage] = [:]
    @State private var refreshTrigger = 0

    private var allPhotos: [MediaItem] {
        viewModel.categories.flatMap { cat in
            cat.items.filter { $0.asset.mediaType == .image }
        }
    }

    private var allVideos: [MediaItem] {
        viewModel.categories.flatMap { cat in
            cat.items.filter { $0.asset.mediaType == .video }
        }
    }

    private var currentItems: [MediaItem] {
        selectedTab == 0 ? allPhotos : allVideos
    }

    private var selectedMediaItems: [MediaItem] {
        currentItems.filter { selectedItems.contains($0.id) }
    }

    private var totalSelectedSize: Int64 {
        selectedMediaItems.reduce(0) { $0 + $1.fileSize }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isAnalyzing {
                    // Loading state
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(viewModel.analysisMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        ProgressView(value: viewModel.analysisProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    }
                    Spacer()
                } else if currentItems.isEmpty {
                    // Empty state
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: selectedTab == 0 ? "photo.stack" : "video.stack")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text(selectedTab == 0 ? "Aucune photo" : "Aucune vidéo")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    // Header with selection toggle
                    HStack {
                        if isSelectionMode {
                            Text("\(selectedItems.count) sélectionné(s)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        } else {
                            Text("Sélectionnez un média à compresser")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            withAnimation {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedItems.removeAll()
                                }
                            }
                        }) {
                            Text(isSelectionMode ? "Annuler" : "Sélectionner")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Segment picker
                    Picker("Type", selection: $selectedTab) {
                        Text("Photos (\(allPhotos.count))").tag(0)
                        Text("Vidéos (\(allVideos.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .onChange(of: selectedTab) { _ in
                        // Clear selection when switching tabs
                        selectedItems.removeAll()
                    }

                    // Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(currentItems) { item in
                                CompressMediaCell(
                                    item: item,
                                    thumbnail: item.thumbnail ?? loadedThumbnails[item.id],
                                    isSelectionMode: isSelectionMode,
                                    isSelected: selectedItems.contains(item.id),
                                    onSelect: {
                                        if isSelectionMode {
                                            toggleSelection(item)
                                        } else {
                                            selectedItem = item
                                            showCompressionSheet = true
                                        }
                                    },
                                    onAppear: { loadThumbnailIfNeeded(for: item) }
                                )
                            }
                        }
                        .padding(2)
                        .id(refreshTrigger)
                    }

                    // Bottom bar for batch compression (when items selected)
                    if isSelectionMode && !selectedItems.isEmpty {
                        VStack(spacing: 0) {
                            Divider()

                            HStack(spacing: 16) {
                                // Select all button
                                Button(action: selectAll) {
                                    VStack(spacing: 4) {
                                        Image(systemName: selectedItems.count == currentItems.count ? "checkmark.circle.fill" : "checkmark.circle")
                                            .font(.title2)
                                        Text("Tout")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.blue)
                                }

                                Spacer()

                                // Size info
                                VStack(spacing: 2) {
                                    Text("\(selectedItems.count) fichier(s)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }

                                Spacer()

                                // Compress button
                                Button(action: {
                                    showBatchCompressionSheet = true
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Compresser")
                                    }
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.blue)
                                    .cornerRadius(20)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .background(Color(.systemBackground))
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCompressionSheet, onDismiss: {
            Task { await refreshData() }
        }) {
            if let item = selectedItem {
                CompressionFlowView(item: item, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showBatchCompressionSheet, onDismiss: {
            Task { await refreshData() }
            isSelectionMode = false
            selectedItems.removeAll()
        }) {
            BatchCompressionFlowView(
                items: selectedMediaItems,
                viewModel: viewModel
            )
        }
    }

    private func toggleSelection(_ item: MediaItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
    }

    private func selectAll() {
        if selectedItems.count == currentItems.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(currentItems.map { $0.id })
        }
    }

    private func loadThumbnailIfNeeded(for item: MediaItem) {
        guard loadedThumbnails[item.id] == nil && item.thumbnail == nil else { return }
        Task {
            if let thumb = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail) {
                await MainActor.run {
                    loadedThumbnails[item.id] = thumb
                }
            }
        }
    }

    private func refreshData() async {
        CacheService.shared.clearCache()
        await viewModel.loadAllCategories()
        refreshTrigger += 1
    }
}

// MARK: - Compress Media Cell

struct CompressMediaCell: View {
    let item: MediaItem
    let thumbnail: UIImage?
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    let onSelect: () -> Void
    let onAppear: () -> Void

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .aspectRatio(1, contentMode: .fill)
                        .overlay(ProgressView().scaleEffect(0.7))
                }

                // Selection overlay
                if isSelectionMode {
                    Color.black.opacity(isSelected ? 0.3 : 0)

                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(isSelected ? Color.blue : Color.white.opacity(0.8))
                                    .frame(width: 24, height: 24)

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Circle()
                                        .stroke(Color.gray, lineWidth: 1.5)
                                        .frame(width: 22, height: 22)
                                }
                            }
                            .padding(6)
                        }
                        Spacer()
                    }
                }

                // Size badge (top right) - only show when not in selection mode
                if !isSelectionMode {
                    VStack {
                        HStack {
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4)
                                .padding(4)
                        }
                        Spacer()
                    }
                }

                // Video duration (bottom left)
                if isVideo {
                    VStack {
                        Spacer()
                        HStack {
                            HStack(spacing: 2) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text(formatDuration(item.asset.duration))
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                            .padding(4)
                            Spacer()
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear { onAppear() }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Batch Compression Flow View

struct BatchCompressionFlowView: View {
    let items: [MediaItem]
    @ObservedObject var viewModel: CleanerViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flowState = BatchCompressionFlowState()

    var body: some View {
        NavigationStack {
            Group {
                switch flowState.step {
                case .selectLevel:
                    BatchCompressionSelectLevelView(
                        items: items,
                        flowState: flowState
                    )
                case .compressing:
                    BatchCompressionProgressView(flowState: flowState)
                case .result:
                    BatchCompressionResultView(
                        flowState: flowState,
                        onDismiss: { dismiss() }
                    )
                case .error:
                    CompressionErrorView(
                        message: flowState.errorMessage,
                        onRetry: { flowState.step = .selectLevel },
                        onDismiss: { dismiss() }
                    )
                }
            }
            .navigationTitle("Compresser \(items.count) fichiers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if flowState.step != .compressing {
                        Button("Annuler") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(flowState.step == .compressing)
        .onAppear {
            flowState.items = items
        }
    }
}

// MARK: - Batch Compression Flow State

@MainActor
class BatchCompressionFlowState: ObservableObject {
    @Published var step: CompressionStep = .selectLevel
    @Published var selectedLevel: CompressionLevel = .medium
    @Published var overallProgress: Double = 0
    @Published var currentItemIndex: Int = 0
    @Published var currentItemProgress: Double = 0
    @Published var statusMessage: String = ""
    @Published var results: [BatchCompressionItemResult] = []
    @Published var errorMessage: String = ""

    var items: [MediaItem] = []
    private var compressionTask: Task<Void, Never>?

    var totalOriginalSize: Int64 {
        results.reduce(0) { $0 + $1.originalSize }
    }

    var totalCompressedSize: Int64 {
        results.filter { $0.success }.reduce(0) { $0 + $1.compressedSize }
    }

    var totalSavedSize: Int64 {
        results.filter { $0.savedBytes > 0 }.reduce(0) { $0 + $1.savedBytes }
    }

    var successCount: Int {
        results.filter { $0.success && $0.savedBytes > 0 }.count
    }

    var skippedCount: Int {
        results.filter { $0.success && $0.savedBytes <= 0 }.count
    }

    var failedCount: Int {
        results.filter { !$0.success }.count
    }

    func startBatchCompression() {
        step = .compressing
        overallProgress = 0
        currentItemIndex = 0
        results = []

        compressionTask = Task {
            for (index, item) in items.enumerated() {
                currentItemIndex = index
                statusMessage = "Compression \(index + 1)/\(items.count)..."
                currentItemProgress = 0

                let result = await compressItem(item)
                results.append(result)

                overallProgress = Double(index + 1) / Double(items.count)
            }

            step = .result
        }
    }

    private func compressItem(_ item: MediaItem) async -> BatchCompressionItemResult {
        if item.asset.mediaType == .video {
            return await compressVideo(item)
        } else {
            return await compressImage(item)
        }
    }

    private func compressImage(_ item: MediaItem) async -> BatchCompressionItemResult {
        currentItemProgress = 0.1

        // Get original image data
        guard let originalImageData = await loadFullImageData(for: item.asset) else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: item.fileSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        guard let originalImage = UIImage(data: originalImageData) else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: item.fileSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        let originalSize = Int64(originalImageData.count)
        currentItemProgress = 0.3

        // Resize if needed
        var imageToCompress = originalImage
        let maxDim = selectedLevel.maxImageDimension
        if originalImage.size.width > maxDim || originalImage.size.height > maxDim {
            imageToCompress = resizeImage(originalImage, maxDimension: maxDim)
        }

        currentItemProgress = 0.6

        // Compress
        guard let compressedData = imageToCompress.jpegData(compressionQuality: selectedLevel.imageQuality) else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: originalSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        currentItemProgress = 0.8

        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try compressedData.write(to: tempURL)
        } catch {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: originalSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        currentItemProgress = 1.0

        return BatchCompressionItemResult(
            item: item,
            success: true,
            originalSize: originalSize,
            compressedSize: Int64(compressedData.count),
            compressedURL: tempURL
        )
    }

    private func compressVideo(_ item: MediaItem) async -> BatchCompressionItemResult {
        currentItemProgress = 0.1

        guard let originalURL = await getVideoURL(for: item.asset) else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: item.fileSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        let originalSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: originalURL.path)
            originalSize = attrs[.size] as? Int64 ?? item.fileSize
        } catch {
            originalSize = item.fileSize
        }

        currentItemProgress = 0.2

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        let preset: String
        switch selectedLevel {
        case .low: preset = AVAssetExportPresetHighestQuality
        case .medium: preset = AVAssetExportPresetMediumQuality
        case .high: preset = AVAssetExportPresetLowQuality
        }

        let avAsset = AVAsset(url: originalURL)
        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset) else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: originalSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        // Monitor progress
        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.currentItemProgress = 0.2 + Double(exportSession.progress) * 0.7
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        guard exportSession.status == .completed else {
            return BatchCompressionItemResult(
                item: item,
                success: false,
                originalSize: originalSize,
                compressedSize: 0,
                compressedURL: nil
            )
        }

        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            compressedSize = attrs[.size] as? Int64 ?? 0
        } catch {
            compressedSize = 0
        }

        currentItemProgress = 1.0

        return BatchCompressionItemResult(
            item: item,
            success: true,
            originalSize: originalSize,
            compressedSize: compressedSize,
            compressedURL: outputURL
        )
    }

    // MARK: - Helpers

    private func loadFullImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func getVideoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        if ratio >= 1 { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? image
    }

    // MARK: - Save Methods

    func saveAllCompressed(replaceOriginals: Bool) async -> Bool {
        let successfulResults = results.filter { $0.success && $0.savedBytes > 0 && $0.compressedURL != nil }

        for result in successfulResults {
            do {
                if result.item.asset.mediaType == .video {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.compressedURL!)
                    }
                } else {
                    if let imageData = try? Data(contentsOf: result.compressedURL!),
                       let image = UIImage(data: imageData) {
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                    }
                }

                if replaceOriginals {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.deleteAssets([result.item.asset] as NSFastEnumeration)
                    }
                }
            } catch {
                print("Error saving: \(error)")
            }
        }

        // Cleanup temp files
        for result in results {
            if let url = result.compressedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        return true
    }

    func cleanupAllTempFiles() {
        for result in results {
            if let url = result.compressedURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - Batch Compression Item Result

struct BatchCompressionItemResult {
    let item: MediaItem
    let success: Bool
    let originalSize: Int64
    let compressedSize: Int64
    let compressedURL: URL?

    var savedBytes: Int64 {
        originalSize - compressedSize
    }

    var savedPercentage: Double {
        guard originalSize > 0 else { return 0 }
        return Double(savedBytes) / Double(originalSize) * 100
    }
}

// MARK: - Batch Select Level View

struct BatchCompressionSelectLevelView: View {
    let items: [MediaItem]
    @ObservedObject var flowState: BatchCompressionFlowState

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }

    private var photoCount: Int {
        items.filter { $0.asset.mediaType == .image }.count
    }

    private var videoCount: Int {
        items.filter { $0.asset.mediaType == .video }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary card
                VStack(spacing: 16) {
                    HStack(spacing: 30) {
                        if photoCount > 0 {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text("\(photoCount)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("Photos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if videoCount > 0 {
                            VStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.title2)
                                    .foregroundColor(.purple)
                                Text("\(videoCount)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("Vidéos")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Text("Taille totale")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                // Compression levels
                VStack(alignment: .leading, spacing: 12) {
                    Text("Niveau de compression")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(CompressionLevel.allCases, id: \.self) { level in
                        CompressionLevelCard(
                            level: level,
                            isSelected: flowState.selectedLevel == level,
                            onSelect: { flowState.selectedLevel = level }
                        )
                    }
                }

                // Compress button
                Button(action: {
                    flowState.startBatchCompression()
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Compresser \(items.count) fichiers")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal)

                Spacer(minLength: 30)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Batch Compression Progress View

struct BatchCompressionProgressView: View {
    @ObservedObject var flowState: BatchCompressionFlowState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Overall progress circle
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: flowState.overallProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: flowState.overallProgress)

                VStack(spacing: 4) {
                    Text("\(flowState.currentItemIndex + 1)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("sur \(flowState.items.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text(flowState.statusMessage)
                .font(.headline)

            // Current item progress
            VStack(spacing: 8) {
                ProgressView(value: flowState.currentItemProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                Text("\(Int(flowState.currentItemProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Batch Compression Result View

struct BatchCompressionResultView: View {
    @ObservedObject var flowState: BatchCompressionFlowState
    let onDismiss: () -> Void

    @State private var isSaving = false

    private var hasAnySavings: Bool {
        flowState.totalSavedSize > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: hasAnySavings ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(hasAnySavings ? .green : .orange)

                    Text(hasAnySavings ? "Compression terminée !" : "Fichiers déjà optimisés")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top)

                // Stats summary
                HStack(spacing: 16) {
                    StatBox(
                        value: "\(flowState.successCount)",
                        label: "Compressés",
                        color: .green
                    )

                    if flowState.skippedCount > 0 {
                        StatBox(
                            value: "\(flowState.skippedCount)",
                            label: "Ignorés",
                            color: .orange
                        )
                    }

                    if flowState.failedCount > 0 {
                        StatBox(
                            value: "\(flowState.failedCount)",
                            label: "Échoués",
                            color: .red
                        )
                    }
                }
                .padding(.horizontal)

                // Size comparison
                if hasAnySavings {
                    HStack(spacing: 20) {
                        VStack(spacing: 4) {
                            Text(ByteCountFormatter.string(fromByteCount: flowState.totalOriginalSize, countStyle: .file))
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("Original")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Image(systemName: "arrow.right")
                            .font(.title2)
                            .foregroundColor(.green)

                        VStack(spacing: 4) {
                            Text(ByteCountFormatter.string(fromByteCount: flowState.totalCompressedSize, countStyle: .file))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                            Text("Compressé")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal)

                    // Total savings
                    VStack(spacing: 8) {
                        Text("Économie totale")
                            .font(.headline)

                        Text(ByteCountFormatter.string(fromByteCount: flowState.totalSavedSize, countStyle: .file))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    if hasAnySavings {
                        Button(action: { saveAndReplace() }) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("Remplacer les originaux")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(14)
                        }
                        .disabled(isSaving)

                        Button(action: { saveKeepBoth() }) {
                            HStack {
                                Image(systemName: "plus.square.on.square")
                                Text("Garder les deux")
                            }
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(14)
                        }
                        .disabled(isSaving)
                    }

                    Button(action: { cancelAndDismiss() }) {
                        Text(hasAnySavings ? "Annuler" : "Fermer")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal)

                Spacer(minLength: 30)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private func saveAndReplace() {
        isSaving = true
        Task {
            _ = await flowState.saveAllCompressed(replaceOriginals: true)
            isSaving = false
            onDismiss()
        }
    }

    private func saveKeepBoth() {
        isSaving = true
        Task {
            _ = await flowState.saveAllCompressed(replaceOriginals: false)
            isSaving = false
            onDismiss()
        }
    }

    private func cancelAndDismiss() {
        flowState.cleanupAllTempFiles()
        onDismiss()
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Single Item Compression Views (kept for single item flow)

struct CompressionFlowView: View {
    let item: MediaItem
    @ObservedObject var viewModel: CleanerViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var flowState = CompressionFlowState()

    var body: some View {
        NavigationStack {
            Group {
                switch flowState.step {
                case .selectLevel:
                    CompressionSelectLevelView(
                        item: item,
                        flowState: flowState
                    )
                case .compressing:
                    CompressionProgressView(flowState: flowState)
                case .result:
                    if let result = flowState.result {
                        CompressionResultView(
                            result: result,
                            flowState: flowState,
                            onDismiss: { dismiss() }
                        )
                    }
                case .error:
                    CompressionErrorView(
                        message: flowState.errorMessage,
                        onRetry: { flowState.step = .selectLevel },
                        onDismiss: { dismiss() }
                    )
                }
            }
            .navigationTitle(item.asset.mediaType == .video ? "Compresser la vidéo" : "Compresser l'image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if flowState.step != .compressing {
                        Button("Annuler") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(flowState.step == .compressing)
    }
}

enum CompressionStep {
    case selectLevel
    case compressing
    case result
    case error
}

@MainActor
class CompressionFlowState: ObservableObject {
    @Published var step: CompressionStep = .selectLevel
    @Published var selectedLevel: CompressionLevel = .medium
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""
    @Published var result: CompressionResult?
    @Published var errorMessage: String = ""

    private var compressionTask: Task<Void, Never>?

    func startCompression(for asset: PHAsset) {
        step = .compressing
        progress = 0
        statusMessage = "Préparation..."

        compressionTask = Task {
            let result = await compressAsset(asset)
            if let result = result {
                self.result = result
                self.step = .result
            } else {
                self.errorMessage = "La compression a échoué. Veuillez réessayer."
                self.step = .error
            }
        }
    }

    private func compressAsset(_ asset: PHAsset) async -> CompressionResult? {
        if asset.mediaType == .video {
            return await compressVideo(asset: asset)
        } else {
            return await compressImage(asset: asset)
        }
    }

    private func compressImage(asset: PHAsset) async -> CompressionResult? {
        statusMessage = "Chargement de l'image..."
        progress = 0.1

        guard let originalImageData = await loadFullImageData(for: asset) else { return nil }
        guard let originalImage = UIImage(data: originalImageData) else { return nil }

        let originalSize = Int64(originalImageData.count)
        progress = 0.3
        statusMessage = "Compression..."

        var imageToCompress = originalImage
        let maxDim = selectedLevel.maxImageDimension
        if originalImage.size.width > maxDim || originalImage.size.height > maxDim {
            imageToCompress = resizeImage(originalImage, maxDimension: maxDim)
        }

        progress = 0.6

        guard let compressedData = imageToCompress.jpegData(compressionQuality: selectedLevel.imageQuality) else { return nil }

        progress = 0.8
        statusMessage = "Finalisation..."

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        do {
            try compressedData.write(to: tempURL)
        } catch {
            return nil
        }

        progress = 1.0

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: Int64(compressedData.count),
            originalURL: nil,
            compressedURL: tempURL,
            compressedImage: UIImage(data: compressedData),
            isVideo: false,
            asset: asset
        )
    }

    private func compressVideo(asset: PHAsset) async -> CompressionResult? {
        statusMessage = "Chargement de la vidéo..."
        progress = 0.1

        guard let originalURL = await getVideoURL(for: asset) else { return nil }

        let originalSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: originalURL.path)
            originalSize = attrs[.size] as? Int64 ?? 0
        } catch {
            return nil
        }

        guard originalSize > 0 else { return nil }

        progress = 0.2
        statusMessage = "Compression de la vidéo..."

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        let preset: String
        switch selectedLevel {
        case .low: preset = AVAssetExportPresetHighestQuality
        case .medium: preset = AVAssetExportPresetMediumQuality
        case .high: preset = AVAssetExportPresetLowQuality
        }

        let avAsset = AVAsset(url: originalURL)
        guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: preset) else { return nil }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        let progressTask = Task {
            while !Task.isCancelled && exportSession.status == .exporting {
                await MainActor.run {
                    self.progress = 0.2 + Double(exportSession.progress) * 0.7
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        await exportSession.export()
        progressTask.cancel()

        guard exportSession.status == .completed else { return nil }

        let compressedSize: Int64
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            compressedSize = attrs[.size] as? Int64 ?? 0
        } catch {
            compressedSize = 0
        }

        progress = 1.0

        return CompressionResult(
            originalSize: originalSize,
            compressedSize: compressedSize,
            originalURL: originalURL,
            compressedURL: outputURL,
            compressedImage: nil,
            isVideo: true,
            asset: asset
        )
    }

    private func loadFullImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func getVideoURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        if ratio >= 1 { return image }

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? image
    }

    func saveCompressedMedia(replaceOriginal: Bool) async -> Bool {
        guard let result = result else { return false }

        do {
            if result.isVideo {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: result.compressedURL)
                }
            } else {
                if let imageData = try? Data(contentsOf: result.compressedURL),
                   let image = UIImage(data: imageData) {
                    try await PHPhotoLibrary.shared().performChanges {
                        PHAssetChangeRequest.creationRequestForAsset(from: image)
                    }
                }
            }

            if replaceOriginal {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets([result.asset] as NSFastEnumeration)
                }
            }

            try? FileManager.default.removeItem(at: result.compressedURL)
            return true
        } catch {
            return false
        }
    }

    func cleanupTempFile() {
        if let result = result {
            try? FileManager.default.removeItem(at: result.compressedURL)
        }
    }
}

// Single item views
struct CompressionSelectLevelView: View {
    let item: MediaItem
    @ObservedObject var flowState: CompressionFlowState
    @State private var thumbnail: UIImage?
    @State private var actualFileSize: Int64 = 0

    private var isVideo: Bool { item.asset.mediaType == .video }
    private var displaySize: Int64 { actualFileSize > 0 ? actualFileSize : item.fileSize }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 280)
                            .cornerRadius(16)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemGray5))
                            .frame(height: 200)
                            .overlay(ProgressView().scaleEffect(1.2))
                    }

                    if isVideo && thumbnail != nil {
                        VStack {
                            Spacer()
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: "video.fill")
                                    Text(formatDuration(item.asset.duration))
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(8)
                                .padding(12)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal)

                HStack {
                    Label(ByteCountFormatter.string(fromByteCount: displaySize, countStyle: .file), systemImage: "doc.fill")
                    Spacer()
                    if let date = item.asset.creationDate {
                        Text(date, style: .date)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Niveau de compression")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(CompressionLevel.allCases, id: \.self) { level in
                        CompressionLevelCard(
                            level: level,
                            isSelected: flowState.selectedLevel == level,
                            onSelect: { flowState.selectedLevel = level }
                        )
                    }
                }

                Button(action: { flowState.startCompression(for: item.asset) }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Compresser")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(14)
                }
                .padding(.horizontal)

                Spacer(minLength: 30)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .task {
            thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .swipe)
            actualFileSize = await getActualFileSize(for: item.asset)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }

    private func getActualFileSize(for asset: PHAsset) async -> Int64 {
        if asset.mediaType == .video {
            return await withCheckedContinuation { continuation in
                let options = PHVideoRequestOptions()
                options.isNetworkAccessAllowed = true
                options.deliveryMode = .highQualityFormat
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    if let urlAsset = avAsset as? AVURLAsset,
                       let attrs = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path),
                       let size = attrs[.size] as? Int64 {
                        continuation.resume(returning: size)
                    } else {
                        continuation.resume(returning: 0)
                    }
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                    continuation.resume(returning: Int64(data?.count ?? 0))
                }
            }
        }
    }
}

struct CompressionProgressView: View {
    @ObservedObject var flowState: CompressionFlowState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView().scaleEffect(1.5)
            Text(flowState.statusMessage).font(.headline)
            ProgressView(value: flowState.progress).progressViewStyle(.linear).frame(width: 200)
            Text("\(Int(flowState.progress * 100))%").font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct CompressionResultView: View {
    let result: CompressionResult
    @ObservedObject var flowState: CompressionFlowState
    let onDismiss: () -> Void
    @State private var isSaving = false

    private var hasActualSavings: Bool { result.savedBytes > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if hasActualSavings {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundColor(.green)
                        Text("Compression réussie !").font(.title2).fontWeight(.bold)
                    }.padding(.top)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 60)).foregroundColor(.orange)
                        Text("Fichier déjà optimisé").font(.title2).fontWeight(.bold)
                        Text("La compression n'a pas réduit la taille du fichier.")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                    }.padding(.top)
                }

                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(result.formattedOriginalSize).font(.title3).fontWeight(.bold)
                        Text("Original").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity)
                    Image(systemName: "arrow.right").font(.title2).foregroundColor(hasActualSavings ? .green : .orange)
                    VStack(spacing: 4) {
                        Text(result.formattedCompressedSize).font(.title3).fontWeight(.bold).foregroundColor(hasActualSavings ? .green : .orange)
                        Text("Compressé").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .padding(.horizontal)

                if hasActualSavings {
                    VStack(spacing: 8) {
                        Text("Économie").font(.headline)
                        Text(result.formattedSavedSize).font(.system(size: 36, weight: .bold)).foregroundColor(.green)
                        Text("\(Int(result.savedPercentage))% de réduction").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }

                if !result.isVideo, let image = result.compressedImage {
                    VStack(spacing: 12) {
                        Text("Aperçu").font(.headline)
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 250).cornerRadius(12)
                    }.padding(.horizontal)
                }

                VStack(spacing: 12) {
                    if hasActualSavings {
                        Button(action: { Task { isSaving = true; _ = await flowState.saveCompressedMedia(replaceOriginal: true); isSaving = false; onDismiss() }}) {
                            HStack {
                                if isSaving { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                                else { Image(systemName: "arrow.triangle.2.circlepath") }
                                Text("Remplacer l'original")
                            }.font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.green).cornerRadius(14)
                        }.disabled(isSaving)

                        Button(action: { Task { isSaving = true; _ = await flowState.saveCompressedMedia(replaceOriginal: false); isSaving = false; onDismiss() }}) {
                            HStack { Image(systemName: "plus.square.on.square"); Text("Garder les deux") }
                                .font(.headline).foregroundColor(.blue).frame(maxWidth: .infinity).padding().background(Color.blue.opacity(0.15)).cornerRadius(14)
                        }.disabled(isSaving)
                    }

                    Button(action: { flowState.cleanupTempFile(); onDismiss() }) {
                        Text(hasActualSavings ? "Annuler" : "Fermer").font(.headline).foregroundColor(.secondary).frame(maxWidth: .infinity).padding()
                    }.disabled(isSaving)
                }.padding(.horizontal)

                Spacer(minLength: 30)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct CompressionErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 60)).foregroundColor(.orange)
            Text("Erreur de compression").font(.title2).fontWeight(.bold)
            Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    HStack { Image(systemName: "arrow.clockwise"); Text("Réessayer") }
                        .font(.headline).foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.blue).cornerRadius(14)
                }
                Button(action: onDismiss) {
                    Text("Annuler").font(.headline).foregroundColor(.secondary).frame(maxWidth: .infinity).padding()
                }
            }.padding(.horizontal)
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }
}

struct CompressionLevelCard: View {
    let level: CompressionLevel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                Image(systemName: level.icon)
                    .font(.title2)
                    .foregroundColor(Color(level.color))
                    .frame(width: 44, height: 44)
                    .background(Color(level.color).opacity(0.15))
                    .cornerRadius(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.rawValue).font(.headline).foregroundColor(.primary)
                    Text(level.description).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

#Preview {
    CompressTabView(viewModel: CleanerViewModel())
}
