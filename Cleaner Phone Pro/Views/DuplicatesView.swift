//
//  DuplicatesView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct DuplicatesView: View {
    @EnvironmentObject private var viewModel: CleanerViewModel
    @State private var selectedItems: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private var totalDuplicates: Int {
        viewModel.duplicateGroups.reduce(0) { $0 + $1.items.count - 1 }
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            if viewModel.duplicateGroups.isEmpty {
                emptyStateView
            } else {
                resultsView
            }
        }
        .navigationTitle("Doublons")
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
            Text("Supprimer \(selectedItems.count) photo(s) en double ?")
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

            Text("Aucun doublon")
                .font(.title2)
                .fontWeight(.bold)

            Text("Votre bibliothèque ne contient pas de photos en double")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Summary Card
                summaryCard
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                // Groups
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.duplicateGroups) { group in
                        DuplicateGroupCard(
                            group: group,
                            selectedItems: $selectedItems
                        )
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
                Text("\(viewModel.duplicateGroups.count) groupe(s)")
                    .font(.headline)

                Text("\(totalDuplicates) doublon(s) détecté(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                selectAllDuplicates()
            } label: {
                Text(selectedItems.count == totalDuplicates ? "Tout désélectionner" : "Tout sélectionner")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(hex: "667eea"))
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
            .background(AppColors.dangerGradient)
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

    private func selectAllDuplicates() {
        if selectedItems.count == totalDuplicates {
            selectedItems.removeAll()
        } else {
            for group in viewModel.duplicateGroups {
                for item in group.items.dropFirst() {
                    selectedItems.insert(item.id)
                }
            }
        }
    }

    private func deleteSelectedPhotos() async {
        isDeleting = true

        var itemsToDelete: [MediaItem] = []
        for group in viewModel.duplicateGroups {
            for item in group.items {
                if selectedItems.contains(item.id) {
                    itemsToDelete.append(item)
                }
            }
        }

        let success = await viewModel.deleteItems(itemsToDelete)

        if success {
            viewModel.removeFromDuplicates(selectedItems)
            selectedItems.removeAll()
        }

        isDeleting = false
    }
}

// MARK: - Duplicate Group Card
struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    @Binding var selectedItems: Set<String>

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "square.on.square")
                    .foregroundStyle(Color(hex: "f5576c"))

                Text("\(group.items.count) photos identiques")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if let date = group.items.first?.creationDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Photos Grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                    DuplicatePhotoCell(
                        item: item,
                        isOriginal: index == 0,
                        isSelected: selectedItems.contains(item.id)
                    ) {
                        if index > 0 {
                            if selectedItems.contains(item.id) {
                                selectedItems.remove(item.id)
                            } else {
                                selectedItems.insert(item.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Duplicate Photo Cell
struct DuplicatePhotoCell: View {
    let item: MediaItem
    let isOriginal: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnail(asset: item.asset, size: CGSize(width: 200, height: 200))
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if isOriginal {
                Text("Original")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: "667eea"))
                    .clipShape(Capsule())
                    .padding(4)
            } else {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "f5576c") : Color.white.opacity(0.9))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(hex: "f5576c") : .clear, lineWidth: 3)
        )
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    NavigationStack {
        DuplicatesView()
            .environmentObject(CleanerViewModel())
    }
}
