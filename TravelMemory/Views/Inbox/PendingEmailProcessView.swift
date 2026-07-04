//
//  PendingEmailProcessView.swift
//  TravelMemory
//
//  Processes emails received from the Share Extension.
//  Automatically parses the email and shows results.
//

import SwiftUI
import SwiftData

struct PendingEmailProcessView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let email: SharedDataStore.SharedEmail
    var onProcessed: () -> Void
    
    @State private var isProcessing = true
    @State private var parseResult: EmailParser.ParseResult?
    @State private var createdTrip: Trip?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                if isProcessing {
                    processingView
                } else if let result = parseResult {
                    ParseResultView(
                        result: result,
                        trip: createdTrip,
                        onAccept: {
                            onProcessed()
                        },
                        onDiscard: {
                            // Delete the trip if discarded
                            if let trip = createdTrip {
                                modelContext.delete(trip)
                                try? modelContext.save()
                            }
                            onProcessed()
                        }
                    )
                }
            }
            .navigationTitle("Shared Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onProcessed()
                    }
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            processEmail()
        }
    }
    
    private var processingView: some View {
        VStack(spacing: 24) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "envelope.open")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.voyagerPrimary)
                    .voyagerGlow(radius: 20, opacity: 0.3)
            }
            
            VStack(spacing: 8) {
                Text("Parsing Email...")
                    .font(VoyagerFont.headlineMediumFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                Text(email.subject)
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            
            ProgressView()
                .tint(Color.voyagerPrimary)
                .scaleEffect(1.2)
        }
        .padding(40)
    }
    
    private func processEmail() {
        Task {
            // Small delay for the animation
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            let service = EmailIngestionService(modelContext: modelContext)
            let trip = await service.ingestEmail(
                subject: email.subject,
                body: email.body,
                sender: email.sender
            )
            
            self.parseResult = service.lastParseResult
            self.createdTrip = trip
            
            withAnimation {
                self.isProcessing = false
            }
        }
    }
}
