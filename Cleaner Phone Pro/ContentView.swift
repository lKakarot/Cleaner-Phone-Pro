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
                            // Warning if limited access
                            if viewModel.authorizationStatus == .limited {
                                LimitedAccessBanner()
                            }

                            // Stats header with diagnostic button
                            if viewModel.totalPhotoCount > 0 || viewModel.totalVideoCount > 0 {
                                HStack {
                                    // Diagnostic info
                                    if let diag = viewModel.diagnostics {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Label("\(viewModel.totalPhotoCount) photos", systemImage: "photo")
                                                Spacer()
                                                Label("\(viewModel.totalVideoCount) vidéos", systemImage: "video")
                                            }

                                            // Show warning only if there's a real discrepancy (excluding audio)
                                            let totalFetched = viewModel.totalPhotoCount + viewModel.totalVideoCount
                                            let expectedTotal = diag.totalImages + diag.totalVideos
                                            if totalFetched < expectedTotal {
                                                let missing = expectedTotal - totalFetched
                                                HStack(spacing: 4) {
                                                    Image(systemName: "eye.slash")
                                                        .foregroundColor(.orange)
                                                    if missing <= diag.hiddenCount && diag.hiddenCount > 0 {
                                                        Text("\(missing) photos masquées")
                                                    } else {
                                                        Text("\(missing) éléments non accessibles")
                                                    }
                                                }
                                                .foregroundColor(.orange)
                                                .font(.caption2)
                                                .padding(.top, 2)
                                            }
                                        }
                                    } else {
                                        HStack {
                                            Label("\(viewModel.totalPhotoCount) photos", systemImage: "photo")
                                            Spacer()
                                            Label("\(viewModel.totalVideoCount) vidéos", systemImage: "video")
                                        }
                                    }
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
                    .overlay {
                        if viewModel.isLoading {
                            LoadingOverlay()
                        }
                    }
                }
            }
            .navigationTitle("Nettoyer")
            .toolbar {
                if viewModel.diagnostics != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            withAnimation {
                                viewModel.showDiagnostics.toggle()
                            }
                        }) {
                            Image(systemName: viewModel.showDiagnostics ? "chart.bar.fill" : "chart.bar")
                        }
                    }
                }
            }
        }
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

                Text("Analyse en cours...")
                    .font(.title3)
                    .fontWeight(.semibold)
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
    @State private var mediaFilter: MediaFilter = .all
    @State private var timelineData: [TimelineSection] = []
    @State private var isLoading = true

    enum TimelineGrouping: String, CaseIterable {
        case month = "Mois"
        case year = "Année"
    }

    enum MediaFilter: String, CaseIterable {
        case all = "Tout"
        case photos = "Photos"
        case videos = "Vidéos"
        case screenshots = "Screenshots"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .photos: return "photo"
            case .videos: return "video"
            case .screenshots: return "camera.viewfinder"
            }
        }
    }

    struct TimelineSection: Identifiable {
        let id = UUID()
        let title: String
        let date: Date
        let items: [MediaItem]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filters
                VStack(spacing: 12) {
                    // Group by selector
                    Picker("Grouper par", selection: $groupBy) {
                        ForEach(TimelineGrouping.allCases, id: \.self) { grouping in
                            Text(grouping.rawValue).tag(grouping)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Media filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(MediaFilter.allCases, id: \.self) { filter in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        mediaFilter = filter
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: filter.icon)
                                            .font(.caption)
                                        Text(filter.rawValue)
                                            .font(.subheadline)
                                    }
                                    .fontWeight(.medium)
                                    .foregroundColor(mediaFilter == filter ? .white : .primary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(mediaFilter == filter ? Color.blue : Color(.systemGray5))
                                    .cornerRadius(20)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 12)
                .background(Color(.systemBackground))

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Chargement...")
                    Spacer()
                } else if timelineData.isEmpty {
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
                        LazyVStack(spacing: 24, pinnedViews: .sectionHeaders) {
                            ForEach(timelineData) { section in
                                Section {
                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: 2),
                                        GridItem(.flexible(), spacing: 2),
                                        GridItem(.flexible(), spacing: 2)
                                    ], spacing: 2) {
                                        ForEach(section.items) { item in
                                            TimelineThumbnailView(item: item)
                                        }
                                    }
                                    .padding(.horizontal, 2)
                                } header: {
                                    HStack {
                                        Text(section.title)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                        Spacer()
                                        Text("\(section.items.count) éléments")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .background(Color(.systemBackground).opacity(0.95))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .onChange(of: groupBy) { _ in loadTimeline() }
            .onChange(of: mediaFilter) { _ in loadTimeline() }
            .onAppear { loadTimeline() }
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
                if seen.contains(item.id) {
                    return false
                }
                seen.insert(item.id)
                return true
            }

            // Filter by media type
            switch mediaFilter {
            case .all:
                break
            case .photos:
                allItems = allItems.filter { $0.asset.mediaType == .image && !isScreenshot($0.asset) }
            case .videos:
                allItems = allItems.filter { $0.asset.mediaType == .video }
            case .screenshots:
                allItems = allItems.filter { isScreenshot($0.asset) }
            }

            // Group by date
            let grouped = Dictionary(grouping: allItems) { item -> String in
                let date = item.asset.creationDate ?? Date()
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "fr_FR")
                if groupBy == .month {
                    formatter.dateFormat = "MMMM yyyy"
                } else {
                    formatter.dateFormat = "yyyy"
                }
                return formatter.string(from: date)
            }

            // Convert to sections and sort
            var sections: [TimelineSection] = []
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "fr_FR")
            if groupBy == .month {
                dateFormatter.dateFormat = "MMMM yyyy"
            } else {
                dateFormatter.dateFormat = "yyyy"
            }

            for (title, items) in grouped {
                let date = dateFormatter.date(from: title) ?? Date()
                let sortedItems = items.sorted { ($0.asset.creationDate ?? Date()) > ($1.asset.creationDate ?? Date()) }
                sections.append(TimelineSection(title: title.capitalized, date: date, items: sortedItems))
            }

            sections.sort { $0.date > $1.date }

            await MainActor.run {
                timelineData = sections
                isLoading = false
            }
        }
    }

    private func isScreenshot(_ asset: PHAsset) -> Bool {
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            return true
        }
        let width = asset.pixelWidth
        let height = asset.pixelHeight
        let screenScales: [(Int, Int)] = [
            (1170, 2532), (1284, 2778), (1179, 2556), (1290, 2796),
            (1125, 2436), (828, 1792), (1080, 1920), (750, 1334),
            (1242, 2688), (1242, 2208)
        ]
        return screenScales.contains { $0.0 == width && $0.1 == height }
    }
}

struct TimelineThumbnailView: View {
    let item: MediaItem
    @State private var thumbnail: UIImage?

    var body: some View {
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
                }

                // Video indicator
                if item.asset.mediaType == .video {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text(formatDuration(item.asset.duration))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        if item.thumbnail == nil {
            Task {
                let image = await PhotoLibraryService.shared.loadThumbnail(for: item.asset, quality: .detail)
                await MainActor.run {
                    thumbnail = image
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
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
            .navigationTitle("Trier")
            .toolbar {
                if !isLoading && currentIndex < allMedia.count {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Terminer") {
                            currentIndex = allMedia.count
                        }
                    }
                }
            }
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

            await MainActor.run {
                allMedia = items
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
        guard currentIndex < allMedia.count else { return }
        let item = allMedia[currentIndex]
        guard item.asset.mediaType == .image else {
            hdImage = nil
            return
        }

        Task {
            if let image = await PhotoLibraryService.shared.loadFullImage(for: item.asset) {
                await MainActor.run {
                    if currentIndex < allMedia.count && allMedia[currentIndex].id == item.id {
                        hdImage = image
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
        currentIndex = 0
        toKeep = []
        toDelete = []
        hdImage = nil
        loadedThumbnails = [:]
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

    @State private var showDeleteConfirmation = false
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
                        showDeleteConfirmation = true
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
        .alert("Confirmer la suppression", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                isDeleting = true
                onDeleteConfirmed()
            }
        } message: {
            Text("Supprimer \(toDelete.count) éléments ?\n\nIls seront déplacés dans \"Supprimés récemment\" pendant 30 jours.")
        }
    }
}

#Preview {
    ContentView()
}
