//
//  BlurryPhotosView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct BlurryPhotosView: View {
    @EnvironmentObject private var viewModel: CleanerViewModel
    @State private var selectedItems: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            if viewModel.blurryPhotos.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .navigationTitle("Photos floues")
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
        .alert("Supprimer les photos", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { await deleteSelectedPhotos() }
            }
        } message: {
            Text("Supprimer \(selectedItems.count) photo(s) floue(s) ?")
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

            Text("Aucune photo floue")
                .font(.title2)
                .fontWeight(.bold)

            Text("Toutes vos photos sont nettes !")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                summaryCard
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.blurryPhotos) { item in
                        SelectablePhotoCell(
                            item: item,
                            isSelected: selectedItems.contains(item.id),
                            accentColor: Color(hex: "fa709a")
                        ) {
                            toggleSelection(item.id)
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(viewModel.blurryPhotos.count) photo(s) floue(s)")
                    .font(.headline)

                Text("Qualité insuffisante détectée")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                toggleSelectAll()
            } label: {
                Text(selectedItems.count == viewModel.blurryPhotos.count ? "Tout désélectionner" : "Tout sélectionner")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: "fa709a"))
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
                    Text("Supprimer \(selectedItems.count) photo(s)")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(AppColors.warningGradient)
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
        if selectedItems.count == viewModel.blurryPhotos.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(viewModel.blurryPhotos.map { $0.id })
        }
    }

    private func deleteSelectedPhotos() async {
        isDeleting = true

        let itemsToDelete = viewModel.blurryPhotos.filter { selectedItems.contains($0.id) }
        let success = await viewModel.deleteItems(itemsToDelete)

        if success {
            viewModel.removeFromBlurry(selectedItems)
            selectedItems.removeAll()
        }

        isDeleting = false
    }
}

// MARK: - Selectable Photo Cell
struct SelectablePhotoCell: View {
    let item: MediaItem
    let isSelected: Bool
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnail(asset: item.asset, size: CGSize(width: 200, height: 200))
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            ZStack {
                Circle()
                    .fill(isSelected ? accentColor : Color.white.opacity(0.9))
                    .frame(width: 26, height: 26)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .padding(8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? accentColor : .clear, lineWidth: 3)
        )
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    NavigationStack {
        BlurryPhotosView()
            .environmentObject(CleanerViewModel())
    }
}
