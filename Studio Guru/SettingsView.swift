//
//  SettingsView.swift
//  Studio Guru
//
//  Settings and preferences view
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var studios: [Studio]
    
    @State private var showingSyncReset = false
    @State private var syncResetConfirmed = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundStyle(.green)
                            Text("iCloud Sync Active")
                                .font(.headline)
                        }
                        
                        Text("Your studios sync automatically across all your devices using iCloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if studios.count > 0 {
                            Text("Currently syncing \(studios.count) studio\(studios.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Data Sync")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your studio data is stored securely in your personal iCloud account and syncs automatically between your iPad and Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Changes sync automatically when online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Last modified data takes priority")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Data never leaves your iCloud account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How It Works")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you see different data on different devices:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("1. Ensure both devices are online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("2. Wait a few minutes for sync to complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("3. Force quit and relaunch the app on both devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("4. The most recently saved changes will appear on all devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showingSyncReset = true
                    } label: {
                        Label("Reset Sync & Use This Device's Data", systemImage: "arrow.triangle.2.circlepath.icloud")
                    }
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("Use 'Reset Sync' only if data isn't syncing properly. This will upload this device's data to iCloud and other devices will download it.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To share studios with others or create backups, use the Export feature from the toolbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                            Text("Export creates a .studioguru file")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(.blue)
                            Text("Import loads a .studioguru file")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Sharing & Backup")
                } footer: {
                    Text("Exported files can be shared via email, AirDrop, or cloud storage services.")
                }
                
                Section {
                    HStack {
                        Text("Version")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appVersion)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("Build")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(buildNumber)
                    }
                    .font(.caption)
                } header: {
                    Text("About")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .padding()
            #endif
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Reset iCloud Sync?", isPresented: $showingSyncReset) {
                Button("Cancel", role: .cancel) {}
                Button("Reset & Upload This Data", role: .destructive) {
                    resetSyncAndForceUpload()
                }
            } message: {
                Text("This will mark all data on this device as 'new' and upload it to iCloud. Other devices will download this data. Use this if sync seems stuck.\n\nIMPORTANT: Make sure this device has the data you want to keep!")
            }
        }
    }
    
    private func resetSyncAndForceUpload() {
        // Touch all studios to update their modification dates
        // This makes CloudKit prioritize this device's data
        for studio in studios {
            // Update timestamp by accessing and re-setting a property
            let currentName = studio.name
            studio.name = currentName
            
            // Same for devices
            for device in studio.devices ?? [] {
                let currentNickname = device.nickname
                device.nickname = currentNickname
            }
        }
        
        // Save to trigger CloudKit sync
        try? modelContext.save()
        
        #if DEBUG
        print("🔄 Sync reset: Updated \(studios.count) studios to force upload to iCloud")
        #endif
    }
}

#Preview {
    SettingsView()
}
