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
    @EnvironmentObject var cloudKitSync: CloudKitSyncManager
    @Query private var studios: [Studio]

    @State private var isShowingPaywall = false
    @State private var paywallReason: PaywallReason = .general
    // Default to false for free users - Pro users can enable it
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled = false

    @State private var showingRestartAlert = false
    @StateObject private var diagnostics = iCloudDiagnostics()
    @State private var showingDiagnostics = false
    @StateObject private var backupManager = BackupManager()
    @State private var showingBackupsList = false
    @State private var showingRestoreConfirmation = false
    @State private var backupToRestore: BackupManager.BackupInfo?
    @State private var showingRestartForRestore = false
    @State private var backupSuccessMessage: String?
    
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
    
    /// Detect if app is running via TestFlight
    private var isTestFlight: Bool {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return appStoreReceiptURL.lastPathComponent == "sandboxReceipt"
    }
    
    /// Show debug section in DEBUG builds or TestFlight
    private var showDebugSection: Bool {
        #if DEBUG
        return true
        #else
        return isTestFlight
        #endif
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
    

    
    // Extract debug section to reduce body complexity
    @ViewBuilder
    private var debugTestingSection: some View {
        Section {
            #if DEBUG
            Toggle(isOn: $storeManager.debugForceFreeTier) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Force Free Tier")
                        .font(.headline)
                    Text("Override all checks and enforce free tier limits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #endif
            
            Toggle(isOn: $storeManager.debugSimulatePro) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Pro for Testing")
                        .font(.headline)
                    Text("Test Pro features without purchasing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            #if DEBUG
            .disabled(storeManager.debugForceFreeTier)
            #endif

            #if DEBUG
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
            }
            #endif
            
            if storeManager.debugSimulatePro {
                VStack(alignment: .leading, spacing: 8) {
                    Text("✅ Pro Mode Enabled")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                    Text("Testing Pro features:")
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
                    Text("• Gear Locker enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            #if DEBUG
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
            #endif
        } header: {
            #if DEBUG
            Text("Debug Testing")
            #else
            Text("TestFlight Testing")
            #endif
        } footer: {
            #if DEBUG
            Text("This section only appears in debug builds. Toggle switches and test scenarios help verify freemium functionality.")
            #else
            Text("This section only appears in TestFlight builds. Enable 'Pro for Testing' to test Pro features during beta testing. This will be hidden in the App Store version.")
            #endif
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
                        Text("Your studio data is stored securely in your personal iCloud Drive and syncs automatically between your iPad and Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• App backs up to iCloud when backgrounded or quit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Latest backup restores automatically on launch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Most recently modified data always wins")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Data never leaves your iCloud account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How It Works")
                } footer: {
                    Text("iCloud sync uses backup/restore to keep your devices in sync. This is simpler and more reliable than real-time sync for a single-user app.")
                }
                
                if iCloudSyncEnabled {
                    Section {
                        Button {
                            Task {
                                backupSuccessMessage = nil
                                do {
                                    let container = modelContext.container
                                    let result = try await backupManager.performAutoSyncWithiCloud(container: container)
                                    
                                    switch result {
                                    case .disabled:
                                        backupSuccessMessage = "iCloud sync is disabled"
                                    case .createdInitialBackup:
                                        backupSuccessMessage = "Created initial iCloud backup"
                                    case .restoredFromiCloud(let date):
                                        let formatter = DateFormatter()
                                        formatter.dateStyle = .short
                                        formatter.timeStyle = .short
                                        backupSuccessMessage = "Restored from iCloud backup (\(formatter.string(from: date)))"
                                        showingRestartAlert = true
                                    case .backedUpToiCloud:
                                        backupSuccessMessage = "Backed up to iCloud"
                                    case .alreadyInSync:
                                        backupSuccessMessage = "Already in sync with iCloud"
                                    case .noLocalData:
                                        backupSuccessMessage = "No local data found"
                                    case .error:
                                        backupSuccessMessage = "Sync error occurred"
                                    }
                                    
                                    // Clear success message after 3 seconds
                                    if let message = backupSuccessMessage, !showingRestartAlert {
                                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                                        backupSuccessMessage = nil
                                    }
                                } catch {
                                    print("❌ Sync failed: \(error)")
                                    backupSuccessMessage = "Sync failed: \(error.localizedDescription)"
                                    
                                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                                    backupSuccessMessage = nil
                                }
                            }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if backupManager.isCreatingBackup || backupManager.isRestoringBackup {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                            }
                        }
                        .disabled(backupManager.isCreatingBackup || backupManager.isRestoringBackup)
                        
                        if let successMessage = backupSuccessMessage {
                            Text(successMessage)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        
                        if let latestBackup = backupManager.availableBackups.first {
                            Text("Last backup: \(latestBackup.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("iCloud Sync")
                    } footer: {
                        Text("Your data is automatically backed up to iCloud Drive when you background the app and restored when you launch it. Use 'Sync Now' to manually sync immediately.")
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
                        
                        Text("2. Use 'Sync Now' button above to force a sync")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("3. Force quit and relaunch the app on both devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("4. The most recently modified data will be used")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let logURL = Studio_GuruApp.getDiagnosticsLogURL() {
                        ShareLink(item: logURL) {
                            Label("Share Diagnostics Log", systemImage: "square.and.arrow.up")
                        }
                    }
                } header: {
                    Text("Troubleshooting")
                } footer: {
                    Text("iCloud sync uses backup/restore - the app automatically backs up when backgrounded and restores the latest backup on launch. The most recently modified data always wins.")
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
                    Button {
                        Task {
                            backupSuccessMessage = nil
                            do {
                                let container = modelContext.container
                                try await backupManager.createBackup(container: container)
                                backupSuccessMessage = "Backup created successfully"
                                
                                // Clear success message after 3 seconds
                                Task {
                                    try await Task.sleep(nanoseconds: 3_000_000_000)
                                    backupSuccessMessage = nil
                                }
                            } catch {
                                backupManager.lastError = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            Label("Create Backup Now", systemImage: "arrow.down.doc")
                            Spacer()
                            if backupManager.isCreatingBackup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(backupManager.isCreatingBackup)
                    
                    if !backupManager.availableBackups.isEmpty {
                        Button {
                            showingBackupsList = true
                        } label: {
                            HStack {
                                Label("View & Restore Backups", systemImage: "clock.arrow.circlepath")
                                Spacer()
                                Text("\(backupManager.availableBackups.count)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    if let successMessage = backupSuccessMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(successMessage)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    if let error = backupManager.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    
                    if let lastBackup = backupManager.availableBackups.first {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last backup:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(lastBackup.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Automatic Backups")
                } footer: {
                    let location = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false) ? "in iCloud Drive" : "locally"
                    return Text("Studio Guru automatically backs up your entire database. The last 5 backups are kept \(location). Backups are created when the app backgrounds or quits if iCloud sync is enabled, or on launch if 24 hours have passed.")
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

                if showDebugSection {
                    debugTestingSection
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
            .sheet(isPresented: $showingBackupsList) {
                BackupsListView(backupManager: backupManager, backupToRestore: $backupToRestore, showingRestoreConfirmation: $showingRestoreConfirmation)
                    .frame(minWidth: 500, minHeight: 400)
                    .onAppear {
                        #if DEBUG
                        print("🔵 Sheet presented - backupManager has \(backupManager.availableBackups.count) backups")
                        #endif
                    }
            }
            .alert("Restore Backup?", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restore", role: .destructive) {
                    if let backup = backupToRestore {
                        // Save which backup to restore - the actual restore will happen on next app launch
                        UserDefaults.standard.set(backup.filename, forKey: "backupToRestoreOnLaunch")
                        
                        #if DEBUG
                        print("📝 Marked backup '\(backup.filename)' for restore on next launch")
                        print("🔄 Quitting app - restore will happen before anything else on relaunch")
                        #endif
                        
                        // Quit immediately - restore will happen on next launch BEFORE container init
                        exit(0)
                    }
                }
            } message: {
                if let backup = backupToRestore {
                    if iCloudSyncEnabled {
                        Text("This will replace all current data with the backup from \(backup.displayName).\n\n⚠️ IMPORTANT: iCloud Sync is enabled. The restored data will become the current version and will sync to ALL your devices, replacing any newer data on those devices.\n\nThe app will quit immediately. When you relaunch, the restore will complete before any sync occurs. This cannot be undone! Consider creating a backup of your current data first.")
                    } else {
                        Text("This will replace all current data with the backup from \(backup.displayName).\n\nThe app will quit immediately. When you relaunch, the restore will complete automatically. This cannot be undone! Consider creating a backup of your current data first.")
                    }
                }
            }
        }
    }
    

}

// MARK: - Backups List View

struct BackupsListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backupManager: BackupManager
    @Binding var backupToRestore: BackupManager.BackupInfo?
    @Binding var showingRestoreConfirmation: Bool
    @State private var backupToDelete: BackupManager.BackupInfo?
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            VStack {
                List(backupManager.availableBackups) { backup in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.displayName)
                                .font(.headline)
                            Text(backup.fileSizeFormatted)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        
                        Spacer()
                        
                        Button {
                            backupToRestore = backup
                            dismiss()
                            showingRestoreConfirmation = true
                        } label: {
                            Label("Restore", systemImage: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            backupToDelete = backup
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .onAppear {
                #if DEBUG
                print("📋 BackupsListView appeared with \(backupManager.availableBackups.count) backups")
                #endif
            }
            .navigationTitle("Backups")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Backup?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let backup = backupToDelete {
                        try? backupManager.deleteBackup(backup)
                    }
                }
            } message: {
                if let backup = backupToDelete {
                    Text("Delete backup from \(backup.displayName)? This cannot be undone.")
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
