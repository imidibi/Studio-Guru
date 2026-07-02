//
//  Studio_GuruApp.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import SwiftUI
import SwiftData
import CloudKit
import CoreData

@main
struct Studio_GuruApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @StateObject private var storeManager = StoreManager()
    @State private var cloudKitSyncStatus: String?
    @State private var isCloudKitSyncing = false
    @Environment(\.scenePhase) var scenePhase
    


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
        
        // IMPORTANT: Use SwiftData's automatic CloudKit sync
        // This is Apple's recommended approach and handles:
        // - Automatic conflict resolution (last-writer-wins based on modifiedAt timestamps)
        // - Background sync across all devices
        // - Schema migration when models change
        // - Fresh install data merging
        // - Error recovery and retry logic
        //
        // The .automatic option reads the first CloudKit container from entitlements
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic  // Use CloudKit container from entitlements
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Log sync activity for debugging and support
            let logMessage = """
            📱 SwiftData Container Initialized
            📱 iCloud Sync: AUTOMATIC via SwiftData CloudKit integration
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
                .onAppear {
                    // Start monitoring CloudKit sync events
                    setupCloudKitMonitoring()
                }
                .onChange(of: storeManager.isPro) { oldValue, newValue in
                    // When Pro status becomes true, ensure Gear Locker exists
                    // But only if user has at least one regular studio
                    if newValue && !oldValue {
                        print("🔍 Pro status changed to true, creating Gear Locker")
                        let context = sharedModelContainer.mainContext
                        let descriptor = FetchDescriptor<Studio>()
                        if let studios = try? context.fetch(descriptor) {
                            let regularStudios = studios.filter { !$0.isSystemStudio }
                            if !regularStudios.isEmpty {
                                StudioSeed.ensureGearLockerExists(modelContext: context, studios: studios)
                            }
                        }
                    }
                }
                .onAppear {
                    // Also check immediately in case user is already Pro
                    // But only if user has at least one regular studio
                    if storeManager.isPro {
                        print("🔍 User is already Pro on appear, creating Gear Locker")
                        let context = sharedModelContainer.mainContext
                        let descriptor = FetchDescriptor<Studio>()
                        if let studios = try? context.fetch(descriptor) {
                            let regularStudios = studios.filter { !$0.isSystemStudio }
                            if !regularStudios.isEmpty {
                                StudioSeed.ensureGearLockerExists(modelContext: context, studios: studios)
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
    
    /// Monitor CloudKit sync events to provide user feedback and log issues
    /// This is the recommended approach per Apple's best practices for NSPersistentCloudKitContainer
    private func setupCloudKitMonitoring() {
        // Monitor CloudKit sync events (available iOS 14+)
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }
            
            let logMessage: String
            
            switch event.type {
            case .setup:
                logMessage = "☁️ CloudKit: Setting up sync"
                self.isCloudKitSyncing = true
                
            case .import:
                if event.endDate != nil {
                    // Import completed
                    logMessage = "☁️ CloudKit: Import completed"
                    self.isCloudKitSyncing = false
                    self.cloudKitSyncStatus = "Synced from iCloud"
                } else {
                    // Import started
                    logMessage = "☁️ CloudKit: Importing from iCloud"
                    self.isCloudKitSyncing = true
                }
                
            case .export:
                if event.endDate != nil {
                    // Export completed
                    logMessage = "☁️ CloudKit: Export completed"
                    self.isCloudKitSyncing = false
                    self.cloudKitSyncStatus = "Synced to iCloud"
                } else {
                    // Export started
                    logMessage = "☁️ CloudKit: Exporting to iCloud"
                    self.isCloudKitSyncing = true
                }
                
            @unknown default:
                logMessage = "☁️ CloudKit: Unknown event type"
            }
            
            #if DEBUG
            print(logMessage)
            #endif
            Self.logToSupportFile(logMessage)
            
            // Handle errors
            if let error = event.error {
                let errorMessage = "❌ CloudKit sync error: \(error.localizedDescription)"
                
                #if DEBUG
                print(errorMessage)
                print("   Error type: \(type(of: error))")
                if let nsError = error as NSError? {
                    print("   Domain: \(nsError.domain), Code: \(nsError.code)")
                    print("   User info: \(nsError.userInfo)")
                }
                #endif
                
                Self.logToSupportFile(errorMessage)
                
                // Handle specific error types per best practices
                if let nsError = error as NSError? {
                    switch nsError.code {
                    case 134404: // CKErrorNotAuthenticated / Not logged in to iCloud
                        self.cloudKitSyncStatus = "Not signed in to iCloud"
                        
                    case 134405: // CKErrorAccountChanged / iCloud account changed
                        self.cloudKitSyncStatus = "iCloud account changed - please restart app"
                        
                    case 25: // CKErrorQuotaExceeded
                        self.cloudKitSyncStatus = "iCloud storage full"
                        
                    case 134020: // NSPersistentStoreError / Merge error
                        self.cloudKitSyncStatus = "Sync conflict - retrying"
                        
                    default:
                        // Log other errors but don't show to user unless persistent
                        if event.succeeded == false {
                            self.cloudKitSyncStatus = "Sync issue - check iCloud settings"
                        }
                    }
                }
                
                self.isCloudKitSyncing = false
            }
            
            // Clear status message after a delay if sync succeeded
            if event.succeeded && event.endDate != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.cloudKitSyncStatus != nil {
                        self.cloudKitSyncStatus = nil
                    }
                }
            }
        }
        
        #if DEBUG
        print("☁️ CloudKit event monitoring enabled")
        #endif
        Self.logToSupportFile("☁️ CloudKit event monitoring enabled")
    }
}
