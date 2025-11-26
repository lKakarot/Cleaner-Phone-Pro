//
//  BurstsView.swift
//  Cleaner Phone Pro
//
//  Vue pour gérer les photos en rafale (burst)
//

import SwiftUI
import Photos

struct BurstsView: View {
    @EnvironmentObject var viewModel: CleanerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedForDeletion: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var expandedGroups: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if viewModel.burstGroups.isEmpty {
                    emptyState
                } else {
                    ForEach(viewModel.burstGroups) { group in
                        BurstGroupCard(
                            group: group,
                            isExpanded: expandedGroups.contains(group.id),
                            selectedForDeletion: $selectedForDeletion,
                            onToggleExpand: {
                                withAnimation(.spring(response: 0.3)) {
                                    if expandedGroups.contains(group.id) {
                                        expandedGroups.remove(group.id)
                                    } else {
                                        expandedGroups.insert(group.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Rafales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selectedForDeletion.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Text("Supprimer (\(selectedForDeletion.count))")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .alert("Supprimer les photos ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { await deleteSelected() }
            }
        } message: {
            Text("Les \(selectedForDeletion.count) photos sélectionnées seront supprimées.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)

            Text("Aucune rafale")
                .font(.headline)

            Text("Vous n'avez pas de photos prises en mode rafale.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func deleteSelected() async {
        let itemsToDelete = viewModel.burstGroups.flatMap { $0.items }.filter { selectedForDeletion.contains($0.id) }
        let success = await viewModel.deleteItems(itemsToDelete)

        if success {
            // Mettre à jour les groupes
            for i in viewModel.burstGroups.indices.reversed() {
                viewModel.burstGroups[i].items.removeAll { selectedForDeletion.contains($0.id) }
                if viewModel.burstGroups[i].items.count <= 1 {
                    viewModel.burstGroups.remove(at: i)
                }
            }
            selectedForDeletion.removeAll()
        }
    }
}

// MARK: - Burst Group Card
struct BurstGroupCard: View {
    let group: BurstGroup
    let isExpanded: Bool
    @Binding var selectedForDeletion: Set<String>
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Thumbnail de la photo principale
                    if let representative = group.representativeItem {
                        PhotoThumbnail(asset: representative.asset, size: CGSize(width: 120, height: 120))
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(group.items.count) photos")
                            .font(.headline)

                        if let date = group.items.first?.creationDate {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .buttonStyle(.plain)

            // Photos expandées
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(group.items) { item in
                        BurstPhotoCell(
                            item: item,
                            isSelected: selectedForDeletion.contains(item.id),
                            isRepresentative: item.asset.representsBurst
                        ) {
                            if selectedForDeletion.contains(item.id) {
                                selectedForDeletion.remove(item.id)
                            } else {
                                selectedForDeletion.insert(item.id)
                            }
                        }
                    }
                }
                .padding(16)

                // Bouton sélection rapide
                HStack(spacing: 12) {
                    Button {
                        // Sélectionner toutes sauf la représentative
                        for item in group.items {
                            if !item.asset.representsBurst {
                                selectedForDeletion.insert(item.id)
                            }
                        }
                    } label: {
                        Text("Garder la meilleure")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "667eea"))
                            .clipShape(Capsule())
                    }

                    Button {
                        // Désélectionner toutes du groupe
                        for item in group.items {
                            selectedForDeletion.remove(item.id)
                        }
                    } label: {
                        Text("Tout garder")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Burst Photo Cell
struct BurstPhotoCell: View {
    let item: MediaItem
    let isSelected: Bool
    let isRepresentative: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                PhotoThumbnail(asset: item.asset, size: CGSize(width: 200, height: 200))
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Badge sélection
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "f5576c") : Color.white.opacity(0.8))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
                .padding(6)

                // Badge "Meilleure"
                if isRepresentative {
                    VStack {
                        Spacer()
                        HStack {
                            Text("Meilleure")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(hex: "667eea"))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .padding(6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BurstsView()
            .environmentObject(CleanerViewModel())
    }
}
