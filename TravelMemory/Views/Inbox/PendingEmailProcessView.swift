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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()

                if isProcessing {
                    processingView
                } else if let result = parseResult {
                    ParseResultView(
                        result: result,
                        onAccept: {
                            // Nothing was persisted during parsing —
                            // commit only on explicit accept.
                            let service = EmailIngestionService(modelContext: modelContext)
                            service.commit(result, subject: email.subject, body: email.body, sender: email.sender)
                            onProcessed()
                        },
                        onDiscard: {
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
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                
                Text(email.subject)
                    .font(VoyagerFont.bodySmall)
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

            self.parseResult = EmailIngestionService.parse(
                subject: email.subject,
                body: email.body,
                sender: email.sender
            )

            withAnimation {
                self.isProcessing = false
            }
        }
    }
}
