//
//  Created by Ian Miller on 2/12/26.
//
//
//  ManualPDFViewer.swift
//  Studio Guru
//

import SwiftUI
import PDFKit

#if os(iOS)
import UIKit
private typealias UXViewRepresentable = UIViewRepresentable
private typealias UXView = UIView
#else
import AppKit
private typealias UXViewRepresentable = NSViewRepresentable
private typealias UXView = NSView
#endif

// MARK: - SwiftUI PDF Viewer

struct ManualPDFViewer: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let title: String

    @State private var searchText: String = ""
    @State private var matches: [PDFSelection] = []
    @State private var currentMatchIndex: Int = 0
    @State private var document: PDFDocument? = nil
    @State private var loadingStatus: String = "Loading PDF..."
    @State private var isDownloading: Bool = false
    @State private var loadingFailed: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    TextField("Search manual…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }

                    Button("Find") {
                        performSearch()
                    }

                    Button("◀") {
                        goToPreviousMatch()
                    }
                    .disabled(matches.isEmpty)

                    Button("▶") {
                        goToNextMatch()
                    }
                    .disabled(matches.isEmpty)

                    if !matches.isEmpty {
                        Text("\(currentMatchIndex + 1)/\(matches.count)")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                if loadingFailed {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        Text("Unable to Load Manual")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Button {
                            dismiss()
                        } label: {
                            Text("Close")
                                .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if document == nil {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(loadingStatus)
                            .foregroundStyle(.secondary)
                        if isDownloading {
                            Text("This may take a few moments...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PDFKitView(
                        url: url,
                        document: $document,
                        matches: $matches,
                        currentMatchIndex: $currentMatchIndex
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                loadDocument()
            }
            .navigationTitle(title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
#if os(macOS)
        .frame(minWidth: 800, idealWidth: 1000, minHeight: 600, idealHeight: 800)
        .fixedSize(horizontal: false, vertical: false)
#endif
    }
    
    private func loadDocument() {
        if document == nil {
            // Check if this is an iCloud file by looking at the URL
            let isiCloudFile = url.path.contains("Mobile Documents") || url.path.contains("iCloud~")
            
            if isiCloudFile {
                loadingStatus = "Downloading from iCloud..."
                isDownloading = true
            } else {
                loadingStatus = "Loading PDF..."
                isDownloading = false
            }
            
            // Try to access security-scoped resource for saved files
            let needsScoped = url.startAccessingSecurityScopedResource()
            defer {
                if needsScoped {
                    // Keep access during viewing - don't stop here
                }
            }
            
            // For iCloud files, ensure download is started and wait a bit
            if isiCloudFile {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                    
                    // Give it a moment to start downloading
                    Task {
                        // Check download status periodically
                        var attempts = 0
                        while attempts < 50 { // Max 5 seconds (50 * 0.1s)
                            attempts += 1
                            
                            // Check if file is downloaded
                            if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
                               let status = values.ubiquitousItemDownloadingStatus {
                                
                                if status == .current {
                                    // File is downloaded, load it
                                    await MainActor.run {
                                        loadingStatus = "Opening PDF..."
                                        loadPDFDocument()
                                    }
                                    return
                                } else if status == .downloaded {
                                    // File is already downloaded
                                    await MainActor.run {
                                        loadPDFDocument()
                                    }
                                    return
                                }
                            }
                            
                            // Wait a bit before checking again
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        }
                        
                        // Timeout - try to load anyway, or show error if still not available
                        await MainActor.run {
                            loadingStatus = "Opening PDF..."
                            loadPDFDocument()
                            
                            // If document is still nil after timeout, it's likely the file doesn't exist
                            if document == nil && !loadingFailed {
                                loadingFailed = true
                                errorMessage = "Unable to download the PDF from iCloud. The file may have been deleted or iCloud sync may be unavailable."
                            }
                        }
                    }
                } catch {
                    // If startDownloadingUbiquitousItem fails, try loading anyway
                    loadPDFDocument()
                }
            } else {
                // Local file, load immediately
                loadPDFDocument()
            }
        }
    }
    
    private func loadPDFDocument() {
        // Load the document
        document = PDFDocument(url: url)
        
        if document == nil {
            // Try alternative loading method
            if let data = try? Data(contentsOf: url) {
                document = PDFDocument(data: data)
            }
        }
        
        isDownloading = false
        
        // If still nil after all attempts, show error
        if document == nil {
            loadingFailed = true
            
            // Check if file exists
            let fileExists = FileManager.default.fileExists(atPath: url.path)
            if !fileExists {
                errorMessage = "The PDF file could not be found. It may have been deleted from iCloud Drive or local storage."
            } else {
                errorMessage = "The PDF file appears to be corrupted or in an unsupported format."
            }
        }
    }

    private func performSearch() {
        guard let doc = document, !searchText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        let results = doc.findString(searchText, withOptions: .caseInsensitive)
        matches = results
        currentMatchIndex = 0
    }

    private func goToNextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    private func goToPreviousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }
}

private struct PDFKitView: UXViewRepresentable {
    let url: URL
    @Binding var document: PDFDocument?
    @Binding var matches: [PDFSelection]
    @Binding var currentMatchIndex: Int

#if os(iOS)
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.usePageViewController(true, withViewOptions: nil)
        v.backgroundColor = .systemBackground
        
        if let doc = document {
            v.document = doc
        }
        
        return v
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if let doc = document {
            if view.document !== doc {
                view.document = doc
                // print("📱 PDFView updated with document: \(doc.pageCount) pages")
            }
        }

        highlightMatches(in: view)
    }
#else
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        
        if let doc = document {
            v.document = doc
        }
        
        return v
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if let doc = document {
            if view.document !== doc {
                view.document = doc
                // print("💻 PDFView updated with document: \(doc.pageCount) pages")
            }
        }

        highlightMatches(in: view)
    }
#endif

    private func highlightMatches(in view: PDFView) {
        view.highlightedSelections = matches

        guard !matches.isEmpty,
              currentMatchIndex < matches.count else { return }

        let selection = matches[currentMatchIndex]
        view.go(to: selection)
        view.setCurrentSelection(selection, animate: true)
    }
}

// MARK: - Manual Storage Helper

enum ManualStorage {
    /// Stores a picked PDF in iCloud Drive and returns the iCloud path, plus legacy bookmark data for backwards compatibility
    static func copyPDFIntoAppSupport(pickedURL: URL, deviceId: UUID) throws -> (url: URL, bookmarkData: Data) {
        // Check if iCloud sync is enabled
        let iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        
        if iCloudSyncEnabled && iCloudDocumentManager.isiCloudAvailable() {
            // Store in iCloud Drive for cross-device sync
            let originalName = pickedURL.lastPathComponent
            let sanitized = sanitizeFileName(originalName.isEmpty ? "Manual.pdf" : originalName)
            
            let iCloudPath = try iCloudDocumentManager.storeFileIniCloud(
                localURL: pickedURL,
                fileName: sanitized
            )
            
            // Return a placeholder URL and empty bookmark data
            // The actual file is in iCloud, referenced by iCloudPath
            let placeholderURL = URL(fileURLWithPath: "/iCloud/\(iCloudPath)")
            return (placeholderURL, Data())
        } else {
            // Fallback to local Application Support storage (legacy behavior)
            return try copyPDFToLocalStorage(pickedURL: pickedURL, deviceId: deviceId)
        }
    }
    
    /// Legacy method: Copies PDF to local Application Support (used when iCloud is disabled)
    private static func copyPDFToLocalStorage(pickedURL: URL, deviceId: UUID) throws -> (url: URL, bookmarkData: Data) {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let manualsDir = appSupport
            .appendingPathComponent("Manuals", isDirectory: true)
            .appendingPathComponent(deviceId.uuidString, isDirectory: true)

        try fm.createDirectory(at: manualsDir, withIntermediateDirectories: true)

        let originalName = pickedURL.lastPathComponent
        let sanitized = sanitizeFileName(originalName.isEmpty ? "Manual.pdf" : originalName)

        var dest = manualsDir.appendingPathComponent(sanitized)

        // Avoid collisions
        if fm.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension.isEmpty ? "pdf" : dest.pathExtension
            dest = manualsDir.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        }

        // If source is security-scoped (common on macOS/iOS), use scoped access.
        let needsScoped = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if needsScoped { pickedURL.stopAccessingSecurityScopedResource() }
        }

        // Copy (or replace if needed)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: pickedURL, to: dest)

        // Create a security-scoped bookmark for the file
        let bookmarkData = try dest.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return (dest, bookmarkData)
    }
    
    /// Resolves a bookmark to a URL, handling stale bookmarks.
    static func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withoutUI,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        // if isStale {
        //     print("⚠️ Bookmark is stale, but URL resolved to: \(url.path)")
        // }
        
        return url
    }
    
    /// Resolves a DocLink to a URL, handling both iCloud and local storage
    static func resolveDocLink(_ doc: DocLink) throws -> URL {
        #if DEBUG
        print("📄 Resolving DocLink: '\(doc.title)'")
        print("   iCloudPath: \(doc.iCloudDocumentPath ?? "nil")")
        print("   localBookmark: \(doc.localBookmarkData != nil ? "present" : "nil")")
        print("   urlString: \(doc.urlString ?? "nil")")
        #endif
        
        // First try iCloud path (new method)
        if let iCloudPath = doc.iCloudDocumentPath, !iCloudPath.isEmpty {
            #if DEBUG
            print("   Attempting iCloud retrieval for: \(iCloudPath)")
            #endif
            
            if let url = iCloudDocumentManager.getFileFromiCloud(relativePath: iCloudPath) {
                #if DEBUG
                print("   ✅ iCloud URL resolved: \(url.path)")
                #endif
                return url
            } else {
                #if DEBUG
                print("   ❌ iCloud file not accessible")
                #endif
                throw iCloudDocumentError.fileNotFound
            }
        }
        
        // Try local bookmark (legacy method)
        if let bookmarkData = doc.localBookmarkData, !bookmarkData.isEmpty {
            #if DEBUG
            print("   Attempting local bookmark resolution")
            #endif
            return try resolveBookmark(bookmarkData)
        }
        
        // Try URL string (oldest legacy method for web URLs)
        if let urlString = doc.urlString, let url = URL(string: urlString) {
            #if DEBUG
            print("   Using URL string: \(urlString)")
            #endif
            return url
        }
        
        #if DEBUG
        print("   ❌ No valid path found for manual")
        #endif
        throw iCloudDocumentError.fileNotFound
    }

    private static func sanitizeFileName(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ()")
        let filtered = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "Manual.pdf" : out
    }
}
