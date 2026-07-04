//
//  ModelContextSaving.swift
//  TravelMemory
//
//  Single choke point for SwiftData saves so failures are logged
//  instead of silently discarded with `try?`.
//

import Foundation
import SwiftData
import os

extension ModelContext {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "TravelMemory",
        category: "persistence"
    )

    /// Saves the context, logging any failure. Returns whether the save
    /// succeeded so callers that can surface an error to the user may do so.
    @discardableResult
    func saveOrLog(operation: String = #function) -> Bool {
        do {
            try save()
            return true
        } catch {
            Self.logger.error("Save failed in \(operation, privacy: .public): \(error, privacy: .public)")
            return false
        }
    }
}
