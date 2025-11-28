//
//  Cleaner_Phone_ProApp.swift
//  Cleaner Phone Pro
//
//  Created by Hasnae HANY on 26/11/2025.
//

import SwiftUI

@main
struct Cleaner_Phone_ProApp: App {

    init() {
        // Configure navigation bar appearance globally - Modern style
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor.systemBackground
        navAppearance.shadowColor = .clear // Remove shadow for cleaner look

        // Modern title style
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        // Custom back button - modern minimal style (no text, just arrow)
        let backImage = UIImage(systemName: "chevron.left")?
            .withConfiguration(UIImage.SymbolConfiguration(weight: .semibold))
        navAppearance.setBackIndicatorImage(backImage, transitionMaskImage: backImage)

        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().isTranslucent = true

        // Modern tint color - adapts to light/dark mode (label color = black in light, white in dark)
        UINavigationBar.appearance().tintColor = UIColor.label

        // Configure tab bar appearance globally - Modern style
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.systemBackground
        tabAppearance.shadowColor = .clear // Remove shadow for cleaner look

        // Modern tab bar item colors
        let normalColor = UIColor.secondaryLabel
        let selectedColor = UIColor.label

        tabAppearance.stackedLayoutAppearance.normal.iconColor = normalColor
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
        tabAppearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = UIColor.label
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

// MARK: - Root View (Onboarding → App)

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var viewModel = CleanerViewModel()
    @State private var isInitialized = false
    @State private var isLoading = true

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingContainerView(
                    viewModel: viewModel,
                    onComplete: {
                        hasCompletedOnboarding = true
                    }
                )
            } else if isLoading {
                // Loading screen while data loads
                LoadingView(viewModel: viewModel)
                    .onAppear {
                        if !isInitialized {
                            isInitialized = true
                            Task {
                                await viewModel.loadAllCategories()
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        isLoading = false
                                    }
                                }
                            }
                        }
                    }
            } else {
                ContentView(viewModel: viewModel)
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    @ObservedObject var viewModel: CleanerViewModel

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App icon placeholder
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    if viewModel.isAnalyzing {
                        Text(viewModel.analysisMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ProgressView(value: viewModel.analysisProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    } else {
                        Text("Chargement...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}
