//
//  MapTabView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData
import MapKit

struct MapTabView: View {
    @Query private var destinations: [Destination]
    @State private var mapPosition = MapCameraPosition.automatic
    @State private var selectedDestination: Destination?
    @State private var selectedMarkerTag: String?
    
    // Filter out destinations with no coordinates
    var mappableDestinations: [Destination] {
        destinations.filter { $0.latitude != 0 || $0.longitude != 0 }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $mapPosition, selection: $selectedMarkerTag) {
                    ForEach(mappableDestinations) { destination in
                        Marker(
                            destination.displayName,
                            systemImage: "airplane",
                            coordinate: destination.coordinate
                        )
                        .tint(.orange)
                        .tag(destination.id.uuidString)
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.airport, .museum, .restaurant])))
                .ignoresSafeArea(edges: .top)
                
                // Bottom card when destination selected
                if let selected = selectedDestination {
                    selectedDestinationCard(selected)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedMarkerTag) { _ in
                withAnimation {
                    selectedDestination = mappableDestinations.first {
                        $0.id.uuidString == selectedMarkerTag
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if !mappableDestinations.isEmpty {
                    Button {
                        withAnimation {
                            mapPosition = .automatic
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
            }
            .overlay {
                if mappableDestinations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "map")
                            .font(.system(size: 50))
                            .foregroundStyle(.tertiary)
                        Text("No locations to show")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Add a trip with a location to see it on the map")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Selected Destination Card
    
    private func selectedDestinationCard(_ destination: Destination) -> some View {
        NavigationLink(destination: DestinationDetailView(destination: destination)) {
            HStack(spacing: 14) {
                // Cover photo
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
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
                        Image(systemName: "airplane")
                            .font(.title2)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(destination.dateRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        Label("\(destination.photos.count)", systemImage: "photo")
                        Label("\(destination.memories.count)", systemImage: "star")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
    }
}

struct MapTabView_Previews: PreviewProvider {
    static var previews: some View {
        MapTabView()
            .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
