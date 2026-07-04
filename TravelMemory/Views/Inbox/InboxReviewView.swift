//
//  InboxReviewView.swift
//  TravelMemory
//
//  Shows emails that need review — driven by real SwiftData.
//  Empty state when nothing needs attention.
//

import SwiftUI
import SwiftData

struct InboxReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ParsedEmail> { $0.statusRaw == "needsReview" },
           sort: \ParsedEmail.parsedAt, order: .reverse)
    private var pendingEmails: [ParsedEmail]
    
    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                    // Header with back button
                    header
                    
                    if pendingEmails.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: VoyagerSpacing.stackMedium) {
                            ForEach(pendingEmails, id: \.id) { email in
                                emailReviewCard(email)
                            }
                        }
                        .padding(.horizontal, VoyagerSpacing.marginMain)
                    }
                }
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Back button row
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                        Text("Back")
                            .font(VoyagerFont.bodySmallFallback)
                    }
                    .foregroundStyle(Color.voyagerPrimary)
                }
                Spacer()
            }
            .padding(.horizontal, VoyagerSpacing.marginMain)
            .padding(.top, 8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Needed")
                    .font(VoyagerFont.headlineLargeFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Review low-confidence data parses to ensure a seamless trip.")
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
            .padding(.horizontal, VoyagerSpacing.marginMain)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.06))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary.opacity(0.6))
            }
            
            VStack(spacing: 6) {
                Text("All Clear")
                    .font(VoyagerFont.headlineMediumFallback)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("No items need your attention right now")
                    .font(VoyagerFont.bodySmallFallback)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    // MARK: - Email Review Card
    
    private func emailReviewCard(_ email: ParsedEmail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "envelope.open")
                    .foregroundStyle(Color.voyagerTertiary)
                Text("EMAIL PARSE")
                    .font(VoyagerFont.labelCapsFallback)
                    .tracking(1.2)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                Spacer()
                Text("\(Int(email.overallConfidence * 100))%")
                    .font(VoyagerFont.labelCapsFallback)
                    .foregroundStyle(email.overallConfidence >= 0.5 ? Color.voyagerTertiary : Color.voyagerError)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((email.overallConfidence >= 0.5 ? Color.voyagerTertiary : Color.voyagerError).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            Text(email.subject)
                .font(VoyagerFont.headlineMediumFallback)
                .foregroundStyle(Color.voyagerOnSurface)
            
            if !email.issues.isEmpty {
                ForEach(email.issues, id: \.self) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.voyagerTertiary)
                            .padding(.top, 2)
                        Text(issue)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                .padding(12)
                .background(Color.voyagerSurfaceVariant.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            HStack(spacing: 12) {
                Button {
                    email.status = .accepted
                    try? modelContext.save()
                } label: {
                    Text("ACCEPT")
                }
                .buttonStyle(VoyagerPrimaryButtonStyle())
                
                Button {
                    email.status = .rejected
                    try? modelContext.save()
                } label: {
                    Text("DISMISS")
                        .font(VoyagerFont.labelCapsFallback)
                        .tracking(0.6)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.voyagerSurfaceVariant.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                }
            }
            .padding(.top, 4)
        }
        .padding(VoyagerSpacing.stackMedium)
        .background(Color.voyagerSurfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.voyagerTertiary).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

struct InboxReviewView_Previews: PreviewProvider {
    static var previews: some View {
        InboxReviewView()
            .modelContainer(for: [ParsedEmail.self], inMemory: true)
            .preferredColorScheme(.dark)
    }
}
