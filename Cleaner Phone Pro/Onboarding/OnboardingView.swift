//
//  OnboardingView.swift
//  Cleaner Phone Pro
//
//  Created by Claude on 27/11/2025.
//

import SwiftUI

// Note: OnboardingContainerView is now used directly from RootView
// This wrapper is kept for compatibility
struct OnboardingView: View {
    @StateObject private var viewModel = CleanerViewModel()

    var body: some View {
        OnboardingContainerView(viewModel: viewModel)
    }
}

// MARK: - Welcome Page (Page 1)

struct WelcomePageView: View {
    @State private var storageInfo = DeviceStorage.getStorageInfo()
    @State private var isRequestingAccess = false
    @State private var showAccessDeniedAlert = false
    @ObservedObject var preloader: OnboardingPreloader
    @Environment(\.colorScheme) private var colorScheme
    let onContinue: () -> Void

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(.secondaryLabel)
    }

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
            .foregroundColor(primaryTextColor)

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
                        .foregroundColor(primaryTextColor)
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
                        .foregroundColor(primaryTextColor)
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
                    .foregroundColor(primaryTextColor)
                Text("utilisés")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.purple)
            }

            Spacer()

            // Texte légal avec demande d'accès
            VStack(spacing: 4) {
                Text("CleanerPhone Pro doit accéder à vos photos pour libérer de l'espace.")
                    .foregroundColor(primaryTextColor)
                + Text(" Nous voulons protéger votre vie privée en toute transparence. En commençant, vous acceptez nos ")
                    .foregroundColor(secondaryTextColor)
                + Text("Conditions d'utilisation")
                    .foregroundColor(secondaryTextColor)
                    .underline()
                + Text(" et notre ")
                    .foregroundColor(secondaryTextColor)
                + Text("Politique de confidentialité")
                    .foregroundColor(secondaryTextColor)
                    .underline()
                + Text(".")
                    .foregroundColor(secondaryTextColor)
            }
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 30)

            // Bouton Commencer - demande l'accès aux photos
            Button(action: requestPhotoAccessAndContinue) {
                HStack(spacing: 10) {
                    if isRequestingAccess {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(preloader.hasAuthorization ? "Commencer" : "Autoriser l'accès aux photos")
                        .font(.system(size: 18, weight: .semibold))
                }
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
            .disabled(isRequestingAccess)
            .padding(.horizontal, 24)

            Spacer()
                .frame(height: 40)
        }
        .alert("Accès aux photos requis", isPresented: $showAccessDeniedAlert) {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Pour utiliser CleanerPhone Pro, veuillez autoriser l'accès aux photos dans les Réglages.")
        }
    }

    private func requestPhotoAccessAndContinue() {
        // If already authorized, start preloading and continue
        if preloader.hasAuthorization {
            preloader.startPreloading()
            onContinue()
            return
        }

        isRequestingAccess = true

        Task {
            let granted = await preloader.requestAuthorizationAndPreload()

            await MainActor.run {
                isRequestingAccess = false

                if granted {
                    // Access granted - preloading started, continue to next page
                    onContinue()
                } else {
                    // Access denied - show alert
                    showAccessDeniedAlert = true
                }
            }
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
