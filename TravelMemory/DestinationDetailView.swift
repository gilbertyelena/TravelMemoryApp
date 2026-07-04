//
//  DestinationDetailView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData
import MapKit
import PhotosUI

struct DestinationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var destination: Destination
    
    @State private var showingEditSheet = false
    @State private var showingAddMemory = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedSection = 0
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Hero Header
                heroHeader
                
                // MARK: - Info Cards
                infoCards
                    .padding(.horizontal)
                    .padding(.top, -30)
                
                // MARK: - Section Picker
                Picker("Section", selection: $selectedSection) {
                    Text("Photos").tag(0)
                    Text("Memories").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                // MARK: - Content
                if selectedSection == 0 {
                    photosSection
                } else {
                    memoriesSection
                }
            }
        }
        .navigationTitle(destination.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingEditSheet = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            AddDestinationView(existingDestination: destination)
        }
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView(destination: destination)
        }
        .onChange(of: selectedPhotos) { _ in
            addPhotos()
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = destination.coverPhotoData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 280)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [.orange, .pink, .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 280)
                .overlay {
                    Image(systemName: "airplane")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            
            // Gradient overlay
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Text overlay
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.city.isEmpty ? "New Trip" : destination.city)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                Text(destination.country)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                
                HStack(spacing: 12) {
                    Label(destination.tripDuration, systemImage: "calendar")
                    Label("\(destination.photos.count) photos", systemImage: "photo")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
    }
    
    // MARK: - Info Cards
    
    private var infoCards: some View {
        HStack(spacing: 12) {
            // Dates card
            infoCard(
                icon: "calendar",
                title: "Dates",
                value: destination.dateRangeText
            )
            
            // Hotel card
            if !destination.hotelName.isEmpty {
                infoCard(
                    icon: "bed.double",
                    title: "Hotel",
                    value: destination.hotelName,
                    link: destination.hotelLink
                )
            }
        }
    }
    
    private func infoCard(icon: String, title: String, value: String, link: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.caption2)
                .lineLimit(2)
            
            if let link, !link.isEmpty, let url = URL(string: link) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
    }
    
    // MARK: - Photos Section
    
    private var photosSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .images
                ) {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            
            if destination.photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No photos yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(destination.photos) { photo in
                        if let data = photo.imageData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(minHeight: 120)
                                .clipped()
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            modelContext.delete(photo)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Memories Section
    
    private var memoriesSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Memories")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddMemory = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal)
            
            if destination.memories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No memories yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Add memorable moments from your trip")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(destination.memories) { memory in
                        MemoryCardView(memory: memory)
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation {
                                        modelContext.delete(memory)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 20)
    }
    
    // MARK: - Actions
    
    private func addPhotos() {
        Task {
            for item in selectedPhotos {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let photo = Photo(imageData: data, dateTaken: .now)
                    destination.photos.append(photo)
                }
            }
            selectedPhotos = []
        }
    }
}

// MARK: - Memory Card View

struct MemoryCardView: View {
    let memory: Memory
    
    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.2), .pink.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                
                Image(systemName: memory.categoryIcon)
                    .font(.body)
                    .foregroundStyle(.orange)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(memory.title)
                    .font(.subheadline.bold())
                
                if !memory.details.isEmpty {
                    Text(memory.details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    Text(Memory.categoryLabel(memory.category))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.1))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    
                    if !memory.externalLink.isEmpty {
                        if let url = URL(string: memory.externalLink) {
                            Link(destination: url) {
                                Label("Open Link", systemImage: "arrow.up.right.square")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DestinationDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DestinationDetailView(destination: Destination(
                city: "Tokyo",
                country: "Japan",
                dateFrom: .now.addingTimeInterval(-86400 * 5),
                dateTo: .now,
                hotelName: "Park Hyatt",
                hotelLink: "https://example.com"
            ))
        }
        .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
