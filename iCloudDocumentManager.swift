//
//  iCloudDocumentManager.swift
//  Studio Guru
//
//  Manager for storing and retrieving device manuals/documents in iCloud Drive
//

import Foundation

enum iCloudDocumentError: Error {
    case iCloudNotAvailable
    case fileNotFound
    case copyFailed
    case ubiquityContainerNotFound
}

class iCloudDocumentManager {
    
    /// Extract the original filename from an iCloud path (removes UUID prefix)
    /// iCloud paths are stored as: UUID_originalfilename.ext
    /// UUID is always 36 characters, so we skip 37 characters (36 + underscore)
    static func extractOriginalFilename(from iCloudPath: String) -> String {
        // UUID format: 8-4-4-4-12 = 36 characters + 1 underscore = 37
        guard iCloudPath.count > 37 else {
            return iCloudPath
        }
        
        let startIndex = iCloudPath.index(iCloudPath.startIndex, offsetBy: 37)
        return String(iCloudPath[startIndex...])
    }
    
    /// Get the iCloud Documents directory for this app
    static func getiCloudDocumentsDirectory() -> URL? {
        // Try with explicit container identifier first
        var ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.ianmiller.studioguru")
        
        if ubiquityURL == nil {
            // Fallback to default container
            ubiquityURL = FileManager.default.url(forUbiquityContainerIdentifier: nil)
        }
        
        guard let ubiquityURL = ubiquityURL else {
            return nil
        }
        
        let documentsURL = ubiquityURL.appendingPathComponent("Documents/DeviceManuals", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: documentsURL.path) {
            try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }
        
        return documentsURL
    }
    
    /// Store a local file in iCloud Drive and return the relative path
    static func storeFileIniCloud(localURL: URL, fileName: String) throws -> String {
        guard let iCloudDocsURL = getiCloudDocumentsDirectory() else {
            throw iCloudDocumentError.iCloudNotAvailable
        }
        
        // Create a unique filename to avoid collisions
        let fileExtension = localURL.pathExtension
        // Remove extension from fileName if it's already there
        let baseFileName = (fileName as NSString).deletingPathExtension
        let uniqueFileName = "\(UUID().uuidString)_\(baseFileName).\(fileExtension)"
        let destinationURL = iCloudDocsURL.appendingPathComponent(uniqueFileName)
        
        // If source is security-scoped (common on macOS/iOS), use scoped access.
        let needsSourceScoped = localURL.startAccessingSecurityScopedResource()
        defer {
            if needsSourceScoped { localURL.stopAccessingSecurityScopedResource() }
        }
        
        // Copy file to iCloud
        do {
            // Check if source file exists
            guard FileManager.default.fileExists(atPath: localURL.path) else {
                throw iCloudDocumentError.fileNotFound
            }
            
            // Read the data and write it (more reliable than copyItem for iCloud)
            let data = try Data(contentsOf: localURL)
            
            // Write to iCloud destination
            try data.write(to: destinationURL, options: .atomic)
            
            // Return relative path (just the filename)
            return uniqueFileName
        } catch {
            throw iCloudDocumentError.copyFailed
        }
    }
    
    /// Retrieve a file from iCloud Drive using its relative path
    static func getFileFromiCloud(relativePath: String) -> URL? {
        guard let iCloudDocsURL = getiCloudDocumentsDirectory() else {
            return nil
        }
        
        let fileURL = iCloudDocsURL.appendingPathComponent(relativePath)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("⚠️ File not found in iCloud: \(relativePath)")
            #endif
            return nil
        }
        
        // Start downloading if not yet downloaded
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        } catch {
            #if DEBUG
            print("⚠️ Could not start downloading: \(error)")
            #endif
        }
        
        return fileURL
    }
    
    /// Delete a file from iCloud Drive
    static func deleteFileFromiCloud(relativePath: String) throws {
        guard let iCloudDocsURL = getiCloudDocumentsDirectory() else {
            throw iCloudDocumentError.iCloudNotAvailable
        }
        
        let fileURL = iCloudDocsURL.appendingPathComponent(relativePath)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
            #if DEBUG
            print("🗑️ Deleted document from iCloud: \(relativePath)")
            #endif
        }
    }
    
    /// Check if iCloud Drive is available
    static func isiCloudAvailable() -> Bool {
        return FileManager.default.ubiquityIdentityToken != nil
    }
    
    /// Migrate existing local bookmarks to iCloud storage
    static func migrateLocalBookmarkToiCloud(bookmarkData: Data, fileName: String) throws -> String {
        var isStale = false
        
        // Resolve bookmark with platform-specific options
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        
        guard let url = try? URL(resolvingBookmarkData: bookmarkData,
                                  options: options,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) else {
            throw iCloudDocumentError.fileNotFound
        }
        
        // Start accessing security-scoped resource
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Copy to iCloud
        return try storeFileIniCloud(localURL: url, fileName: fileName)
    }
    
    /// Migrate a DocLink from local storage to iCloud (if iCloud is enabled and available)
    static func migrateDocLinkToiCloud(_ docLink: DocLink) -> Bool {
        // Only migrate if iCloud is enabled and available
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"),
              isiCloudAvailable() else {
            return false
        }
        
        // Only migrate if it has a local bookmark and no iCloud path yet
        guard let bookmarkData = docLink.localBookmarkData,
              !bookmarkData.isEmpty,
              docLink.iCloudDocumentPath == nil else {
            return false
        }
        
        do {
            let fileName = docLink.title.isEmpty ? "Manual.pdf" : docLink.title
            let iCloudPath = try migrateLocalBookmarkToiCloud(
                bookmarkData: bookmarkData,
                fileName: fileName
            )
            
            // Update the DocLink to use iCloud path
            docLink.iCloudDocumentPath = iCloudPath
            docLink.localBookmarkData = nil  // Clear old bookmark
            docLink.markAsModified()
            
            #if DEBUG
            print("✅ Migrated manual to iCloud: \(fileName)")
            #endif
            
            return true
        } catch {
            #if DEBUG
            print("⚠️ Failed to migrate manual to iCloud: \(error)")
            #endif
            return false
        }
    }
}
