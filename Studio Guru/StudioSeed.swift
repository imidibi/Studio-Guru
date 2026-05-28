//
//  StudioSeed.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//
import Foundation
import SwiftData

enum StudioSeed {
    static func ensureSeedStudioExists(modelContext: ModelContext, studios: [Studio]) {
        guard studios.isEmpty else { return }

        let studio = Studio(name: "My Studio")

        let ssl = DeviceInstance(manufacturer: "Solid State Logic", model: "SSL 18", nickname: "SSL 18", posX: 220, posY: 180)
        let p1 = Port(name: "Analog In", type: .analogIn, direction: .input)
        p1.channels = (1...8).map { Channel(index: $0, nameLong: "Analog In \($0)", nameShort: "In\($0)") }
        if ssl.ports == nil { ssl.ports = [] }
        ssl.ports?.append(p1)

        let kong = DeviceInstance(manufacturer: "Korg", model: "Kong Keyboard", nickname: "Kong Keys", posX: 220, posY: 420)
        let p2 = Port(name: "Analog Out", type: .analogOut, direction: .output)
        p2.channels = [
            Channel(index: 1, nameLong: "Left", nameShort: "L", grouping: .fixedStereoPair),
            Channel(index: 2, nameLong: "Right", nameShort: "R", grouping: .fixedStereoPair)
        ]
        if kong.ports == nil { kong.ports = [] }
        kong.ports?.append(p2)

        if studio.devices == nil { studio.devices = [] }
        studio.devices?.append(contentsOf: [ssl, kong])
        modelContext.insert(studio)
    }
    
    static func ensureGearLockerExists(modelContext: ModelContext, studios: [Studio]) {
        // Check if Gear Locker already exists
        let existingLocker = studios.first {
            $0.isSystemStudio && $0.systemStudioType == "gear_locker"
        }
        
        if existingLocker == nil {
            let locker = Studio(name: "Gear Locker")
            locker.isSystemStudio = true
            locker.systemStudioType = "gear_locker"
            locker.layoutMode = "list"  // Custom layout mode for inventory view
            modelContext.insert(locker)
            
            do {
                try modelContext.save()
            } catch {
                print("Failed to create Gear Locker: \(error)")
            }
        }
    }
}   
