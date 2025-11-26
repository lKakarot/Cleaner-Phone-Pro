//
//  DuplicateDetectionService.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos
import UIKit
import CryptoKit

class DuplicateDetectionService {

    static let shared = DuplicateDetectionService()

    private init() {}

    func findDuplicates(in items: [MediaItem], progress: @escaping (Double) -> Void) async -> [DuplicateGroup] {
        var hashGroups: [String: [MediaItem]] = [:]
        let total = Double(items.count)

        for (index, item) in items.enumerated() {
            if let hash = await computeImageHash(for: item.asset) {
                if hashGroups[hash] != nil {
                    hashGroups[hash]?.append(item)
                } else {
                    hashGroups[hash] = [item]
                }
            }

            await MainActor.run {
                progress(Double(index + 1) / total)
            }
        }

        let duplicateGroups = hashGroups
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(items: $0.value) }
            .sorted { $0.items.count > $1.items.count }

        return duplicateGroups
    }

    func findSimilarPhotos(in items: [MediaItem], progress: @escaping (Double) -> Void) async -> [DuplicateGroup] {
        var perceptualHashes: [(item: MediaItem, hash: [Bool])] = []
        let total = Double(items.count)

        for (index, item) in items.enumerated() {
            if let hash = await computePerceptualHash(for: item.asset) {
                perceptualHashes.append((item, hash))
            }

            await MainActor.run {
                progress(Double(index + 1) / total * 0.5)
            }
        }

        var groups: [[MediaItem]] = []
        var used = Set<String>()

        for i in 0..<perceptualHashes.count {
            guard !used.contains(perceptualHashes[i].item.id) else { continue }

            var group = [perceptualHashes[i].item]
            used.insert(perceptualHashes[i].item.id)

            for j in (i + 1)..<perceptualHashes.count {
                guard !used.contains(perceptualHashes[j].item.id) else { continue }

                let distance = hammingDistance(perceptualHashes[i].hash, perceptualHashes[j].hash)
                if distance < 10 {
                    group.append(perceptualHashes[j].item)
                    used.insert(perceptualHashes[j].item.id)
                }
            }

            if group.count > 1 {
                groups.append(group)
            }

            await MainActor.run {
                progress(0.5 + Double(i + 1) / Double(perceptualHashes.count) * 0.5)
            }
        }

        return groups.map { DuplicateGroup(items: $0) }
    }

    private func computeImageHash(for asset: PHAsset) async -> String? {
        guard let imageData = await loadImageData(for: asset) else {
            return nil
        }

        let hash = SHA256.hash(data: imageData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func computePerceptualHash(for asset: PHAsset) async -> [Bool]? {
        guard let image = await loadThumbnail(for: asset, size: CGSize(width: 32, height: 32)),
              let grayscale = convertToGrayscale(image) else {
            return nil
        }

        let pixels = getPixelValues(from: grayscale)
        guard pixels.count == 1024 else { return nil }

        let average = pixels.reduce(0, +) / Double(pixels.count)
        return pixels.map { $0 > average }
    }

    private func hammingDistance(_ a: [Bool], _ b: [Bool]) -> Int {
        guard a.count == b.count else { return Int.max }
        return zip(a, b).filter { $0 != $1 }.count
    }

    private func loadImageData(for asset: PHAsset) async -> Data? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false

            PHImageManager.default().requestImageDataAndOrientation(
                for: asset,
                options: options
            ) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func loadThumbnail(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .exact
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func convertToGrayscale(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIPhotoEffectMono") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)

        guard let outputImage = filter.outputImage,
              let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: outputCGImage)
    }

    private func getPixelValues(from image: UIImage) -> [Double] {
        guard let cgImage = image.cgImage else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var values: [Double] = []
        for i in stride(from: 0, to: pixelData.count, by: bytesPerPixel) {
            let gray = Double(pixelData[i])
            values.append(gray)
        }

        return values
    }
}
