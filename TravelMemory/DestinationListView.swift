//
//  DestinationListView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData

struct DestinationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Destination.dateFrom, order: .reverse) private var destinations: [Destination]
    @State private var showingAddSheet = false
    @State private var searchText = ""
    
    var filteredDestinations: [Destination] {
        if searchText.isEmpty { return destinations }
        return destinations.filter {
            $0.city.localizedCaseInsensitiveContains(searchText) ||
            $0.country.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if destinations.isEmpty {
                    emptyStateView
                } else {
                    destinationList
                }
            }
            .navigationTitle("My Trips")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddDestinationView()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "airplane.departure")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolRenderingMode(.hierarchical)
            
            Text("No trips yet")
                .font(.title2.bold())
            
            Text("Tap + to add your first travel memory")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button {
                showingAddSheet = true
            } label: {
                Label("Add Trip", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Destination List
    
    private var destinationList: some View {
        List {
            ForEach(filteredDestinations) { destination in
                NavigationLink(destination: DestinationDetailView(destination: destination)) {
                    DestinationRowView(destination: destination)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
            .onDelete(perform: deleteDestinations)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search destinations")
    }
    
    // MARK: - Actions
    
    private func deleteDestinations(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredDestinations[index])
            }
        }
    }
}

// MARK: - Destination Row

struct DestinationRowView: View {
    let destination: Destination
    
    var body: some View {
        HStack(spacing: 14) {
            // Cover photo or placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.3), .pink.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                if let data = destination.coverPhotoData,
                   let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(destination.city.isEmpty ? "New Trip" : destination.city)
                    .font(.headline)
                
                if !destination.country.isEmpty {
                    Text(destination.country)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(destination.dateRangeText)
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Stats
            VStack(alignment: .trailing, spacing: 4) {
                if !destination.photos.isEmpty {
                    Label("\(destination.photos.count)", systemImage: "photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !destination.memories.isEmpty {
                    Label("\(destination.memories.count)", systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DestinationListView_Previews: PreviewProvider {
    static var previews: some View {
        DestinationListView()
            .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
