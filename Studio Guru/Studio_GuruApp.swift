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
            DocLink.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            StudioCanvasView()
        }
        .modelContainer(sharedModelContainer)
    }
}
