//
//  SharedDataStore.swift
//  ShareExtension
//
//  Shared data layer between the main app and Share Extension.
//  Uses App Groups to pass email content from the extension
//  to the main app for parsing.
//
//  NOTE: This file is a copy of TravelMemory/Services/SharedDataStore.swift
//  Both must stay in sync.
//

import Foundation

/// Manages data shared between the main app and Share Extension
/// via App Groups (shared UserDefaults).
struct SharedDataStore {
    
    /// App Group identifier — must match in both targets and entitlements
    static let appGroupID = "group.com.alenka.TravelSteward"
    
    /// Keys for shared UserDefaults
    private enum Keys {
        static let pendingEmails = "pendingEmails"
    }
    
    /// A single email captured by the Share Extension
    struct SharedEmail: Codable {
        var id: String = UUID().uuidString
        var subject: String
        var sender: String
        var body: String
        var timestamp: Date = Date()
    }
    
    /// Shared UserDefaults via App Group
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    // MARK: - Write (called from Share Extension)
    
    /// Save a new email to the shared queue
    static func savePendingEmail(_ email: SharedEmail) {
        var pending = loadPendingEmails()
        pending.append(email)
        
        if let data = try? JSONEncoder().encode(pending) {
            sharedDefaults?.set(data, forKey: Keys.pendingEmails)
            sharedDefaults?.synchronize()
        }
    }
    
    // MARK: - Read (called from main app)
    
    /// Load all pending emails from the shared queue
    static func loadPendingEmails() -> [SharedEmail] {
        guard let data = sharedDefaults?.data(forKey: Keys.pendingEmails),
              let emails = try? JSONDecoder().decode([SharedEmail].self, from: data) else {
            return []
        }
        return emails
    }
    
    /// Remove a processed email from the queue
    static func removePendingEmail(id: String) {
        var pending = loadPendingEmails()
        pending.removeAll { $0.id == id }
        
        if let data = try? JSONEncoder().encode(pending) {
            sharedDefaults?.set(data, forKey: Keys.pendingEmails)
            sharedDefaults?.synchronize()
        }
    }
    
    /// Clear all pending emails
    static func clearPendingEmails() {
        sharedDefaults?.removeObject(forKey: Keys.pendingEmails)
        sharedDefaults?.synchronize()
    }
    
    /// Check if there are any pending emails to process
    static var hasPendingEmails: Bool {
        !loadPendingEmails().isEmpty
    }
}
