//
//  Studio_GuruApp.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import SwiftUI
import SwiftData
import CloudKit

@main
struct Studio_GuruApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var storeManager = StoreManager()
    @StateObject private var cloudKitSync = CloudKitSyncManager()
    @StateObject private var backupManager = BackupManager()
    @State private var autoSyncMessage: String?
    @State private var showingRestoreAlert = false
    @State private var restoreBackupDate: Date?
    @State private var lastBackupCheck = Date()
    @Environment(\.scenePhase) var scenePhase
    
    private var restoreAlertMessage: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        if let date = restoreBackupDate {
            return "Newer data from iCloud Drive is available (\(formatter.string(from: date))). The app will sync this data and restart.\n\nYour current data will be replaced with the iCloud data."
        } else {
            return "Newer data from iCloud Drive is available. The app will sync this data and restart."
        }
    }

    var sharedModelContainer: ModelContainer = {
        // SwiftData schema - migration happens automatically when models change
        let schema = Schema([
            Studio.self,
            DeviceInstance.self,
            Port.self,
            Channel.self,
            Connection.self,
            DocLink.self,
            ConnectionBundleModel.self,
            ConnectionEdgeModel.self,
            EndpointNameModel.self
        ])
        
        // CRITICAL: Perform complete backup restore BEFORE creating main container
        // This does: 1) Copy backup files  2) Update timestamps  3) Set success flag
        // Must happen before ModelContainer opens the database to avoid corruption and sync conflicts
        do {
            try BackupManager.performRestoreOnLaunchIfNeeded(schema: schema)
        } catch {
            #if DEBUG
            print("❌ Failed to restore backup on launch: \(error)")
            #endif
            // Continue anyway - better to launch than crash
            // User will see the error and can try restore again
        }
        
        // IMPORTANT: We use manual CloudKit sync instead of SwiftData's automatic sync
        // This gives us complete control and deterministic behavior
        // SwiftData's automatic CloudKit sync (.automatic) is disabled
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none  // Manual CloudKit sync via CloudKitSyncManager
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Log sync activity for debugging and support
            let logMessage = """
            📱 SwiftData Container Initialized
            📱 iCloud Sync: Manual CloudKit sync via CloudKitSyncManager
            📱 Container URL: \(container.configurations.first?.url.path ?? "unknown")
            📱 CloudKit Database: \(modelConfiguration.cloudKitDatabase)
            📱 Team ID: BSUPN2VUX7
            📱 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
            📱 App Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
            📱 Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
            📱 Ubiquity Identity Token: \(FileManager.default.ubiquityIdentityToken != nil ? "Present" : "Missing")
            """
            
            #if DEBUG
            print(logMessage)
            #endif
            
            // Always log to support file for troubleshooting
            Self.logToSupportFile(logMessage)
            
            // Check CloudKit container status (manual sync always available for Pro users)
            let checkCloudKit = true
            if checkCloudKit {
                Task {
                    let ckContainer = CKContainer(identifier: "iCloud.com.ianmiller.studioguru")
                    let containerLog = "📱 CloudKit container: iCloud.com.ianmiller.studioguru"
                    
                    #if DEBUG
                    print(containerLog)
                    #endif
                    Self.logToSupportFile(containerLog)
                    
                    do {
                        let accountStatus = try await ckContainer.accountStatus()
                        var statusLog = ""
                        
                        switch accountStatus {
                        case .available:
                            statusLog = "✅ iCloud account is available"
                        case .noAccount:
                            statusLog = "❌ No iCloud account signed in"
                        case .restricted:
                            statusLog = "❌ iCloud account is restricted"
                        case .couldNotDetermine:
                            statusLog = "⚠️ Could not determine iCloud account status"
                        case .temporarilyUnavailable:
                            statusLog = "⚠️ iCloud temporarily unavailable"
                        @unknown default:
                            statusLog = "⚠️ Unknown iCloud account status"
                        }
                        
                        #if DEBUG
                        print(statusLog)
                        #endif
                        Self.logToSupportFile(statusLog)
                        
                        // Try to get user record ID to verify container access
                        do {
                            let userRecordID = try await ckContainer.userRecordID()
                            let userLog = "✅ CloudKit user record accessible: \(userRecordID.recordName)"
                            #if DEBUG
                            print(userLog)
                            #endif
                            Self.logToSupportFile(userLog)
                        } catch {
                            let errorLog = "⚠️ Could not access user record: \(error.localizedDescription)"
                            #if DEBUG
                            print(errorLog)
                            #endif
                            Self.logToSupportFile(errorLog)
                        }
                        
                    } catch {
                        let errorLog = """
                        ❌ CloudKit account check error: \(error)
                        ❌ This may indicate Team ID mismatch or container configuration issues
                        """
                        #if DEBUG
                        print(errorLog)
                        #endif
                        Self.logToSupportFile(errorLog)
                    }
                }
            }
            #if DEBUG
            #else
            // In production, log that we're running in production mode
            Self.logToSupportFile("📱 Running in PRODUCTION mode")
            #endif
            
            return container
        } catch {
            // Log the error for debugging with details
            print("❌ Failed to create ModelContainer: \(error)")
            print("❌ Error type: \(type(of: error))")
            print("❌ Error description: \(error.localizedDescription)")
            
            #if DEBUG
            // In debug, try to create without CloudKit to help diagnose
            print("⚠️ Attempting to create local-only container for debugging...")
            do {
                let localConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: false,
                    cloudKitDatabase: .none
                )
                let localContainer = try ModelContainer(for: schema, configurations: [localConfig])
                print("✅ Local-only container created successfully")
                print("⚠️ WARNING: iCloud sync is DISABLED - check iCloud container configuration!")
                return localContainer
            } catch {
                print("❌ Even local container failed: \(error)")
                fatalError("Could not create ModelContainer: \(error)")
            }
            #else
            // In production, try to create a fallback in-memory container
            print("⚠️ Attempting to create fallback in-memory container")
            do {
                let fallbackConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
            }
            #endif
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            StudioCanvasView()
                .environmentObject(storeManager)
                .environmentObject(cloudKitSync)
                .onAppear {
                    // Initialize CloudKit sync manager with model context
                    cloudKitSync.setModelContext(sharedModelContainer.mainContext)
                    
                    #if os(macOS)
                    // Pass backup manager and container to AppDelegate for quit handling
                    appDelegate.backupManager = backupManager
                    appDelegate.modelContainer = sharedModelContainer
                    #endif
                }
                .onChange(of: storeManager.isPro) { oldValue, newValue in
                    // When Pro status becomes true, ensure Gear Locker exists
                    if newValue && !oldValue {
                        print("🔍 Pro status changed to true, creating Gear Locker")
                        let context = sharedModelContainer.mainContext
                        let descriptor = FetchDescriptor<Studio>()
                        if let studios = try? context.fetch(descriptor) {
                            StudioSeed.ensureGearLockerExists(modelContext: context, studios: studios)
                        }
                    }
                }
                .onAppear {
                    // Also check immediately in case user is already Pro
                    if storeManager.isPro {
                        print("🔍 User is already Pro on appear, creating Gear Locker")
                        let context = sharedModelContainer.mainContext
                        let descriptor = FetchDescriptor<Studio>()
                        if let studios = try? context.fetch(descriptor) {
                            StudioSeed.ensureGearLockerExists(modelContext: context, studios: studios)
                        }
                    }
                    
                    // Perform automatic iCloud Drive sync on launch
                    let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
                    if iCloudSyncEnabled {
                        Task {
                            do {
                                let result = try await backupManager.performAutoSyncWithiCloud(container: sharedModelContainer)
                                
                                // Handle sync from iCloud scheduled for next launch
                                if case .restoredFromiCloud(let backupDate) = result {
                                    await MainActor.run {
                                        restoreBackupDate = backupDate
                                        showingRestoreAlert = true
                                    }
                                    print("📥 Sync from iCloud scheduled - user needs to restart app")
                                } else if let message = result.message {
                                    await MainActor.run {
                                        autoSyncMessage = message
                                    }
                                    print("✅ Auto-sync: \(message)")
                                }
                            } catch {
                                print("❌ Auto-sync failed: \(error)")
                            }
                        }
                    }
                }
                .alert("iCloud Sync Available", isPresented: $showingRestoreAlert) {
                    Button("Restart Now", role: .destructive) {
                        exit(0)
                    }
                    Button("Cancel", role: .cancel) {
                        // Clear the restore flag
                        UserDefaults.standard.removeObject(forKey: "backupToRestoreOnLaunch")
                    }
                } message: {
                    Text(restoreAlertMessage)
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    // Auto-sync to iCloud when app goes to background or becomes inactive
                    let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
                    
                    // Sync when transitioning FROM active to inactive/background
                    // This catches: minimizing, switching apps, closing windows, etc.
                    if iCloudSyncEnabled && oldPhase == .active && (newPhase == .background || newPhase == .inactive) {
                        Task {
                            do {
                                try await backupManager.createBackup(container: sharedModelContainer)
                                print("✅ Auto-sync to iCloud completed (phase: \(oldPhase) → \(newPhase))")
                                lastBackupCheck = Date()
                            } catch {
                                print("❌ Auto-sync to iCloud failed: \(error)")
                            }
                        }
                    }
                    
                    // Also sync periodically when app becomes active (every 5 minutes)
                    // This ensures syncs happen even if scene phase changes don't fire reliably
                    if iCloudSyncEnabled && newPhase == .active {
                        let timeSinceLastBackup = Date().timeIntervalSince(lastBackupCheck)
                        if timeSinceLastBackup > 300 { // 5 minutes
                            Task {
                                do {
                                    try await backupManager.createBackup(container: sharedModelContainer)
                                    print("✅ Periodic sync to iCloud completed (5+ min since last sync)")
                                    lastBackupCheck = Date()
                                } catch {
                                    print("❌ Periodic sync to iCloud failed: \(error)")
                                }
                            }
                        }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Studio Guru Help") {
                    // Post notification to show help
                    NotificationCenter.default.post(name: NSNotification.Name("ShowHelp"), object: nil)
                }
                .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
    
    /// Log messages to a support file that users can share for troubleshooting
    static func logToSupportFile(_ message: String) {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let logFileURL = documentsPath.appendingPathComponent("StudioGuru_iCloud_Diagnostics.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        // Create or append to log file
        if let data = logEntry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                // Append to existing file
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                // Create new file
                try? data.write(to: logFileURL)
            }
        }
        
        // Keep log file size reasonable (max 100KB)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
           let fileSize = attributes[.size] as? Int,
           fileSize > 100_000 {
            // Truncate old entries - just keep last 50KB
            if let logData = try? Data(contentsOf: logFileURL) {
                let truncatedData = logData.suffix(50_000)
                try? truncatedData.write(to: logFileURL)
            }
        }
    }
    
    /// Get the diagnostics log file URL for sharing
    static func getDiagnosticsLogURL() -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let logFileURL = documentsPath.appendingPathComponent("StudioGuru_iCloud_Diagnostics.log")
        return FileManager.default.fileExists(atPath: logFileURL.path) ? logFileURL : nil
    }
}
