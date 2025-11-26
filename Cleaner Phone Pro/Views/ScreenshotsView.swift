//
//  ScreenshotsView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct ScreenshotsView: View {
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

            if viewModel.screenshots.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .navigationTitle("Captures d'écran")
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
        .alert("Supprimer les captures", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { await deleteSelectedPhotos() }
            }
        } message: {
            Text("Supprimer \(selectedItems.count) capture(s) d'écran ?")
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

            Text("Aucune capture d'écran")
                .font(.title2)
                .fontWeight(.bold)

            Text("Votre bibliothèque ne contient pas de screenshots")
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

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(viewModel.screenshots) { item in
                        SelectablePhotoCell(
                            item: item,
                            isSelected: selectedItems.contains(item.id),
                            accentColor: Color(hex: "4facfe")
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
                Text("\(viewModel.screenshots.count) capture(s)")
                    .font(.headline)

                Text("Sélectionnez celles à supprimer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                toggleSelectAll()
            } label: {
                Text(selectedItems.count == viewModel.screenshots.count ? "Tout désélectionner" : "Tout sélectionner")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: "4facfe"))
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
                    Text("Supprimer \(selectedItems.count) capture(s)")
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(AppColors.successGradient)
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
        if selectedItems.count == viewModel.screenshots.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(viewModel.screenshots.map { $0.id })
        }
    }

    private func deleteSelectedPhotos() async {
        isDeleting = true

        let itemsToDelete = viewModel.screenshots.filter { selectedItems.contains($0.id) }
        let success = await viewModel.deleteItems(itemsToDelete)

        if success {
            viewModel.removeFromScreenshots(selectedItems)
            selectedItems.removeAll()
        }

        isDeleting = false
    }
}

#Preview {
    NavigationStack {
        ScreenshotsView()
            .environmentObject(CleanerViewModel())
    }
}
