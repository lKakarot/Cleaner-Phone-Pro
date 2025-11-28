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
    @StateObject private var compressionService = CompressionService.shared
    @State private var selectedItem: MediaItem?
    @State private var showCompressionOptions = false
    @State private var selectedTab = 0
    @State private var loadedThumbnails: [String: UIImage] = [:]

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
                } else {
                    // Header info
                    VStack(spacing: 8) {
                        Text("Sélectionnez un média à compresser")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

                    // Segment picker
                    Picker("Type", selection: $selectedTab) {
                        Text("Photos (\(allPhotos.count))").tag(0)
                        Text("Vidéos (\(allVideos.count))").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                    // Grid
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(selectedTab == 0 ? allPhotos : allVideos) { item in
                                CompressMediaCell(
                                    item: item,
                                    thumbnail: item.thumbnail ?? loadedThumbnails[item.id],
                                    onSelect: {
                                        selectedItem = item
                                        showCompressionOptions = true
                                    },
                                    onAppear: { loadThumbnailIfNeeded(for: item) }
                                )
                            }
                        }
                        .padding(2)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showCompressionOptions) {
                if let item = selectedItem {
                    CompressionOptionsView(
                        item: item,
                        compressionService: compressionService
                    )
                }
            }
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
}

// MARK: - Compress Media Cell

struct CompressMediaCell: View {
    let item: MediaItem
    let thumbnail: UIImage?
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

                // Size badge (top right)
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

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text("\(count)")
                .font(.title)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15))
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Media Picker View

struct MediaPickerView: View {
    @ObservedObject var viewModel: CleanerViewModel
    let onSelect: (MediaItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loadedThumbnails: [String: UIImage] = [:]
    @State private var selectedTab = 0

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

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segment picker
                Picker("Type", selection: $selectedTab) {
                    Text("Photos (\(allPhotos.count))").tag(0)
                    Text("Vidéos (\(allVideos.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // Grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(selectedTab == 0 ? allPhotos : allVideos) { item in
                            MediaPickerCell(
                                item: item,
                                thumbnail: item.thumbnail ?? loadedThumbnails[item.id],
                                onSelect: { onSelect(item) },
                                onAppear: { loadThumbnailIfNeeded(for: item) }
                            )
                        }
                    }
                    .padding(2)
                }
            }
            .navigationTitle("Sélectionner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
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
}

// MARK: - Media Picker Cell

struct MediaPickerCell: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let onSelect: () -> Void
    let onAppear: () -> Void

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .bottomTrailing) {
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

                // Video badge
                if isVideo {
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
                }

                // Size badge
                VStack {
                    HStack {
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(4)
                    }
                    Spacer()
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

// MARK: - Compression Options View

struct CompressionOptionsView: View {
    let item: MediaItem
    @ObservedObject var compressionService: CompressionService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLevel: CompressionLevel = .medium
    @State private var thumbnail: UIImage?
    @State private var isCompressing = false
    @State private var compressionResult: CompressionResult?
    @State private var showResult = false

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if isCompressing {
                    // Compression in progress
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text(compressionService.statusMessage)
                            .font(.headline)

                        ProgressView(value: compressionService.progress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)

                        Text("\(Int(compressionService.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if showResult, let result = compressionResult {
                    // Show result
                    CompressionResultView(
                        result: result,
                        compressionService: compressionService,
                        onDismiss: { dismiss() }
                    )
                } else {
                    // Selection view
                    ScrollView {
                        VStack(spacing: 24) {
                            // Preview
                            if let thumbnail = thumbnail {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 300)
                                        .cornerRadius(16)

                                    // Video badge
                                    if isVideo {
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
                                    }
                                }
                            } else {
                                Rectangle()
                                    .fill(Color(.systemGray5))
                                    .frame(height: 200)
                                    .cornerRadius(16)
                                    .overlay(ProgressView())
                            }

                            // File info
                            HStack {
                                Label(
                                    ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file),
                                    systemImage: "doc.fill"
                                )

                                Spacer()

                                if let date = item.asset.creationDate {
                                    Text(date, style: .date)
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                            // Compression levels
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Niveau de compression")
                                    .font(.headline)
                                    .padding(.horizontal)

                                ForEach(CompressionLevel.allCases, id: \.self) { level in
                                    CompressionLevelCard(
                                        level: level,
                                        isSelected: selectedLevel == level,
                                        onSelect: { selectedLevel = level }
                                    )
                                }
                            }

                            // Compress button
                            Button(action: { startCompression() }) {
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
                }
            }
            .navigationTitle(isVideo ? "Compresser la vidéo" : "Compresser l'image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .task {
            // Load thumbnail
            thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .swipe)
        }
    }

    private func startCompression() {
        isCompressing = true
        Task {
            if let result = await compressionService.compress(asset: item.asset, level: selectedLevel) {
                compressionResult = result
                showResult = true
            }
            isCompressing = false
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Compression Level Card

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
                    Text(level.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(level.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

// MARK: - Compression Result View

struct CompressionResultView: View {
    let result: CompressionResult
    @ObservedObject var compressionService: CompressionService
    let onDismiss: () -> Void

    @State private var compressedThumbnail: UIImage?
    @State private var showOriginal = false
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Success header
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Compression réussie !")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                .padding(.top)

                // Stats
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(result.formattedOriginalSize)
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
                        Text(result.formattedCompressedSize)
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

                // Savings
                VStack(spacing: 8) {
                    Text("Économie")
                        .font(.headline)

                    Text(result.formattedSavedSize)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.green)

                    Text("\(Int(result.savedPercentage))% de réduction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)

                // Preview comparison
                if !result.isVideo {
                    VStack(spacing: 12) {
                        Text("Aperçu")
                            .font(.headline)

                        ZStack {
                            if showOriginal {
                                // Would show original - for now show compressed
                                if let image = result.compressedImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxHeight: 250)
                                        .cornerRadius(12)
                                }
                            } else if let image = result.compressedImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 250)
                                    .cornerRadius(12)
                            }
                        }

                        // Toggle
                        Picker("Version", selection: $showOriginal) {
                            Text("Compressé").tag(false)
                            Text("Original").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                    }
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Keep only compressed
                    Button(action: { saveAndReplace() }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Remplacer par le compressé")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(14)
                    }
                    .disabled(isSaving)

                    // Keep both
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

                    // Cancel
                    Button(action: { cancelAndDismiss() }) {
                        Text("Annuler")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .disabled(isSaving)
                }
                .padding(.horizontal)

                if isSaving {
                    ProgressView("Sauvegarde...")
                        .padding()
                }

                Spacer(minLength: 30)
            }
        }
    }

    private func saveAndReplace() {
        isSaving = true
        Task {
            let success = await compressionService.saveCompressedMedia(result, replaceOriginal: true)
            isSaving = false
            if success {
                onDismiss()
            }
        }
    }

    private func saveKeepBoth() {
        isSaving = true
        Task {
            let success = await compressionService.saveCompressedMedia(result, replaceOriginal: false)
            isSaving = false
            if success {
                onDismiss()
            }
        }
    }

    private func cancelAndDismiss() {
        // Clean up temp file
        try? FileManager.default.removeItem(at: result.compressedURL)
        onDismiss()
    }
}

#Preview {
    CompressTabView(viewModel: CleanerViewModel())
}
