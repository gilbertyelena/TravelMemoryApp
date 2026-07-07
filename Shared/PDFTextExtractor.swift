//
//  PDFTextExtractor.swift
//  TravelMemory / ShareExtension (single file, member of both targets)
//
//  Pulls the text out of PDF confirmations (Booking.com's "Share PDF",
//  airline e-tickets) so they flow through the same parsing pipeline
//  as pasted emails.
//

import Foundation
import PDFKit

enum PDFTextExtractor {

    static func isPDF(_ data: Data) -> Bool {
        data.prefix(5) == Data("%PDF-".utf8)
    }

    static func text(from data: Data) -> String? {
        guard isPDF(data), let document = PDFDocument(data: data) else { return nil }
        return extract(from: document)
    }

    static func text(from url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        return extract(from: document)
    }

    private static func extract(from document: PDFDocument) -> String? {
        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let pageText = document.page(at: index)?.string {
                pages.append(pageText)
            }
        }
        let text = pages.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
