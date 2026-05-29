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
        // Find all Gear Lockers (there might be duplicates from iCloud sync)
        let existingLockers = studios.filter {
            $0.isSystemStudio && $0.systemStudioType == "gear_locker"
        }
        
        if existingLockers.isEmpty {
            // No Gear Locker exists, create one
            let locker = Studio(name: "Gear Locker")
            locker.isSystemStudio = true
            locker.systemStudioType = "gear_locker"
            locker.layoutMode = "list"  // Custom layout mode for inventory view
            modelContext.insert(locker)
            
            do {
                try modelContext.save()
                print("✅ Created Gear Locker")
            } catch {
                print("❌ Failed to create Gear Locker: \(error)")
            }
        } else if existingLockers.count > 1 {
            // Multiple Gear Lockers exist - merge them
            print("⚠️ Found \(existingLockers.count) Gear Lockers, merging...")
            mergeDuplicateGearLockers(modelContext: modelContext, lockers: existingLockers)
        } else {
            // Exactly one Gear Locker exists - all good
            print("✅ Gear Locker exists: \(existingLockers[0].id)")
        }
    }
    
    /// Merges multiple Gear Lockers into one, preserving all devices
    static func mergeDuplicateGearLockers(modelContext: ModelContext, lockers: [Studio]) {
        guard lockers.count > 1 else { return }
        
        print("⚠️ Merging \(lockers.count) Gear Lockers...")
        
        // Sort by creation date - keep the oldest one (most likely to have been synced first)
        let sortedLockers = lockers.sorted { $0.createdAt < $1.createdAt }
        let primaryLocker = sortedLockers[0]
        let duplicateLockers = Array(sortedLockers.dropFirst())
        
        print("  Keeping locker \(primaryLocker.id) (created: \(primaryLocker.createdAt))")
        
        if primaryLocker.devices == nil {
            primaryLocker.devices = []
        }
        
        // Collect all devices from duplicate lockers
        for locker in duplicateLockers {
            guard let devices = locker.devices, !devices.isEmpty else { continue }
            
            print("  Processing \(devices.count) devices from locker \(locker.id)")
            
            for device in devices {
                // Check if device already exists in primary locker
                let isDuplicate = primaryLocker.devices?.contains { existing in
                    existing.manufacturer == device.manufacturer &&
                    existing.model == device.model &&
                    existing.serialNumber == device.serialNumber
                } ?? false
                
                if !isDuplicate {
                    // Remove from old locker's array (don't rely on cascade)
                    if let index = locker.devices?.firstIndex(where: { $0.id == device.id }) {
                        locker.devices?.remove(at: index)
                    }
                    // Add to primary locker
                    primaryLocker.devices?.append(device)
                    print("    Moved: \(device.manufacturer) \(device.model)")
                } else {
                    print("    Skipping duplicate: \(device.manufacturer) \(device.model)")
                }
            }
        }
        
        // Save changes to move devices
        do {
            try modelContext.save()
            print("  Saved device moves")
        } catch {
            print("  ❌ Failed to save device moves: \(error)")
            return
        }
        
        // Now delete duplicate lockers (should be empty now)
        for locker in duplicateLockers {
            print("  Deleting locker: \(locker.id) (has \(locker.devices?.count ?? 0) devices)")
            modelContext.delete(locker)
        }
        
        primaryLocker.markAsModified()
        
        do {
            try modelContext.save()
            print("✅ Successfully merged - primary locker now has \(primaryLocker.devices?.count ?? 0) devices")
        } catch {
            print("❌ Failed to delete duplicate lockers: \(error)")
        }
    }
}   
