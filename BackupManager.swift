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
        loadAvailableBackups()
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
        
        // Note: The app will need to restart for changes to take effect
        // We'll show this in the UI
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
    
    // MARK: - Private Methods
    
    private func loadAvailableBackups() {
        guard let backupDir = backupDirectory else {
            availableBackups = []
            return
        }
        
        // Load metadata file
        let metadataURL = backupDir.appendingPathComponent("backups_metadata.json")
        
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            availableBackups = []
            return
        }
        
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode([BackupInfo].self, from: data) else {
            availableBackups = []
            return
        }
        
        // Sort by timestamp descending (newest first)
        availableBackups = metadata.sorted { $0.timestamp > $1.timestamp }
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
            metadata = (try? JSONDecoder().decode([BackupInfo].self, from: data)) ?? []
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
        
        guard let data = try? Data(contentsOf: metadataURL),
              var metadata = try? JSONDecoder().decode([BackupInfo].self, from: data) else {
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
        
        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed:
                return "Failed to create backup directory"
            case .storeNotFound:
                return "SwiftData store not found"
            case .backupNotFound:
                return "Backup file not found"
            }
        }
    }
}
