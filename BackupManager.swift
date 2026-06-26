//
//  BackupManager.swift
//  Studio Guru
//

import Foundation
import SwiftData
import Combine

/// Manages automatic backups and restoration of SwiftData database
@MainActor
class BackupManager: ObservableObject {
    @Published var availableBackups: [BackupInfo] = []
    @Published var isCreatingBackup = false
    @Published var isRestoringBackup = false
    @Published var lastError: String?
    
    private let maxBackups = 5
    private let backupDirectoryName = "StudioGuruBackups"
    
    struct BackupInfo: Identifiable, Codable {
        let id: UUID
        let filename: String
        let timestamp: Date
        let fileSize: Int64
        
        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }
        
        var fileSizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        }
    }
    
    init() {
        loadAvailableBackups()
    }
    
    /// Directory where backups are stored (local, not iCloud)
    private var backupDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }
    
    /// Get the current SwiftData store URL
    private func getStoreURL(from container: ModelContainer) -> URL? {
        return container.configurations.first?.url
    }
    
    /// Create a new backup of the SwiftData database
    func createBackup(container: ModelContainer) async throws {
        isCreatingBackup = true
        lastError = nil
        
        defer {
            isCreatingBackup = false
        }
        
        guard let backupDir = backupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        // Create backup directory if it doesn't exist
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Get source store URL
        guard let storeURL = getStoreURL(from: container) else {
            throw BackupError.storeNotFound
        }
        
        // Verify source exists
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw BackupError.storeNotFound
        }
        
        // Create backup filename with timestamp
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestampString = formatter.string(from: timestamp).replacingOccurrences(of: ":", with: "-")
        let backupFilename = "backup_\(timestampString).store"
        let backupURL = backupDir.appendingPathComponent(backupFilename)
        
        // Copy the store file
        try FileManager.default.copyItem(at: storeURL, to: backupURL)
        
        // Also copy the -wal and -shm files if they exist (SQLite Write-Ahead Log)
        let walURL = storeURL.appendingPathExtension("wal")
        let shmURL = storeURL.appendingPathExtension("shm")
        
        if FileManager.default.fileExists(atPath: walURL.path) {
            let backupWalURL = backupURL.appendingPathExtension("wal")
            try? FileManager.default.copyItem(at: walURL, to: backupWalURL)
        }
        
        if FileManager.default.fileExists(atPath: shmURL.path) {
            let backupShmURL = backupURL.appendingPathExtension("shm")
            try? FileManager.default.copyItem(at: shmURL, to: backupShmURL)
        }
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: backupURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        // Record backup info
        let backupInfo = BackupInfo(
            id: UUID(),
            filename: backupFilename,
            timestamp: timestamp,
            fileSize: fileSize
        )
        
        // Save backup metadata
        try saveBackupMetadata(backupInfo)
        
        // Cleanup old backups
        try cleanupOldBackups()
        
        // Reload available backups
        await MainActor.run {
            loadAvailableBackups()
            #if DEBUG
            print("✅ Backup created successfully at: \(backupURL.path)")
            print("📋 Total backups available: \(availableBackups.count)")
            #endif
        }
    }
    
    /// Restore from a backup
    func restoreFromBackup(_ backup: BackupInfo, container: ModelContainer) async throws {
        isRestoringBackup = true
        lastError = nil
        
        defer {
            isRestoringBackup = false
        }
        
        guard let backupDir = backupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        let backupURL = backupDir.appendingPathComponent(backup.filename)
        
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw BackupError.backupNotFound
        }
        
        guard let storeURL = getStoreURL(from: container) else {
            throw BackupError.storeNotFound
        }
        
        // Create a safety backup of current state before restoring
        let safetyBackupURL = storeURL.deletingLastPathComponent().appendingPathComponent("pre-restore-backup.store")
        try? FileManager.default.removeItem(at: safetyBackupURL)
        try FileManager.default.copyItem(at: storeURL, to: safetyBackupURL)
        
        // Remove current store files
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        
        // Copy backup to store location
        try FileManager.default.copyItem(at: backupURL, to: storeURL)
        
        // Copy WAL and SHM files if they exist
        let backupWalURL = backupURL.appendingPathExtension("wal")
        let backupShmURL = backupURL.appendingPathExtension("shm")
        
        if FileManager.default.fileExists(atPath: backupWalURL.path) {
            let walURL = storeURL.appendingPathExtension("wal")
            try? FileManager.default.copyItem(at: backupWalURL, to: walURL)
        }
        
        if FileManager.default.fileExists(atPath: backupShmURL.path) {
            let shmURL = storeURL.appendingPathExtension("shm")
            try? FileManager.default.copyItem(at: backupShmURL, to: shmURL)
        }
        
        // CRITICAL: Mark that we need to update timestamps on next app launch
        // We can't do it now because the database was just copied and the main container might still have locks
        // The timestamp update will happen in updateRestoredTimestampsIfNeeded() on app startup
        UserDefaults.standard.set(true, forKey: "needsTimestampUpdateAfterRestore")
        
        #if DEBUG
        print("✅ Backup restored - timestamps will be updated on next app launch")
        #endif
        
        // Note: The app will need to restart for changes to take effect
        // We'll show this in the UI
    }
    
    /// Updates all modifiedAt timestamps in the restored database to the current date
    /// This ensures the restored data is treated as "newer" than iCloud data during sync
    /// This is called on app startup after a restore, not during the restore itself
    /// This function runs on a background thread to avoid blocking the main thread
    static func updateRestoredTimestampsIfNeeded(container: ModelContainer) throws {
        // Check if we need to update timestamps
        guard UserDefaults.standard.bool(forKey: "needsTimestampUpdateAfterRestore") else {
            return
        }
        
        #if DEBUG
        print("⏰ Updating timestamps in restored database for iCloud sync compatibility...")
        #endif
        
        // Create a background context (doesn't require @MainActor)
        let context = ModelContext(container)
        let now = Date()
        var updatedCount = 0
        
        // Update Studio objects
        let studios = try context.fetch(FetchDescriptor<Studio>())
        for studio in studios {
            studio.modifiedAt = now
            updatedCount += 1
        }
        
        // Update DeviceInstance objects
        let devices = try context.fetch(FetchDescriptor<DeviceInstance>())
        for device in devices {
            device.modifiedAt = now
            updatedCount += 1
        }
        
        // Update Connection objects
        let connections = try context.fetch(FetchDescriptor<Connection>())
        for connection in connections {
            connection.modifiedAt = now
            updatedCount += 1
        }
        
        // Update DocLink objects
        let docLinks = try context.fetch(FetchDescriptor<DocLink>())
        for docLink in docLinks {
            docLink.modifiedAt = now
            updatedCount += 1
        }
        
        // Update ConnectionBundleModel objects
        let bundles = try context.fetch(FetchDescriptor<ConnectionBundleModel>())
        for bundle in bundles {
            bundle.modifiedAt = now
            updatedCount += 1
        }
        
        // Update ConnectionEdgeModel objects
        let edges = try context.fetch(FetchDescriptor<ConnectionEdgeModel>())
        for edge in edges {
            edge.modifiedAt = now
            updatedCount += 1
        }
        
        // Update EndpointNameModel objects
        let endpointNames = try context.fetch(FetchDescriptor<EndpointNameModel>())
        for endpointName in endpointNames {
            endpointName.modifiedAt = now
            updatedCount += 1
        }
        
        // Save all changes
        try context.save()
        
        // Clear the flag now that we're done
        UserDefaults.standard.removeObject(forKey: "needsTimestampUpdateAfterRestore")
        
        // Set a flag so the UI knows to show the success alert
        UserDefaults.standard.set(true, forKey: "didCompleteRestoreThisLaunch")
        
        #if DEBUG
        print("✅ Updated \(updatedCount) object timestamps to \(now)")
        print("   This ensures restored data wins in iCloud sync conflict resolution")
        #endif
    }
    
    /// Delete a specific backup
    func deleteBackup(_ backup: BackupInfo) throws {
        guard let backupDir = backupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        let backupURL = backupDir.appendingPathComponent(backup.filename)
        try FileManager.default.removeItem(at: backupURL)
        
        // Also remove associated WAL and SHM files
        try? FileManager.default.removeItem(at: backupURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: backupURL.appendingPathExtension("shm"))
        
        // Remove from metadata
        try removeBackupMetadata(backup)
        
        loadAvailableBackups()
    }
    
    /// Check if a backup should be created (if last backup is older than 24 hours)
    func shouldCreateAutomaticBackup() -> Bool {
        guard let lastBackup = availableBackups.first else {
            return true // No backups exist
        }
        
        let hoursSinceLastBackup = Date().timeIntervalSince(lastBackup.timestamp) / 3600
        return hoursSinceLastBackup >= 24
    }
    
    /// Check if this is the first launch of a new app version
    func shouldCreateVersionBackup() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        let versionKey = "LastBackupVersion"
        let buildKey = "LastBackupBuild"
        
        let lastVersion = UserDefaults.standard.string(forKey: versionKey)
        let lastBuild = UserDefaults.standard.string(forKey: buildKey)
        
        // If version or build changed, create a backup
        if lastVersion != currentVersion || lastBuild != currentBuild {
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
            UserDefaults.standard.set(currentBuild, forKey: buildKey)
            return true
        }
        
        return false
    }
    
    // MARK: - Private Methods
    
    private func loadAvailableBackups() {
        guard let backupDir = backupDirectory else {
            availableBackups = []
            #if DEBUG
            print("❌ Backup directory not available")
            #endif
            return
        }
        
        #if DEBUG
        print("📂 Backup directory: \(backupDir.path)")
        #endif
        
        // Load metadata file
        let metadataURL = backupDir.appendingPathComponent("backups_metadata.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            availableBackups = []
            #if DEBUG
            print("⚠️ No backup metadata file found at: \(metadataURL.path)")
            #endif
            return
        }
        
        guard let data = try? Data(contentsOf: metadataURL) else {
            availableBackups = []
            #if DEBUG
            print("❌ Failed to read backup metadata file")
            #endif
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let metadata = try? decoder.decode([BackupInfo].self, from: data) else {
            availableBackups = []
            #if DEBUG
            print("❌ Failed to decode backup metadata")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("   Raw JSON: \(jsonString)")
            }
            #endif
            return
        }
        
        // Sort by timestamp descending (newest first)
        availableBackups = metadata.sorted { $0.timestamp > $1.timestamp }
        
        #if DEBUG
        print("✅ Loaded \(availableBackups.count) backups from metadata")
        for backup in availableBackups {
            print("  📦 \(backup.displayName) - \(backup.fileSizeFormatted)")
        }
        #endif
    }
    
    private func saveBackupMetadata(_ backup: BackupInfo) throws {
        guard let backupDir = backupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        let metadataURL = backupDir.appendingPathComponent("backups_metadata.json")
        
        // Load existing metadata
        var metadata: [BackupInfo] = []
        if FileManager.default.fileExists(atPath: metadataURL.path),
           let data = try? Data(contentsOf: metadataURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            metadata = (try? decoder.decode([BackupInfo].self, from: data)) ?? []
        }
        
        // Add new backup
        metadata.append(backup)
        
        // Save
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL)
    }
    
    private func removeBackupMetadata(_ backup: BackupInfo) throws {
        guard let backupDir = backupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        let metadataURL = backupDir.appendingPathComponent("backups_metadata.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return
        }
        
        guard let data = try? Data(contentsOf: metadataURL) else {
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard var metadata = try? decoder.decode([BackupInfo].self, from: data) else {
            return
        }
        
        metadata.removeAll { $0.id == backup.id }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let newData = try encoder.encode(metadata)
        try newData.write(to: metadataURL)
    }
    
    private func cleanupOldBackups() throws {
        guard availableBackups.count > maxBackups else { return }
        
        // Get backups to delete (oldest ones beyond maxBackups)
        let backupsToDelete = availableBackups.sorted { $0.timestamp < $1.timestamp }.prefix(availableBackups.count - maxBackups)
        
        for backup in backupsToDelete {
            try? deleteBackup(backup)
        }
    }
    
    enum BackupError: LocalizedError {
        case directoryCreationFailed
        case storeNotFound
        case backupNotFound
        case timestampUpdateFailed
        
        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed:
                return "Failed to create backup directory"
            case .storeNotFound:
                return "SwiftData store not found"
            case .backupNotFound:
                return "Backup file not found"
            case .timestampUpdateFailed:
                return "Failed to update timestamps for iCloud sync"
            }
        }
    }
}
