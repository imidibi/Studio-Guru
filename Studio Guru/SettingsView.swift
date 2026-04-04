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
    
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = true
    @State private var showingSyncReset = false
    @State private var syncResetConfirmed = false
    @State private var showingRestartAlert = false
    @State private var isSyncing = false
    @State private var lastSyncMessage: String?
    
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
                    Toggle(isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            iCloudSyncEnabled = newValue
                            showingRestartAlert = true
                        }
                    )) {
                        HStack {
                            Image(systemName: iCloudSyncEnabled ? "checkmark.icloud.fill" : "icloud.slash.fill")
                                .foregroundStyle(iCloudSyncEnabled ? .green : .secondary)
                            Text("iCloud Sync")
                                .font(.headline)
                        }
                    }
                    
                    if iCloudSyncEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your studios sync automatically across all your devices using iCloud.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if studios.count > 0 {
                                Text("Currently syncing \(studios.count) studio\(studios.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("iCloud sync is disabled. Your data is stored locally on this device only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Data Sync")
                } footer: {
                    Text("Changing this setting requires restarting the app to take effect.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your studio data is stored securely in your personal iCloud account and syncs automatically between your iPad and Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Changes sync automatically when online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Most recently modified item wins in conflicts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Turning sync off then on may lose local changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Data never leaves your iCloud account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How It Works")
                } footer: {
                    Text("IMPORTANT: If you disable iCloud sync and make changes, then re-enable it, your local changes may be overwritten by iCloud's version. Use Export before disabling sync to backup your data.")
                }
                
                if iCloudSyncEnabled {
                    Section {
                        Button {
                            Task {
                                await forceSyncNow()
                            }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(isSyncing)
                        
                        if let message = lastSyncMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Manual Sync")
                    } footer: {
                        Text("Forces an immediate sync with iCloud. Changes from all devices will be merged. If conflicts occur, the most recently modified data wins.")
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you see different data on different devices:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("1. Ensure both devices are online and signed into iCloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("2. Use 'Sync Now' button above on both devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("3. Wait a few minutes for sync to complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("4. If still not syncing, force quit and relaunch on both devices")
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
                    Text("Use 'Reset Sync' only if data isn't syncing properly after trying 'Sync Now'. This marks all data on this device as new and uploads it to iCloud. Other devices will download this version.")
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
            .alert("Restart Required", isPresented: $showingRestartAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please quit and restart Studio Guru for the sync setting change to take effect.")
            }
        }
    }
    
    private func forceSyncNow() async {
        await MainActor.run {
            isSyncing = true
            lastSyncMessage = "Syncing..."
        }
        
        // Touch the model context to trigger a save and sync
        // This doesn't modify data, just forces CloudKit to sync
        try? modelContext.save()
        
        // Wait a moment for the sync to initiate
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        await MainActor.run {
            isSyncing = false
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            lastSyncMessage = "Last sync: \(formatter.string(from: Date()))"
        }
        
        #if DEBUG
        print("🔄 Manual sync triggered for \(studios.count) studios")
        #endif
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
