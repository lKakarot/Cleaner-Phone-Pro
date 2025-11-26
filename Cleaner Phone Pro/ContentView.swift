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

                if viewModel.authorizationStatus == .notDetermined {
                    PermissionRequestView {
                        Task {
                            await viewModel.requestAccess()
                        }
                    }
                } else if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    PermissionDeniedView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.categories) { categoryData in
                                CategoryCardView(categoryData: categoryData)
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
            if viewModel.authorizationStatus == .authorized || viewModel.authorizationStatus == .limited {
                await viewModel.loadAllCategories()
            }
        }
    }
}

struct PermissionRequestView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Accès aux photos requis")
                .font(.title2)
                .fontWeight(.bold)

            Text("Pour analyser et nettoyer vos photos, l'application a besoin d'accéder à votre photothèque.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Button(action: onRequest) {
                Text("Autoriser l'accès")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
        }
        .padding()
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
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)

                Text("Analyse en cours...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(Color(.systemGray6))
            .cornerRadius(16)
        }
    }
}

#Preview {
    ContentView()
}
