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
    @EnvironmentObject var storeManager: StoreManager
    @Query private var studios: [Studio]

    @State private var isShowingPaywall = false
    @State private var paywallReason: PaywallReason = .general
    // Default to false for free users - Pro users can enable it
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false
    @State private var showingSyncReset = false
    @State private var syncResetConfirmed = false
    @State private var showingRestartAlert = false
    @State private var isSyncing = false
    @State private var lastSyncMessage: String?
    @StateObject private var diagnostics = iCloudDiagnostics()
    @State private var showingDiagnostics = false
    
    // Category color settings (stored as hex strings)
    @AppStorage("categoryColor_ADATExpander") private var adatExpanderColor = "#9B59B6"
    @AppStorage("categoryColor_AudioInterface") private var audioInterfaceColor = "#3498DB"
    @AppStorage("categoryColor_BusCompressor") private var busCompressorColor = "#E74C3C"
    @AppStorage("categoryColor_ChannelStrip") private var channelStripColor = "#F39C12"
    @AppStorage("categoryColor_Compressor") private var compressorColor = "#E67E22"
    @AppStorage("categoryColor_Computer") private var computerColor = "#95A5A6"
    @AppStorage("categoryColor_ControlSurface") private var controlSurfaceColor = "#1ABC9C"
    @AppStorage("categoryColor_DigitalMixer") private var digitalMixerColor = "#16A085"
    @AppStorage("categoryColor_EffectsUnit") private var effectsUnitColor = "#8E44AD"
    @AppStorage("categoryColor_Equalizer") private var equalizerColor = "#D35400"
    @AppStorage("categoryColor_HeadphoneAmp") private var headphoneAmpColor = "#2C3E50"
    @AppStorage("categoryColor_Headphones") private var headphonesColor = "#34495E"
    @AppStorage("categoryColor_Keyboard") private var keyboardColor = "#C0392B"
    @AppStorage("categoryColor_Microphone") private var microphoneColor = "#16A085"
    @AppStorage("categoryColor_MIDIDevice") private var midiDeviceColor = "#2980B9"
    @AppStorage("categoryColor_MIDIInterface") private var midiInterfaceColor = "#5DADE2"
    @AppStorage("categoryColor_Mixer") private var mixerColor = "#27AE60"
    @AppStorage("categoryColor_StudioMonitor") private var monitorColor = "#F1C40F"
    @AppStorage("categoryColor_Multi") private var multiColor = "#34495E"
    @AppStorage("categoryColor_Patchbay") private var patchbayColor = "#7F8C8D"
    @AppStorage("categoryColor_Preamp") private var preampColor = "#E74C3C"
    @AppStorage("categoryColor_Synth") private var synthColor = "#9B59B6"
    @AppStorage("categoryColor_USBHub") private var usbHubColor = "#BDC3C7"
    @AppStorage("categoryColor_USBExpander") private var usbExpanderColor = "#95A5A6"
    @AppStorage("categoryColor_VideoMonitor") private var videoMonitorColor = "#ECF0F1"
    @AppStorage("categoryColor_Other") private var otherColor = "#7F8C8D"
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// Get color for a category
    private func colorFor(_ category: DeviceCategory) -> Color {
        let hex: String
        switch category {
        case .adatExpander: hex = adatExpanderColor
        case .audioInterface: hex = audioInterfaceColor
        case .busCompressor: hex = busCompressorColor
        case .channelStrip: hex = channelStripColor
        case .compressor: hex = compressorColor
        case .computer: hex = computerColor
        case .controlSurface: hex = controlSurfaceColor
        case .digitalMixer: hex = digitalMixerColor
        case .effectsUnit: hex = effectsUnitColor
        case .equalizer: hex = equalizerColor
        case .headphoneAmp: hex = headphoneAmpColor
        case .headphones: hex = headphonesColor
        case .keyboard: hex = keyboardColor
        case .microphone: hex = microphoneColor
        case .midiDevice: hex = midiDeviceColor
        case .midiInterface: hex = midiInterfaceColor
        case .mixer: hex = mixerColor
        case .monitor: hex = monitorColor
        case .multi: hex = multiColor
        case .patchbay: hex = patchbayColor
        case .preamp: hex = preampColor
        case .synth: hex = synthColor
        case .usbHub: hex = usbHubColor
        case .usbExpander: hex = usbExpanderColor
        case .videoMonitor: hex = videoMonitorColor
        case .other: hex = otherColor
        }
        return Color(hex: hex) ?? .gray
    }
    
    /// Set color for a category
    private func setColor(_ color: Color, for category: DeviceCategory) {
        guard let hex = color.toHex() else { return }
        switch category {
        case .adatExpander: adatExpanderColor = hex
        case .audioInterface: audioInterfaceColor = hex
        case .busCompressor: busCompressorColor = hex
        case .channelStrip: channelStripColor = hex
        case .compressor: compressorColor = hex
        case .computer: computerColor = hex
        case .controlSurface: controlSurfaceColor = hex
        case .digitalMixer: digitalMixerColor = hex
        case .effectsUnit: effectsUnitColor = hex
        case .equalizer: equalizerColor = hex
        case .headphoneAmp: headphoneAmpColor = hex
        case .headphones: headphonesColor = hex
        case .keyboard: keyboardColor = hex
        case .microphone: microphoneColor = hex
        case .midiDevice: midiDeviceColor = hex
        case .midiInterface: midiInterfaceColor = hex
        case .mixer: mixerColor = hex
        case .monitor: monitorColor = hex
        case .multi: multiColor = hex
        case .patchbay: patchbayColor = hex
        case .preamp: preampColor = hex
        case .synth: synthColor = hex
        case .usbHub: usbHubColor = hex
        case .usbExpander: usbExpanderColor = hex
        case .videoMonitor: videoMonitorColor = hex
        case .other: otherColor = hex
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Pro status and upgrade section
                Section {
                    if storeManager.isPro {
                        HStack {
                            Image(systemName: "star.circle.fill")
                                .foregroundStyle(.yellow)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Studio Guru Pro")
                                    .font(.headline)
                                Text("Thank you for your support!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title2)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "star.circle")
                                    .foregroundStyle(.yellow)
                                    .font(.title)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Free Version")
                                        .font(.headline)
                                    Text("\(StoreManager.freeDeviceLimit) devices • \(StoreManager.freeStudioLimit) studio")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button {
                                isShowingPaywall = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text("Upgrade to Pro")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Pro Features:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("• Unlimited studios and devices")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("• iCloud sync across all devices")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("• Export & import studios")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("• Support development")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { iCloudSyncEnabled },
                        set: { newValue in
                            // Check if user has Pro when trying to enable iCloud sync
                            if newValue && !storeManager.canUseICloudSync {
                                paywallReason = .iCloudSync
                                isShowingPaywall = true
                            } else {
                                iCloudSyncEnabled = newValue
                                showingRestartAlert = true
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: iCloudSyncEnabled ? "checkmark.icloud.fill" : "icloud.slash.fill")
                                .foregroundStyle(iCloudSyncEnabled ? .green : .secondary)
                            Text("iCloud Sync")
                                .font(.headline)
                            if !storeManager.isPro {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                            }
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
                    
                    Divider()
                    
                    Button {
                        showingDiagnostics = true
                    } label: {
                        Label("Run iCloud Diagnostics", systemImage: "stethoscope")
                    }
                    
                    if let logURL = Studio_GuruApp.getDiagnosticsLogURL() {
                        ShareLink(item: logURL) {
                            Label("Share Diagnostics Log", systemImage: "square.and.arrow.up")
                        }
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
                
                if iCloudSyncEnabled && !studios.isEmpty {
                    Section {
                        ForEach(studios) { studio in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(studio.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                HStack {
                                    Text("Last modified:")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(studio.modifiedAt, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text("ago")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Studios & Sessions")
                    } footer: {
                        Text("Shows when each studio or session was last modified. Recent changes should sync to other devices within a few minutes.")
                    }
                }
                
                Section {
                    ForEach(DeviceCategory.allCases, id: \.self) { category in
                        HStack {
                            Text(category.rawValue)
                                .font(.caption)
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { colorFor(category) },
                                set: { setColor($0, for: category) }
                            ))
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Device Category Colors")
                } footer: {
                    Text("Set default colors for each device category. Individual devices can override these in the device editor.")
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

                #if DEBUG
                // Debug section for testing freemium features
                Section {
                    Toggle(isOn: $storeManager.debugForceFreeTier) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Force Free Tier")
                                .font(.headline)
                            Text("Override all checks and enforce free tier limits")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Toggle(isOn: $storeManager.debugSimulatePro) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Simulate Pro Tier")
                                .font(.headline)
                            Text("Test Pro user experience without purchasing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(storeManager.debugForceFreeTier)

                    if storeManager.debugForceFreeTier {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ Force Free Tier Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                            Text("All Pro checks bypassed - free limits enforced:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• Max \(StoreManager.freeDeviceLimit) devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• \(StoreManager.freeStudioLimit) studio only")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• No iCloud sync")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• No export/import")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if storeManager.debugSimulatePro {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⚠️ Debug Mode Active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                            Text("App will behave as a Pro user:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• Unlimited studios")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• Unlimited devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• iCloud sync enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("• Export/import enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    VStack(spacing: 12) {
                        Text("Test Scenarios")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button {
                            // Simulate upgrading from v1.21 (original purchaser)
                            UserDefaults.standard.removeObject(forKey: "hasGrantedOriginalPurchaserPro")
                            UserDefaults.standard.set("1.21", forKey: "lastKnownVersion")
                            storeManager.debugSimulatePro = false
                            storeManager.debugForceFreeTier = false
                            storeManager.refreshProStatus()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Simulate Original Purchaser")
                                        .font(.headline)
                                }
                                Text("Sets lastKnownVersion to 1.21, grants Pro on next check")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive) {
                            // Simulate new user (no previous version)
                            UserDefaults.standard.removeObject(forKey: "hasGrantedOriginalPurchaserPro")
                            UserDefaults.standard.removeObject(forKey: "lastKnownVersion")
                            storeManager.debugSimulatePro = false
                            storeManager.debugForceFreeTier = true
                            storeManager.refreshProStatus()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .foregroundStyle(.orange)
                                    Text("Simulate New User")
                                        .font(.headline)
                                }
                                Text("Clears all flags, enforces free tier limits")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Debug Testing")
                } footer: {
                    Text("This section only appears in debug builds. Toggle ON to test Pro features without making an actual purchase.")
                }
                #endif
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
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(reason: paywallReason)
                    .environmentObject(storeManager)
            }
            .sheet(isPresented: $showingDiagnostics) {
                iCloudDiagnosticsView(diagnostics: diagnostics)
            }
        }
    }
    
    private func forceSyncNow() async {
        await MainActor.run {
            isSyncing = true
            lastSyncMessage = "Syncing..."
        }
        
        #if DEBUG
        print("🔄 Manual sync started for \(studios.count) studios")
        for studio in studios {
            print("  📱 Studio: '\(studio.name)' - Modified: \(studio.modifiedAt)")
        }
        #endif
        
        // Force a save to trigger CloudKit sync
        // SwiftData automatically syncs changed records to CloudKit
        do {
            try modelContext.save()
            
            // Give CloudKit time to process the sync
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
            await MainActor.run {
                isSyncing = false
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                lastSyncMessage = "Sync initiated at \(formatter.string(from: Date())). Changes may take a few moments to appear on other devices."
            }
            
            #if DEBUG
            print("✅ Manual sync completed successfully")
            #endif
        } catch {
            await MainActor.run {
                isSyncing = false
                lastSyncMessage = "Sync failed: \(error.localizedDescription)"
            }
            
            #if DEBUG
            print("❌ Manual sync failed: \(error)")
            #endif
        }
    }
    
    private func resetSyncAndForceUpload() {
        #if DEBUG
        print("🔄 Sync reset: Marking \(studios.count) studios as modified")
        #endif
        
        // Mark all studios and devices as modified with current timestamp
        // This makes CloudKit prioritize this device's data in conflicts
        for studio in studios {
            studio.markAsModified()
            
            // Mark all devices in this studio as modified too
            for device in studio.devices ?? [] {
                device.markAsModified()
            }
            
            #if DEBUG
            print("  ✏️ Updated studio '\(studio.name)' modifiedAt: \(studio.modifiedAt)")
            #endif
        }
        
        // Save to trigger CloudKit sync
        do {
            try modelContext.save()
            
            #if DEBUG
            print("✅ Sync reset complete - all data marked as modified and saved")
            print("   CloudKit will now upload this device's data as the newest version")
            #endif
        } catch {
            #if DEBUG
            print("❌ Sync reset failed: \(error)")
            #endif
        }
    }
}

#Preview {
    SettingsView()
}
