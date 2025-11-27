//
//  OnboardingContainerView.swift
//  Cleaner Phone Pro
//

import SwiftUI
import Photos

// MARK: - Onboarding Colors (adapts to light/dark mode)

struct OnboardingColors {
    @Environment(\.colorScheme) static var colorScheme

    static var background: Color {
        Color(.systemBackground)
    }

    static var secondaryBackground: Color {
        Color(.secondarySystemBackground)
    }

    static var primaryText: Color {
        Color(.label)
    }

    static var secondaryText: Color {
        Color(.secondaryLabel)
    }

    static var tertiaryText: Color {
        Color(.tertiaryLabel)
    }

    static var cardBackground: Color {
        Color(.secondarySystemBackground)
    }
}

// MARK: - Onboarding Preloader (loads photos during onboarding)

@MainActor
class OnboardingPreloader: ObservableObject {
    @Published var isPreloading = false
    @Published var hasAuthorization = false
    @Published var preloadProgress: Double = 0

    private var preloadTask: Task<Void, Never>?
    private weak var viewModel: CleanerViewModel?

    func setViewModel(_ viewModel: CleanerViewModel) {
        self.viewModel = viewModel
    }

    func checkAuthorizationStatus() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        hasAuthorization = (status == .authorized || status == .limited)
    }

    func requestAuthorizationAndPreload() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        hasAuthorization = (status == .authorized || status == .limited)

        if hasAuthorization {
            startPreloading()
        }

        return hasAuthorization
    }

    func startPreloading() {
        guard hasAuthorization && !isPreloading else { return }
        guard let viewModel = viewModel else { return }

        isPreloading = true

        preloadTask = Task {
            // Start the actual photo analysis NOW during onboarding!
            // This will analyze all categories while user browses onboarding pages
            await viewModel.loadAllCategories()

            await MainActor.run {
                preloadProgress = 1.0
                isPreloading = false
            }
        }
    }

    func cancelPreloading() {
        preloadTask?.cancel()
        isPreloading = false
    }
}

struct OnboardingContainerView: View {
    @ObservedObject var viewModel: CleanerViewModel
    @State private var currentPage = 0
    @State private var storageInfo = DeviceStorage.getStorageInfo()
    @StateObject private var preloader = OnboardingPreloader()
    @Environment(\.colorScheme) private var colorScheme

    var onComplete: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Background adapts to system theme
            (colorScheme == .dark ? Color(red: 0.02, green: 0.02, blue: 0.06) : Color(.systemBackground))
                .ignoresSafeArea()

            switch currentPage {
            case 0:
                WelcomePageView(
                    preloader: preloader,
                    onContinue: { currentPage = 1 }
                )
            case 1:
                DuplicatePhotosPageView(onContinue: { currentPage = 2 })
            case 2:
                OptimizeStoragePageView(storageInfo: storageInfo, onContinue: { currentPage = 3 })
            case 3:
                PaywallPageView(storageInfo: storageInfo, onClose: {
                    onComplete?()
                }, onSubscribe: {
                    onComplete?()
                })
            default:
                WelcomePageView(preloader: preloader, onContinue: { currentPage = 1 })
            }
        }
        .onAppear {
            // Connect preloader to viewModel so it can start analysis
            preloader.setViewModel(viewModel)
            preloader.checkAuthorizationStatus()
        }
    }
}

// MARK: - Progress Bar (2 segments)

struct OnboardingProgressBar: View {
    let currentStep: Int // 0, 1

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorForStep(index))
                    .frame(height: 6)
            }
        }
        .padding(.horizontal, 24)
    }

    private func colorForStep(_ index: Int) -> Color {
        if index <= currentStep {
            return .blue
        } else {
            return Color.gray.opacity(0.4)
        }
    }
}

// MARK: - Sparkle Icon

struct SparkleIcon: View {
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: 24))
            .foregroundColor(.gray.opacity(0.6))
    }
}

// MARK: - Bottom Links

struct OnboardingBottomLinks: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Politique de confidentialité")
                .underline()
            Text("et")
            Text("Conditions d'utilisation")
                .underline()
        }
        .font(.system(size: 12))
        .foregroundColor(.gray)
    }
}

// MARK: - Page 2: Supprimer les photos en double

struct DuplicatePhotosPageView: View {
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(.secondaryLabel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Progress bar
            OnboardingProgressBar(currentStep: 0)

            // Sparkle icon
            HStack {
                Spacer()
                SparkleIcon()
                    .padding(.trailing, 24)
                    .padding(.top, 8)
            }

            Spacer().frame(height: 10)

            // Titre
            VStack(spacing: 16) {
                Text("Supprimer les\nphotos en double")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(primaryTextColor)

                Text("Éliminez instantanément les photos en\ndouble et récupérez votre stockage !")
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            // Mockup photos
            DuplicatePhotosMockup()

            Spacer()

            // Bouton Suivant
            Button(action: onContinue) {
                Text("Suivant")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            OnboardingBottomLinks()

            Spacer().frame(height: 30)
        }
    }
}

// MARK: - Duplicate Photos Mockup with Animation

struct DuplicatePhotosMockup: View {
    @State private var animationPhase = 0
    @State private var duplicateOffsets: [CGSize] = [.zero, .zero, .zero]
    @State private var duplicateOpacities: [Double] = [1, 1, 1]
    @State private var duplicateScales: [CGFloat] = [1, 1, 1]
    @State private var trashScale: CGFloat = 1.0

    let timer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    // Couleurs pour simuler différentes photos
    let photoColors: [(Color, Color)] = [
        (Color.blue.opacity(0.4), Color.purple.opacity(0.4)),
        (Color.orange.opacity(0.4), Color.red.opacity(0.4)),
        (Color.green.opacity(0.4), Color.teal.opacity(0.4))
    ]

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            // Photos principales à gauche (originaux à garder)
            VStack(spacing: 16) {
                ForEach(0..<3) { index in
                    PhotoCard(
                        colors: photoColors[index],
                        size: 110,
                        showCheckCircle: true,
                        isSelected: false
                    )
                }
            }

            // Photos doublons + corbeille à droite
            VStack(spacing: 16) {
                ForEach(0..<3) { index in
                    PhotoCard(
                        colors: photoColors[index],
                        size: 70,
                        showCheckCircle: false,
                        isSelected: true
                    )
                    .scaleEffect(duplicateScales[index])
                    .offset(duplicateOffsets[index])
                    .opacity(duplicateOpacities[index])
                }

                // Corbeille
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "trash.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                .scaleEffect(trashScale)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 40)
        .onAppear {
            startAnimation()
        }
        .onReceive(timer) { _ in
            startAnimation()
        }
    }

    private func startAnimation() {
        // Reset
        duplicateOffsets = [.zero, .zero, .zero]
        duplicateOpacities = [1, 1, 1]
        duplicateScales = [1, 1, 1]
        trashScale = 1.0

        // Animer chaque photo vers la corbeille avec un délai
        for index in 0..<3 {
            let delay = Double(index) * 0.4

            withAnimation(.easeInOut(duration: 0.6).delay(delay + 0.5)) {
                // Descendre vers la corbeille
                duplicateOffsets[index] = CGSize(
                    width: 0,
                    height: CGFloat((2 - index) * 86 + 60)
                )
                duplicateScales[index] = 0.3
            }

            withAnimation(.easeOut(duration: 0.3).delay(delay + 1.0)) {
                duplicateOpacities[index] = 0
            }
        }

        // Animation de la corbeille qui "reçoit" les photos
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(1.0)) {
            trashScale = 1.15
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(1.3)) {
            trashScale = 1.0
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(1.7)) {
            trashScale = 1.15
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(2.0)) {
            trashScale = 1.0
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(2.4)) {
            trashScale = 1.15
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(2.7)) {
            trashScale = 1.0
        }
    }
}

struct PhotoCard: View {
    let colors: (Color, Color)
    let size: CGFloat
    let showCheckCircle: Bool
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Photo avec dégradé
            RoundedRectangle(cornerRadius: size * 0.12)
                .fill(
                    LinearGradient(
                        colors: [colors.0, colors.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Cercle de sélection (pour les originaux)
            if showCheckCircle {
                Circle()
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .padding(size * 0.08)
            }

            // Checkmark rouge (pour les doublons sélectionnés)
            if isSelected {
                Circle()
                    .fill(Color.red)
                    .frame(width: size * 0.25, height: size * 0.25)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.12, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: size * 0.08, y: -size * 0.08)
            }
        }
    }
}

// MARK: - Page 3: Optimiser le stockage

struct OptimizeStoragePageView: View {
    let storageInfo: DeviceStorage
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(.secondaryLabel)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 20)

            // Progress bar
            OnboardingProgressBar(currentStep: 1)

            // Sparkle icon
            HStack {
                Spacer()
                SparkleIcon()
                    .padding(.trailing, 24)
                    .padding(.top, 8)
            }

            Spacer().frame(height: 10)

            // Titre
            VStack(spacing: 16) {
                Text("Optimiser le\nstockage de l'iPhone")
                    .font(.system(size: 32, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(primaryTextColor)

                Text("Libérez jusqu'à 80 % de votre stockage et\nobtenez plus d'espace.")
                    .font(.system(size: 16))
                    .multilineTextAlignment(.center)
                    .foregroundColor(secondaryTextColor)
            }

            Spacer()

            // Icônes Photos et iCloud
            HStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image("photos_icon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(22)
                    Text("Photos")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(primaryTextColor)
                }

                VStack(spacing: 14) {
                    Image("icloud_icon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(22)
                    Text("iCloud")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(primaryTextColor)
                }
            }

            Spacer().frame(height: 30)

            // Storage info
            HStack {
                Text("iPhone")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                Spacer()
                Text("\(storageInfo.usedGB) GB de \(storageInfo.totalGB) GB utilisés")
                    .font(.system(size: 14))
                    .foregroundColor(secondaryTextColor)
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 12)

            // Barre de stockage détaillée
            DetailedStorageBar(storageInfo: storageInfo)
                .padding(.horizontal, 40)

            Spacer().frame(height: 12)

            // Légende
            StorageLegend()
                .padding(.horizontal, 40)

            Spacer()

            // Note
            Text("*Basé sur les données internes de CleanerPhone Pro")
                .font(.system(size: 12))
                .foregroundColor(secondaryTextColor)

            Spacer().frame(height: 20)

            // Bouton Suivant
            Button(action: onContinue) {
                Text("Suivant")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            OnboardingBottomLinks()

            Spacer().frame(height: 30)
        }
    }
}

// MARK: - Detailed Storage Bar with Animation

struct DetailedStorageBar: View {
    let storageInfo: DeviceStorage

    // Pourcentage utilisé réel
    private var usedPercentage: CGFloat {
        guard storageInfo.totalGB > 0 else { return 0.5 }
        return CGFloat(storageInfo.usedGB) / CGFloat(storageInfo.totalGB)
    }

    // Estimation de la répartition (basée sur des moyennes typiques)
    private var photosPercentage: CGFloat { usedPercentage * 0.45 }  // ~45% du stockage utilisé = photos
    private var appsPercentage: CGFloat { usedPercentage * 0.30 }   // ~30% = apps
    private var iosPercentage: CGFloat { usedPercentage * 0.15 }    // ~15% = iOS
    private var systemPercentage: CGFloat { usedPercentage * 0.10 } // ~10% = système

    @State private var currentPhotosWidth: CGFloat = 0
    @State private var hasAnimated = false

    let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                // Photos (rouge) - cette partie se vide
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red)
                    .frame(width: geometry.size.width * currentPhotosWidth)

                // Applications (orange)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange)
                    .frame(width: geometry.size.width * appsPercentage)

                // iOS (gris)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray)
                    .frame(width: geometry.size.width * iosPercentage)

                // Données système (gris foncé)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: geometry.size.width * systemPercentage)

                Spacer()
            }
        }
        .frame(height: 10)
        .onAppear {
            currentPhotosWidth = photosPercentage
            startAnimation()
        }
        .onReceive(timer) { _ in
            restartAnimation()
        }
    }

    private func startAnimation() {
        // Attendre un peu puis animer la réduction de 80%
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 1.5)) {
                // Réduire les photos de 80%
                currentPhotosWidth = photosPercentage * 0.2
            }
        }
    }

    private func restartAnimation() {
        // Reset
        currentPhotosWidth = photosPercentage
        // Relancer l'animation
        startAnimation()
    }
}

// MARK: - Storage Legend

struct StorageLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                LegendItem(color: .red, text: "Photos")
                LegendItem(color: .orange, text: "Applications")
                LegendItem(color: .gray, text: "iOS")
            }
            HStack {
                LegendItem(color: Color.gray.opacity(0.5), text: "Données système")
            }
        }
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Page 4: Paywall

struct PaywallPageView: View {
    let storageInfo: DeviceStorage
    let onClose: () -> Void
    let onSubscribe: () -> Void

    @State private var freeTrialEnabled = true
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(.secondaryLabel)
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(.secondarySystemBackground)
    }

    // Pourcentage utilisé
    private var usedPercentage: Int {
        guard storageInfo.totalGB > 0 else { return 73 }
        return Int((Double(storageInfo.usedGB) / Double(storageInfo.totalGB)) * 100)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {}) {
                    Text("Restaurer l'achat")
                        .font(.system(size: 14))
                        .foregroundColor(secondaryTextColor)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer().frame(height: 20)

            // Titre
            VStack(spacing: 12) {
                Text("Nettoyez le stockage")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(primaryTextColor)

                Text("Dites adieu à ce dont vous n'avez pas besoin")
                    .font(.system(size: 15))
                    .foregroundColor(secondaryTextColor)
            }

            Spacer().frame(height: 24)

            // Icônes avec badges
            HStack(spacing: 28) {
                // Photos avec badge
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        Image("photos_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .cornerRadius(20)
                        Text("Photos")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(primaryTextColor)
                    }

                    // Badge
                    Text("416")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 10, y: -5)
                }

                // iCloud avec badge
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 10) {
                        Image("icloud_icon")
                            .renderingMode(.original)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 90, height: 90)
                            .cornerRadius(20)
                        Text("iCloud")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(primaryTextColor)
                    }

                    // Badge
                    Text("224")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 10, y: -5)
                }
            }

            Spacer().frame(height: 20)

            // Barre de stockage simple
            PaywallStorageBar(usedPercentage: usedPercentage)
                .padding(.horizontal, 40)

            Spacer().frame(height: 12)

            // Texte stockage
            HStack(spacing: 4) {
                Text("\(usedPercentage)")
                    .foregroundColor(.red)
                    .fontWeight(.bold)
                Text("sur 100% utilisé")
                    .foregroundColor(primaryTextColor)
            }
            .font(.system(size: 16))

            Spacer().frame(height: 24)

            // Carte Pro
            ProFeatureCard()
                .padding(.horizontal, 20)

            Spacer().frame(height: 16)

            // Toggle essai gratuit
            HStack {
                Text("Essai gratuit activé")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(primaryTextColor)

                Spacer()

                Toggle("", isOn: $freeTrialEnabled)
                    .labelsHidden()
                    .tint(.blue)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(cardBackgroundColor)
            .cornerRadius(12)
            .padding(.horizontal, 20)

            Spacer().frame(height: 16)

            // Échéances
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(primaryTextColor)
                            .frame(width: 8, height: 8)
                        Text("Échéance aujourd'hui")
                            .font(.system(size: 14))
                            .foregroundColor(primaryTextColor)
                    }

                    Spacer()

                    Text("7 jours gratuits")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(10)

                    Text("€0,00")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }

                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .stroke(secondaryTextColor, lineWidth: 1)
                            .frame(width: 8, height: 8)
                        Text("Échéance 4 décembre 2025")
                            .font(.system(size: 14))
                            .foregroundColor(secondaryTextColor)
                    }

                    Spacer()

                    Text("€8,99")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Bouton principal
            Button(action: onSubscribe) {
                Text("Essayer gratuitement")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.blue)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 20)

            Spacer().frame(height: 16)

            // Footer
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 12))
                    Text("Sécurisé avec Apple")
                        .font(.system(size: 12))
                }
                .foregroundColor(secondaryTextColor)

                HStack(spacing: 4) {
                    Text("Confidentialité")
                        .underline()
                    Text("et")
                    Text("Conditions")
                        .underline()
                }
                .font(.system(size: 12))
                .foregroundColor(secondaryTextColor)
            }

            Spacer().frame(height: 20)
        }
    }
}

// MARK: - Paywall Storage Bar

struct PaywallStorageBar: View {
    let usedPercentage: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Partie utilisée (rouge)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red)
                    .frame(width: geometry.size.width * CGFloat(usedPercentage) / 100)

                // Partie libre (gris)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.4))
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Pro Feature Card

struct ProFeatureCard: View {
    @Environment(\.colorScheme) private var colorScheme

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : Color(.label)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .gray : Color(.secondaryLabel)
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color(.secondarySystemBackground)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CleanerPhone Pro")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(primaryTextColor)

            Text("Nettoyage intelligent, compresseur vidéo, stockage secret, gestion des contacts, sans annonces ni limites.")
                .font(.system(size: 14))
                .foregroundColor(secondaryTextColor)
                .lineSpacing(2)

            Text("Gratuit pendant 7 jours, puis €8,99/semaine")
                .font(.system(size: 14))
                .foregroundColor(primaryTextColor.opacity(0.8))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor)
        .cornerRadius(14)
    }
}

// MARK: - Preview

#Preview {
    OnboardingContainerView(viewModel: CleanerViewModel())
}
