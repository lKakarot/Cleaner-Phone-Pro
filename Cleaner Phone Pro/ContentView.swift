//
//  ContentView.swift
//  Cleaner Phone Pro
//
//  Created by Hasnae HANY on 26/11/2025.
//

import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var viewModel = CleanerViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Cleaner (existing)
            CleanerTabView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "trash.circle.fill")
                    Text("Nettoyer")
                }
                .tag(0)

            // Tab 2: Timeline (par mois/an)
            TimelineTabView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Timeline")
                }
                .tag(1)

            // Tab 3: Swipe (triage rapide)
            SwipeTabView(viewModel: viewModel)
                .tabItem {
                    Image(systemName: "hand.draw.fill")
                    Text("Trier")
                }
                .tag(2)
        }
        .tint(.blue)
        .task {
            await viewModel.requestAccess()
        }
    }
}

// MARK: - Cleaner Tab (existing functionality)

struct CleanerTabView: View {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    PermissionDeniedView()
                } else if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Progress bar for background analysis
                            if viewModel.isAnalyzing {
                                AnalysisProgressBar(
                                    progress: viewModel.analysisProgress,
                                    message: viewModel.analysisMessage
                                )
                            }

                            // Warning if limited access
                            if viewModel.authorizationStatus == .limited {
                                LimitedAccessBanner()
                            }

                            // Stats header
                            if viewModel.totalPhotoCount > 0 || viewModel.totalVideoCount > 0 {
                                HStack {
                                    Label("\(viewModel.totalPhotoCount) photos", systemImage: "photo")
                                    Spacer()
                                    Label("\(viewModel.totalVideoCount) vidéos", systemImage: "video")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            }

                            // Diagnostic panel (expandable)
                            if let diag = viewModel.diagnostics, viewModel.showDiagnostics {
                                DiagnosticsView(diagnostics: diag)
                            }

                            ForEach(viewModel.categories) { categoryData in
                                NavigationLink(destination: CategoryDetailView(
                                    viewModel: viewModel,
                                    categoryData: categoryData
                                )) {
                                    CategoryCardView(categoryData: categoryData)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.loadAllCategories()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Analysis Progress Bar

struct AnalysisProgressBar: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemGray5))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    let diagnostics: LibraryDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .foregroundColor(.blue)
                Text("Diagnostic de la bibliothèque")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                DiagRow(title: "Total assets", value: "\(diagnostics.totalAssets)", icon: "square.stack.3d.up")
                DiagRow(title: "Images", value: "\(diagnostics.totalImages)", icon: "photo")
                DiagRow(title: "Vidéos", value: "\(diagnostics.totalVideos)", icon: "video")
                if diagnostics.totalAudio > 0 {
                    DiagRow(title: "Audio (non inclus)", value: "\(diagnostics.totalAudio)", icon: "waveform", color: .gray)
                }
                DiagRow(title: "Album 'Toutes les photos'", value: "\(diagnostics.allPhotosAlbumCount)", icon: "photo.on.rectangle")

                Divider()

                DiagRow(title: "Locaux sur iPhone", value: "~\(diagnostics.localCount)", icon: "iphone", color: .green)
                DiagRow(title: "iCloud uniquement", value: "~\(diagnostics.iCloudOnlyCount)", icon: "icloud", color: .blue)

                if diagnostics.hiddenCount > 0 || diagnostics.burstExtraCount > 0 {
                    Divider()
                    Text("Non inclus par défaut:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if diagnostics.hiddenCount > 0 {
                    DiagRow(title: "Photos masquées", value: "\(diagnostics.hiddenCount)", icon: "eye.slash", color: .orange)
                }

                if diagnostics.burstExtraCount > 0 {
                    DiagRow(title: "Burst photos supplémentaires", value: "\(diagnostics.burstExtraCount)", icon: "square.stack.3d.down.right", color: .purple)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct DiagRow: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

struct LimitedAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Accès limité")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Seules certaines photos sont accessibles. Modifiez dans Réglages pour accéder à toutes vos photos.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .fontWeight(.semibold)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Accès refusé")
                .font(.title2)
                .fontWeight(.bold)

            Text("Veuillez autoriser l'accès aux photos dans les Réglages de votre appareil.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Ouvrir les Réglages")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct LoadingOverlay: View {
    var message: String = "Analyse en cours..."
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Fond flouté
            Color(.systemBackground).opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icône animée
                ZStack {
                    // Cercle extérieur qui pulse
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
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
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))

                    // Icône centrale
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text(message)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Timeline Tab View

struct TimelineTabView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @State private var groupBy: TimelineGrouping = .month
    @State private var timelineSections: [TimelinePeriod] = []
    @State private var isLoading = true
    @State private var selectedPeriod: TimelinePeriod?

    enum TimelineGrouping: String, CaseIterable {
        case month = "Mois"
        case year = "Année"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with grouping selector
                VStack(spacing: 12) {
                    Picker("Grouper par", selection: $groupBy) {
                        ForEach(TimelineGrouping.allCases, id: \.self) { grouping in
                            Text(grouping.rawValue).tag(grouping)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Chargement...")
                    Spacer()
                } else if timelineSections.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("Aucun média")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(timelineSections) { period in
                                TimelinePeriodCard(
                                    period: period,
                                    groupBy: groupBy,
                                    onTap: { selectedPeriod = period }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: groupBy) { _ in loadTimeline() }
            .onAppear { loadTimeline() }
            .fullScreenCover(item: $selectedPeriod) { period in
                TimelinePeriodDetailView(
                    period: period,
                    groupBy: groupBy,
                    viewModel: viewModel
                )
            }
        }
    }

    private func loadTimeline() {
        isLoading = true
        Task {
            // Get all items from all categories
            var allItems: [MediaItem] = []

            for categoryData in viewModel.categories {
                if categoryData.category.hasSimilarGroups && !categoryData.similarGroups.isEmpty {
                    for group in categoryData.similarGroups {
                        allItems.append(contentsOf: group.items)
                    }
                } else {
                    allItems.append(contentsOf: categoryData.items)
                }
            }

            // Remove duplicates by ID
            var seen = Set<String>()
            allItems = allItems.filter { item in
                if seen.contains(item.id) { return false }
                seen.insert(item.id)
                return true
            }

            // Group by date
            let calendar = Calendar.current
            let grouped = Dictionary(grouping: allItems) { item -> DateComponents in
                let date = item.asset.creationDate ?? Date()
                if groupBy == .month {
                    return calendar.dateComponents([.year, .month], from: date)
                } else {
                    return calendar.dateComponents([.year], from: date)
                }
            }

            // Convert to TimelinePeriod
            var periods: [TimelinePeriod] = []
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "fr_FR")

            for (components, items) in grouped {
                var date = calendar.date(from: components) ?? Date()
                let title: String
                let subtitle: String

                if groupBy == .month {
                    dateFormatter.dateFormat = "MMMM"
                    title = dateFormatter.string(from: date).capitalized
                    dateFormatter.dateFormat = "yyyy"
                    subtitle = dateFormatter.string(from: date)
                } else {
                    dateFormatter.dateFormat = "yyyy"
                    title = dateFormatter.string(from: date)
                    subtitle = ""
                }

                let sortedItems = items.sorted { ($0.asset.creationDate ?? Date()) > ($1.asset.creationDate ?? Date()) }
                let photoCount = sortedItems.filter { $0.asset.mediaType == .image }.count
                let videoCount = sortedItems.filter { $0.asset.mediaType == .video }.count

                periods.append(TimelinePeriod(
                    title: title,
                    subtitle: subtitle,
                    date: date,
                    items: sortedItems,
                    photoCount: photoCount,
                    videoCount: videoCount
                ))
            }

            periods.sort { $0.date > $1.date }

            await MainActor.run {
                timelineSections = periods
                isLoading = false
            }
        }
    }
}

// MARK: - Timeline Period Model

struct TimelinePeriod: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let date: Date
    let items: [MediaItem]
    let photoCount: Int
    let videoCount: Int

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.fileSize }
    }
}

// MARK: - Timeline Period Card

struct TimelinePeriodCard: View {
    let period: TimelinePeriod
    let groupBy: TimelineTabView.TimelineGrouping
    let onTap: () -> Void

    @State private var previewImages: [UIImage] = []

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Preview images grid
                HStack(spacing: 2) {
                    ForEach(0..<min(4, period.items.count), id: \.self) { index in
                        if index < previewImages.count {
                            Image(uiImage: previewImages[index])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fit)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(Color(.systemGray5))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }

                    // Fill remaining slots if less than 4 items
                    if period.items.count < 4 {
                        ForEach(period.items.count..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(Color(.systemGray6))
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Info bar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(period.title)
                                .font(.headline)
                                .fontWeight(.bold)
                            if !period.subtitle.isEmpty {
                                Text(period.subtitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 12) {
                            if period.photoCount > 0 {
                                Label("\(period.photoCount)", systemImage: "photo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if period.videoCount > 0 {
                                Label("\(period.videoCount)", systemImage: "video")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: period.totalSize, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .onAppear {
            loadPreviews()
        }
    }

    private func loadPreviews() {
        let itemsToLoad = Array(period.items.prefix(4))
        Task {
            var images: [UIImage] = []
            for item in itemsToLoad {
                if let thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .preview) {
                    images.append(thumbnail)
                }
            }
            await MainActor.run {
                previewImages = images
            }
        }
    }
}

// MARK: - Timeline Period Detail View

struct TimelinePeriodDetailView: View {
    let period: TimelinePeriod
    let groupBy: TimelineTabView.TimelineGrouping
    @ObservedObject var viewModel: CleanerViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoIndex: Int?
    @State private var showSwipeMode = false
    @State private var loadedThumbnails: [String: UIImage] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(Array(period.items.enumerated()), id: \.element.id) { index, item in
                        TimelineGridCell(
                            item: item,
                            thumbnail: loadedThumbnails[item.id],
                            onTap: { selectedPhotoIndex = index },
                            onAppear: { loadThumbnailIfNeeded(for: item) }
                        )
                    }
                }
                .padding(2)
            }
            .navigationTitle("\(period.title) \(period.subtitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSwipeMode = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.draw")
                            Text("Trier")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                    }
                }
            }
            .fullScreenCover(item: $selectedPhotoIndex) { index in
                PhotoViewerView(
                    items: period.items,
                    initialIndex: index,
                    onDismiss: { selectedPhotoIndex = nil }
                )
            }
            .fullScreenCover(isPresented: $showSwipeMode) {
                TimelineSwipeModeView(
                    period: period,
                    viewModel: viewModel,
                    onDismiss: { showSwipeMode = false }
                )
            }
        }
    }

    private func loadThumbnailIfNeeded(for item: MediaItem) {
        guard loadedThumbnails[item.id] == nil else { return }
        Task {
            if let thumbnail = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail) {
                await MainActor.run {
                    loadedThumbnails[item.id] = thumbnail
                }
            }
        }
    }
}

// MARK: - Timeline Grid Cell

struct TimelineGridCell: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let onTap: () -> Void
    let onAppear: () -> Void

    private var isVideo: Bool { item.asset.mediaType == .video }

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack {
                    if let thumbnail = thumbnail ?? item.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.width)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .overlay(ProgressView().scaleEffect(0.7))
                    }

                    // Video indicator
                    if isVideo {
                        VStack {
                            Spacer()
                            HStack {
                                HStack(spacing: 3) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8))
                                    Text(formatDuration(item.asset.duration))
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .padding(4)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
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

// MARK: - Photo Viewer (Full Screen with Swipe)

struct PhotoViewerView: View {
    let items: [MediaItem]
    let initialIndex: Int
    let onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var dragOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0

    init(items: [MediaItem], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.items = items
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo pager
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PhotoViewerPage(
                        item: item,
                        image: loadedImages[item.id],
                        onLoadRequest: { loadImage(for: item) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Header
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)

                    Spacer()

                    // Spacer for symmetry
                    Color.clear
                        .frame(width: 44, height: 44)
                }
                .padding()

                Spacer()

                // Footer info
                if currentIndex < items.count {
                    let item = items[currentIndex]
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let date = item.asset.creationDate {
                                Text(date, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(date, style: .time)
                                    .font(.caption)
                            }
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                            .font(.caption)
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
        }
        .onChange(of: currentIndex) { _ in
            preloadAdjacentImages()
        }
        .onAppear {
            loadImage(for: items[currentIndex])
            preloadAdjacentImages()
        }
    }

    private func loadImage(for item: MediaItem) {
        guard loadedImages[item.id] == nil else { return }
        Task {
            if let image = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                await MainActor.run {
                    loadedImages[item.id] = image
                }
            }
        }
    }

    private func preloadAdjacentImages() {
        let indicesToLoad = [currentIndex - 1, currentIndex, currentIndex + 1]
            .filter { $0 >= 0 && $0 < items.count }

        for index in indicesToLoad {
            loadImage(for: items[index])
        }

        // Cleanup distant images to save memory
        let keepIndices = Set((max(0, currentIndex - 2)...min(items.count - 1, currentIndex + 2)))
        let keepIds = Set(keepIndices.map { items[$0].id })
        loadedImages = loadedImages.filter { keepIds.contains($0.key) }
    }
}

struct PhotoViewerPage: View {
    let item: MediaItem
    let image: UIImage?
    let onLoadRequest: () -> Void

    @State private var scale: CGFloat = 1.0
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale * magnifyBy)
                    .gesture(
                        MagnificationGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                scale = max(1, min(scale * value, 4))
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1 ? 1 : 2
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
            } else if let thumbnail = item.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay(ProgressView().scaleEffect(1.5))
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .onAppear { onLoadRequest() }
    }
}

// MARK: - Timeline Swipe Mode View

struct TimelineSwipeModeView: View {
    let period: TimelinePeriod
    @ObservedObject var viewModel: CleanerViewModel
    let onDismiss: () -> Void

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
                // Results view
                TimelineSwipeResultsView(
                    periodTitle: "\(period.title) \(period.subtitle)",
                    toKeep: toKeep,
                    toDelete: toDelete,
                    onDeleteConfirmed: deleteSelectedItems,
                    onReset: resetSwipe,
                    onDismiss: onDismiss
                )
            } else if currentIndex >= period.items.count {
                // Finished - show results
                Color.clear.onAppear { showResults = true }
            } else {
                VStack(spacing: 20) {
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

                        VStack(spacing: 2) {
                            Text("\(period.title) \(period.subtitle)")
                                .font(.headline)
                            Text("\(currentIndex + 1) / \(period.items.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { showResults = true }) {
                            Text("Terminer")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemGray5))
                                .cornerRadius(20)
                        }
                    }
                    .padding(.horizontal)

                    // Stats
                    HStack(spacing: 20) {
                        Label("\(toDelete.count)", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Label("\(toKeep.count)", systemImage: "heart.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }

                    // Card
                    ZStack {
                        // Background cards
                        ForEach(0..<min(2, period.items.count - currentIndex - 1), id: \.self) { i in
                            let index = currentIndex + i + 1
                            if index < period.items.count {
                                SwipeCardBackground(
                                    item: period.items[index],
                                    thumbnail: getThumbnail(for: period.items[index]),
                                    offset: CGFloat(i)
                                )
                            }
                        }

                        // Current card
                        SwipeCard(
                            item: period.items[currentIndex],
                            thumbnail: getThumbnail(for: period.items[currentIndex]),
                            hdImage: hdImage,
                            offset: offset,
                            onSwipe: handleSwipe
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
                    .padding(.horizontal)

                    // Action buttons
                    HStack(spacing: 30) {
                        Button(action: swipeLeft) {
                            Image(systemName: "xmark")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(width: 65, height: 65)
                                .background(Color.red)
                                .clipShape(Circle())
                                .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
                        }

                        Button(action: undoSwipe) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.title2)
                                .foregroundColor(.orange)
                                .frame(width: 50, height: 50)
                                .background(Color(.systemBackground))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                        }
                        .disabled(currentIndex == 0)
                        .opacity(currentIndex == 0 ? 0.4 : 1)

                        Button(action: swipeRight) {
                            Image(systemName: "heart.fill")
                                .font(.title)
                                .foregroundColor(.white)
                                .frame(width: 65, height: 65)
                                .background(Color.green)
                                .clipShape(Circle())
                                .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                        }
                    }
                    .padding(.bottom, 20)

                    // Instructions
                    HStack(spacing: 30) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Supprimer")
                        }
                        .font(.caption)
                        .foregroundColor(.red)

                        HStack(spacing: 4) {
                            Text("Garder")
                            Image(systemName: "arrow.right")
                        }
                        .font(.caption)
                        .foregroundColor(.green)
                    }
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
        let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex + 2]
            .filter { $0 >= 0 && $0 < period.items.count }

        for index in indicesToLoad {
            let item = period.items[index]
            if item.thumbnail == nil && loadedThumbnails[item.id] == nil {
                Task {
                    if let thumb = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail) {
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
        guard currentIndex < period.items.count else { return }
        let item = period.items[currentIndex]
        guard item.asset.mediaType == .image else {
            hdImage = nil
            return
        }

        let itemId = item.id
        hdLoadTask = Task {
            if let image = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                if !Task.isCancelled {
                    await MainActor.run {
                        if currentIndex < period.items.count && period.items[currentIndex].id == itemId {
                            hdImage = image
                        }
                    }
                }
            }
        }
    }

    private func handleGestureEnd(_ gesture: DragGesture.Value) {
        let threshold: CGFloat = 100
        if gesture.translation.width > threshold {
            swipeRight()
        } else if gesture.translation.width < -threshold {
            swipeLeft()
        } else {
            withAnimation(.spring()) { offset = .zero }
        }
    }

    private func handleSwipe(_ direction: SwipeDirection) {
        if direction == .left { swipeLeft() } else { swipeRight() }
    }

    private func swipeLeft() {
        withAnimation(.spring()) { offset = CGSize(width: -500, height: 0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex < period.items.count {
                toDelete.append(period.items[currentIndex])
                currentIndex += 1
                offset = .zero
            }
        }
    }

    private func swipeRight() {
        withAnimation(.spring()) { offset = CGSize(width: 500, height: 0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex < period.items.count {
                toKeep.append(period.items[currentIndex])
                currentIndex += 1
                offset = .zero
            }
        }
    }

    private func undoSwipe() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        let item = period.items[currentIndex]
        toKeep.removeAll { $0.id == item.id }
        toDelete.removeAll { $0.id == item.id }
        offset = .zero
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
                onDismiss()
            }
        }
    }
}

// MARK: - Timeline Swipe Results View

struct TimelineSwipeResultsView: View {
    let periodTitle: String
    let toKeep: [MediaItem]
    let toDelete: [MediaItem]
    let onDeleteConfirmed: () -> Void
    let onReset: () -> Void
    let onDismiss: () -> Void

    @State private var isDeleting = false

    var totalSizeToDelete: Int64 {
        toDelete.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)

            Text("Tri terminé !")
                .font(.title)
                .fontWeight(.bold)

            Text(periodTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 20) {
                HStack(spacing: 40) {
                    VStack(spacing: 8) {
                        Text("\(toKeep.count)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.green)
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                            Text("Gardées")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        Text("\(toDelete.count)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.red)
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                            Text("À supprimer")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if !toDelete.isEmpty {
                    VStack(spacing: 4) {
                        Text(ByteCountFormatter.string(fromByteCount: totalSizeToDelete, countStyle: .file))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("à libérer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(24)
            .background(Color(.systemGray6))
            .cornerRadius(20)

            Spacer()

            VStack(spacing: 12) {
                if !toDelete.isEmpty {
                    Button(action: {
                        isDeleting = true
                        onDeleteConfirmed()
                    }) {
                        HStack {
                            if isDeleting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text("Supprimer \(toDelete.count) éléments")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                    .disabled(isDeleting)
                }

                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Recommencer")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(14)
                }
                .disabled(isDeleting)

                Button(action: onDismiss) {
                    Text("Fermer")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(isDeleting)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .padding()
    }
}

// Extension for optional binding with index
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - Swipe Tab View

struct SwipeTabView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @State private var allMedia: [MediaItem] = []
    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var isLoading = true
    @State private var toKeep: [MediaItem] = []
    @State private var toDelete: [MediaItem] = []
    @State private var hdImage: UIImage?
    @State private var loadedThumbnails: [String: UIImage] = [:] // Cache for visible thumbnails only
    @State private var hdLoadTask: Task<Void, Never>?

    // OPTIMIZATION: Limit items loaded at once for better performance
    private let maxInitialItems = 500

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Chargement des médias...")
                            .foregroundColor(.secondary)
                    }
                } else if allMedia.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)
                        Text("Tout est trié !")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Aucun média à trier")
                            .foregroundColor(.secondary)
                    }
                } else if currentIndex >= allMedia.count {
                    // Results view
                    SwipeResultsView(
                        toKeep: toKeep,
                        toDelete: toDelete,
                        onDeleteConfirmed: deleteSelectedItems,
                        onReset: resetSwipe
                    )
                } else {
                    VStack(spacing: 20) {
                        // Progress
                        HStack {
                            Text("\(currentIndex + 1) / \(allMedia.count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Spacer()

                            HStack(spacing: 16) {
                                Label("\(toDelete.count)", systemImage: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                Label("\(toKeep.count)", systemImage: "heart.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            Spacer()

                            Button("Terminer") {
                                currentIndex = allMedia.count
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        }
                        .padding(.horizontal)

                        // Card
                        ZStack {
                            // Background cards (next items)
                            ForEach(0..<min(2, allMedia.count - currentIndex - 1), id: \.self) { i in
                                let index = currentIndex + i + 1
                                if index < allMedia.count {
                                    SwipeCardBackground(
                                        item: allMedia[index],
                                        thumbnail: getThumbnail(for: allMedia[index]),
                                        offset: CGFloat(i)
                                    )
                                }
                            }

                            // Current card
                            if currentIndex < allMedia.count {
                                SwipeCard(
                                    item: allMedia[currentIndex],
                                    thumbnail: getThumbnail(for: allMedia[currentIndex]),
                                    hdImage: hdImage,
                                    offset: offset,
                                    onSwipe: handleSwipe
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
                        }
                        .padding(.horizontal)

                        // Action buttons
                        HStack(spacing: 30) {
                            // Delete button
                            Button(action: { swipeLeft() }) {
                                Image(systemName: "xmark")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 65, height: 65)
                                    .background(Color.red)
                                    .clipShape(Circle())
                                    .shadow(color: .red.opacity(0.3), radius: 10, y: 5)
                            }

                            // Undo button
                            Button(action: { undoSwipe() }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                    .frame(width: 50, height: 50)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            }
                            .disabled(currentIndex == 0)
                            .opacity(currentIndex == 0 ? 0.4 : 1)

                            // Keep button
                            Button(action: { swipeRight() }) {
                                Image(systemName: "heart.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 65, height: 65)
                                    .background(Color.green)
                                    .clipShape(Circle())
                                    .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                            }
                        }
                        .padding(.bottom, 30)

                        // Instructions
                        HStack(spacing: 30) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                Text("Supprimer")
                            }
                            .font(.caption)
                            .foregroundColor(.red)

                            HStack(spacing: 4) {
                                Text("Garder")
                                Image(systemName: "arrow.right")
                            }
                            .font(.caption)
                            .foregroundColor(.green)
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                loadAllMedia()
            }
            .onChange(of: currentIndex) { _ in
                loadHDForCurrentItem()
            }
        }
    }

    private func loadAllMedia() {
        isLoading = true
        hdLoadTask?.cancel()

        Task {
            var items: [MediaItem] = []

            for categoryData in viewModel.categories {
                if categoryData.category.hasSimilarGroups && !categoryData.similarGroups.isEmpty {
                    for group in categoryData.similarGroups {
                        items.append(contentsOf: group.items)
                    }
                } else {
                    items.append(contentsOf: categoryData.items)
                }
            }

            // Remove duplicates
            var seen = Set<String>()
            items = items.filter { item in
                if seen.contains(item.id) { return false }
                seen.insert(item.id)
                return true
            }

            // Sort by date descending (most recent first)
            items.sort { item1, item2 in
                let date1 = item1.asset.creationDate ?? Date.distantPast
                let date2 = item2.asset.creationDate ?? Date.distantPast
                return date1 > date2
            }

            // OPTIMIZATION: Limit initial load for better performance
            let limitedItems = Array(items.prefix(maxInitialItems))

            await MainActor.run {
                allMedia = limitedItems
                isLoading = false
                loadVisibleItems()
            }
        }
    }

    // Only load thumbnails for current + next 2 items
    private func loadVisibleItems() {
        hdImage = nil
        loadedThumbnails = [:] // Clear old thumbnails to free memory

        let indicesToLoad = [currentIndex, currentIndex + 1, currentIndex + 2]
            .filter { $0 >= 0 && $0 < allMedia.count }

        for index in indicesToLoad {
            let item = allMedia[index]

            // Load thumbnail if not already loaded
            if item.thumbnail == nil && loadedThumbnails[item.id] == nil {
                Task {
                    if let thumb = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail) {
                        await MainActor.run {
                            loadedThumbnails[item.id] = thumb
                        }
                    }
                }
            }
        }

        // Load HD for current item only
        loadHDForCurrentItem()
    }

    private func loadHDForCurrentItem() {
        hdLoadTask?.cancel()

        guard currentIndex < allMedia.count else { return }
        let item = allMedia[currentIndex]
        guard item.asset.mediaType == .image else {
            hdImage = nil
            return
        }

        let itemId = item.id
        hdLoadTask = Task {
            if let image = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                if !Task.isCancelled {
                    await MainActor.run {
                        // Double check we're still on the same item
                        if currentIndex < allMedia.count && allMedia[currentIndex].id == itemId {
                            hdImage = image
                        }
                    }
                }
            }
        }
    }

    private func getThumbnail(for item: MediaItem) -> UIImage? {
        return item.thumbnail ?? loadedThumbnails[item.id]
    }

    private func handleGestureEnd(_ gesture: DragGesture.Value) {
        let threshold: CGFloat = 100

        if gesture.translation.width > threshold {
            swipeRight()
        } else if gesture.translation.width < -threshold {
            swipeLeft()
        } else {
            withAnimation(.spring()) {
                offset = .zero
            }
        }
    }

    private func handleSwipe(_ direction: SwipeDirection) {
        if direction == .left {
            swipeLeft()
        } else {
            swipeRight()
        }
    }

    private func swipeLeft() {
        withAnimation(.spring()) {
            offset = CGSize(width: -500, height: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex < allMedia.count {
                toDelete.append(allMedia[currentIndex])
                currentIndex += 1
                offset = .zero
                loadVisibleItems()
            }
        }
    }

    private func swipeRight() {
        withAnimation(.spring()) {
            offset = CGSize(width: 500, height: 0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if currentIndex < allMedia.count {
                toKeep.append(allMedia[currentIndex])
                currentIndex += 1
                offset = .zero
                loadVisibleItems()
            }
        }
    }

    private func undoSwipe() {
        guard currentIndex > 0 else { return }

        currentIndex -= 1
        let item = allMedia[currentIndex]

        // Remove from either list
        toKeep.removeAll { $0.id == item.id }
        toDelete.removeAll { $0.id == item.id }

        offset = .zero
        loadVisibleItems()
    }

    private func resetSwipe() {
        hdLoadTask?.cancel()
        currentIndex = 0
        toKeep = []
        toDelete = []
        hdImage = nil
        loadedThumbnails.removeAll()
        allMedia.removeAll()
        loadAllMedia()
    }

    private func deleteSelectedItems() {
        Task {
            let _ = await viewModel.deleteItems(toDelete)
            await viewModel.loadAllCategories()

            await MainActor.run {
                toDelete = []
                toKeep = []
                currentIndex = 0
                hdImage = nil
                loadedThumbnails = [:]
                loadAllMedia()
            }
        }
    }
}

enum SwipeDirection {
    case left, right
}

struct SwipeCard: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let hdImage: UIImage?
    let offset: CGSize
    let onSwipe: (SwipeDirection) -> Void

    private var isVideo: Bool {
        item.asset.mediaType == .video
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Image
                if let image = hdImage ?? thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .overlay(ProgressView())
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
                        // Delete indicator (left)
                        if offset.width < -20 {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.red)
                                .opacity(min(1, Double(-offset.width) / 100))
                        }

                        Spacer()

                        // Keep indicator (right)
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

                // File info at bottom
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

struct SwipeCardBackground: View {
    let item: MediaItem
    let thumbnail: UIImage?
    let offset: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .overlay(ProgressView().scaleEffect(0.8))
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

struct SwipeResultsView: View {
    let toKeep: [MediaItem]
    let toDelete: [MediaItem]
    let onDeleteConfirmed: () -> Void
    let onReset: () -> Void

    @State private var isDeleting = false

    var totalSizeToDelete: Int64 {
        toDelete.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Header
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.green)

            Text("Tri terminé !")
                .font(.title)
                .fontWeight(.bold)

            // Stats
            VStack(spacing: 20) {
                HStack(spacing: 40) {
                    VStack(spacing: 8) {
                        Text("\(toKeep.count)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.green)
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.caption)
                            Text("Gardées")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }

                    VStack(spacing: 8) {
                        Text("\(toDelete.count)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.red)
                        HStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                            Text("À supprimer")
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                if !toDelete.isEmpty {
                    VStack(spacing: 4) {
                        Text(ByteCountFormatter.string(fromByteCount: totalSizeToDelete, countStyle: .file))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)
                        Text("à libérer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(24)
            .background(Color(.systemGray6))
            .cornerRadius(20)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                if !toDelete.isEmpty {
                    Button(action: {
                        isDeleting = true
                        onDeleteConfirmed()
                    }) {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash.fill")
                            }
                            Text("Supprimer \(toDelete.count) éléments")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                    .disabled(isDeleting)
                }

                Button(action: onReset) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(toDelete.isEmpty ? "Trier d'autres photos" : "Annuler et recommencer")
                    }
                    .font(.headline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(14)
                }
                .disabled(isDeleting)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
