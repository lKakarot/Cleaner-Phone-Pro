//
//  PhotoLibraryView.swift
//  Cleaner Phone Pro
//
//  Vue galerie complète style iOS Photos avec groupement par date
//

import SwiftUI
import Photos

struct PhotoLibraryView: View {
    @EnvironmentObject var viewModel: CleanerViewModel
    @Binding var isExpanded: Bool
    @State private var selectedPhoto: MediaItem? = nil
    @State private var groupedPhotos: [PhotoSection] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Chargement...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 20, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedPhotos) { section in
                                Section {
                                    photoGrid(for: section.photos)
                                } header: {
                                    sectionHeader(for: section)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("Bibliothèque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isExpanded = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                            Text("Retour")
                        }
                    }
                }
            }
            .sheet(item: $selectedPhoto) { photo in
                PhotoDetailView(photo: photo)
            }
            .task {
                await loadPhotos()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func loadPhotos() async {
        // Faire le groupement en background
        let photos = viewModel.allPhotos
        let sections = await Task.detached(priority: .userInitiated) {
            PhotoLibraryView.groupPhotosByMonth(photos)
        }.value

        groupedPhotos = sections
        isLoading = false
    }

    // MARK: - Section Header
    private func sectionHeader(for section: PhotoSection) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.title3)
                    .fontWeight(.bold)

                Text("\(section.photos.count) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Photo Grid
    private func photoGrid(for photos: [MediaItem]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(photos) { photo in
                PhotoGridCell(
                    asset: photo.asset,
                    mediaType: photo.mediaType
                )
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPhoto = photo
                }
            }
        }
    }

    // MARK: - Group Photos by Month
    private static func groupPhotosByMonth(_ photos: [MediaItem]) -> [PhotoSection] {
        let calendar = Calendar.current
        let now = Date()

        var sections: [String: [MediaItem]] = [:]
        var sectionDates: [String: Date] = [:]

        for photo in photos {
            guard let date = photo.creationDate else { continue }

            let key: String
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)

            if components.year == nowComponents.year &&
               components.month == nowComponents.month &&
               components.day == nowComponents.day {
                key = "Aujourd'hui"
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                      calendar.isDate(date, inSameDayAs: yesterday) {
                key = "Hier"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                formatter.locale = Locale(identifier: "fr_FR")
                key = formatter.string(from: date).capitalized
            }

            if sections[key] == nil {
                sections[key] = []
                sectionDates[key] = date
            }
            sections[key]?.append(photo)
        }

        // Trier les sections par date (plus récent en premier)
        let sortedKeys = sections.keys.sorted { key1, key2 in
            if key1 == "Aujourd'hui" { return true }
            if key2 == "Aujourd'hui" { return false }
            if key1 == "Hier" { return true }
            if key2 == "Hier" { return false }

            guard let date1 = sectionDates[key1],
                  let date2 = sectionDates[key2] else { return false }
            return date1 > date2
        }

        return sortedKeys.compactMap { key in
            guard let photos = sections[key], let date = sectionDates[key] else { return nil }
            return PhotoSection(title: key, date: date, photos: photos)
        }
    }
}

// MARK: - Photo Section
struct PhotoSection: Identifiable {
    let id = UUID()
    let title: String
    let date: Date
    let photos: [MediaItem]
}

// MARK: - Photo Grid Cell
struct PhotoGridCell: View {
    let asset: PHAsset
    let mediaType: MediaItem.MediaType
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }

            // Badge pour les vidéos
            if mediaType == .video {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))

                    Text(formatDuration(asset.duration))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(4)
            }

            // Badge pour les Live Photos
            if mediaType == .livePhoto {
                Image(systemName: "livephoto")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .task(id: asset.localIdentifier) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.resizeMode = .fast

            let targetSize = CGSize(width: 100, height: 100)

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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Photo Detail View
struct PhotoDetailView: View {
    let photo: MediaItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            image = await loadFullImage()
        }
    }

    private func loadFullImage() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: photo.asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Preview
#Preview {
    PhotoLibraryView(isExpanded: .constant(true))
        .environmentObject(CleanerViewModel())
}
