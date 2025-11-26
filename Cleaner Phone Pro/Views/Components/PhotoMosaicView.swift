//
//  PhotoMosaicView.swift
//  Cleaner Phone Pro
//
//  Mosaïque asymétrique style Google Photos
//

import SwiftUI
import Photos

// MARK: - Photo Mosaic View
struct PhotoMosaicView: View {
    let photos: [MediaItem]
    let height: CGFloat
    var onTap: (() -> Void)? = nil

    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            if photos.count >= 6 {
                asymmetricLayout
            } else if photos.count >= 4 {
                gridLayout4
            } else if photos.count >= 2 {
                gridLayout2
            } else if photos.count == 1 {
                singlePhoto
            } else {
                placeholderView
            }
        }
        .frame(height: height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    // MARK: - Asymmetric Layout (6+ photos)
    // ┌────────────┬───────┬───────┐
    // │            │   1   │   2   │
    // │     0      ├───────┼───────┤
    // │  (large)   │   3   │   4   │
    // │            ├───────┴───────┤
    // │            │    5 (+N)     │
    // └────────────┴───────────────┘
    private var asymmetricLayout: some View {
        HStack(spacing: spacing) {
            // Colonne gauche - grande photo
            MosaicCell(
                asset: photos[0].asset,
                showCount: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Colonne droite - 5 petites photos
            VStack(spacing: spacing) {
                // Row 1
                HStack(spacing: spacing) {
                    MosaicCell(asset: photos[1].asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MosaicCell(asset: photos[2].asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Row 2
                HStack(spacing: spacing) {
                    MosaicCell(asset: photos[3].asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MosaicCell(asset: photos[4].asset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Row 3 - full width avec compteur
                MosaicCell(
                    asset: photos[5].asset,
                    showCount: photos.count > 6 ? photos.count - 6 : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Grid 2x2 Layout (4-5 photos)
    private var gridLayout4: some View {
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                MosaicCell(asset: photos[0].asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MosaicCell(asset: photos[1].asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack(spacing: spacing) {
                MosaicCell(asset: photos[2].asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MosaicCell(
                    asset: photos[3].asset,
                    showCount: photos.count > 4 ? photos.count - 4 : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Grid 1x2 Layout (2-3 photos)
    private var gridLayout2: some View {
        HStack(spacing: spacing) {
            MosaicCell(asset: photos[0].asset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            MosaicCell(
                asset: photos[1].asset,
                showCount: photos.count > 2 ? photos.count - 2 : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Single Photo
    private var singlePhoto: some View {
        MosaicCell(asset: photos[0].asset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Placeholder
    private var placeholderView: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color(hex: "667eea").opacity(0.2),
                        Color(hex: "764ba2").opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("Vos photos apparaîtront ici")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
    }
}

// MARK: - Mosaic Cell
struct MosaicCell: View {
    let asset: PHAsset
    var showCount: Int? = nil

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
                                .scaleEffect(0.6)
                        }
                }

                // Overlay "+N" pour les photos supplémentaires
                if let count = showCount, count > 0 {
                    Rectangle()
                        .fill(.black.opacity(0.5))

                    Text("+\(count)")
                        .font(.system(size: min(geo.size.width, geo.size.height) * 0.25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .clipped()
        .task(id: asset.localIdentifier) {
            await loadImage()
        }
    }

    private func loadImage() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .fast
        options.isSynchronous = false

        let targetSize = CGSize(width: 400, height: 400)

        let loadedImage = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }

        await MainActor.run {
            self.image = loadedImage
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        PhotoMosaicView(photos: [], height: 250)

        Text("Avec photos: voir sur device")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
}
