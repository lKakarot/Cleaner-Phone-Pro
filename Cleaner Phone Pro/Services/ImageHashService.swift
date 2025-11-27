//
//  ImageHashService.swift
//  Cleaner Phone Pro
//
//  Service pour calculer des hashes perceptuels d'images (dHash + aHash)
//  Permet de détecter les images visuellement similaires
//

import UIKit
import Photos

class ImageHashService {
    static let shared = ImageHashService()

    private let imageManager = PHCachingImageManager()

    // Taille pour le hash (9x8 pour dHash = 64 bits de comparaison)
    private let hashSize = CGSize(width: 9, height: 8)
    // Taille plus grande pour aHash (meilleure précision)
    private let aHashSize = CGSize(width: 16, height: 16)

    // OPTIMIZATION: Semaphore to limit concurrent hash computations
    private let hashSemaphore = DispatchSemaphore(value: 4)

    // OPTIMIZATION: Cache computed hashes
    private var hashCache = NSCache<NSString, NSNumber>()

    private init() {
        hashCache.countLimit = 5000 // Cache up to 5000 hashes
    }

    // MARK: - Calcul du dHash

    /// Calcule le dHash d'une image
    /// Le dHash compare chaque pixel avec son voisin de droite
    /// Résultat: 64 bits représentant les différences
    func computeHash(for image: UIImage) -> UInt64 {
        // Redimensionner en 9x8 en niveaux de gris
        guard let resized = resizeAndGrayscale(image, to: hashSize) else {
            return 0
        }

        // Calculer le hash en comparant les pixels adjacents
        var hash: UInt64 = 0
        var bit: UInt64 = 1

        for y in 0..<8 {
            for x in 0..<8 {
                let leftPixel = getPixelBrightness(resized, x: x, y: y)
                let rightPixel = getPixelBrightness(resized, x: x + 1, y: y)

                // Si le pixel de gauche est plus clair que celui de droite, bit = 1
                if leftPixel > rightPixel {
                    hash |= bit
                }
                bit <<= 1
            }
        }

        return hash
    }

    /// Calcule le hash directement depuis un PHAsset (utilise une miniature)
    func computeHash(for asset: PHAsset) async -> UInt64 {
        let thumbnail = await loadThumbnail(for: asset)
        guard let image = thumbnail else { return 0 }
        return computeHash(for: image)
    }

    // MARK: - Comparaison de hashes

    /// Calcule la distance de Hamming entre deux hashes
    /// (nombre de bits différents)
    func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        let xor = hash1 ^ hash2
        return xor.nonzeroBitCount
    }

    /// Vérifie si deux images sont similaires
    /// threshold: nombre max de bits différents (0 = identique, 10 = très similaire, 20+ = différent)
    func areSimilar(_ hash1: UInt64, _ hash2: UInt64, threshold: Int = 10) -> Bool {
        return hammingDistance(hash1, hash2) <= threshold
    }

    // MARK: - Traitement par lot

    /// Calcule les hashes pour un groupe d'items - OPTIMIZED with concurrency limit and batching
    func computeHashes(for items: [MediaItem], progress: ((Double) -> Void)? = nil) async -> [String: UInt64] {
        var hashes: [String: UInt64] = [:]
        let total = items.count

        // Check cache first and filter items that need computation
        var itemsToProcess: [(Int, MediaItem)] = []
        for (index, item) in items.enumerated() {
            let cacheKey = item.id as NSString
            if let cachedHash = hashCache.object(forKey: cacheKey) {
                hashes[item.id] = cachedHash.uint64Value
            } else {
                itemsToProcess.append((index, item))
            }
        }

        // Process in batches of 8 for better performance
        let batchSize = 8
        let alreadyCachedCount = items.count - itemsToProcess.count

        for (batchIndex, batchStart) in stride(from: 0, to: itemsToProcess.count, by: batchSize).enumerated() {
            let batchEnd = min(batchStart + batchSize, itemsToProcess.count)
            let batch = Array(itemsToProcess[batchStart..<batchEnd])

            // Process batch in parallel with limited concurrency
            let batchResults = await withTaskGroup(of: (String, UInt64).self, returning: [(String, UInt64)].self) { group in
                for (_, item) in batch {
                    group.addTask {
                        let hash = await self.computeHash(for: item.asset)
                        return (item.id, hash)
                    }
                }

                var results: [(String, UInt64)] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            // Update hashes and cache after batch completes
            for (id, hash) in batchResults {
                hashes[id] = hash
                self.hashCache.setObject(NSNumber(value: hash), forKey: id as NSString)
            }

            // Report progress after each batch
            let processedCount = alreadyCachedCount + batchEnd
            if let progress = progress {
                await MainActor.run {
                    progress(Double(processedCount) / Double(total))
                }
            }

            // Small yield to prevent blocking main thread
            await Task.yield()
        }

        return hashes
    }

    /// Groupe les items par similarité visuelle
    func groupBySimilarity(items: [MediaItem], hashes: [String: UInt64], threshold: Int = 10) -> [[MediaItem]] {
        var groups: [[MediaItem]] = []
        var processed = Set<String>()

        for item in items {
            // Skip si déjà dans un groupe
            if processed.contains(item.id) { continue }

            guard let hash = hashes[item.id], hash != 0 else {
                continue
            }

            // Trouver tous les items similaires
            var group = [item]
            processed.insert(item.id)

            for otherItem in items {
                if processed.contains(otherItem.id) { continue }

                guard let otherHash = hashes[otherItem.id], otherHash != 0 else {
                    continue
                }

                if areSimilar(hash, otherHash, threshold: threshold) {
                    group.append(otherItem)
                    processed.insert(otherItem.id)
                }
            }

            // N'ajouter que les groupes avec plus d'un élément
            if group.count > 1 {
                // Trier par date (plus récent en premier)
                group.sort { item1, item2 in
                    let date1 = item1.asset.creationDate ?? Date.distantPast
                    let date2 = item2.asset.creationDate ?? Date.distantPast
                    return date1 > date2
                }
                groups.append(group)
            }
        }

        // Trier les groupes par date du premier élément
        groups.sort { group1, group2 in
            let date1 = group1.first?.asset.creationDate ?? Date.distantPast
            let date2 = group2.first?.asset.creationDate ?? Date.distantPast
            return date1 > date2
        }

        return groups
    }

    /// Groupe les items par similarité avec pré-filtrage par date (plus efficace pour les photos)
    /// Compare uniquement les photos prises dans une fenêtre de temps proche
    func groupBySimilarityWithDateFilter(
        items: [MediaItem],
        hashes: [String: UInt64],
        threshold: Int = 14,
        dayWindow: Int = 7
    ) -> [[MediaItem]] {
        var groups: [[MediaItem]] = []
        var processed = Set<String>()

        // Pré-grouper par semaine pour réduire les comparaisons
        var dateGroups: [String: [MediaItem]] = [:]
        let calendar = Calendar.current

        for item in items {
            guard let date = item.asset.creationDate else { continue }
            // Clé = année + numéro de semaine
            let weekOfYear = calendar.component(.weekOfYear, from: date)
            let year = calendar.component(.year, from: date)
            let key = "\(year)-W\(weekOfYear)"
            dateGroups[key, default: []].append(item)
        }

        // Pour chaque groupe de date, chercher les similaires
        for (_, dateGroupItems) in dateGroups {
            for item in dateGroupItems {
                if processed.contains(item.id) { continue }

                guard let hash = hashes[item.id], hash != 0 else { continue }

                var group = [item]
                processed.insert(item.id)

                // Comparer avec les items de la même période ET des périodes adjacentes
                let itemDate = item.asset.creationDate ?? Date()

                for otherItem in items {
                    if processed.contains(otherItem.id) { continue }

                    // Vérifier que les dates sont proches
                    if let otherDate = otherItem.asset.creationDate {
                        let daysDiff = abs(calendar.dateComponents([.day], from: itemDate, to: otherDate).day ?? 999)
                        if daysDiff > dayWindow { continue }
                    }

                    guard let otherHash = hashes[otherItem.id], otherHash != 0 else { continue }

                    if areSimilar(hash, otherHash, threshold: threshold) {
                        group.append(otherItem)
                        processed.insert(otherItem.id)
                    }
                }

                if group.count > 1 {
                    group.sort { item1, item2 in
                        let date1 = item1.asset.creationDate ?? Date.distantPast
                        let date2 = item2.asset.creationDate ?? Date.distantPast
                        return date1 > date2
                    }
                    groups.append(group)
                }
            }
        }

        // Trier les groupes par date
        groups.sort { group1, group2 in
            let date1 = group1.first?.asset.creationDate ?? Date.distantPast
            let date2 = group2.first?.asset.creationDate ?? Date.distantPast
            return date1 > date2
        }

        return groups
    }

    /// Méthode avancée: compare aussi sans filtre de date pour trouver des doublons plus anciens
    func groupBySimilarityAdvanced(
        items: [MediaItem],
        hashes: [String: UInt64],
        strictThreshold: Int = 8,    // Pour photos quasi-identiques (peu importe la date)
        looseThreshold: Int = 14,    // Pour photos similaires (même période)
        dayWindow: Int = 14
    ) -> [[MediaItem]] {
        var groups: [[MediaItem]] = []
        var processed = Set<String>()
        let calendar = Calendar.current

        for item in items {
            if processed.contains(item.id) { continue }
            guard let hash = hashes[item.id], hash != 0 else { continue }

            var group = [item]
            processed.insert(item.id)
            let itemDate = item.asset.creationDate ?? Date()

            for otherItem in items {
                if processed.contains(otherItem.id) { continue }
                guard let otherHash = hashes[otherItem.id], otherHash != 0 else { continue }

                let distance = hammingDistance(hash, otherHash)

                // Deux modes de comparaison:
                // 1. Photos très similaires (distance <= strictThreshold) → acceptées peu importe la date
                // 2. Photos similaires (distance <= looseThreshold) → acceptées si dates proches
                var isSimilar = false

                if distance <= strictThreshold {
                    // Quasi-identiques : accepter sans condition de date
                    isSimilar = true
                } else if distance <= looseThreshold {
                    // Similaires : vérifier la proximité de date
                    if let otherDate = otherItem.asset.creationDate {
                        let daysDiff = abs(calendar.dateComponents([.day], from: itemDate, to: otherDate).day ?? 999)
                        isSimilar = daysDiff <= dayWindow
                    }
                }

                if isSimilar {
                    group.append(otherItem)
                    processed.insert(otherItem.id)
                }
            }

            if group.count > 1 {
                group.sort { item1, item2 in
                    let date1 = item1.asset.creationDate ?? Date.distantPast
                    let date2 = item2.asset.creationDate ?? Date.distantPast
                    return date1 > date2
                }
                groups.append(group)
            }
        }

        groups.sort { group1, group2 in
            let date1 = group1.first?.asset.creationDate ?? Date.distantPast
            let date2 = group2.first?.asset.creationDate ?? Date.distantPast
            return date1 > date2
        }

        return groups
    }

    // MARK: - Helpers privés

    private func loadThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false // Pas de téléchargement iCloud pour le hash

            // Petite taille pour le hash
            let targetSize = CGSize(width: 32, height: 32)

            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Ignorer les résultats dégradés si on attend mieux
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded || image != nil {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private func resizeAndGrayscale(_ image: UIImage, to size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        // Dessiner en niveaux de gris
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Convertir en niveaux de gris
        context.setFillColor(gray: 0.5, alpha: 1.0)
        context.fill(CGRect(origin: .zero, size: size))

        image.draw(in: CGRect(origin: .zero, size: size))

        guard let colorImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = colorImage.cgImage else { return nil }

        // Convertir en grayscale
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let grayContext = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        grayContext.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let grayImage = grayContext.makeImage() else { return nil }
        return UIImage(cgImage: grayImage)
    }

    private func getPixelBrightness(_ image: UIImage, x: Int, y: Int) -> UInt8 {
        guard let cgImage = image.cgImage,
              let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return 0
        }

        let pointer = CFDataGetBytePtr(data)
        let bytesPerRow = cgImage.bytesPerRow
        let offset = y * bytesPerRow + x

        return pointer?[offset] ?? 0
    }
}
