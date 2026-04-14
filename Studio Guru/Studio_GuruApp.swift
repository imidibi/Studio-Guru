//
//  Studio_GuruApp.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import SwiftUI
import SwiftData

@main
struct Studio_GuruApp: App {
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
        
        // Check user preference for iCloud sync
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? true
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: iCloudSyncEnabled ? .automatic : .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Log sync activity for debugging
            #if DEBUG
            print("📱 SwiftData container initialized")
            print("📱 iCloud Sync: \(iCloudSyncEnabled ? "Enabled" : "Disabled")")
            print("📱 Container URL: \(container.configurations.first?.url.path ?? "unknown")")
            print("📱 CloudKit database: \(modelConfiguration.cloudKitDatabase)")
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
}
