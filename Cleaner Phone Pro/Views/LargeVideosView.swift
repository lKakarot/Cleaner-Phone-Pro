//
//  LargeVideosView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct LargeVideosView: View {
    @EnvironmentObject private var viewModel: CleanerViewModel
    @State private var selectedItems: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private var totalSize: Int64 {
        viewModel.largeVideos.reduce(0) { $0 + $1.size }
    }

    private var selectedSize: Int64 {
        viewModel.largeVideos
            .filter { selectedItems.contains($0.item.id) }
            .reduce(0) { $0 + $1.size }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            if viewModel.largeVideos.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .navigationTitle("Grosses vidéos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Supprimer")
                            .fontWeight(.semibold)
                            .foregroundStyle(.pink)
                    }
                }
            }
        }
        .alert("Supprimer les vidéos", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { await deleteSelectedVideos() }
            }
        } message: {
            Text("Supprimer \(selectedItems.count) vidéo(s) ?\nVous libérerez \(formatSize(selectedSize))")
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(AppColors.successGradient)
                    .frame(width: 80, height: 80)

                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text("Aucune grosse vidéo")
                .font(.title2)
                .fontWeight(.bold)

            Text("Toutes vos vidéos sont de taille raisonnable")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                summaryCard
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                LazyVStack(spacing: 12) {
                    ForEach(viewModel.largeVideos, id: \.item.id) { video in
                        VideoRowCard(
                            item: video.item,
                            size: video.size,
                            duration: video.duration,
                            isSelected: selectedItems.contains(video.item.id)
                        ) {
                            toggleSelection(video.item.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .overlay(alignment: .bottom) {
            if !selectedItems.isEmpty {
                deleteButton
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.largeVideos.count) vidéo(s)")
                        .font(.headline)

                    Text("Total : \(formatSize(totalSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    toggleSelectAll()
                } label: {
                    Text(selectedItems.count == viewModel.largeVideos.count ? "Tout désélectionner" : "Tout sélectionner")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(hex: "667eea"))
                }
            }

            if selectedSize > 0 {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("Espace récupérable : \(formatSize(selectedSize))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            HStack {
                if isDeleting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "trash")
                    Text("Libérer \(formatSize(selectedSize))")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(AppColors.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isDeleting)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [.clear, Color(.systemBackground).opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func toggleSelection(_ id: String) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    private func toggleSelectAll() {
        if selectedItems.count == viewModel.largeVideos.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(viewModel.largeVideos.map { $0.item.id })
        }
    }

    private func deleteSelectedVideos() async {
        isDeleting = true

        let itemsToDelete = viewModel.largeVideos
            .filter { selectedItems.contains($0.item.id) }
            .map { $0.item }

        let success = await viewModel.deleteItems(itemsToDelete)

        if success {
            viewModel.largeVideos.removeAll { selectedItems.contains($0.item.id) }
            selectedItems.removeAll()
        }

        isDeleting = false
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Video Row Card
struct VideoRowCard: View {
    let item: MediaItem
    let size: Int64
    let duration: TimeInterval
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                PhotoThumbnail(asset: item.asset, size: CGSize(width: 240, height: 136))
                    .frame(width: 120, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(formatDuration(duration))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }

            // Info
            VStack(alignment: .leading, spacing: 6) {
                if let date = item.creationDate {
                    Text(date, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text(formatSize(size))
                    .font(.headline)
                    .foregroundStyle(Color(hex: "667eea"))
            }

            Spacer()

            // Selection
            ZStack {
                Circle()
                    .fill(isSelected ? Color(hex: "667eea") : Color.white.opacity(0.9))
                    .frame(width: 28, height: 28)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color(hex: "667eea") : .clear, lineWidth: 2)
        )
        .onTapGesture(perform: onTap)
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        LargeVideosView()
            .environmentObject(CleanerViewModel())
    }
}
