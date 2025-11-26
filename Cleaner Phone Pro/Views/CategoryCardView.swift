//
//  CategoryCardView.swift
//  Cleaner Phone Pro
//

import SwiftUI

struct CategoryCardView: View {
    let categoryData: CategoryData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with title and badge
            HStack {
                // Icon and title
                HStack(spacing: 8) {
                    Image(systemName: categoryData.category.icon)
                        .font(.title2)
                        .foregroundColor(categoryData.category.color)
                    
                    Text(categoryData.category.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Badge with count and size
                BadgeView(
                    count: categoryData.items.count,
                    size: categoryData.formattedSize,
                    color: categoryData.category.color
                )
            }
            
            // Preview images (3 photos)
            PreviewImagesView(items: categoryData.previewItems)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }
}

struct BadgeView: View {
    let count: Int
    let size: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .fontWeight(.bold)
            
            Text(size)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
        .cornerRadius(12)
    }
}

struct PreviewImagesView: View {
    let items: [MediaItem]

    var body: some View {
        GeometryReader { geometry in
            let imageWidth = (geometry.size.width - 16) / 3

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    if index < items.count, let thumbnail = items[index].thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: imageWidth, height: 100)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray5))
                            .frame(width: imageWidth, height: 100)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            )
                    }
                }
            }
        }
        .frame(height: 100)
    }
}

#Preview {
    CategoryCardView(
        categoryData: CategoryData(
            category: .screenshots,
            items: []
        )
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
