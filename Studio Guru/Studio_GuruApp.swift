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
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Log sync activity for debugging
            #if DEBUG
            // print("📱 SwiftData container initialized with CloudKit sync")
            // print("📱 Container URL: \(container.configurations.first?.url.path ?? "unknown")")
            // print("📱 CloudKit database: \(modelConfiguration.cloudKitDatabase)")
            #endif
            
            return container
        } catch {
            // Log the error for debugging with details
            print("❌ Failed to create ModelContainer: \(error)")
            print("❌ Error type: \(type(of: error))")
            if let swiftDataError = error as? any Error {
                print("❌ Error description: \(swiftDataError.localizedDescription)")
            }
            
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
    }
}
