//
//  MainTabView.swift
//  Cleaner Phone Pro
//
//  TabBar flottante personnalisée
//

import SwiftUI

enum Tab: String, CaseIterable {
    case home
    case swipe
    case settings

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .swipe: return "hand.draw.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Accueil"
        case .swipe: return "Tri"
        case .settings: return "Réglages"
        }
    }
}

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @StateObject private var viewModel = CleanerViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            // Contenu de l'onglet
            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .swipe:
                    SwipeCleanupView()
                case .settings:
                    SettingsView()
                }
            }
            .environmentObject(viewModel)

            // TabBar flottante
            floatingTabBar
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Floating TabBar (Glassy blur iOS style)
    private var floatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                TabBarButton(
                    tab: tab,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            ZStack {
                Capsule()
                    .fill(.regularMaterial)

                Capsule()
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
            }
        )
        .padding(.horizontal, 50)
        .padding(.bottom, 20)
    }
}

// MARK: - Tab Bar Button
struct TabBarButton: View {
    let tab: Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(hex: "667eea") : .gray)
                    .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(hex: "667eea") : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color(hex: "667eea"))
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("À propos") {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("Noter l'application")
                    }

                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(Color(hex: "667eea"))
                        Text("Nous contacter")
                    }

                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color(hex: "11998e"))
                        Text("Politique de confidentialité")
                    }
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

#Preview {
    MainTabView()
}
