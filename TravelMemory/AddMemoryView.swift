//
//  AddMemoryView.swift
//  TravelMemory
//
//  Created by Yelena Gilbert on 28/04/2026.
//

import SwiftUI
import SwiftData

struct AddMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: Destination
    
    @State private var title = ""
    @State private var details = ""
    @State private var category = "other"
    @State private var externalLink = ""
    @State private var date = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    TextField("Title", text: $title)
                    TextEditor(text: $details)
                        .frame(minHeight: 60)
                }
                
                Section("Category") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 4),
                        spacing: 12
                    ) {
                        ForEach(Memory.categories, id: \.self) { cat in
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    category = cat
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle()
                                            .fill(category == cat
                                                  ? LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                                  : LinearGradient(colors: [.gray.opacity(0.15), .gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            )
                                            .frame(width: 48, height: 48)
                                        
                                        Image(systemName: Memory(category: cat).categoryIcon)
                                            .font(.title3)
                                            .foregroundStyle(category == cat ? .white : .secondary)
                                    }
                                    
                                    Text(Memory.categoryLabel(cat))
                                        .font(.caption2)
                                        .foregroundStyle(category == cat ? .orange : .secondary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("Date") {
                    DatePicker("When", selection: $date, displayedComponents: .date)
                        .tint(.orange)
                }
                
                Section("External Link") {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.orange)
                        TextField("Link to app or website (optional)", text: $externalLink)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                    }
                    
                    Text("e.g. link to a Ski Tracks recording, restaurant, or event")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("New Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let memory = Memory(
                            title: title,
                            details: details,
                            category: category,
                            externalLink: externalLink,
                            date: date
                        )
                        destination.memories.append(memory)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .tint(.orange)
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

struct AddMemoryView_Previews: PreviewProvider {
    static var previews: some View {
        AddMemoryView(destination: Destination(city: "Paris", country: "France"))
            .modelContainer(for: [Destination.self, Memory.self, Photo.self], inMemory: true)
    }
}
