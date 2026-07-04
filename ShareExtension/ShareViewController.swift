//
//  ShareViewController.swift
//  ShareExtension
//
//  Handles incoming shared content from Mail and other apps.
//  Extracts email subject, sender, and body text, then saves
//  to the shared App Group for the main app to parse.
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    
    private var emailSubject: String = ""
    private var emailBody: String = ""
    private var emailSender: String = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Style the compose view
        navigationController?.navigationBar.tintColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
        title = "Travel Steward"
        
        // Extract shared content
        extractSharedContent()
    }
    
    override func isContentValid() -> Bool {
        return !contentText.isEmpty || !emailBody.isEmpty
    }
    
    override func didSelectPost() {
        let finalBody = emailBody.isEmpty ? (contentText ?? "") : emailBody
        let finalSubject = emailSubject.isEmpty ? "Shared Content" : emailSubject
        
        let sharedEmail = SharedDataStore.SharedEmail(
            subject: finalSubject,
            sender: emailSender,
            body: finalBody
        )
        
        // Save to App Group shared storage
        SharedDataStore.savePendingEmail(sharedEmail)
        
        // Complete the extension
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
    
    override func configurationItems() -> [Any]! {
        var items: [SLComposeSheetConfigurationItem] = []
        
        if !emailSubject.isEmpty {
            let subjectItem = SLComposeSheetConfigurationItem()!
            subjectItem.title = "Subject"
            subjectItem.value = emailSubject
            items.append(subjectItem)
        }
        
        if !emailSender.isEmpty {
            let senderItem = SLComposeSheetConfigurationItem()!
            senderItem.title = "From"
            senderItem.value = emailSender
            items.append(senderItem)
        }
        
        return items
    }
    
    // MARK: - Content Extraction
    
    private func extractSharedContent() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        
        for item in extensionItems {
            if let subject = item.attributedContentText?.string {
                if emailSubject.isEmpty {
                    emailSubject = subject
                }
            }
            
            guard let attachments = item.attachments else { continue }
            
            for provider in attachments {
                // Handle plain text
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        if let text = item as? String {
                            DispatchQueue.main.async {
                                self?.emailBody = text
                                self?.reloadConfigurationItems()
                            }
                        }
                    }
                }
                
                // Handle URLs
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        if let url = item as? URL {
                            if url.scheme == "mailto" {
                                DispatchQueue.main.async {
                                    self?.emailSender = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
                                    self?.reloadConfigurationItems()
                                }
                            } else {
                                DispatchQueue.main.async {
                                    self?.emailBody += "\n\(url.absoluteString)"
                                    self?.reloadConfigurationItems()
                                }
                            }
                        }
                    }
                }
                
                // Handle HTML content (rich email bodies)
                if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.html.identifier, options: nil) { [weak self] item, _ in
                        if let htmlString = item as? String {
                            let plainText = self?.stripHTML(htmlString) ?? htmlString
                            DispatchQueue.main.async {
                                self?.emailBody = plainText
                                self?.reloadConfigurationItems()
                            }
                        }
                    }
                }
            }
        }
    }
    
    /// Strip HTML tags and decode entities
    private func stripHTML(_ html: String) -> String {
        var stripped = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&bull;", "•")
        ]
        for (entity, char) in entities {
            stripped = stripped.replacingOccurrences(of: entity, with: char)
        }
        
        stripped = stripped.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
