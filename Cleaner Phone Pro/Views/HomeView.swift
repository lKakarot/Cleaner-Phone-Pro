//
//  HomeView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct HomeView: View {
    @StateObject private var viewModel = CleanerViewModel()
    @State private var showPermissionAlert = false
    @State private var navigateToDuplicates = false
    @State private var navigateToBlurry = false
    @State private var navigateToScreenshots = false
    @State private var navigateToLargeVideos = false
    @State private var navigateToSwipe = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerSection

                        if viewModel.isScanning {
                            scanningCard
                        } else if viewModel.hasCompletedScan {
                            resultsSection
                        } else {
                            welcomeCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Cleaner Pro")
                        .font(.headline)
                        .fontWeight(.bold)
                }

                if viewModel.hasCompletedScan {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await viewModel.startFullScan() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .onAppear {
                Task {
                    await checkAndScan()
                }
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
            .navigationDestination(isPresented: $navigateToDuplicates) {
                DuplicatesView()
            }
            .navigationDestination(isPresented: $navigateToBlurry) {
                BlurryPhotosView()
            }
            .navigationDestination(isPresented: $navigateToScreenshots) {
                ScreenshotsView()
            }
            .navigationDestination(isPresented: $navigateToLargeVideos) {
                LargeVideosView()
            }
            .navigationDestination(isPresented: $navigateToSwipe) {
                SwipeCleanupView()
            }
        }
        .environmentObject(viewModel)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppColors.primaryGradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(hex: "667eea").opacity(0.5), radius: 20, y: 10)

                if viewModel.isScanning {
                    CircularProgressView(progress: viewModel.scanProgress, lineWidth: 4)
                        .frame(width: 110, height: 110)
                }

                Image(systemName: viewModel.hasCompletedScan ? "checkmark.shield.fill" : "sparkles")
                    .font(.system(size: 40))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
            }
            .padding(.top, 20)

            if viewModel.hasCompletedScan {
                VStack(spacing: 8) {
                    Text("\(viewModel.totalIssuesCount)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("éléments à nettoyer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Welcome Card
    private var welcomeCard: some View {
        GlassCard {
            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 50))
                    .foregroundStyle(AppColors.primaryGradient)

                Text("Bienvenue")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Analysez votre bibliothèque pour trouver les photos en double, floues et libérer de l'espace.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                PrimaryButton("Analyser ma bibliothèque", icon: "magnifyingglass") {
                    Task { await viewModel.startFullScan() }
                }
                .padding(.top, 8)
            }
            .padding(28)
        }
    }

    // MARK: - Scanning Card
    private var scanningCard: some View {
        GlassCard {
            VStack(spacing: 24) {
                ZStack {
                    CircularProgressView(progress: viewModel.scanProgress, lineWidth: 8)
                        .frame(width: 120, height: 120)

                    VStack(spacing: 4) {
                        Text("\(Int(viewModel.scanProgress * 100))%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

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
                        .animation(.easeInOut, value: viewModel.scanPhase)
                }
            }
            .padding(32)
        }
    }

    // MARK: - Results Section
    private var resultsSection: some View {
        VStack(spacing: 16) {
            // Quick Actions
            HStack(spacing: 12) {
                QuickStatCard(
                    icon: "photo.fill",
                    value: "\(viewModel.allPhotos.count)",
                    label: "Photos",
                    color: Color(hex: "667eea")
                )

                QuickStatCard(
                    icon: "square.on.square",
                    value: "\(viewModel.duplicateGroups.reduce(0) { $0 + $1.items.count - 1 })",
                    label: "Doublons",
                    color: Color(hex: "f5576c")
                )
            }

            // Issue Cards
            VStack(spacing: 12) {
                if !viewModel.duplicateGroups.isEmpty {
                    IssueCard(
                        icon: "square.on.square",
                        title: "Photos en double",
                        count: viewModel.duplicateGroups.reduce(0) { $0 + $1.items.count - 1 },
                        subtitle: "\(viewModel.duplicateGroups.count) groupe(s) trouvé(s)",
                        gradient: AppColors.dangerGradient
                    ) {
                        navigateToDuplicates = true
                    }
                }

                if !viewModel.blurryPhotos.isEmpty {
                    IssueCard(
                        icon: "camera.metering.unknown",
                        title: "Photos floues",
                        count: viewModel.blurryPhotos.count,
                        subtitle: "Qualité insuffisante",
                        gradient: AppColors.warningGradient
                    ) {
                        navigateToBlurry = true
                    }
                }

                if !viewModel.screenshots.isEmpty {
                    IssueCard(
                        icon: "camera.viewfinder",
                        title: "Captures d'écran",
                        count: viewModel.screenshots.count,
                        subtitle: "À trier",
                        gradient: AppColors.successGradient
                    ) {
                        navigateToScreenshots = true
                    }
                }

                if !viewModel.largeVideos.isEmpty {
                    let totalSize = viewModel.largeVideos.reduce(0) { $0 + $1.size }
                    IssueCard(
                        icon: "film",
                        title: "Grosses vidéos",
                        count: viewModel.largeVideos.count,
                        subtitle: formatSize(totalSize),
                        gradient: AppColors.primaryGradient
                    ) {
                        navigateToLargeVideos = true
                    }
                }

                // Swipe Cleanup Card
                swipeCleanupCard
            }

            if viewModel.totalIssuesCount == 0 {
                allCleanCard
            }
        }
    }

    private var swipeCleanupCard: some View {
        Button {
            navigateToSwipe = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "11998e"), Color(hex: "38ef7d")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "hand.draw")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nettoyage rapide")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Swipez pour trier vos photos")
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
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var allCleanCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(AppColors.successGradient)

                Text("Tout est propre !")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Aucun problème détecté dans votre bibliothèque.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
        }
    }

    // MARK: - Functions
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
}

// MARK: - Quick Stat Card
struct QuickStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

#Preview {
    HomeView()
}
