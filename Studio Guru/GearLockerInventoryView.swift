//
//  GearLockerInventoryView.swift
//  Studio Guru
//
//  Gear Locker inventory view - shows devices grouped by category
//

import SwiftUI
import SwiftData

struct GearLockerInventoryView: View {
    let studio: Studio
    @Query(sort: \Studio.name, order: .forward) private var allStudios: [Studio]
    @Binding var selectedDeviceId: UUID?
    @Environment(\.modelContext) private var modelContext
    
    let onAssignDevice: (DeviceInstance) -> Void
    let onEditDevice: (DeviceInstance) -> Void
    let onDeleteDevice: (DeviceInstance) -> Void
    
    var body: some View {
        Group {
            if let devices = studio.devices, !devices.isEmpty {
                List {
                    ForEach(groupedDevices.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { category in
                        if let categoryDevices = groupedDevices[category], !categoryDevices.isEmpty {
                            Section(category.rawValue) {
                                ForEach(categoryDevices.sorted(by: { $0.nickname < $1.nickname })) { device in
                                    GearLockerDeviceRow(
                                        device: device,
                                        isAvailable: isDeviceAvailable(device),
                                        assignedStudioName: assignedStudioName(for: device),
                                        onTap: {
                                            selectedDeviceId = device.id
                                        },
                                        onAssign: {
                                            onAssignDevice(device)
                                        },
                                        onEdit: {
                                            onEditDevice(device)
                                        },
                                        onDelete: {
                                            onDeleteDevice(device)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.sidebar)
                #endif
            } else {
                emptyState
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Gear in Locker")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add equipment to your Gear Locker to track gear that's owned but not permanently installed in a studio.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // Group devices by category
    private var groupedDevices: [DeviceCategory: [DeviceInstance]] {
        guard let devices = studio.devices else { return [:] }
        return Dictionary(grouping: devices) { $0.category }
    }
    
    // Check if a device is available (not assigned to a studio)
    private func isDeviceAvailable(_ lockerDevice: DeviceInstance) -> Bool {
        guard lockerDevice.isInGearLocker else { return false }
        
        // Check if any studio device references this locker device
        for studio in allStudios where !studio.isSystemStudio {
            for device in studio.devices ?? [] {
                if device.lockerSourceDeviceId == lockerDevice.id && !device.isGhostDevice {
                    return false  // Device is assigned
                }
            }
        }
        
        return true  // Device is available
    }
    
    // Get the name of the studio where a device is assigned
    private func assignedStudioName(for lockerDevice: DeviceInstance) -> String? {
        guard lockerDevice.isInGearLocker else { return nil }
        
        for studio in allStudios where !studio.isSystemStudio {
            for device in studio.devices ?? [] {
                if device.lockerSourceDeviceId == lockerDevice.id && !device.isGhostDevice {
                    return studio.name
                }
            }
        }
        
        return nil
    }
}

// MARK: - Device Row

struct GearLockerDeviceRow: View {
    let device: DeviceInstance
    let isAvailable: Bool
    let assignedStudioName: String?
    let onTap: () -> Void
    let onAssign: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    private var deviceColor: Color {
        let categoryColors = CategoryColorSettings.loadCategoryColors()
        return device.resolvedColor(categoryColors: categoryColors)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Device icon
                Image(systemName: deviceIcon(for: device.category))
                    .font(.title2)
                    .foregroundColor(deviceColor)
                    .frame(width: 40, height: 40)
                    .background(deviceColor.opacity(0.1))
                    .cornerRadius(8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.nickname)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("\(device.manufacturer) \(device.model)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !isAvailable, let studioName = assignedStudioName {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                            Text("In use: \(studioName)")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if isAvailable {
                    Button(action: onAssign) {
                        Label("Assign", systemImage: "arrow.right.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            #if os(macOS)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            #else
            .padding(.vertical, 4)
            #endif
        }
        .buttonStyle(.plain)
        .opacity(isAvailable ? 1.0 : 0.6)
        #if os(macOS)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        #endif
        .contextMenu {
            Button {
                onTap()
            } label: {
                Label("View Details", systemImage: "info.circle")
            }
            
            if isAvailable {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button {
                    onAssign()
                } label: {
                    Label("Assign to Studio", systemImage: "arrow.right.circle")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // Helper function to get icon for device category
    private func deviceIcon(for category: DeviceCategory) -> String {
        switch category {
        case .adatExpander: return "rectangle.stack"
        case .audioInterface: return "hifispeaker.2"
        case .busCompressor: return "waveform.path.ecg"
        case .channelStrip: return "slider.horizontal.3"
        case .compressor: return "waveform"
        case .computer: return "desktopcomputer"
        case .controlSurface: return "slider.horizontal.2.square.badge.arrow.down"
        case .digitalMixer: return "music.mic"
        case .effectsUnit: return "sparkles"
        case .equalizer: return "slider.horizontal.3"
        case .headphoneAmp: return "amplifier"
        case .headphones: return "headphones"
        case .keyboard: return "pianokeys"
        case .microphone: return "mic"
        case .midiDevice: return "pianokeys.inverse"
        case .mixer: return "dial.medium"
        case .monitor: return "speaker.wave.2"
        case .multi: return "square.stack.3d.up"
        case .patchbay: return "square.grid.3x3"
        case .preamp: return "waveform.circle"
        case .synth: return "waveform.and.person.filled"
        case .usbHub: return "hub"
        case .usbExpander: return "rectangle.connected.to.line.below"
        case .videoMonitor: return "tv"
        case .other: return "shippingbox"
        }
    }
}
