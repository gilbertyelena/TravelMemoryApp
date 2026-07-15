//
//  SecureVaultView.swift
//  TravelMemory
//
//  Biometric/passcode-gated storage for passports, visas, and boarding
//  passes. Documents live in the local SwiftData store and are protected
//  by iOS data protection plus the Face ID / passcode gate below.
//  Features a document scanner (camera/photo capture) and document grid.
//

import SwiftUI
import SwiftData
import LocalAuthentication
import PhotosUI

struct SecureVaultView: View {
    @State private var isAuthenticated = false
    @State private var authError: String?
    @State private var passcodeNotSet = false

    var body: some View {
        ZStack {
            Color.voyagerBackground.ignoresSafeArea()

            if isAuthenticated {
                VaultContentView()
            } else {
                BiometricGateView(
                    authError: authError,
                    passcodeNotSet: passcodeNotSet,
                    onRetry: {
                        authError = nil
                        authenticate()
                    },
                    onContinueUnprotected: {
                        withAnimation(.easeOut(duration: 0.4)) {
                            isAuthenticated = true
                        }
                    }
                )
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            authenticate()
        }
    }

    private func authenticate() {
        let context = LAContext()
        var error: NSError?

        // .deviceOwnerAuthentication falls back to the device passcode
        // when Face ID / Touch ID is unavailable or fails.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on this device — there is nothing to
            // authenticate against. Require an explicit user choice
            // instead of unlocking silently.
            passcodeNotSet = true
            authError = "This device has no passcode. Set one in Settings to protect your vault."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock your Secure Vault"
        ) { success, authenticationError in
            DispatchQueue.main.async {
                if success {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isAuthenticated = true
                    }
                } else {
                    authError = authenticationError?.localizedDescription ?? "Authentication failed"
                }
            }
        }
    }
}

// MARK: - Vault Content

struct VaultContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VaultDocument.createdAt, order: .reverse) private var documents: [VaultDocument]
    
    @State private var showAddSheet = false
    @State private var selectedDocument: VaultDocument?
    @State private var appeared = false
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: VoyagerSpacing.stackLarge) {
                VoyagerTopBar()
                vaultHeader
                
                if documents.isEmpty {
                    emptyState
                } else {
                    documentGrid
                }
            }
            .padding(.bottom, 120)
        }
        .overlay(alignment: .bottomTrailing) {
            addButton
        }
        .sheet(isPresented: $showAddSheet) {
            AddDocumentView()
        }
        .sheet(item: $selectedDocument) { doc in
            DocumentDetailView(document: doc)
        }
        .onAppear {
            withAnimation { appeared = true }
        }
    }
    
    // MARK: - Header
    
    private var vaultHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.voyagerPrimary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Secure Vault")
                        .font(VoyagerFont.headlineLarge)
                        .foregroundStyle(Color.voyagerOnSurface)
                    Text("\(documents.count) document\(documents.count == 1 ? "" : "s")")
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
        .padding(.bottom, VoyagerSpacing.stackMedium)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.voyagerOutlineVariant.opacity(0.2))
                .frame(height: 0.5)
                .padding(.horizontal, VoyagerSpacing.marginMain)
        }
    }
    
    // MARK: - Document Grid
    
    private var documentGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { idx, doc in
                Button { selectedDocument = doc } label: {
                    documentCard(doc)
                }
                .buttonStyle(.plain)
                .staggeredAppear(index: idx, appeared: appeared)
            }
        }
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    private func documentCard(_ doc: VaultDocument) -> some View {
        let catColor = Color(hex: doc.category.color)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                    .fill(Color.voyagerSurfaceContainerHigh)
                    .frame(height: 100)
                
                if let data = doc.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                } else {
                    Image(systemName: doc.category.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(catColor.opacity(0.4))
                }
            }
            
            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(doc.title.isEmpty ? doc.category.label : doc.title)
                    .font(VoyagerFont.bodySmallMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: doc.category.icon)
                        .font(.system(size: 9))
                    Text(doc.category.label.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .tracking(0.5)
                }
                .foregroundStyle(catColor)
            }
        }
        .padding(10)
        .background(Color.voyagerSurfaceContainerLow)
        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: VoyagerRadius.large)
                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 28) {
            // Animated illustration
            ZStack {
                Circle()
                    .fill(Color.voyagerPrimary.opacity(0.06))
                    .frame(width: 140, height: 140)
                
                Circle()
                    .stroke(Color.voyagerPrimary.opacity(0.1), lineWidth: 1)
                    .frame(width: 160, height: 160)
                
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(Color.voyagerPrimary)
                    .symbolEffect(.pulse, options: .repeating)
            }
            
            VStack(spacing: 8) {
                Text("No Documents Yet")
                    .font(VoyagerFont.headlineMedium)
                    .foregroundStyle(Color.voyagerOnSurface)
                Text("Scan or photograph your passports,\nvisas, and boarding passes")
                    .font(VoyagerFont.bodySmall)
                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // Quick-add buttons
            VStack(spacing: 10) {
                ForEach([VaultCategory.passport, .visa, .boarding], id: \.rawValue) { cat in
                    Button { showAddSheet = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: cat.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(Color(hex: cat.color))
                                .frame(width: 24)
                            Text("Add \(cat.label)")
                                .font(VoyagerFont.bodySmall)
                                .foregroundStyle(Color.voyagerOnSurface)
                            Spacer()
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.voyagerPrimary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.voyagerSurfaceContainerLow)
                        .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        .overlay(
                            RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                .stroke(Color.voyagerOutlineVariant.opacity(0.2), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
        .padding(.horizontal, VoyagerSpacing.marginMain)
    }
    
    // MARK: - FAB
    
    private var addButton: some View {
        Button { showAddSheet = true } label: {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.voyagerPrimaryAccent)
                .clipShape(Circle())
                .shadow(color: Color.voyagerPrimaryAccent.opacity(0.4), radius: 12, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 110)
    }
}

// MARK: - Add Document View

struct AddDocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var selectedCategory: VaultCategory = .passport
    @State private var notes = ""
    @State private var selectedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Image capture area
                        captureArea
                        
                        // Category picker
                        categoryPicker
                        
                        // Title
                        formField(title: "DOCUMENT NAME", placeholder: "e.g. UK Passport", text: $title)
                        
                        // Notes
                        notesField
                        
                        // Save button
                        Button { save() } label: {
                            Text("SAVE DOCUMENT")
                        }
                        .buttonStyle(VoyagerPrimaryButtonStyle())
                        .disabled(selectedImage == nil)
                        .opacity(selectedImage == nil ? 0.5 : 1)
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                }
            }
            .sheet(isPresented: $showCamera) {
                DocumentCameraView(image: $selectedImage)
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, newItem in
                loadPhoto(from: newItem)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Capture Area
    
    private var captureArea: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
                    .overlay(
                        RoundedRectangle(cornerRadius: VoyagerRadius.large)
                            .stroke(Color.voyagerPrimary.opacity(0.3), lineWidth: 1)
                    )
                
                Button {
                    selectedImage = nil
                    photoItem = nil
                } label: {
                    Text("REMOVE")
                        .font(VoyagerFont.labelCaps)
                        .tracking(0.6)
                        .foregroundStyle(Color.voyagerError)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Color.voyagerPrimary.opacity(0.5))
                    
                    Text("Scan or select a document photo")
                        .font(VoyagerFont.bodySmall)
                        .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    
                    HStack(spacing: 12) {
                        Button { showCamera = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14))
                                Text("CAMERA")
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(0.6)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.voyagerPrimaryAccent)
                            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        }
                        
                        Button { showPhotoPicker = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 14))
                                Text("GALLERY")
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(0.6)
                            }
                            .foregroundStyle(Color.voyagerPrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.voyagerPrimary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                            .overlay(
                                RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                                    .stroke(Color.voyagerPrimary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color.voyagerSurfaceContainerLow)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.large)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8, 6]))
                        .foregroundStyle(Color.voyagerPrimary.opacity(0.3))
                )
            }
        }
    }
    
    // MARK: - Category Picker
    
    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CATEGORY")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VaultCategory.allCases, id: \.rawValue) { cat in
                        Button {
                            selectedCategory = cat
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 12))
                                Text(cat.label)
                                    .font(VoyagerFont.labelCaps)
                            }
                            .foregroundStyle(selectedCategory == cat ? .white : Color.voyagerOnSurfaceVariant)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedCategory == cat ? Color(hex: cat.color) : Color.voyagerSurfaceContainerHigh)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField(placeholder, text: text)
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurface)
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                )
        }
    }
    
    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(VoyagerFont.labelCaps)
                .tracking(1.0)
                .foregroundStyle(Color.voyagerOnSurfaceVariant)
            TextField("Optional notes...", text: $notes, axis: .vertical)
                .font(VoyagerFont.bodyLarge)
                .foregroundStyle(Color.voyagerOnSurface)
                .lineLimit(3...6)
                .padding(14)
                .background(Color.voyagerInputBackground)
                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                .overlay(
                    RoundedRectangle(cornerRadius: VoyagerRadius.medium)
                        .stroke(Color.voyagerInputBorder, lineWidth: 1)
                )
        }
    }
    
    // MARK: - Actions
    
    private func save() {
        guard let image = selectedImage else { return }
        let data = image.jpegData(compressionQuality: 0.8)
        let doc = VaultDocument(
            title: title.isEmpty ? selectedCategory.label : title,
            categoryRaw: selectedCategory.rawValue,
            imageData: data,
            notes: notes
        )
        modelContext.insert(doc)
        modelContext.saveOrLog()
        dismiss()
    }
    
    private func loadPhoto(from item: PhotosPickerItem?) {
        guard let item = item else { return }
        item.loadTransferable(type: Data.self) { result in
            if case .success(let data) = result, let data = data,
               let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    selectedImage = uiImage
                }
            }
        }
    }
}

// MARK: - Camera View (UIKit bridge)

struct DocumentCameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: DocumentCameraView
        init(_ parent: DocumentCameraView) { self.parent = parent }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Document Detail View

struct DocumentDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let document: VaultDocument
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.voyagerBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: VoyagerSpacing.stackLarge) {
                        // Document image
                        if let data = document.imageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.large))
                                .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                        }
                        
                        // Info
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: document.category.icon)
                                    .foregroundStyle(Color(hex: document.category.color))
                                Text(document.category.label.uppercased())
                                    .font(VoyagerFont.labelCaps)
                                    .tracking(0.8)
                                    .foregroundStyle(Color(hex: document.category.color))
                            }
                            
                            Text(document.title)
                                .font(VoyagerFont.headlineMedium)
                                .foregroundStyle(Color.voyagerOnSurface)
                            
                            if !document.notes.isEmpty {
                                Text(document.notes)
                                    .font(VoyagerFont.bodySmall)
                                    .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            }
                            
                            let fmt = DateFormatter()
                            let _ = fmt.dateStyle = .medium
                            Text("Added \(fmt.string(from: document.createdAt))")
                                .font(VoyagerFont.labelCaps)
                                .foregroundStyle(Color.voyagerOnSurfaceVariant.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Delete
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text("DELETE DOCUMENT")
                            }
                            .font(VoyagerFont.labelCaps)
                            .tracking(0.6)
                            .foregroundStyle(Color.voyagerError)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.voyagerError.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: VoyagerRadius.medium))
                        }
                    }
                    .padding(.horizontal, VoyagerSpacing.marginMain)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.voyagerPrimary)
                }
            }
            .alert("Delete Document?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    modelContext.delete(document)
                    modelContext.saveOrLog()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Biometric Gate View

struct BiometricGateView: View {
    var authError: String?
    var passcodeNotSet: Bool
    var onRetry: () -> Void
    var onContinueUnprotected: () -> Void
    @State private var progress: CGFloat = 0
    @State private var scanLineOffset: CGFloat = -60
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Security rings
            VStack {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.voyagerPrimary.opacity(0.1), lineWidth: 1)
                        .frame(width: 400, height: 400)
                    Circle()
                        .stroke(Color.voyagerPrimary.opacity(0.2), lineWidth: 1)
                        .frame(width: 256, height: 256)
                    Circle()
                        .stroke(Color.voyagerPrimary.opacity(0.15), lineWidth: 1)
                        .frame(width: 192, height: 192)
                }
                .opacity(0.3)
                Spacer()
            }
            
            VStack(spacing: VoyagerSpacing.stackLarge) {
                ZStack {
                    Circle()
                        .fill(Color.voyagerPrimary.opacity(0.2))
                        .frame(width: 160, height: 160)
                        .blur(radius: 30)
                    
                    Circle()
                        .stroke(Color.voyagerPrimary.opacity(0.3), lineWidth: 1)
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "faceid")
                        .font(.system(size: 72, weight: .ultraLight))
                        .foregroundStyle(Color.voyagerPrimary)
                        .voyagerGlow(radius: 24, opacity: 0.2)
                    
                    Rectangle()
                        .fill(Color.voyagerPrimary)
                        .frame(width: 120, height: 2)
                        .voyagerGlow(radius: 12, opacity: 0.8)
                        .offset(y: scanLineOffset)
                }
                
                VStack(spacing: VoyagerSpacing.stackSmall) {
                    if let error = authError {
                        Text("Authentication Failed")
                            .font(VoyagerFont.headlineMedium)
                            .foregroundStyle(Color.voyagerError)
                        Text(error)
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Authenticating...")
                            .font(VoyagerFont.headlineMedium)
                            .foregroundStyle(Color.voyagerOnSurface)
                        Text("Verifying biometric credentials")
                            .font(VoyagerFont.bodySmall)
                            .foregroundStyle(Color.voyagerOnSurfaceVariant)
                    }
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.voyagerSurfaceContainerHighest)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(authError != nil ? Color.voyagerError : Color.voyagerPrimary)
                            .frame(width: geo.size.width * progress, height: 4)
                            .voyagerGlow(radius: 8)
                    }
                }
                .frame(width: 200, height: 4)
                
                if passcodeNotSet {
                    Button { onContinueUnprotected() } label: {
                        Text("CONTINUE WITHOUT PROTECTION")
                    }
                    .buttonStyle(VoyagerPrimaryButtonStyle())
                    .frame(width: 260)
                    .padding(.top, 8)
                } else if authError != nil {
                    Button { onRetry() } label: {
                        Text("TRY AGAIN")
                    }
                    .buttonStyle(VoyagerPrimaryButtonStyle())
                    .frame(width: 200)
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                scanLineOffset = 60
            }
            withAnimation(.easeInOut(duration: 2.0)) {
                progress = authError != nil ? 1.0 : 0.6
            }
        }
    }
}
