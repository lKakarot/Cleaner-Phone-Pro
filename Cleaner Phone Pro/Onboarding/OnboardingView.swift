//
//  OnboardingView.swift
//  Cleaner Phone Pro
//
//  Created by Claude on 27/11/2025.
//

import SwiftUI

struct OnboardingView: View {
    var body: some View {
        OnboardingContainerView()
    }
}

// MARK: - Welcome Page (Page 1)

struct WelcomePageView: View {
    @State private var storageInfo = DeviceStorage.getStorageInfo()
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 60)

            // Titre
            VStack(spacing: 4) {
                Text("Bienvenue à")
                    .font(.system(size: 34, weight: .bold))
                    .italic()
                Text("CleanerPhone Pro")
                    .font(.system(size: 34, weight: .bold))
            }
            .foregroundColor(.white)

            Spacer()
                .frame(height: 50)

            // Icônes Photos et iCloud
            HStack(spacing: 28) {
                // Photos
                VStack(spacing: 14) {
                    Image("photos_icon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(26)
                    Text("Photos")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }

                // iCloud
                VStack(spacing: 14) {
                    Image("icloud_icon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .cornerRadius(26)
                    Text("iCloud")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                }
            }

            Spacer()
                .frame(height: 40)

            // Barre de stockage
            StorageBarView(
                usedGB: storageInfo.usedGB,
                totalGB: storageInfo.totalGB
            )
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 16)

            // Texte stockage
            HStack(spacing: 4) {
                Text("\(storageInfo.usedGB) sur \(storageInfo.totalGB)Go")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                Text("utilisés")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.purple)
            }

            Spacer()

            // Texte légal
            VStack(spacing: 4) {
                Text("CleanerPhone Pro doit accéder à vos photos pour libérer de l'espace.")
                    .foregroundColor(.white)
                + Text(" Nous voulons protéger votre vie privée en toute transparence. En commençant, vous acceptez nos ")
                    .foregroundColor(.gray)
                + Text("Conditions d'utilisation")
                    .foregroundColor(.gray)
                    .underline()
                + Text(" et notre ")
                    .foregroundColor(.gray)
                + Text("Politique de confidentialité")
                    .foregroundColor(.gray)
                    .underline()
                + Text(".")
                    .foregroundColor(.gray)
            }
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 30)

            // Bouton Commencer
            Button(action: onContinue) {
                Text("Commencer")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 40)
        }
    }
}

// MARK: - Storage Bar View

struct StorageBarView: View {
    let usedGB: Int
    let totalGB: Int

    private var progress: CGFloat {
        guard totalGB > 0 else { return 0 }
        return CGFloat(usedGB) / CGFloat(totalGB)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 12)

                // Progress (bleu/violet comme dans le reste de l'app)
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 12)
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Device Storage Helper

struct DeviceStorage {
    let usedGB: Int
    let totalGB: Int
    let freeGB: Int

    static func getStorageInfo() -> DeviceStorage {
        let fileManager = FileManager.default

        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())

            if let totalSpace = attributes[.systemSize] as? Int64,
               let freeSpace = attributes[.systemFreeSize] as? Int64 {

                let totalGB = Int(totalSpace / 1_073_741_824) // bytes to GB
                let freeGB = Int(freeSpace / 1_073_741_824)
                let usedGB = totalGB - freeGB

                return DeviceStorage(usedGB: usedGB, totalGB: totalGB, freeGB: freeGB)
            }
        } catch {
            print("Erreur récupération stockage: \(error)")
        }

        // Valeurs par défaut si erreur
        return DeviceStorage(usedGB: 0, totalGB: 0, freeGB: 0)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
}
