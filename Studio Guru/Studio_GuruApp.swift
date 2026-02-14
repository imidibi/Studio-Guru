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
    var body: some Scene {
        WindowGroup {
            StudioCanvasView()
        }
        .modelContainer(for: [
            Studio.self,
            DeviceInstance.self,
            Port.self,
            Channel.self,
            Connection.self,
            DocLink.self
        ])
    }
}
