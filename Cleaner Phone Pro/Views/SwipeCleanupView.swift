//
//  SwipeCleanupView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

struct SwipeCleanupView: View {
    @EnvironmentObject private var viewModel: CleanerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var currentIndex = 0
    @State private var photosToDelete: [MediaItem] = []
    @State private var photosKept = 0
    @State private var showSummary = false
    @State private var dragOffset: CGSize = .zero
    @State private var isDeleting = false

    private var photos: [MediaItem] {
        viewModel.allPhotos
    }

    private var currentPhoto: MediaItem? {
        guard currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            AnimatedGradientBackground()

            if photos.isEmpty {
                emptyView
            } else if showSummary {
                summaryView
            } else {
                swipeContent
            }
        }
        .navigationTitle("Nettoyage rapide")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Empty View
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Aucune photo à trier")
                .font(.title2)
                .fontWeight(.bold)

            Text("Votre bibliothèque est vide")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Swipe Content
    private var swipeContent: some View {
        VStack(spacing: 0) {
            // Progress
            progressHeader
                .padding(.horizontal, 20)
                .padding(.top, 10)

            // Cards Stack
            ZStack {
                // Background cards (next photos preview)
                ForEach(0..<min(3, photos.count - currentIndex), id: \.self) { offset in
                    let index = currentIndex + (2 - offset)
                    if index < photos.count && offset < 2 {
                        CardView(photo: photos[index])
                            .scaleEffect(1 - CGFloat(2 - offset) * 0.05)
                            .offset(y: CGFloat(2 - offset) * 8)
                            .opacity(0.5)
                    }
                }

                // Current card
                if let photo = currentPhoto {
                    CardView(photo: photo)
                        .offset(dragOffset)
                        .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                        .gesture(dragGesture)
                        .overlay(swipeIndicators)
                        .animation(.interactiveSpring(response: 0.4, dampingFraction: 0.7), value: dragOffset)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            // Action Buttons
            actionButtons
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
        }
    }

    // MARK: - Progress Header
    private var progressHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(currentIndex + 1) sur \(photos.count)")
                        .font(.headline)
                    Text("\(photosToDelete.count) à supprimer")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }

                Spacer()

                // Mini stats
                HStack(spacing: 16) {
                    Label("\(photosKept)", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)

                    Label("\(photosToDelete.count)", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.primaryGradient)
                        .frame(width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(max(photos.count, 1)))
                        .animation(.easeInOut, value: currentIndex)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Swipe Indicators
    private var swipeIndicators: some View {
        ZStack {
            // Keep indicator
            HStack {
                Spacer()
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                    Text("GARDER")
                        .font(.headline)
                        .fontWeight(.black)
                }
                .foregroundStyle(.green)
                .padding(30)
                .opacity(dragOffset.width > 0 ? min(dragOffset.width / 100, 1) : 0)
                Spacer()
            }

            // Delete indicator
            HStack {
                Spacer()
                VStack {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 60))
                    Text("SUPPRIMER")
                        .font(.headline)
                        .fontWeight(.black)
                }
                .foregroundStyle(.pink)
                .padding(30)
                .opacity(dragOffset.width < 0 ? min(-dragOffset.width / 100, 1) : 0)
                Spacer()
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack(spacing: 60) {
            // Delete button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    performSwipe(direction: .left)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "ff6b6b"), Color(hex: "ee5a5a")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: .pink.opacity(0.4), radius: 12, y: 6)

                    Image(systemName: "xmark")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }

            // Keep button
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    performSwipe(direction: .right)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "51cf66"), Color(hex: "40c057")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 70, height: 70)
                        .shadow(color: .green.opacity(0.4), radius: 12, y: 6)

                    Image(systemName: "checkmark")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
        }
    }

    // MARK: - Summary View
    private var summaryView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(AppColors.successGradient)
                    .frame(width: 100, height: 100)
                    .shadow(color: Color(hex: "4facfe").opacity(0.5), radius: 20, y: 10)

                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Text("Tri terminé !")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Vous avez passé en revue \(photos.count) photos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stats
            HStack(spacing: 40) {
                VStack(spacing: 8) {
                    Text("\(photosKept)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("Gardées")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(width: 1, height: 50)

                VStack(spacing: 8) {
                    Text("\(photosToDelete.count)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.pink)
                    Text("À supprimer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            Spacer()

            // Actions
            VStack(spacing: 12) {
                if !photosToDelete.isEmpty {
                    Button {
                        Task { await confirmDeletion() }
                    } label: {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "trash")
                                Text("Supprimer \(photosToDelete.count) photo(s)")
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
                }

                Button {
                    dismiss()
                } label: {
                    Text("Terminer")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Drag Gesture
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 120

                if value.translation.width > threshold {
                    performSwipe(direction: .right)
                } else if value.translation.width < -threshold {
                    performSwipe(direction: .left)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Actions
    private enum SwipeDirection {
        case left, right
    }

    private func performSwipe(direction: SwipeDirection) {
        guard let photo = currentPhoto else { return }

        // Animate card off screen
        withAnimation(.easeOut(duration: 0.3)) {
            dragOffset = CGSize(
                width: direction == .right ? 500 : -500,
                height: 0
            )
        }

        // Record action
        if direction == .left {
            photosToDelete.append(photo)
        } else {
            photosKept += 1
        }

        // Move to next or show summary
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dragOffset = .zero

            if currentIndex < photos.count - 1 {
                currentIndex += 1
            } else {
                showSummary = true
            }
        }
    }

    private func confirmDeletion() async {
        isDeleting = true
        let success = await viewModel.deleteItems(photosToDelete)
        isDeleting = false

        if success {
            photosToDelete.removeAll()
        }
    }
}

// MARK: - Card View
struct CardView: View {
    let photo: MediaItem
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Photo
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            ProgressView()
                                .tint(.gray)
                        }
                }

                // Date overlay
                VStack {
                    Spacer()
                    HStack {
                        if let date = photo.creationDate {
                            Text(date, style: .date)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
        }
        .aspectRatio(3/4, contentMode: .fit)
        .task(id: photo.id) {
            image = await PhotoLibraryService.shared.loadImage(
                for: photo.asset,
                targetSize: CGSize(width: 800, height: 1000)
            )
        }
    }
}

#Preview {
    NavigationStack {
        SwipeCleanupView()
            .environmentObject(CleanerViewModel())
    }
}
