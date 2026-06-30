//
//  BackupManager.swift
//  Studio Guru
//

import Foundation
import SwiftData
import Combine
import SQLite3

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
    
    /// Directory where backups are stored (iCloud Drive)
    private var backupDirectory: URL? {
        // Check if iCloud sync is enabled
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        
        if iCloudSyncEnabled {
            // Use iCloud Drive
            guard let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                #if DEBUG
                print("⚠️ iCloud Drive not available, falling back to local storage")
                #endif
                return localBackupDirectory
            }
            return iCloudURL.appendingPathComponent("Documents/\(backupDirectoryName)", isDirectory: true)
        } else {
            // Use local storage when iCloud sync is disabled
            return localBackupDirectory
        }
    }
    
    /// Local backup directory (fallback when iCloud is unavailable)
    private var localBackupDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent(backupDirectoryName, isDirectory: true)
    }
    
    /// Static version for use during app launch before BackupManager instance exists
    static var staticBackupDirectory: URL? {
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        
        if iCloudSyncEnabled {
            if let iCloudURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
                return iCloudURL.appendingPathComponent("Documents/StudioGuruBackups", isDirectory: true)
            }
        }
        
        // Fallback to local
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("StudioGuruBackups", isDirectory: true)
    }
    
    /// Get the default SwiftData store URL without needing a container
    static var defaultStoreURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("default.store")
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
        
        // CRITICAL: Checkpoint the WAL file first to consolidate all changes into the main database
        // This ensures we get a complete, consistent backup without needing WAL/SHM files
        try checkpointWAL(storeURL: storeURL)
        
        // Create backup filename with timestamp
        let timestamp = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestampString = formatter.string(from: timestamp).replacingOccurrences(of: ":", with: "-")
        let backupFilename = "backup_\(timestampString).store"
        let backupURL = backupDir.appendingPathComponent(backupFilename)
        
        // Copy ONLY the main store file (after WAL has been checkpointed)
        // Do NOT copy WAL or SHM files - they should not be part of backups
        try FileManager.default.copyItem(at: storeURL, to: backupURL)
        
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
    
    /// Checkpoint the WAL file to consolidate all changes into the main database file
    /// This ensures the database is in a consistent state before backup
    private func checkpointWAL(storeURL: URL) throws {
        var db: OpaquePointer?
        
        // Open database
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: "Failed to open database: \(errmsg)"])
        }
        
        defer {
            sqlite3_close(db)
        }
        
        // Execute WAL checkpoint
        var statement: OpaquePointer?
        let sql = "PRAGMA wal_checkpoint(TRUNCATE);"
        
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                #if DEBUG
                let busy = sqlite3_column_int(statement, 0)
                let log = sqlite3_column_int(statement, 1)
                let checkpointed = sqlite3_column_int(statement, 2)
                print("📝 WAL checkpoint: busy=\(busy), log=\(log), checkpointed=\(checkpointed)")
                #endif
            }
            sqlite3_finalize(statement)
        } else {
            let errmsg = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw NSError(domain: "SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: "Failed to checkpoint WAL: \(errmsg)"])
        }
    }
    
    /// Restore from a backup
    /// This schedules the backup to be restored on the next app launch (before the ModelContainer is created)
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
        
        // Schedule this backup to be restored on next app launch (before ModelContainer creation)
        // This avoids database corruption from trying to restore while the database is open
        UserDefaults.standard.set(backup.filename, forKey: "backupToRestoreOnLaunch")
        
        #if DEBUG
        print("✅ Backup scheduled for restore on next app launch")
        print("   User will need to restart the app to complete the restore")
        #endif
        
        // Note: The app will need to restart for changes to take effect
        // We'll show this in the UI
    }
    

    
    /// Performs complete backup restore on app launch BEFORE container initialization
    /// This is called from Studio_GuruApp before the main ModelContainer is created
    /// Simply copies the backup file - no timestamp manipulation to avoid database corruption
    static func performRestoreOnLaunchIfNeeded(schema: Schema) throws {
        // Check if there's a backup marked for restore
        guard let backupFilename = UserDefaults.standard.string(forKey: "backupToRestoreOnLaunch") else {
            return
        }
        
        #if DEBUG
        print("🔄 RESTORE ON LAUNCH: Starting restore of '\(backupFilename)'")
        #endif
        
        guard let backupDir = staticBackupDirectory else {
            throw BackupError.directoryCreationFailed
        }
        
        guard let storeURL = defaultStoreURL else {
            throw BackupError.storeNotFound
        }
        
        let backupURL = backupDir.appendingPathComponent(backupFilename)
        
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            #if DEBUG
            print("❌ Backup file not found: \(backupURL.path)")
            #endif
            throw BackupError.backupNotFound
        }
        
        // Create a safety backup of current state before restoring
        let safetyBackupURL = storeURL.deletingLastPathComponent().appendingPathComponent("pre-restore-backup.store")
        try? FileManager.default.removeItem(at: safetyBackupURL)
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try? FileManager.default.copyItem(at: storeURL, to: safetyBackupURL)
            #if DEBUG
            print("📦 Created safety backup at: \(safetyBackupURL.path)")
            #endif
        }
        
        // Remove current store files (including WAL/SHM)
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
        try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
        
        // Copy ONLY the main backup file (backups don't include WAL/SHM)
        try FileManager.default.copyItem(at: backupURL, to: storeURL)
        
        #if DEBUG
        print("✅ Backup restored successfully")
        #endif
        
        // Clean up flags and mark success
        UserDefaults.standard.removeObject(forKey: "backupToRestoreOnLaunch")
        UserDefaults.standard.set(true, forKey: "didCompleteRestoreThisLaunch")
        
        #if DEBUG
        print("✅ RESTORE ON LAUNCH COMPLETE")
        print("   Note: Restored data will use its original timestamps")
        print("   If iCloud has newer data, it may overwrite the restored data during next sync")
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
    
    /// Automatically sync with iCloud Drive backups
    /// Checks if there's a newer backup in iCloud and schedules restore if needed
    /// Or backs up local data if it's newer than what's in iCloud
    func performAutoSyncWithiCloud(container: ModelContainer) async throws -> AutoSyncResult {
        // Only sync if iCloud is enabled
        guard UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false else {
            return .disabled
        }
        
        #if DEBUG
        print("🔄 Checking for iCloud sync...")
        #endif
        
        // Reload backups to get latest from iCloud
        await MainActor.run {
            loadAvailableBackups()
        }
        
        // Get the most recent backup
        guard let latestBackup = availableBackups.first else {
            #if DEBUG
            print("📦 No data found in iCloud, creating initial sync")
            #endif
            try await createBackup(container: container)
            return .createdInitialBackup
        }
        
        // Get the local database's last modified time
        guard let storeURL = getStoreURL(from: container),
              FileManager.default.fileExists(atPath: storeURL.path) else {
            #if DEBUG
            print("⚠️ Local database not found")
            #endif
            return .noLocalData
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        guard let localModifiedDate = attributes[.modificationDate] as? Date else {
            return .error
        }
        
        #if DEBUG
        print("📅 Latest iCloud data: \(latestBackup.timestamp)")
        print("📅 Local data modified: \(localModifiedDate)")
        #endif
        
        // Compare timestamps - if iCloud backup is significantly newer (>60 seconds), schedule restore
        let timeDifference = latestBackup.timestamp.timeIntervalSince(localModifiedDate)
        
        if timeDifference > 60 {
            // iCloud data is newer - schedule it for restore on next launch
            #if DEBUG
            print("📥 iCloud data is newer, scheduling sync from iCloud on next launch...")
            #endif
            UserDefaults.standard.set(latestBackup.filename, forKey: "backupToRestoreOnLaunch")
            return .restoredFromiCloud(backupDate: latestBackup.timestamp)
        } else if timeDifference < -60 {
            // Local data is newer - sync it to iCloud
            #if DEBUG
            print("📤 Local data is newer, syncing to iCloud...")
            #endif
            try await createBackup(container: container)
            return .backedUpToiCloud
        } else {
            // Data is in sync
            #if DEBUG
            print("✅ Data is already in sync")
            #endif
            return .alreadyInSync
        }
    }
    
    enum AutoSyncResult {
        case disabled
        case createdInitialBackup
        case restoredFromiCloud(backupDate: Date)
        case backedUpToiCloud
        case alreadyInSync
        case noLocalData
        case error
        
        var message: String? {
            switch self {
            case .createdInitialBackup:
                return "Created initial iCloud sync"
            case .restoredFromiCloud(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Synced from iCloud (\(formatter.string(from: date)))"
            case .backedUpToiCloud:
                return "Synced to iCloud"
            case .alreadyInSync:
                return nil // Don't show message when already in sync
            default:
                return nil
            }
        }
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
        guard let backupDir = backupDirectory else { return }
        
        // Delete old backups beyond maxBackups
        if availableBackups.count > maxBackups {
            let backupsToDelete = availableBackups.sorted { $0.timestamp < $1.timestamp }.prefix(availableBackups.count - maxBackups)
            
            for backup in backupsToDelete {
                try? deleteBackup(backup)
            }
        }
        
        // Clean up orphaned WAL and SHM files from all backups (these should never exist)
        // We're removing these because old backups may have created them before the fix
        guard let files = try? FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil) else {
            return
        }
        
        for file in files {
            let ext = file.pathExtension.lowercased()
            if ext == "wal" || ext == "shm" {
                #if DEBUG
                print("🧹 Removing orphaned \(ext.uppercased()) file: \(file.lastPathComponent)")
                #endif
                try? FileManager.default.removeItem(at: file)
            }
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
