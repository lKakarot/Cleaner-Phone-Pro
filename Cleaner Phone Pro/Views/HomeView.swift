//
//  HomeView.swift
//  Cleaner Phone Pro
//
//  Design premium avec mosaïque de photos edge-to-edge
//

import SwiftUI
import Photos

struct HomeView: View {
    @StateObject private var viewModel = CleanerViewModel()
    @State private var showPermissionAlert = false
    @State private var isPhotoLibraryExpanded = false
    @State private var showRefreshSuccess = false
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if isPhotoLibraryExpanded {
                    // Vue photos étendue
                    expandedPhotoLibrary
                        .transition(.move(edge: .bottom))
                } else {
                    // Vue normale
                    normalView
                }

                // Floating Header avec blur
                floatingHeader

                // Success indicator
                if showRefreshSuccess {
                    refreshSuccessIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .onAppear {
                Task { await checkAndScan() }
            }
            .alert("Accès Photos Requis", isPresented: $showPermissionAlert) {
                Button("Paramètres") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Pour analyser vos photos, l'application a besoin d'accéder à votre bibliothèque.")
            }
            .navigationDestination(for: CleanupCategory.self) { category in
                destinationView(for: category)
            }
        }
        .environmentObject(viewModel)
    }

    // MARK: - Normal View
    private var normalView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Section avec Mosaïque edge-to-edge
                heroSection

                // Content
                VStack(spacing: 16) {
                    if viewModel.isScanning && !isRefreshing {
                        scanningSection
                            .padding(.top, 20)
                    } else if viewModel.hasCompletedScan {
                        cleanupSection
                    } else if !viewModel.isScanning {
                        startSection
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .refreshable {
            await performRefresh()
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Expanded Photo Library
    private var expandedPhotoLibrary: some View {
        ExpandedPhotoGridView(
            photos: viewModel.allPhotos,
            onClose: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isPhotoLibraryExpanded = false
                }
            }
        )
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Floating Header
    private var floatingHeader: some View {
        VStack(spacing: 0) {
            // Zone pour couvrir la Dynamic Island / Notch
            Color.clear
                .frame(height: 50)

            // Header content
            HStack {
                Text("Cleaner Pro")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(0.5),
                    .black.opacity(0.3),
                    .black.opacity(0.1),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Hero Section
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Mosaïque edge-to-edge
            PhotoMosaicView(
                photos: viewModel.allPhotos,
                height: 380
            ) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPhotoLibraryExpanded = true
                    }
            }
            .clipShape(Rectangle()) // Pas de rounded corners en haut

            // Gradient overlay en bas
            LinearGradient(
                colors: [.clear, .clear, Color(.systemGroupedBackground).opacity(0.8), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)

            // Info overlay
            if !viewModel.allPhotos.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(viewModel.allPhotos.count) souvenirs")
                            .font(.title2)
                            .fontWeight(.bold)

                        if let storageText = storageText {
                            Text(storageText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPhotoLibraryExpanded = true
                    }
                    } label: {
                        Text("Voir tout")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColors.primaryGradient)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private var storageText: String? {
        let (used, total) = PhotoLibraryService.shared.getStorageInfo()
        guard total > 0 else { return nil }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .file

        let usedStr = formatter.string(fromByteCount: used)
        let totalStr = formatter.string(fromByteCount: total)
        return "\(usedStr) sur \(totalStr) utilisés"
    }

    // MARK: - Quick Stats Pills
    private var quickStatsPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                StatPill(
                    icon: "photo.fill",
                    value: "\(viewModel.allPhotos.count)",
                    label: "Photos",
                    color: Color(hex: "667eea")
                )

                if viewModel.totalIssuesCount > 0 {
                    StatPill(
                        icon: "exclamationmark.circle.fill",
                        value: "\(viewModel.totalIssuesCount)",
                        label: "À revoir",
                        color: Color(hex: "f5576c")
                    )
                }

                if !viewModel.largeVideos.isEmpty {
                    let totalSize = viewModel.largeVideos.reduce(0) { $0 + $1.size }
                    StatPill(
                        icon: "arrow.down.circle.fill",
                        value: formatSize(totalSize),
                        label: "Récupérable",
                        color: Color(hex: "11998e")
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Start Section
    private var startSection: some View {
        VStack(spacing: 20) {
            // Card d'action principale
            Button {
                Task { await viewModel.startFullScan() }
            } label: {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primaryGradient)
                            .frame(width: 56, height: 56)

                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Analyser ma bibliothèque")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("Trouvez les doublons, photos floues et plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Scanning Section
    private var scanningSection: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: viewModel.scanProgress)
                    .stroke(
                        AppColors.primaryGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.scanProgress)

                VStack(spacing: 4) {
                    Text("\(Int(viewModel.scanProgress * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                Text("Analyse en cours")
                    .font(.headline)

                Text(viewModel.scanPhase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Cleanup Section
    private var cleanupSection: some View {
        VStack(spacing: 16) {
            // Swipe cleanup action en premier
            swipeCleanupCard

            // Section header Optimisation
            HStack(spacing: 8) {
                Text("Optimisation")
                    .font(.title3)
                    .fontWeight(.bold)

                if viewModel.totalIssuesCount == 0 {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.body)
                        .foregroundStyle(Color(hex: "11998e"))
                }

                Spacer()
            }
            .padding(.top, 8)

            // Cleanup cards en scroll horizontal
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Doublons
                    NavigationLink(value: CleanupCategory.duplicates) {
                        CompactCleanupCardContent(
                            icon: "square.on.square",
                            title: "Doublons",
                            count: viewModel.duplicateGroups.reduce(0) { $0 + $1.items.count - 1 },
                            color: Color(hex: "f5576c"),
                            isEmpty: viewModel.duplicateGroups.isEmpty
                        )
                    }
                    .disabled(viewModel.duplicateGroups.isEmpty)

                    // Photos floues
                    NavigationLink(value: CleanupCategory.blurry) {
                        CompactCleanupCardContent(
                            icon: "camera.metering.unknown",
                            title: "Floues",
                            count: viewModel.blurryPhotos.count,
                            color: Color(hex: "fa709a"),
                            isEmpty: viewModel.blurryPhotos.isEmpty
                        )
                    }
                    .disabled(viewModel.blurryPhotos.isEmpty)

                    // Rafales
                    NavigationLink(value: CleanupCategory.bursts) {
                        CompactCleanupCardContent(
                            icon: "square.stack.3d.up",
                            title: "Rafales",
                            count: viewModel.burstGroups.reduce(0) { $0 + $1.items.count - 1 },
                            color: Color(hex: "667eea"),
                            isEmpty: viewModel.burstGroups.isEmpty
                        )
                    }
                    .disabled(viewModel.burstGroups.isEmpty)

                    // Captures d'écran
                    NavigationLink(value: CleanupCategory.screenshots) {
                        CompactCleanupCardContent(
                            icon: "camera.viewfinder",
                            title: "Captures",
                            count: viewModel.screenshots.count,
                            color: Color(hex: "4facfe"),
                            isEmpty: viewModel.screenshots.isEmpty
                        )
                    }
                    .disabled(viewModel.screenshots.isEmpty)

                    // Grosses vidéos
                    NavigationLink(value: CleanupCategory.largeVideos) {
                        CompactCleanupCardContent(
                            icon: "film",
                            title: "Vidéos",
                            count: viewModel.largeVideos.count,
                            color: Color(hex: "11998e"),
                            isEmpty: viewModel.largeVideos.isEmpty
                        )
                    }
                    .disabled(viewModel.largeVideos.isEmpty)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, -20)
            .padding(.leading, 20)
        }
    }

    // MARK: - Swipe Cleanup Card
    private var swipeCleanupCard: some View {
        NavigationLink(value: CleanupCategory.swipe) {
            ZStack(alignment: .bottomLeading) {
                // Aperçu photo en arrière-plan
                if let firstPhoto = viewModel.allPhotos.first {
                    PhotoThumbnail(asset: firstPhoto.asset, size: CGSize(width: 400, height: 400))
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 180)
                }

                // Overlay gradient pour lisibilité
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Contenu texte
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.draw.fill")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text("Tri rapide")
                                .font(.title3)
                                .fontWeight(.bold)
                        }

                        Text("Swipez pour garder ou supprimer")
                            .font(.subheadline)
                            .opacity(0.9)
                    }

                    Spacer()

                    Image(systemName: "chevron.right.circle.fill")
                        .font(.title)
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }


    // MARK: - Helper Functions
    private func checkAndScan() async {
        if viewModel.authorizationStatus == .notDetermined {
            let granted = await viewModel.requestAuthorization()
            if !granted {
                showPermissionAlert = true
                return
            }
        } else if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
            showPermissionAlert = true
            return
        }

        if !viewModel.hasCompletedScan && !viewModel.isScanning {
            await viewModel.startFullScan()
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func performRefresh() async {
        isRefreshing = true
        await viewModel.startFullScan()
        isRefreshing = false
        showSuccessToast()
    }

    private func showSuccessToast() {
        withAnimation(.spring(response: 0.3)) {
            showRefreshSuccess = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                showRefreshSuccess = false
            }
        }
    }

    // MARK: - Refresh Success Indicator
    private var refreshSuccessIndicator: some View {
        VStack {
            Spacer()

            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)

                Text("Actualisé")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(hex: "11998e"))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            )
            .padding(.bottom, 100)
        }
    }

    @ViewBuilder
    private func destinationView(for category: CleanupCategory) -> some View {
        switch category {
        case .duplicates:
            DuplicatesView()
        case .blurry:
            BlurryPhotosView()
        case .screenshots:
            ScreenshotsView()
        case .largeVideos:
            LargeVideosView()
        case .bursts:
            BurstsView()
        case .swipe:
            SwipeCleanupView()
        }
    }
}

// MARK: - Cleanup Category
enum CleanupCategory: String, Identifiable, Hashable {
    case duplicates
    case blurry
    case screenshots
    case largeVideos
    case bursts
    case swipe

    var id: String { rawValue }
}

// MARK: - Stat Pill
struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)

            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }
}

// MARK: - Compact Cleanup Card Content (pour scroll horizontal avec NavigationLink)
struct CompactCleanupCardContent: View {
    let icon: String
    let title: String
    let count: Int
    let color: Color
    let isEmpty: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(isEmpty ? 0.1 : 0.15))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(isEmpty ? .secondary : color)
            }

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isEmpty ? .secondary : .primary)

            if !isEmpty {
                Text("\(count)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            } else {
                Text("0")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 80)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .opacity(isEmpty ? 0.5 : 1)
    }
}

// MARK: - Preview
#Preview {
    HomeView()
}
