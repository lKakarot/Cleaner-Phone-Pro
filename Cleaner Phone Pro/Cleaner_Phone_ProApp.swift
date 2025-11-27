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
        // Configure navigation bar appearance globally
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor.systemBackground
        navAppearance.shadowColor = UIColor.separator

        // Background effect for all states
        navAppearance.backgroundEffect = nil
        navAppearance.backgroundImage = UIImage()

        // Apply to all navigation bar states
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().isTranslucent = false
        UINavigationBar.appearance().barTintColor = UIColor.systemBackground

        // Configure tab bar appearance globally (fix transparent TabBar when scrolling to bottom)
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor.systemBackground

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
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

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingContainerView(
                    viewModel: viewModel,
                    onComplete: {
                        hasCompletedOnboarding = true
                    }
                )
            } else {
                ContentView(viewModel: viewModel)
                    .onAppear {
                        // Load photos if returning user (already completed onboarding)
                        if !isInitialized {
                            isInitialized = true
                            Task {
                                await viewModel.loadAllCategories()
                            }
                        }
                    }
            }
        }
    }
}
