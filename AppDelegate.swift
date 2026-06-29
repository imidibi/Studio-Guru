//
//  AppDelegate.swift
//  Studio Guru
//
//  Handles app lifecycle events including graceful shutdown with backup
//

import SwiftUI
import SwiftData

#if os(macOS)
import class AppKit.NSApplication

class AppDelegate: NSObject, NSApplicationDelegate {
    var backupManager: BackupManager?
    var modelContainer: ModelContainer?
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check if iCloud sync is enabled
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        
        guard iCloudSyncEnabled, let backupManager = backupManager, let container = modelContainer else {
            // No backup needed, can terminate immediately
            return .terminateNow
        }
        
        print("🛑 App is quitting - syncing final changes to iCloud...")
        
        // Create a semaphore to block termination until sync completes
        let semaphore = DispatchSemaphore(value: 0)
        var syncSucceeded = false
        
        Task {
            do {
                try await backupManager.createBackup(container: container)
                print("✅ Final sync to iCloud completed before quit")
                syncSucceeded = true
            } catch {
                print("❌ Final sync to iCloud failed: \(error)")
            }
            semaphore.signal()
        }
        
        // Wait up to 5 seconds for sync to complete
        let timeout = DispatchTime.now() + .seconds(5)
        let result = semaphore.wait(timeout: timeout)
        
        if result == .timedOut {
            print("⚠️ Sync timed out, terminating anyway")
        } else if syncSucceeded {
            print("✅ Sync completed, safe to terminate")
        }
        
        return .terminateNow
    }
}
#endif

