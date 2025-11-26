//
//  BlurDetectionService.swift
//  Cleaner Phone Pro
//

import Foundation
import Photos
import UIKit
import Accelerate

class BlurDetectionService {

    static let shared = BlurDetectionService()

    private let blurThreshold: Double = 100.0

    private init() {}

    func findBlurryPhotos(in items: [MediaItem], progress: @escaping (Double) -> Void) async -> [MediaItem] {
        var blurryPhotos: [MediaItem] = []
        let total = Double(items.count)

        for (index, item) in items.enumerated() {
            guard item.mediaType == .photo else {
                await MainActor.run {
                    progress(Double(index + 1) / total)
                }
                continue
            }

            if let isBlurry = await isImageBlurry(asset: item.asset), isBlurry {
                blurryPhotos.append(item)
            }

            await MainActor.run {
                progress(Double(index + 1) / total)
            }
        }

        return blurryPhotos
    }

    private func isImageBlurry(asset: PHAsset) async -> Bool? {
        guard let image = await loadImage(for: asset) else {
            return nil
        }

        let variance = calculateLaplacianVariance(image: image)
        return variance < blurThreshold
    }

    private func loadImage(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true

            let targetSize = CGSize(width: 500, height: 500)

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func calculateLaplacianVariance(image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return Double.infinity }

        let width = cgImage.width
        let height = cgImage.height

        guard width > 0 && height > 0 else { return Double.infinity }

        var pixelData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return Double.infinity }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var laplacianKernel: [Float] = [
            0,  1,  0,
            1, -4,  1,
            0,  1,  0
        ]

        var floatPixels = pixelData.map { Float($0) }
        var outputPixels = [Float](repeating: 0, count: width * height)

        floatPixels.withUnsafeMutableBufferPointer { inputBuffer in
            outputPixels.withUnsafeMutableBufferPointer { outputBuffer in
                laplacianKernel.withUnsafeMutableBufferPointer { kernelBuffer in
                    var srcBuffer = vImage_Buffer(
                        data: inputBuffer.baseAddress,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width * MemoryLayout<Float>.size
                    )

                    var destBuffer = vImage_Buffer(
                        data: outputBuffer.baseAddress,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width * MemoryLayout<Float>.size
                    )

                    vImageConvolve_PlanarF(
                        &srcBuffer,
                        &destBuffer,
                        nil,
                        0, 0,
                        kernelBuffer.baseAddress!,
                        3, 3,
                        0,
                        vImage_Flags(kvImageEdgeExtend)
                    )
                }
            }
        }

        let mean = outputPixels.reduce(0, +) / Float(outputPixels.count)
        let variance = outputPixels.reduce(0) { sum, value in
            let diff = value - mean
            return sum + diff * diff
        } / Float(outputPixels.count)

        return Double(variance)
    }
}
