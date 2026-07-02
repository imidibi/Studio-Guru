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
    
    /// Detect if app is running via TestFlight
    private var isTestFlight: Bool {
        #if DEBUG
        return false
        #else
        // Check if running in TestFlight environment
        if let receiptURL = Bundle.main.appStoreReceiptURL {
            return receiptURL.lastPathComponent == "sandboxReceipt"
        }
        return false
        #endif
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
            
            #if DEBUG || targetEnvironment(simulator)
            Toggle(isOn: $storeManager.debugSimulatePro) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Pro for Testing")
                        .font(.headline)
                    Text("Test Pro features without purchasing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
            
            #if DEBUG || targetEnvironment(simulator)
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
            #endif
            
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
                    HStack {
                        Image(systemName: storeManager.isPro ? "checkmark.icloud.fill" : "icloud.slash.fill")
                            .foregroundStyle(storeManager.isPro ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iCloud Sync")
                                .font(.headline)
                            if storeManager.isPro {
                                Text("Active - syncing automatically")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Text("Requires Studio Guru Pro")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !storeManager.isPro {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                        }
                    }
                    
                    if storeManager.isPro {
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
                    if storeManager.isPro {
                        Text("SwiftData automatically syncs your data to iCloud in the background. No configuration needed!")
                    } else {
                        Text("Upgrade to Pro to enable automatic iCloud sync across all your devices.")
                    }
                }
                
                if storeManager.isPro {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your studio data is stored securely in your personal iCloud and syncs automatically between your iPad and Mac.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("• Changes sync automatically in the background")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("• Works seamlessly across all your devices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("• Uses Apple's CloudKit for reliable sync")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Text("• Data never leaves your iCloud account")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("How It Works")
                    } footer: {
                        Text("iCloud sync uses Apple's CloudKit technology to keep your data automatically synchronized across all your devices. No configuration required!")
                    }
                }
                
                // Automatic CloudKit sync sections removed
                // CloudKit now syncs automatically in the background for Pro users
                
                if storeManager.isPro {
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
                    Text("iCloud sync automatically syncs your data when the app backgrounds and when you launch it. The most recently modified data always wins.")
                }
                }  // Close if storeManager.isPro
                
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
                
                // Manual backup sections removed - CloudKit sync is automatic
                
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

            .sheet(isPresented: $isShowingPaywall) {
                PaywallView(reason: paywallReason)
                    .environmentObject(storeManager)
            }
            .sheet(isPresented: $showingDiagnostics) {
                iCloudDiagnosticsView(diagnostics: diagnostics)
            }
        }
    }
    

}

// MARK: - Backups List View

// BackupsListView removed - CloudKit handles sync automatically now

#Preview {
    SettingsView()
}
