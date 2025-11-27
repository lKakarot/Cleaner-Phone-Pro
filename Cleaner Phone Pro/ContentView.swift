//
//  ContentView.swift
//  Cleaner Phone Pro
//
//  Created by Hasnae HANY on 26/11/2025.
//

import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var viewModel = CleanerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    PermissionDeniedView()
                } else if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.categories) { categoryData in
                                NavigationLink(destination: CategoryDetailView(
                                    viewModel: viewModel,
                                    categoryData: categoryData
                                )) {
                                    CategoryCardView(categoryData: categoryData)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .overlay {
                        if viewModel.isLoading {
                            LoadingOverlay()
                        }
                    }
                }
            }
            .navigationTitle("Cleaner Pro")
        }
        .task {
            // Request permission on launch (shows system popup if not determined)
            await viewModel.requestAccess()
        }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Accès refusé")
                .font(.title2)
                .fontWeight(.bold)

            Text("Veuillez autoriser l'accès aux photos dans les Réglages de votre appareil.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Ouvrir les Réglages")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

struct LoadingOverlay: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Fond flouté
            Color(.systemBackground).opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Icône animée
                ZStack {
                    // Cercle extérieur qui pulse
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .opacity(isAnimating ? 0.3 : 0.8)

                    // Cercle qui tourne
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))

                    // Icône centrale
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Analyse en cours...")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
            )
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    ContentView()
}
