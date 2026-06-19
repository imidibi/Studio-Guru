//
//  StudioCanvasView.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import Combine
import CryptoKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import CloudKit

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

// MARK: - Helper Functions

/// Ensures a URL has a proper scheme (http/https), adding https:// if missing
private func ensureURLScheme(_ url: URL) -> URL {
    // If URL already has a scheme, return it as-is
    if url.scheme != nil {
        return url
    }
    
    // No scheme - add https:// prefix
    let urlString = url.absoluteString
    if let newURL = URL(string: "https://\(urlString)") {
        return newURL
    }
    
    // Fallback to original if construction fails
    return url
}

// Device location enum for Gear Locker
enum DeviceLocation {
    case currentStudio
    case gearLocker
}

struct StudioCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Studio.name, order: .forward) private var studios: [Studio]
    @EnvironmentObject var storeManager: StoreManager

    @State private var selectedStudioId: UUID?

    // Paywall
    @State private var isShowingPaywall: Bool = false
    @State private var paywallReason: PaywallReason = .general

    // New studio prompt
    @State private var isShowingNewStudioPrompt: Bool = false
    @State private var newStudioNameDraft: String = ""

    // Delete studio confirm
    @State private var isShowingDeleteStudioConfirm: Bool = false
    @State private var studioIdPendingDelete: UUID?

    // Export result
    @State private var isShowingExportResult: Bool = false
    @State private var exportResultMessage: String = ""
    @State private var isShowingExportPicker: Bool = false
    @State private var exportDocument: StudioDocument? = nil

    // Import
    @State private var isShowingImportPicker: Bool = false
    @State private var pendingImportURL: URL? = nil
    @State private var pendingImportStudio: ExportableStudio? = nil
    @State private var isShowingImportNameConflict: Bool = false
    @State private var importConflictStudioName: String = ""
    @State private var importNewName: String = ""

    // Settings
    @State private var isShowingSettings: Bool = false

    // Connection Legend
    @State private var isShowingConnectionLegend: Bool = false
    
    // Connection Matrix View
    @State private var isShowingMatrixView: Bool = false
    
    // Help
    @State private var isShowingHelp: Bool = false

    // Export canvas alert
    @State private var isShowingExportCanvasAlert: Bool = false
    @State private var isExportingCanvas: Bool = false

    // Selection (devices/connections)
    @StateObject private var selectionState = SelectionState()
    // Connections (persisted in UserDefaults)
    @StateObject private var connectionsStore = ConnectionsStore()

    @State private var isShowingConnectionsEditor: Bool = false
    @State private var connectionEditorLinkId: UUID? = nil
    @State private var connectionEditorDirection: ArrowDirection = .forward

    // Canvas sizing (used to place new devices without overlap)
    @State private var canvasSize: CGSize = CGSize(width: 1200, height: 800)

    // Device CRUD
    @State private var isShowingDeviceEditor: Bool = false
    @State private var editingDeviceId: UUID? = nil

    // Guru
    @State private var isShowingGuru: Bool = false

    // Draft fields for Device Editor
    @State private var draftNickname: String = ""
    @State private var draftManufacturer: String = ""
    @State private var draftProductId: String = ""
    @State private var draftCategory: DeviceCategory = .other
    @State private var draftSerialNumber: String = ""
    @State private var draftLocation: String = ""
    @State private var draftCustomColor: Color? = nil

    @State private var draftSupportPageURL: String = ""
    @State private var draftDownloadsPageURL: String = ""

    @State private var draftAudioInputs: Int = 0
    @State private var draftAudioOutputs: Int = 0
    @State private var draftAdatInputPorts: Int = 0
    @State private var draftAdatOutputPorts: Int = 0
    @State private var draftMadiInputPorts: Int = 0
    @State private var draftMadiOutputPorts: Int = 0
    @State private var draftMidiInputPorts: Int = 0
    @State private var draftMidiOutputPorts: Int = 0
    @State private var draftSampleRate: SampleRate =
        SampleRate.allCases.first ?? SampleRate(rawValue: 0)!

    @State private var draftDigitalInputs: Set<DigitalFormat> = []
    @State private var draftDigitalOutputs: Set<DigitalFormat> = []
    /// Quantities for host interfaces (USB/Thunderbolt/Ethernet etc.).
    @State private var draftComputerInterfaceCounts: [ComputerInterface: Int] =
        [:]
    @State private var deviceEditorError: String? = nil
    
    // Draft manuals for device editor (supports multiple)
    @State private var draftManualURLs: [URL] = []
    @State private var isSelectingManualForDraft: Bool = false
    
    // Draft device location for Gear Locker
    @State private var draftDeviceLocation: DeviceLocation = .currentStudio
    
    // Draft asset inventory fields
    @State private var draftPurchasePrice: Double = 0.0
    @State private var draftPurchaseDate: Date? = nil
    @State private var draftPurchaseLocation: String = ""
    @State private var draftWarrantyExpirationDate: Date? = nil
    @State private var draftInsurancePolicyNumber: String = ""
    @State private var draftCurrentEstimatedValue: Double = 0.0
    @State private var draftAssetNotes: String = ""
    
    // Gear Locker assignment workflow
    @State private var deviceToAssign: DeviceInstance? = nil
    @State private var assignmentData: AssignGearSheet.AssignmentData? = nil
    @State private var isPlacingDeviceFromLocker: Bool = false
    @State private var deviceToPlace: DeviceInstance? = nil
    
    // Auto-arrange undo
    @State private var savedDevicePositions: [UUID: (x: Double, y: Double)] = [:]
    @State private var canUndoAutoArrange: Bool = false

    // Delete device confirm
    @State private var isShowingDeleteDeviceConfirm: Bool = false
    @State private var deviceIdPendingDelete: UUID? = nil

    // Clone / Move device
    @State private var isShowingMoveDeviceDialog: Bool = false
    @State private var deviceIdPendingMove: UUID? = nil
    @State private var moveTargetStudioId: UUID? = nil
    @State private var moveErrorMessage: String? = nil

    // Connection “explosion”
    @State private var isShowingConnectionExplosion: Bool = false
    @State private var explosionDeviceId: UUID? = nil
    @State private var explosionDeviceSnapshot: DeviceInstance? = nil
    @State private var explosionCooldownUntil: Date? = nil
    @State private var suppressExplosionReopen: Bool = false

    // Device inspector overlay
    @State private var presentedInspectorDeviceId: UUID? = nil
    @State private var suppressInspectorUntil: Date? = nil
    
    // Canvas annotations (drawing mode)
    @State private var isDrawingMode: Bool = false
    @State private var inspectorDetent: PresentationDetent = .large

    // When saving from the device editor we often set selection to the saved device.
    // That should NOT immediately pop the inspector overlay.
    @State private var suppressNextInspectorPresentation: Bool = false

    // Delete connection confirm
    @State private var isShowingDeleteConnectionConfirm: Bool = false
    @State private var connectionPendingDelete: Connection? = nil

    var body: some View {
        mainContent
    }
    
    private var mainContent: some View {
        NavigationSplitView {
            StudiosList(
                studios: studiosSortedByName,
                selectedStudioId: $selectedStudioId,
                onDuplicate: { duplicateStudio(from: $0) },
                onExport: { exportStudio($0) },
                onRequestDelete: { studio in
                    studioIdPendingDelete = studio.id
                    isShowingDeleteStudioConfirm = true
                }
            )
        } detail: {
            detail
        }
        .alert("New Studio", isPresented: $isShowingNewStudioPrompt) {
            TextField("Studio Name", text: $newStudioNameDraft)
            Button("Create") {
                let trimmed = newStudioNameDraft.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let name = trimmed.isEmpty ? "My Studio" : trimmed

                let s = Studio(name: name)
                // If the model has createdAt, ensure it’s set so @Query sorting works.
                // (This is safe even if Studio doesn’t use createdAt; the compiler will tell us and we can remove it.)
                // swiftlint:disable:next unused_optional_binding
                if Optional.some(s) as Studio? != nil {
                    // Best-effort: set createdAt if the property exists.
                    // s.createdAt = Date()
                }

                modelContext.insert(s)

                do {
                    try modelContext.save()
                } catch {
                    print("Studio save failed: \(error)")
                }

                selectedStudioId = s.id
                isShowingNewStudioPrompt = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name your studio.")
        }
        .alert("Delete Studio", isPresented: $isShowingDeleteStudioConfirm) {
            Button("Delete", role: .destructive) { deletePendingStudio() }
            Button("Cancel", role: .cancel) { studioIdPendingDelete = nil }
        } message: {
            if let studio = studioPendingDelete, !(studio.devices?.isEmpty ?? true) {
                Text(
                    "This studio has \(studio.devices?.count ?? 0) device(s). Deleting it will permanently delete the studio and all its devices and connections."
                )
            } else {
                Text("This studio will be permanently deleted.")
            }
        }
        .alert("Export", isPresented: $isShowingExportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportResultMessage)
        }
        .alert("Cannot Export Canvas", isPresented: $isShowingExportCanvasAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No devices to export. Add devices to your studio before exporting the canvas.")
        }
        .overlay {
            if isExportingCanvas {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Preparing Export...")
                            .font(.headline)
                    }
                    .padding(32)
                    #if os(iOS)
                    .background(Color(uiColor: .systemBackground))
                    #else
                    .background(Color(nsColor: .windowBackgroundColor))
                    #endif
                    .cornerRadius(12)
                    .shadow(radius: 10)
                }
            }
        }
        .alert(
            "Studio Name Conflict",
            isPresented: $isShowingImportNameConflict
        ) {
            Button("Replace Existing", role: .destructive) {
                // Delete existing studio with same name and import with original name
                if let existingStudio = studios.first(where: {
                    $0.name == importConflictStudioName
                }) {
                    modelContext.delete(existingStudio)
                    try? modelContext.save()
                }
                performImportWithName(importConflictStudioName)
            }
            Button("Import as '\(importNewName)'") {
                performImportWithName(importNewName)
            }
            Button("Cancel", role: .cancel) {
                pendingImportURL = nil
                pendingImportStudio = nil
            }
        } message: {
            Text(
                "A studio named '\(importConflictStudioName)' already exists. Do you want to replace it or import with a different name?"
            )
        }
        .sheet(isPresented: $isShowingGuru) {
            GuruHomeView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingConnectionLegend) {
            ConnectionLegendView()
        }
        #if os(macOS)
        .sheet(isPresented: $isShowingMatrixView) {
            if let studio = studios.first(where: { $0.id == selectedStudioId }) {
                ConnectionMatrixView(studio: studio, connectionsStore: connectionsStore)
                    .frame(minWidth: 1200, maxWidth: .infinity, minHeight: 800, maxHeight: .infinity)
                    .presentationSizing(.fitted)
            }
        }
        #else
        .fullScreenCover(isPresented: $isShowingMatrixView) {
            if let studio = studios.first(where: { $0.id == selectedStudioId }) {
                ConnectionMatrixView(studio: studio, connectionsStore: connectionsStore)
            }
        }
        #endif
        .sheet(isPresented: $isShowingHelp) {
            HelpView()
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(reason: paywallReason)
                .environmentObject(storeManager)
        }
        .fileExporter(
            isPresented: $isShowingExportPicker,
            document: exportDocument,
            contentType: .studioGuru,
            defaultFilename: "Studio.studioguru"
        ) { result in
            handleExportResult(result)
        }
        .fileImporter(
            isPresented: $isShowingImportPicker,
            allowedContentTypes: [.studioGuru, .json],
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowHelp"))) { _ in
            isShowingHelp = true
        }
        .onAppear {
            // Set up model context for ConnectionsStore (enables iCloud sync)
            connectionsStore.setModelContext(modelContext)
            
            // Initialize Gear Locker for Pro users
            if storeManager.isPro {
                StudioSeed.ensureGearLockerExists(modelContext: modelContext, studios: studios)
            }
            
            #if DEBUG
            // print("📱 StudioCanvasView appeared - Studios count: \(studios.count)")
            // if !studios.isEmpty {
            //     print("📱 Studios: \(studios.map { $0.name }.joined(separator: ", "))")
            //     print("📱 Studio IDs: \(studios.map { $0.id.uuidString }.joined(separator: ", "))")
            // }
            // 
            // // CloudKit diagnostics
            // print("📱 ModelContext: \(modelContext)")
            // print("📱 Container: \(modelContext.container)")
            // if let config = modelContext.container.configurations.first {
            //     print("📱 Container URL: \(config.url.path)")
            //     print("📱 CloudKit database: \(config.cloudKitDatabase)")
            // }
            // 
            // // Check CloudKit account status
            // CKContainer(identifier: "iCloud.com.ianmiller.studioguru").accountStatus { status, error in
            //     DispatchQueue.main.async {
            //         if let error = error {
            //             print("❌ CloudKit account error: \(error)")
            //         } else {
            //             switch status {
            //             case .available:
            //                 print("✅ CloudKit account: Available")
            //             case .noAccount:
            //                 print("⚠️ CloudKit account: No iCloud account signed in")
            //             case .restricted:
            //                 print("⚠️ CloudKit account: Restricted")
            //             case .couldNotDetermine:
            //                 print("⚠️ CloudKit account: Could not determine")
            //             case .temporarilyUnavailable:
            //                 print("⚠️ CloudKit account: Temporarily unavailable")
            //             @unknown default:
            //                 print("⚠️ CloudKit account: Unknown status")
            //             }
            //         }
            //     }
            // }
            #endif
            
            if selectedStudioId == nil {
                selectedStudioId = studios.first?.id
            }
            
            // Defer state-modifying operations to avoid "Modifying state during view update" warning
            if let sid = selectedStudioId,
                let studio = studios.first(where: { $0.id == sid })
            {
                let capturedStudio = studio
                let capturedSid = sid
                Task.detached { @MainActor [weak connectionsStore] in
                    guard let connectionsStore else { return }
                    // One-time migration: fix computer interface port types without breaking connections
                    fixComputerInterfacePortTypes(in: capturedStudio)
                    connectionsStore.load(studioId: capturedSid)
                    connectionsStore.cleanupOrphanedConnections(studio: capturedStudio)
                }
            }
        }
        .onChange(of: selectedStudioId) { _, newValue in
            // Clear auto-arrange undo state when switching studios
            canUndoAutoArrange = false
            savedDevicePositions.removeAll()
            
            // Turn off annotation mode when switching studios
            isDrawingMode = false

            // Defer state-modifying operations to avoid "Modifying state during view update" warning
            if let sid = newValue,
                let studio = studios.first(where: { $0.id == sid })
            {
                let capturedStudio = studio
                let capturedSid = sid
                Task.detached { @MainActor [weak selectionState, weak connectionsStore] in
                    guard let selectionState, let connectionsStore else { return }
                    selectionState.selection = nil
                    // Fix computer interface port types when switching studios
                    fixComputerInterfacePortTypes(in: capturedStudio)
                    connectionsStore.load(studioId: capturedSid)
                    connectionsStore.cleanupOrphanedConnections(studio: capturedStudio)
                }
            }
        }
    }

    // MARK: - Sidebar
    // Removed - replaced with StudiosList subview

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let studio = currentStudio {
                if studio.isSystemStudio && studio.systemStudioType == "gear_locker" {
                    // Show Gear Locker inventory view
                    gearLockerDetailView(studio)
                } else {
                    // Show regular studio canvas view
                    studioDetailView(studio)
                }
            } else {
                noStudioSelectedView
            }
        }
        .navigationTitle(currentStudio?.isSystemStudio == true && currentStudio?.systemStudioType == "gear_locker" ? "Studio Guru - Gear Locker" : "Studio Guru")
        .toolbar {
            // Conditional toolbar based on whether viewing Gear Locker or regular studio
            if let studio = currentStudio, studio.isSystemStudio && studio.systemStudioType == "gear_locker" {
                // GEAR LOCKER TOOLBAR
                ToolbarItem(placement: .navigation) {
                    Button {
                        beginCreateDevice()
                    } label: {
                        Label("Add Device", systemImage: "plus")
                    }
                    .help("Add a new device to Gear Locker")
                }
            } else {
                // REGULAR STUDIO TOOLBAR
                // Left side: Studio Actions
                ToolbarItem(placement: .navigation) {
                    Button {
                        // Check studio limit for free tier
                        if !storeManager.canAddStudio(currentCount: studios.count) {
                            paywallReason = .studioLimit
                            isShowingPaywall = true
                        } else {
                            newStudioNameDraft = "My Studio"
                            isShowingNewStudioPrompt = true
                        }
                    } label: {
                        Label("New Studio", systemImage: "plus")
                    }
                    .help("Create a new studio")
                }
                
                if let studio = currentStudio {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            duplicateStudio(from: studio)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .help("Duplicate this studio")
                    }
                    
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            Button {
                                // Check if import is allowed for free tier
                                if !storeManager.canExportImport {
                                    paywallReason = .exportImport
                                    isShowingPaywall = true
                                } else {
                                    isShowingImportPicker = true
                                }
                            } label: {
                                Label("Import Studio...", systemImage: "square.and.arrow.down")
                            }

                            Button {
                                exportStudio(studio)
                            } label: {
                                Label("Export Studio...", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                exportCanvasAsPDF(studio: studio)
                            } label: {
                                Label("Export Canvas as PDF...", systemImage: "arrow.down.doc")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                studioIdPendingDelete = studio.id
                                isShowingDeleteStudioConfirm = true
                            } label: {
                                Label("Delete Studio...", systemImage: "trash")
                            }
                        } label: {
                            Label("Files", systemImage: "folder")
                        }
                        .help("Import, export, and manage studio files")
                    }
                } else {
                    // Show import option even without a studio
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            Button {
                                // Check if import is allowed for free tier
                                if !storeManager.canExportImport {
                                    paywallReason = .exportImport
                                    isShowingPaywall = true
                                } else {
                                    isShowingImportPicker = true
                                }
                            } label: {
                                Label("Import Studio...", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Label("Files", systemImage: "folder")
                        }
                        .help("Import a studio file")
                    }
                }
                
                if let studio = currentStudio {

                    ToolbarItem(placement: .navigation) {
                        Button {
                            autoArrangeWithHubDetection(in: studio)
                        } label: {
                            Label("Auto-Arrange", systemImage: "square.grid.3x2")
                        }
                        .help("Automatically arrange devices using hub detection")
                    }
                    
                    ToolbarItem(placement: .navigation) {
                        Menu {
                            Toggle(isOn: Binding(
                                get: { studio.showGridOverlay },
                                set: { newValue in
                                    studio.showGridOverlay = newValue
                                    studio.markAsModified()
                                }
                            )) {
                                Label("Show Grid", systemImage: "squareshape.split.3x3")
                            }
                            
                            Toggle(isOn: Binding(
                                get: { studio.layoutMode == "snapToGrid" },
                                set: { newValue in
                                    studio.layoutMode = newValue ? "snapToGrid" : "freeform"
                                    studio.markAsModified()
                                }
                            )) {
                                Label("Snap to Grid", systemImage: "square.grid.3x3")
                            }
                            
                            Divider()
                            
                            Menu("Grid Size") {
                                ForEach([16.0, 24.0, 32.0, 48.0], id: \.self) { size in
                                    Button {
                                        studio.gridSize = size
                                        studio.markAsModified()
                                    } label: {
                                        HStack {
                                            Text("\(Int(size))px")
                                            if studio.gridSize == size {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Grid", systemImage: "grid")
                        }
                        .help("Grid and layout settings")
                    }
                    
                    #if os(iOS)
                    ToolbarItem(placement: .navigation) {
                        Button {
                            isDrawingMode.toggle()
                        } label: {
                            Label(
                                isDrawingMode ? "Done Drawing" : "Annotate",
                                systemImage: isDrawingMode ? "checkmark.circle.fill" : "pencil.tip.crop.circle"
                            )
                        }
                        .help(isDrawingMode ? "Exit annotation mode" : "Draw annotations on canvas")
                        .keyboardShortcut("d", modifiers: [.command])
                    }
                    #endif
                    
                    ToolbarItem(placement: .navigation) {
                        Button {
                            isShowingMatrixView.toggle()
                        } label: {
                            Label("Connection Matrix", systemImage: "tablecells")
                        }
                        .help("View connections in spreadsheet format")
                    }
                }
            }
            
            // Right side: App actions (consolidated into single group with constant items)
            ToolbarItemGroup(placement: .automatic) {
                // Clear Annotations - visible on all platforms when annotations exist
                if let studio = currentStudio, !(studio.isSystemStudio && studio.systemStudioType == "gear_locker") {
                    Button(role: .destructive) {
                        studio.canvasDrawingData = nil
                        studio.markAsModified()
                    } label: {
                        Label("Clear Annotations", systemImage: "trash")
                    }
                    .help("Clear all annotations from this studio")
                    .disabled(studio.canvasDrawingData == nil)
                    .opacity(studio.canvasDrawingData != nil ? 1.0 : 0.3)
                }
                
                Button {
                    isShowingGuru = true
                } label: {
                    Label("Guru", systemImage: "lightbulb")
                }
                .help("Quick setup suggestions for common devices")
                
                Button {
                    isShowingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                .help("How to use Studio Guru")
                .keyboardShortcut("?", modifiers: .command)

                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("App settings and preferences")
            }
        }
    }

    @ViewBuilder
    private func studioDetailView(_ studio: Studio) -> some View {
        studioDetailBase(for: studio)
            .sheet(isPresented: $isShowingDeviceEditor) {
                deviceEditorSheetContent
            }
            .sheet(isPresented: $isShowingConnectionsEditor) {
                connectionEditorContent
            }
            .sheet(
                isPresented: $isShowingConnectionExplosion,
                onDismiss: {
                    suppressExplosionReopen = true
                    explosionCooldownUntil = Date().addingTimeInterval(0.9)
                    explosionDeviceId = nil
                    explosionDeviceSnapshot = nil
                    suppressNextInspectorPresentation = true
                    selectionState.selection = nil
                    suppressInspectorUntil = Date().addingTimeInterval(0.9)
                    presentedInspectorDeviceId = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        suppressExplosionReopen = false
                    }
                }
            ) {
                explosionSheetContent
            }
            .sheet(isPresented: $isShowingMoveDeviceDialog) {
                moveDeviceSheetContent
            }
            // Device Inspector Overlay Sheet
            .onReceive(selectionState.$selection) { sel in
                if isShowingConnectionExplosion || suppressExplosionReopen {
                    return
                }
                if let until = suppressInspectorUntil, Date() < until {
                    return
                }
                // If we just saved from the editor, don't immediately present the inspector.
                if suppressNextInspectorPresentation {
                    suppressNextInspectorPresentation = false
                    return
                }

                if case .device(let id) = sel {
                    presentedInspectorDeviceId = id
                    inspectorDetent = .large  // Always open at large size
                } else {
                    presentedInspectorDeviceId = nil
                }
            }
            .sheet(
                item: Binding<IdentifiableUUID?>(
                    get: {
                        guard let id = presentedInspectorDeviceId else {
                            return nil
                        }
                        return IdentifiableUUID(id: id)
                    },
                    set: { newValue in
                        presentedInspectorDeviceId = newValue?.id
                        if newValue == nil {
                            selectionState.selection = nil
                        }
                    }
                )
            ) { item in
                inspectorSheetContent(item: item)
                    .presentationDetents([.large, .medium], selection: $inspectorDetent)
            }
            .alert("Delete Device", isPresented: $isShowingDeleteDeviceConfirm)
        {
            Button("Delete", role: .destructive) { deletePendingDevice() }
            Button("Cancel", role: .cancel) { deviceIdPendingDelete = nil }
        } message: {
            Text("This will permanently delete the device from the studio.")
        }
            .alert(
                "Delete Connection?",
                isPresented: $isShowingDeleteConnectionConfirm
            ) {
                Button("Delete", role: .destructive) {
                    guard let studio = currentStudio else { return }
                    guard let linkId = connectionEditorLinkId else { return }

                    _ = connectionsStore.deleteBundle(
                        studioId: studio.id,
                        linkId: linkId
                    )

                    if case .connection(let selectedId) = selectionState
                        .selection, selectedId == linkId
                    {
                        selectionState.selection = nil
                    }

                    connectionEditorLinkId = nil
                }
                Button("Cancel", role: .cancel) {
                    connectionEditorLinkId = nil
                }
            } message: {
                Text("This will remove the selected connection.")
            }
    }
    
    @ViewBuilder
    private func gearLockerDetailView(_ studio: Studio) -> some View {
        GearLockerInventoryView(
            studio: studio,
            selectedDeviceId: Binding(
                get: {
                    if case .device(let id) = selectionState.selection {
                        return id
                    }
                    return nil
                },
                set: { newId in
                    if let newId = newId {
                        selectionState.selection = .device(newId)
                    } else {
                        selectionState.selection = nil
                    }
                }
            ),
            onAssignDevice: { device in
                beginAssignDeviceToStudio(device)
            },
            onEditDevice: { device in
                beginEditDevice(device)
            },
            onDeleteDevice: { device in
                deviceIdPendingDelete = device.id
                isShowingDeleteDeviceConfirm = true
            }
        )
        .sheet(isPresented: $isShowingDeviceEditor, onDismiss: {
            // Clear selection to close inspector when device editor is dismissed
            selectionState.selection = nil
        }) {
            deviceEditorSheetContent
        }
        .sheet(item: $assignmentData) { data in
            AssignGearSheet(
                deviceInfo: data.deviceInfo,
                studioOptions: data.studioOptions,
                onAssign: { targetStudioId in
                    // Look up the actual studio and device objects only when assigning
                    if let device = deviceToAssign,
                       let targetStudio = studios.first(where: { $0.id == targetStudioId }) {
                        assignDeviceToStudio(device, targetStudio: targetStudio)
                    }
                    // Clear the item to dismiss
                    assignmentData = nil
                }
            )
        }
        .alert("Delete Device", isPresented: $isShowingDeleteDeviceConfirm) {
            Button("Delete", role: .destructive) { deletePendingDevice() }
            Button("Cancel", role: .cancel) { deviceIdPendingDelete = nil }
        } message: {
            Text("This will permanently delete the device from the Gear Locker.")
        }
        // Device Inspector Overlay Sheet
        .sheet(
            item: Binding<IdentifiableUUID?>(
                get: {
                    if case .device(let id) = selectionState.selection {
                        return IdentifiableUUID(id: id)
                    }
                    return nil
                },
                set: { newValue in
                    if let newValue = newValue {
                        selectionState.selection = .device(newValue.id)
                    } else {
                        selectionState.selection = nil
                    }
                }
            )
        ) { item in
            inspectorSheetContent(item: item)
                .presentationDetents([.large, .medium], selection: $inspectorDetent)
        }
    }

    private func studioDetailBase(for studio: Studio) -> some View {
        ZStack {
            VStack(spacing: 0) {
                DetailHeader(
                    studio: studio,
                    onCreateDevice: { beginCreateDevice() },
                    onShowLegend: { isShowingConnectionLegend = true }
                )
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                DetailCanvas(
                    studio: studio,
                    background: canvasBackground,
                    connectionsStore: connectionsStore,
                    isExplosionEnabled: isExplosionReady,
                    onSelectLink: { link in
                        selectionState.selection = .connection(link.id)
                        connectionEditorLinkId = link.id
                        connectionEditorDirection = .forward  // Default to forward when clicking line
                        isShowingConnectionsEditor = true
                    },
                    onRequestDeleteLink: { link in
                        connectionEditorLinkId = link.id
                        isShowingDeleteConnectionConfirm = true
                    },
                    onArrowTap: { link, direction in
                        selectionState.selection = .connection(link.id)
                        connectionEditorLinkId = link.id
                        connectionEditorDirection = direction
                        isShowingConnectionsEditor = true
                    },
                    onExplodeDevice: { device in
                        if suppressExplosionReopen { return }
                        if let until = explosionCooldownUntil, Date() < until {
                            return
                        }
                        if isShowingConnectionExplosion { return }
                        explosionDeviceId = device.id
                        explosionDeviceSnapshot = device
                        isShowingConnectionExplosion = true
                    },
                    onClearAutoArrangeUndo: {
                        canUndoAutoArrange = false
                        savedDevicePositions.removeAll()
                    },
                    isDrawingMode: $isDrawingMode,
                    isPlacingDeviceFromLocker: $isPlacingDeviceFromLocker,
                    onPlaceDevice: { location in
                        placeDeviceFromLocker(at: location)
                    },
                    canvasSize: $canvasSize
                )
                .environmentObject(selectionState)
            }
            
            // Floating undo button - completely non-blocking
            if canUndoAutoArrange {
                GeometryReader { geo in
                    Button {
                        undoAutoArrange(in: studio)
                    } label: {
                        Label("Undo Auto-Arrange", systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .position(
                        x: geo.size.width - 120,
                        y: geo.size.height - 40
                    )
                }
                .allowsHitTesting(true)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: canUndoAutoArrange)
    }

    private var isExplosionReady: Bool {
        if isShowingConnectionExplosion || suppressExplosionReopen {
            return false
        }
        if let until = explosionCooldownUntil, Date() < until { return false }
        return true
    }

    @ViewBuilder
    private var explosionSheetContent: some View {
        if let studio = currentStudio,
            let center = explosionDeviceSnapshot
                ?? studio.devices?.first(where: { $0.id == explosionDeviceId })
        {
            ExplosionOverviewView(
                studio: studio,
                centerDevice: center,
                connectionsStore: connectionsStore,
                onClose: {
                    suppressExplosionReopen = true
                    explosionCooldownUntil = Date().addingTimeInterval(0.9)
                    explosionDeviceId = nil
                    explosionDeviceSnapshot = nil
                    isShowingConnectionExplosion = false
                    suppressNextInspectorPresentation = true
                    selectionState.selection = nil
                    suppressInspectorUntil = Date().addingTimeInterval(0.9)
                    presentedInspectorDeviceId = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        suppressExplosionReopen = false
                    }
                }
            )
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("No device selected")
                Button("Close") {
                    suppressExplosionReopen = true
                    explosionCooldownUntil = Date().addingTimeInterval(0.9)
                    explosionDeviceId = nil
                    explosionDeviceSnapshot = nil
                    isShowingConnectionExplosion = false
                    suppressNextInspectorPresentation = true
                    selectionState.selection = nil
                    suppressInspectorUntil = Date().addingTimeInterval(0.9)
                    presentedInspectorDeviceId = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        suppressExplosionReopen = false
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var moveDeviceSheetContent: some View {
        if let deviceId = deviceIdPendingMove,
            let sourceStudio = currentStudio,
            let device = sourceStudio.devices?.first(where: { $0.id == deviceId }
            )
        {
            NavigationStack {
                Form {
                    Section("Move To Studio") {
                        Picker(
                            "Destination",
                            selection: Binding(
                                get: {
                                    moveTargetStudioId ?? studios.first?.id
                                },
                                set: { moveTargetStudioId = $0 }
                            )
                        ) {
                            ForEach(
                                studiosSortedByName.filter {
                                    $0.id != sourceStudio.id
                                },
                                id: \.id
                            ) { s in
                                Text(s.name).tag(s.id as UUID?)
                            }
                        }
                    }
                    if let msg = moveErrorMessage {
                        Section {
                            Text(msg).foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle("Move Device")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            moveTargetStudioId = nil
                            moveErrorMessage = nil
                            deviceIdPendingMove = nil
                            isShowingMoveDeviceDialog = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
                            guard
                                let destId = moveTargetStudioId
                                    ?? studios.first?.id,
                                let destStudio = studios.first(where: {
                                    $0.id == destId
                                }),
                                destStudio.id != sourceStudio.id
                            else {
                                moveErrorMessage =
                                    "Please choose a different destination studio."
                                return
                            }
                            moveDevice(
                                device,
                                from: sourceStudio,
                                to: destStudio
                            )
                            moveTargetStudioId = nil
                            moveErrorMessage = nil
                            deviceIdPendingMove = nil
                            isShowingMoveDeviceDialog = false
                        }
                    }
                }
            }
        } else {
            Text("No device selected").padding()
        }
    }

    @ViewBuilder
    private func inspectorSheetContent(item: IdentifiableUUID) -> some View {
        if let studio = currentStudio {
            DeviceInspectorOverlay(
                studio: studio,
                deviceId: item.id,
                onEditDevice: { d in beginEditDevice(d) },
                onRequestDeleteDevice: { d in
                    presentedInspectorDeviceId = nil
                    isShowingDeviceEditor = false
                    deviceIdPendingDelete = d.id
                    isShowingDeleteDeviceConfirm = true
                },
                onCloneDevice: { d in
                    presentedInspectorDeviceId = nil
                    isShowingDeviceEditor = false
                    cloneDevice(d, in: studio)
                },
                onRequestMoveDevice: { d in
                    presentedInspectorDeviceId = nil
                    deviceIdPendingMove = d.id
                    isShowingMoveDeviceDialog = true
                }
            )
        } else {
            Text("No studio").padding()
        }
    }

    private var noStudioSelectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Studio Selected")
                .font(.title3)
            Text("Create or select a studio.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - View Helpers for Sheet Content

    @ViewBuilder
    private var connectionEditorContent: some View {
        if let studio = currentStudio,
            let linkId = connectionEditorLinkId,
            let bundle = connectionsStore.bundle(for: studio.id, linkId: linkId)
        {
            // Swap from/to based on arrow direction
            let fromDevice = connectionEditorDirection == .forward ? bundle.fromDeviceId : bundle.toDeviceId
            let toDevice = connectionEditorDirection == .forward ? bundle.toDeviceId : bundle.fromDeviceId
            
            ConnectionsDialogView(
                studio: studio,
                fromDeviceId: fromDevice,
                toDeviceId: toDevice,
                store: connectionsStore
            )
            .id(bundle.id)
        } else {
            Text("No connection selected").padding()
        }
    }

    @ViewBuilder
    private var deviceEditorSheetContent: some View {
        if let studio = currentStudio {
            DeviceEditorSheet(
                title: editingDeviceId == nil ? "Add Device" : "Edit Device",
                nickname: $draftNickname,
                manufacturer: $draftManufacturer,
                productId: $draftProductId,
                category: $draftCategory,
                serialNumber: $draftSerialNumber,
                location: $draftLocation,
                customColor: $draftCustomColor,
                supportPageURL: $draftSupportPageURL,
                downloadsPageURL: $draftDownloadsPageURL,
                audioInputs: $draftAudioInputs,
                audioOutputs: $draftAudioOutputs,
                adatInputPorts: $draftAdatInputPorts,
                adatOutputPorts: $draftAdatOutputPorts,
                madiInputPorts: $draftMadiInputPorts,
                madiOutputPorts: $draftMadiOutputPorts,
                midiInputPorts: $draftMidiInputPorts,
                midiOutputPorts: $draftMidiOutputPorts,
                sampleRate: $draftSampleRate,
                digitalInputs: $draftDigitalInputs,
                digitalOutputs: $draftDigitalOutputs,
                computerInterfaceCounts: $draftComputerInterfaceCounts,
                errorMessage: $deviceEditorError,
                manualURLs: $draftManualURLs,
                isSelectingManual: $isSelectingManualForDraft,
                deviceLocation: $draftDeviceLocation,
                canAccessGearLocker: storeManager.canAccessGearLocker,
                purchasePrice: $draftPurchasePrice,
                purchaseDate: $draftPurchaseDate,
                purchaseLocation: $draftPurchaseLocation,
                warrantyExpirationDate: $draftWarrantyExpirationDate,
                insurancePolicyNumber: $draftInsurancePolicyNumber,
                currentEstimatedValue: $draftCurrentEstimatedValue,
                assetNotes: $draftAssetNotes,
                onCancel: { isShowingDeviceEditor = false },
                onSave: { saveDeviceEdits(into: studio) }
            )
        } else {
            Text("No studio")
                .padding()
        }
    }

    // MARK: - Device Actions

    private func beginCreateDevice() {
        // Check device limit for free tier
        if let studio = currentStudio {
            let deviceCount = studio.devices?.count ?? 0
            if !storeManager.canAddDevice(currentCount: deviceCount) {
                paywallReason = .deviceLimit
                isShowingPaywall = true
                return
            }
        }

        editingDeviceId = nil
        deviceEditorError = nil

        draftNickname = ""
        draftManufacturer = ""
        draftProductId = ""
        draftCategory = .other
        draftSerialNumber = ""
        draftLocation = ""

        draftSupportPageURL = ""
        draftDownloadsPageURL = ""

        draftAudioInputs = 0
        draftAudioOutputs = 0
        draftAdatInputPorts = 0
        draftAdatOutputPorts = 0
        draftMadiInputPorts = 0
        draftMadiOutputPorts = 0
        draftMidiInputPorts = 0
        draftMidiOutputPorts = 0
        if let first = SampleRate.allCases.first { draftSampleRate = first }
        draftDigitalInputs = []
        draftDigitalOutputs = []
        draftComputerInterfaceCounts = [:]
        draftManualURLs = []
        
        // Reset asset inventory fields
        draftPurchasePrice = 0.0
        draftPurchaseDate = nil
        draftPurchaseLocation = ""
        draftWarrantyExpirationDate = nil
        draftInsurancePolicyNumber = ""
        draftCurrentEstimatedValue = 0.0
        draftAssetNotes = ""

        isShowingDeviceEditor = true
    }

    private func beginEditDevice(_ d: DeviceInstance) {
        editingDeviceId = d.id
        presentedInspectorDeviceId = nil
        deviceEditorError = nil

        draftNickname = d.nickname
        draftManufacturer = d.manufacturer
        draftProductId = d.model
        draftCategory = d.category
        draftSerialNumber = d.serialNumber
        draftLocation = d.location
        draftCustomColor = d.customColor

        draftSupportPageURL = d.supportPageURLString ?? ""
        draftDownloadsPageURL = d.downloadsPageURLString ?? ""

        draftAudioInputs = max(0, d.audioInputsCount)
        draftAudioOutputs = max(0, d.audioOutputsCount)
        draftAdatInputPorts = max(0, d.adatInputPortsCount)
        draftAdatOutputPorts = max(0, d.adatOutputPortsCount)
        draftMadiInputPorts = max(0, d.madiInputPortsCount)
        draftMadiOutputPorts = max(0, d.madiOutputPortsCount)
        draftMidiInputPorts = max(0, d.midiInputPortsCount)
        draftMidiOutputPorts = max(0, d.midiOutputPortsCount)
        if let sr = SampleRate(rawValue: d.sampleRateRaw) {
            draftSampleRate = sr
        }

        draftDigitalInputs = Set(d.digitalInputs)
        draftDigitalOutputs = Set(d.digitalOutputs)

        var counts: [ComputerInterface: Int] = [:]
        for (k, v) in d.computerInterfaceCounts {
            counts[k] = max(0, v)
        }
        draftComputerInterfaceCounts = counts
        
        // Load asset inventory fields
        draftPurchasePrice = d.purchasePrice
        draftPurchaseDate = d.purchaseDate
        draftPurchaseLocation = d.purchaseLocation
        draftWarrantyExpirationDate = d.warrantyExpirationDate
        draftInsurancePolicyNumber = d.insurancePolicyNumber
        draftCurrentEstimatedValue = d.currentEstimatedValue
        draftAssetNotes = d.assetNotes
        
        // Clear draft manuals (existing device manuals are already saved, new ones can be added)
        draftManualURLs = []

        suppressNextInspectorPresentation = true
        isShowingDeviceEditor = true
    }

    private func expandComputerInterfaces(from counts: [ComputerInterface: Int])
        -> [ComputerInterface]
    {
        var result: [ComputerInterface] = []
        for key in counts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let n = max(0, counts[key] ?? 0)
            if n > 0 {
                result.append(contentsOf: Array(repeating: key, count: n))
            }
        }
        return result
    }
    
    // MARK: - Gear Locker Assignment
    
    private func beginAssignDeviceToStudio(_ device: DeviceInstance) {
        // Store device reference
        deviceToAssign = device
        
        // Get available studios (exclude Gear Locker and other system studios)
        let availableStudios = studios.filter { !$0.isSystemStudio }
        
        // Create lightweight studio options (read minimal data to avoid SwiftData materialization delays)
        let studioOptions = availableStudios.map { studio in
            AssignGearSheet.StudioOption(
                id: studio.id,
                name: studio.name,
                deviceCount: studio.devices?.count ?? 0
            )
        }
        
        // Create assignment data with both device info and studio options
        // Setting this triggers the sheet via .sheet(item:)
        assignmentData = AssignGearSheet.AssignmentData(
            deviceInfo: AssignGearSheet.DeviceInfo(
                id: device.id,
                nickname: device.nickname
            ),
            studioOptions: studioOptions
        )
    }
    
    private func assignDeviceToStudio(_ device: DeviceInstance, targetStudio: Studio) {
        // Switch to target studio
        selectedStudioId = targetStudio.id
        
        // Enter click-to-place mode
        deviceToPlace = device
        isPlacingDeviceFromLocker = true
    }
    
    private func placeDeviceFromLocker(at location: CGPoint) {
        guard let sourceDevice = deviceToPlace,
              let targetStudio = currentStudio else { return }
        
        // Create new device instance (independent copy)
        let newDevice = DeviceInstance(
            manufacturer: sourceDevice.manufacturer,
            model: sourceDevice.model,
            nickname: sourceDevice.nickname,
            category: sourceDevice.category,
            serialNumber: sourceDevice.serialNumber,
            location: sourceDevice.location,
            audioInputsCount: sourceDevice.audioInputsCount,
            audioOutputsCount: sourceDevice.audioOutputsCount,
            adatInputPortsCount: sourceDevice.adatInputPortsCount,
            adatOutputPortsCount: sourceDevice.adatOutputPortsCount,
            madiInputPortsCount: sourceDevice.madiInputPortsCount,
            madiOutputPortsCount: sourceDevice.madiOutputPortsCount,
            ethernetPortsCount: 0,
            sampleRate: SampleRate(rawValue: sourceDevice.sampleRateRaw) ?? SampleRate.allCases.first!,
            digitalInputs: sourceDevice.digitalInputs,
            digitalOutputs: sourceDevice.digitalOutputs,
            computerInterfaces: expandComputerInterfaces(from: sourceDevice.computerInterfaceCounts),
            posX: location.x,
            posY: location.y,
            scale: 1.0,
            zIndex: 0
        )
        
        // Mark as assigned from locker
        newDevice.isInGearLocker = false
        newDevice.isAssignedFromLocker = true
        newDevice.lockerSourceDeviceId = sourceDevice.id
        
        // Copy custom color if set
        newDevice.customColorHex = sourceDevice.customColorHex
        
        // Copy support URLs
        newDevice.supportPageURLString = sourceDevice.supportPageURLString
        newDevice.downloadsPageURLString = sourceDevice.downloadsPageURLString
        
        // Copy documentation links
        if let docs = sourceDevice.docs {
            newDevice.docs = docs.map { original in
                if let bookmarkData = original.localBookmarkData {
                    return DocLink(title: original.title, kind: original.kind, bookmarkData: bookmarkData)
                } else if let urlString = original.urlString, let url = URL(string: urlString) {
                    return DocLink(title: original.title, kind: original.kind, url: url)
                } else {
                    return DocLink(title: original.title, kind: original.kind, url: URL(string: "about:blank")!)
                }
            }.compactMap { $0 }
        }
        
        // Copy images
        newDevice.frontImagePath = sourceDevice.frontImagePath
        newDevice.rearImagePath = sourceDevice.rearImagePath
        
        // Copy ports and channels
        newDevice.ports = sourceDevice.ports?.map { p in
            let np = Port(name: p.name, type: p.type, direction: p.direction)
            np.channels = p.channels?.map { ch in
                Channel(
                    index: ch.index,
                    nameLong: ch.nameLong,
                    nameShort: ch.nameShort,
                    signal: ch.signal,
                    grouping: ch.grouping
                )
            } ?? []
            return np
        }
        
        // Add to target studio
        if targetStudio.devices == nil {
            targetStudio.devices = []
        }
        targetStudio.devices?.append(newDevice)
        targetStudio.markAsModified()
        
        // Save
        do {
            try modelContext.save()
        } catch {
            print("Failed to save device from locker: \(error)")
        }
        
        // Clear selection (don't auto-open inspector after placement)
        selectionState.selection = nil
        
        // Exit placement mode
        isPlacingDeviceFromLocker = false
        deviceToPlace = nil
    }
    
    @MainActor
    private func saveDeviceEdits(into studio: Studio) {
        // Determine target studio based on location picker
        let targetStudio: Studio
        if draftDeviceLocation == .gearLocker {
            // Find Gear Locker
            targetStudio = studios.first {
                $0.isSystemStudio && $0.systemStudioType == "gear_locker"
            } ?? studio
        } else {
            targetStudio = studio
        }
        
        let nickname = draftNickname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let manufacturer = draftManufacturer.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let productId = draftProductId.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let serialNumber = draftSerialNumber.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let location = draftLocation.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let supportURL = draftSupportPageURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let downloadsURL = draftDownloadsPageURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !nickname.isEmpty else {
            deviceEditorError = "Nickname is required."
            return
        }

        // Warn if another device in target studio already uses the same serial number
        if !serialNumber.isEmpty {
            let duplicate = targetStudio.devices?.first { other in
                other.serialNumber.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .localizedCaseInsensitiveCompare(serialNumber) == .orderedSame
                    && other.id != editingDeviceId
            }

            if duplicate != nil {
                deviceEditorError =
                    "Another device in this location already uses this serial number."
                return
            }
        }

        let device: DeviceInstance
        if let id = editingDeviceId,
            let existing = targetStudio.devices?.first(where: { $0.id == id })
        {
            device = existing
        } else {
            let pos = findAvailableDevicePosition(
                in: targetStudio,
                canvas: canvasSize
            )
            device = DeviceInstance(
                manufacturer: manufacturer.isEmpty ? "Unknown" : manufacturer,
                model: productId,
                nickname: nickname,
                category: draftCategory,
                serialNumber: serialNumber,
                location: location,
                audioInputsCount: draftAudioInputs,
                audioOutputsCount: draftAudioOutputs,
                adatInputPortsCount: max(0, draftAdatInputPorts),
                adatOutputPortsCount: max(0, draftAdatOutputPorts),
                madiInputPortsCount: max(0, draftMadiInputPorts),
                madiOutputPortsCount: max(0, draftMadiOutputPorts),
                midiInputPortsCount: max(0, draftMidiInputPorts),
                midiOutputPortsCount: max(0, draftMidiOutputPorts),
                ethernetPortsCount: 0,
                sampleRate: draftSampleRate,
                digitalInputs: Array(draftDigitalInputs),
                digitalOutputs: Array(draftDigitalOutputs),
                computerInterfaces: expandComputerInterfaces(
                    from: draftComputerInterfaceCounts
                ),
                posX: pos.x,
                posY: pos.y,
                scale: 1.0,
                zIndex: 0
            )
            
            // Set Gear Locker flags
            if targetStudio.isSystemStudio && targetStudio.systemStudioType == "gear_locker" {
                device.isInGearLocker = true
                device.isAssignedFromLocker = false
                device.lockerSourceDeviceId = nil
            }
            
            if targetStudio.devices == nil {
                targetStudio.devices = []
            }
            targetStudio.devices?.append(device)
        }

        device.nickname = nickname
        if !manufacturer.isEmpty { device.manufacturer = manufacturer }
        device.model = productId
        device.category = draftCategory
        device.serialNumber = serialNumber
        device.location = location
        device.customColor = draftCustomColor

        device.supportPageURLString = supportURL.isEmpty ? nil : supportURL
        device.downloadsPageURLString =
            downloadsURL.isEmpty ? nil : downloadsURL
        device.audioInputsCount = max(0, draftAudioInputs)
        device.audioOutputsCount = max(0, draftAudioOutputs)
        device.adatInputPortsCount = max(0, draftAdatInputPorts)
        device.adatOutputPortsCount = max(0, draftAdatOutputPorts)
        device.madiInputPortsCount = max(0, draftMadiInputPorts)
        device.madiOutputPortsCount = max(0, draftMadiOutputPorts)
        device.midiInputPortsCount = max(0, draftMidiInputPorts)
        device.midiOutputPortsCount = max(0, draftMidiOutputPorts)
        device.sampleRateRaw = draftSampleRate.rawValue
        device.digitalInputs = Array(draftDigitalInputs)
        device.digitalOutputs = Array(draftDigitalOutputs)
        device.computerInterfaces = expandComputerInterfaces(
            from: draftComputerInterfaceCounts
        )
        
        // Save asset inventory fields
        device.purchasePrice = draftPurchasePrice
        device.purchaseDate = draftPurchaseDate
        device.purchaseLocation = draftPurchaseLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        device.warrantyExpirationDate = draftWarrantyExpirationDate
        device.insurancePolicyNumber = draftInsurancePolicyNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        device.currentEstimatedValue = draftCurrentEstimatedValue
        device.assetNotes = draftAssetNotes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build ports from counts/formats for visualization and later connection tooling.
        device.ports = buildPorts(
            audioInputs: device.audioInputsCount,
            audioOutputs: device.audioOutputsCount,
            digitalInputs: device.digitalInputs,
            digitalOutputs: device.digitalOutputs,
            adatInputPorts: device.adatInputPortsCount,
            adatOutputPorts: device.adatOutputPortsCount,
            madiInputPorts: device.madiInputPortsCount,
            madiOutputPorts: device.madiOutputPortsCount,
            midiInputPorts: device.midiInputPortsCount,
            midiOutputPorts: device.midiOutputPortsCount,
            computerInterfaceCounts: device.computerInterfaceCounts,
            sampleRate: draftSampleRate
        )
        
        // Handle manual PDFs if any were selected (supports multiple)
        if !draftManualURLs.isEmpty {
            if device.docs == nil {
                device.docs = []
            }
            
            for pickedURL in draftManualURLs {
                do {
                    let (storedURL, bookmarkData) = try ManualStorage.copyPDFIntoAppSupport(
                        pickedURL: pickedURL,
                        deviceId: device.id
                    )
                    
                    let doc: DocLink
                    // Check if this is an iCloud-stored document (path starts with /iCloud/)
                    if storedURL.path.hasPrefix("/iCloud/") {
                        let iCloudPath = String(storedURL.path.dropFirst("/iCloud/".count))
                        // Extract original filename (removes UUID prefix) and remove extension
                        let fullFilename = iCloudDocumentManager.extractOriginalFilename(from: iCloudPath)
                        let title = (fullFilename as NSString).deletingPathExtension
                        doc = DocLink(
                            title: title,
                            kind: .manual,
                            iCloudPath: iCloudPath
                        )
                    } else {
                        // Legacy local storage
                        doc = DocLink(
                            title: storedURL.lastPathComponent,
                            kind: .manual,
                            bookmarkData: bookmarkData
                        )
                    }
                    
                    device.docs?.append(doc)
                } catch {
                    print("❌ Manual import failed for \(pickedURL.lastPathComponent): \(error)")
                    // Don't fail the entire save operation if one manual import fails
                }
            }
        }

        // Mark device and target studio as modified for iCloud sync
        device.markAsModified()
        targetStudio.markAsModified()
        
        // Only set selection if device was saved to current studio AND it's not a system studio
        // System studios (like Gear Locker) use list views and don't need canvas selection
        if targetStudio.id == studio.id && !targetStudio.isSystemStudio {
            // Keep selection for highlighting, but do not pop the inspector immediately after saving.
            suppressNextInspectorPresentation = true
            selectionState.selection = .device(device.id)
        }
        
        isShowingDeviceEditor = false
    }

    private func deletePendingDevice() {
        guard let studio = currentStudio else { return }
        guard let id = deviceIdPendingDelete else { return }
        guard let idx = studio.devices?.firstIndex(where: { $0.id == id }) else {
            return
        }

        studio.devices?.remove(at: idx)
        studio.markAsModified()
        deviceIdPendingDelete = nil
        selectionState.selection = nil
    }

    private func cloneDevice(_ device: DeviceInstance, in studio: Studio) {
        // Simple clone: duplicate the device with a slight offset and same properties.
        let newDevice = DeviceInstance(
            manufacturer: device.manufacturer,
            model: device.model,
            nickname: device.nickname + " Copy",
            category: device.category,
            serialNumber: "",
            location: device.location,
            audioInputsCount: device.audioInputsCount,
            audioOutputsCount: device.audioOutputsCount,
            adatInputPortsCount: device.adatInputPortsCount,
            adatOutputPortsCount: device.adatOutputPortsCount,
            madiInputPortsCount: device.madiInputPortsCount,
            madiOutputPortsCount: device.madiOutputPortsCount,
            sampleRate: SampleRate(rawValue: device.sampleRateRaw)
                ?? (SampleRate.allCases.first ?? SampleRate(rawValue: 0)!),
            digitalInputs: device.digitalInputs,
            digitalOutputs: device.digitalOutputs,
            computerInterfaces: device.computerInterfaces,
            posX: device.posX + 30,
            posY: device.posY + 30,
            scale: device.scale,
            zIndex: device.zIndex
        )
        newDevice.ports = device.ports?.map { p in
            let np = Port(name: p.name, type: p.type, direction: p.direction)
            np.channels = p.channels?.map { ch in
                Channel(
                    index: ch.index,
                    nameLong: ch.nameLong,
                    nameShort: ch.nameShort,
                    signal: ch.signal,
                    grouping: ch.grouping
                )
            } ?? []
            return np
        }
        if studio.devices == nil {
            studio.devices = []
        }
        studio.devices?.append(newDevice)
        newDevice.markAsModified()
        studio.markAsModified()
        selectionState.selection = .device(newDevice.id)
    }

    private func moveDevice(
        _ device: DeviceInstance,
        from source: Studio,
        to destination: Studio
    ) {
        // Special handling: If moving a Gear Locker-assigned device back to Gear Locker, just delete it
        // The original locker device will automatically become available again
        if destination.isSystemStudio && destination.systemStudioType == "gear_locker" && device.isAssignedFromLocker {
            // Remove from source studio
            if let idx = source.devices?.firstIndex(where: { $0.id == device.id }) {
                source.devices?.remove(at: idx)
                
                // Remove any connections
                let sourceLinks = connectionsStore.links(for: source.id)
                for link in sourceLinks where (link.fromDeviceId == device.id || link.toDeviceId == device.id) {
                    _ = connectionsStore.deleteBundle(studioId: source.id, linkId: link.id)
                }
                
                // Delete the device (it was a copy from the locker)
                modelContext.delete(device)
                
                source.markAsModified()
                try? modelContext.save()
                
                // Switch to Gear Locker to show it's available again
                selectedStudioId = destination.id
                selectionState.selection = nil
            }
            return
        }
        
        // Remove from source studio
        if let idx = source.devices?.firstIndex(where: { $0.id == device.id }) {
            // Dismiss any presented inspector overlay during move
            presentedInspectorDeviceId = nil

            guard let removed = source.devices?.remove(at: idx) else { return }
            // Append to destination studio
            let newPos = findAvailableDevicePosition(
                in: destination,
                canvas: canvasSize
            )
            let moved = DeviceInstance(
                manufacturer: removed.manufacturer,
                model: removed.model,
                nickname: removed.nickname,
                category: removed.category,
                serialNumber: removed.serialNumber,
                location: removed.location,
                audioInputsCount: removed.audioInputsCount,
                audioOutputsCount: removed.audioOutputsCount,
                adatInputPortsCount: removed.adatInputPortsCount,
                adatOutputPortsCount: removed.adatOutputPortsCount,
                madiInputPortsCount: removed.madiInputPortsCount,
                madiOutputPortsCount: removed.madiOutputPortsCount,
                sampleRate: SampleRate(rawValue: removed.sampleRateRaw)
                    ?? (SampleRate.allCases.first ?? SampleRate(rawValue: 0)!),
                digitalInputs: removed.digitalInputs,
                digitalOutputs: removed.digitalOutputs,
                computerInterfaces: removed.computerInterfaces,
                posX: newPos.x,
                posY: newPos.y,
                scale: removed.scale,
                zIndex: removed.zIndex
            )
            moved.frontImagePath = removed.frontImagePath
            moved.rearImagePath = removed.rearImagePath
            moved.ports = removed.ports?.map { p in
                let np = Port(
                    name: p.name,
                    type: p.type,
                    direction: p.direction
                )
                np.channels = p.channels?.map { ch in
                    Channel(
                        index: ch.index,
                        nameLong: ch.nameLong,
                        nameShort: ch.nameShort,
                        signal: ch.signal,
                        grouping: ch.grouping
                    )
                } ?? []
                return np
            }
            
            // Set Gear Locker flags if moving to Gear Locker
            if destination.isSystemStudio && destination.systemStudioType == "gear_locker" {
                moved.isInGearLocker = true
                moved.isAssignedFromLocker = false
                moved.lockerSourceDeviceId = nil
            } else {
                // Moving to a regular studio
                moved.isInGearLocker = false
                moved.isAssignedFromLocker = false
                moved.lockerSourceDeviceId = nil
            }
            
            if destination.devices == nil {
                destination.devices = []
            }
            destination.devices?.append(moved)

            // Remove any connections involving the old device in the source studio
            let sourceLinks = connectionsStore.links(for: source.id)
            for link in sourceLinks
            where
                (link.fromDeviceId == device.id || link.toDeviceId == device.id)
            {
                _ = connectionsStore.deleteBundle(
                    studioId: source.id,
                    linkId: link.id
                )
            }
            // Ensure there are no connections in destination that reference the new device (should be none yet)
            let destLinks = connectionsStore.links(for: destination.id)
            for link in destLinks
            where (link.fromDeviceId == moved.id || link.toDeviceId == moved.id)
            {
                _ = connectionsStore.deleteBundle(
                    studioId: destination.id,
                    linkId: link.id
                )
            }

            // Update selection to moved device and switch selected studio
            selectedStudioId = destination.id
            selectionState.selection = .device(moved.id)
        }
    }

    private func buildPorts(
        audioInputs: Int,
        audioOutputs: Int,
        digitalInputs: [DigitalFormat],
        digitalOutputs: [DigitalFormat],
        adatInputPorts: Int,
        adatOutputPorts: Int,
        madiInputPorts: Int,
        madiOutputPorts: Int,
        midiInputPorts: Int,
        midiOutputPorts: Int,
        computerInterfaceCounts: [ComputerInterface: Int],
        sampleRate: SampleRate
    ) -> [Port] {
        var ports: [Port] = []

        let srHz = sampleRateRawHz(sampleRate)
        let adatChannelsPerPort: Int = srHz >= 88_200 ? 4 : 8
        let madiChannelsPerPort: Int =
            srHz >= 176_400 ? 16 : (srHz >= 88_200 ? 32 : 64)
        let danteChannelsPerLink: Int = 64

        func portLetter(_ i: Int) -> String {
            let scalar = UnicodeScalar(65 + max(0, i))!
            return String(Character(scalar))  // A, B, C...
        }

        if audioInputs > 0 {
            let p = Port(name: "Analog In", type: .analogIn, direction: .input)
            p.channels = (1...audioInputs).map {
                Channel(
                    index: $0,
                    nameLong: "Analog In \($0)",
                    nameShort: "In\($0)"
                )
            }
            ports.append(p)
        }

        if audioOutputs > 0 {
            let p = Port(
                name: "Analog Out",
                type: .analogOut,
                direction: .output
            )
            p.channels = (1...audioOutputs).map {
                Channel(
                    index: $0,
                    nameLong: "Analog Out \($0)",
                    nameShort: "Out\($0)"
                )
            }
            ports.append(p)
        }
        
        // MIDI DIN 5-pin ports (each port is independent, unlike ADAT)
        // MIDI Input Ports
        if midiInputPorts > 0 {
            for i in 1...midiInputPorts {
                let p = Port(name: "MIDI In \(i)", type: .midiIn, direction: .input)
                p.channels = [
                    Channel(
                        index: 1,
                        nameLong: "MIDI In \(i)",
                        nameShort: "In\(i)"
                    )
                ]
                ports.append(p)
            }
        }
        
        // MIDI Output Ports
        if midiOutputPorts > 0 {
            for i in 1...midiOutputPorts {
                let p = Port(name: "MIDI Out \(i)", type: .midiOut, direction: .output)
                p.channels = [
                    Channel(
                        index: 1,
                        nameLong: "MIDI Out \(i)",
                        nameShort: "Out\(i)"
                    )
                ]
                ports.append(p)
            }
        }

        func digitalPort(
            type: PortType,
            name: String,
            direction: PortDirection,
            channels: Int
        ) -> Port {
            let p = Port(name: name, type: type, direction: direction)
            p.channels = (1...channels).map {
                Channel(
                    index: $0,
                    nameLong: "\(name) \($0)",
                    nameShort: "\($0)"
                )
            }
            return p
        }

        for f in digitalInputs.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch f {
            case .adat:
                let count = max(1, max(0, adatInputPorts))
                for i in 0..<count {
                    let name = "ADAT In \(portLetter(i))"
                    ports.append(
                        digitalPort(
                            type: .adatIn,
                            name: name,
                            direction: .input,
                            channels: adatChannelsPerPort
                        )
                    )
                }
            case .madi:
                let count = max(1, max(0, madiInputPorts))
                for i in 0..<count {
                    let name = "MADI In \(portLetter(i))"
                    ports.append(
                        digitalPort(
                            type: .madiIn,
                            name: name,
                            direction: .input,
                            channels: madiChannelsPerPort
                        )
                    )
                }
            case .dante:
                // Represent Dante as an Ethernet-based digital input (one logical link = 64ch).
                ports.append(
                    digitalPort(
                        type: .ethernet,
                        name: "Dante In (Ethernet)",
                        direction: .input,
                        channels: danteChannelsPerLink
                    )
                )
            case .spdif:
                let p = Port(name: "Digital In (S/PDIF)", type: .spdifIn, direction: .input)
                p.channels = [
                    Channel(
                        index: 1,
                        nameLong: "Digital In (S/PDIF) L/R",
                        nameShort: "L/R"
                    )
                ]
                ports.append(p)
            case .midi:
                // MIDI over USB (bidirectional - appears in both inputs and outputs)
                ports.append(
                    digitalPort(
                        type: .midiIn,
                        name: "MIDI over USB In",
                        direction: .input,
                        channels: 1
                    )
                )
            case .wordClock:
                ports.append(
                    digitalPort(
                        type: .wordClockIn,
                        name: "Word Clock In",
                        direction: .input,
                        channels: 1
                    )
                )
            case .aesebu:
                ports.append(
                    digitalPort(
                        type: .aesIn,
                        name: "Digital In (AES/EBU)",
                        direction: .input,
                        channels: 2
                    )
                )
            }
        }

        for f in digitalOutputs.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch f {
            case .adat:
                let count = max(1, max(0, adatOutputPorts))
                for i in 0..<count {
                    let name = "ADAT Out \(portLetter(i))"
                    ports.append(
                        digitalPort(
                            type: .adatOut,
                            name: name,
                            direction: .output,
                            channels: adatChannelsPerPort
                        )
                    )
                }
            case .madi:
                let count = max(1, max(0, madiOutputPorts))
                for i in 0..<count {
                    let name = "MADI Out \(portLetter(i))"
                    ports.append(
                        digitalPort(
                            type: .madiOut,
                            name: name,
                            direction: .output,
                            channels: madiChannelsPerPort
                        )
                    )
                }
            case .dante:
                ports.append(
                    digitalPort(
                        type: .ethernet,
                        name: "Dante Out (Ethernet)",
                        direction: .output,
                        channels: danteChannelsPerLink
                    )
                )
            case .spdif:
                let p = Port(name: "Digital Out (S/PDIF)", type: .spdifOut, direction: .output)
                p.channels = [
                    Channel(
                        index: 1,
                        nameLong: "Digital Out (S/PDIF) L/R",
                        nameShort: "L/R"
                    )
                ]
                ports.append(p)
            case .midi:
                // MIDI over USB (bidirectional - appears in both inputs and outputs)
                ports.append(
                    digitalPort(
                        type: .midiOut,
                        name: "MIDI over USB Out",
                        direction: .output,
                        channels: 1
                    )
                )
            case .wordClock:
                ports.append(
                    digitalPort(
                        type: .wordClockOut,
                        name: "Word Clock Out",
                        direction: .output,
                        channels: 1
                    )
                )
            case .aesebu:
                ports.append(
                    digitalPort(
                        type: .aesOut,
                        name: "Digital Out (AES/EBU)",
                        direction: .output,
                        channels: 2
                    )
                )
            }
        }

        // Computer Interfaces (USB / Thunderbolt / Ethernet, etc.)
        // These are *bidirectional* physical ports. We represent each physical port as a single
        // 1-channel logical port so they can show up in I/O lists and participate in occupancy.
        // IMPORTANT: Do NOT model these as separate "In" and "Out" ports.
        if !computerInterfaceCounts.isEmpty {
            let sortedIfaces = computerInterfaceCounts.keys.sorted(by: {
                $0.rawValue < $1.rawValue
            })
            for iface in sortedIfaces {
                let count = max(0, computerInterfaceCounts[iface] ?? 0)
                if count == 0 { continue }

                for i in 0..<count {
                    let suffix = count > 1 ? " \(i + 1)" : ""
                    let name = "\(iface.rawValue)\(suffix)"

                    // Map computer interface type to appropriate PortType
                    let portType: PortType
                    switch iface {
                    case .usb, .usbc:
                        portType = .usbAudio
                    case .thunderbolt:
                        portType = .thunderboltAudio
                    case .ethernet:
                        portType = .ethernet
                    case .firewire:
                        portType = .computerHost  // Fallback for older interface
                    }

                    // NOTE: PortDirection only supports input/output in the current model.
                    // We choose `.input` as a neutral placeholder; UI labels should rely on `name`
                    // (and not append "In"/"Out" for computer interfaces).
                    let p = Port(name: name, type: portType, direction: .input)
                    p.channels = [
                        Channel(index: 1, nameLong: "\(name) 1", nameShort: "1")
                    ]
                    ports.append(p)
                }
            }
        }

        return ports
    }

    private func findAvailableDevicePosition(in studio: Studio, canvas: CGSize)
        -> (x: Double, y: Double)
    {
        // Match the card size used in CanvasSurfaceView clamping.
        let cardSize = CGSize(width: 260, height: 96)
        let halfW = Double(cardSize.width / 2)
        let halfH = Double(cardSize.height / 2)

        let width = max(Double(canvas.width), 600)
        let height = max(Double(canvas.height), 400)

        // Search around the center in a spiral.
        let centerX = width / 2
        let centerY = height / 2

        func clamped(_ x: Double, _ y: Double) -> (Double, Double) {
            let cx = min(max(x, halfW), width - halfW)
            let cy = min(max(y, halfH), height - halfH)
            return (cx, cy)
        }

        func intersectsAny(_ x: Double, _ y: Double) -> Bool {
            // Simple AABB intersection test with a small padding.
            let pad: Double = 12
            let leftA = x - halfW - pad
            let rightA = x + halfW + pad
            let topA = y - halfH - pad
            let bottomA = y + halfH + pad

            for d in studio.devices ?? [] {
                let dx = d.posX
                let dy = d.posY
                let leftB = dx - halfW
                let rightB = dx + halfW
                let topB = dy - halfH
                let bottomB = dy + halfH

                let overlap =
                    !(rightA < leftB || rightB < leftA || bottomA < topB
                    || bottomB < topA)
                if overlap { return true }
            }
            return false
        }

        // Try center first.
        let (cX, cY) = clamped(centerX, centerY)
        if !intersectsAny(cX, cY) { return (cX, cY) }

        // Spiral parameters
        let step: Double = 50
        let maxR = max(width, height)
        var r: Double = step

        while r <= maxR {
            // sample points around the circle-ish perimeter
            let points: [(Double, Double)] = [
                (centerX + r, centerY),
                (centerX - r, centerY),
                (centerX, centerY + r),
                (centerX, centerY - r),
                (centerX + r, centerY + r),
                (centerX - r, centerY + r),
                (centerX + r, centerY - r),
                (centerX - r, centerY - r),
            ]

            for (x0, y0) in points {
                let (x, y) = clamped(x0, y0)
                if !intersectsAny(x, y) { return (x, y) }
            }

            // Add more samples for larger rings.
            let samples = Int(max(8, r / step * 8))
            if samples > 8 {
                for i in 0..<samples {
                    let t = (Double(i) / Double(samples)) * (Double.pi * 2)
                    let x0 = centerX + cos(t) * r
                    let y0 = centerY + sin(t) * r
                    let (x, y) = clamped(x0, y0)
                    if !intersectsAny(x, y) { return (x, y) }
                }
            }

            r += step
        }

        // Fallback: staggered placement based on count
        let idx = Double(studio.devices?.count ?? 0)
        let (fx, fy) = clamped(
            centerX + (idx * 20).truncatingRemainder(dividingBy: 240) - 120,
            centerY + (idx * 16).truncatingRemainder(dividingBy: 200) - 100
        )
        return (fx, fy)
    }

    private func defaultPortsGuess(
        forManufacturer manufacturer: String,
        model: String
    ) -> [Port] {
        // Backward compatibility: used only by duplicateStudio if older devices exist.
        let analogIn = Port(
            name: "Analog In",
            type: .analogIn,
            direction: .input
        )
        analogIn.channels = (1...2).map {
            Channel(
                index: $0,
                nameLong: "Analog In \($0)",
                nameShort: "In\($0)"
            )
        }

        let analogOut = Port(
            name: "Analog Out",
            type: .analogOut,
            direction: .output
        )
        analogOut.channels = (1...2).map {
            Channel(
                index: $0,
                nameLong: "Analog Out \($0)",
                nameShort: "Out\($0)"
            )
        }

        return [analogIn, analogOut]
    }

    // MARK: - View Helpers

    private var studiosSortedByName: [Studio] {
        studios.sorted { a, b in
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var canvasBackground: Color {
        #if os(iOS)
            Color(UIColor.systemBackground)
        #else
            Color(NSColor.windowBackgroundColor)
        #endif
    }

    private var currentStudio: Studio? {
        guard let id = selectedStudioId else { return studios.first }
        return studios.first(where: { $0.id == id })
    }

    private var studioPendingDelete: Studio? {
        guard let id = studioIdPendingDelete else { return nil }
        return studios.first(where: { $0.id == id })
    }

    private func deletePendingStudio() {
        guard let studio = studioPendingDelete else { return }

        if selectedStudioId == studio.id {
            selectedStudioId = nil
        }

        modelContext.delete(studio)
        studioIdPendingDelete = nil

        if selectedStudioId == nil {
            selectedStudioId = studios.first(where: { $0.id != studio.id })?.id
        }
    }

    private func duplicateStudio(from source: Studio) {
        // Check studio limit for free tier
        if !storeManager.canAddStudio(currentCount: studios.count) {
            paywallReason = .studioLimit
            isShowingPaywall = true
            return
        }

        let copy = Studio(name: "\(source.name) Copy")
        
        // Map old device UUIDs to new devices
        var deviceMap: [UUID: DeviceInstance] = [:]
        var portMap: [UUID: Port] = [:]
        var channelMap: [UUID: Channel] = [:]
        var computerPortIdMap: [UUID: UUID] = [:]
        var computerChannelIdMap: [UUID: UUID] = [:]
        
        // Copy devices with all properties
        for d in source.devices ?? [] {
            let newDevice = DeviceInstance(
                manufacturer: d.manufacturer,
                model: d.model,
                nickname: d.nickname,
                category: d.category,
                serialNumber: d.serialNumber,
                location: d.location,
                audioInputsCount: d.audioInputsCount,
                audioOutputsCount: d.audioOutputsCount,
                adatInputPortsCount: d.adatInputPortsCount,
                adatOutputPortsCount: d.adatOutputPortsCount,
                madiInputPortsCount: d.madiInputPortsCount,
                madiOutputPortsCount: d.madiOutputPortsCount,
                ethernetPortsCount: d.ethernetPortsCount,
                sampleRate: d.sampleRate,
                digitalInputs: d.digitalInputs,
                digitalOutputs: d.digitalOutputs,
                computerInterfaces: d.computerInterfaces,
                posX: d.posX + 30,
                posY: d.posY + 30,
                scale: d.scale,
                zIndex: d.zIndex
            )
            newDevice.frontImagePath = d.frontImagePath
            newDevice.rearImagePath = d.rearImagePath
            newDevice.supportPageURLString = d.supportPageURLString
            newDevice.downloadsPageURLString = d.downloadsPageURLString

            // Copy ports
            for p in d.ports ?? [] {
                let newPort = Port(
                    name: p.name,
                    type: p.type,
                    direction: p.direction
                )
                
                // Copy channels
                for ch in p.channels ?? [] {
                    let newChannel = Channel(
                        index: ch.index,
                        nameLong: ch.nameLong,
                        nameShort: ch.nameShort,
                        signal: ch.signal,
                        grouping: ch.grouping
                    )
                    if newPort.channels == nil {
                        newPort.channels = []
                    }
                    newPort.channels?.append(newChannel)
                    channelMap[ch.id] = newChannel
                }
                
                if newDevice.ports == nil {
                    newDevice.ports = []
                }
                newDevice.ports?.append(newPort)
                portMap[p.id] = newPort
            }
            
            // Copy docs
            for doc in d.docs ?? [] {
                let newDoc: DocLink
                if let bookmarkData = doc.localBookmarkData {
                    newDoc = DocLink(title: doc.title, kind: doc.kind, bookmarkData: bookmarkData)
                } else if let urlString = doc.urlString, let url = URL(string: urlString) {
                    newDoc = DocLink(title: doc.title, kind: doc.kind, url: url)
                } else {
                    continue
                }
                if newDevice.docs == nil {
                    newDevice.docs = []
                }
                newDevice.docs?.append(newDoc)
            }

            if copy.devices == nil {
                copy.devices = []
            }
            copy.devices?.append(newDevice)
            deviceMap[d.id] = newDevice
            
            // Map virtual computer interface ports/channels
            let oldDeviceId = d.id
            let newDeviceId = newDevice.id
            let counts = newDevice.computerInterfaceCounts
            
            for iface in d.computerInterfaces {
                let count = counts[iface] ?? 0
                if count == 0 { continue }
                
                for i in 1...count {
                    let oldPortId = stableUUID("computerPort|\(oldDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                    let oldChannelId = stableUUID("computerCh|\(oldDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                    let newPortId = stableUUID("computerPort|\(newDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                    let newChannelId = stableUUID("computerCh|\(newDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                    
                    computerPortIdMap[oldPortId] = newPortId
                    computerChannelIdMap[oldChannelId] = newChannelId
                }
            }
        }
        
        // Copy connections from ConnectionsStore
        let sourceLinks = connectionsStore.links(for: source.id)
        for link in sourceLinks {
            guard let bundle = connectionsStore.bundle(for: source.id, linkId: link.id) else { continue }
            
            // Map each edge to the new device/port/channel IDs
            for edge in bundle.edges {
                guard let fromDevice = deviceMap[edge.from.deviceId],
                      let toDevice = deviceMap[edge.to.deviceId] else {
                    continue
                }
                
                // Map port and channel IDs (check regular first, then computer interface maps)
                let fromPortId: UUID
                let toPortId: UUID
                let fromChannelId: UUID
                let toChannelId: UUID
                
                if let port = portMap[edge.from.portId] {
                    fromPortId = port.id
                } else if let mappedPortId = computerPortIdMap[edge.from.portId] {
                    fromPortId = mappedPortId
                } else {
                    continue
                }
                
                if let port = portMap[edge.to.portId] {
                    toPortId = port.id
                } else if let mappedPortId = computerPortIdMap[edge.to.portId] {
                    toPortId = mappedPortId
                } else {
                    continue
                }
                
                if let channel = channelMap[edge.from.channelId] {
                    fromChannelId = channel.id
                } else if let mappedChannelId = computerChannelIdMap[edge.from.channelId] {
                    fromChannelId = mappedChannelId
                } else {
                    continue
                }
                
                if let channel = channelMap[edge.to.channelId] {
                    toChannelId = channel.id
                } else if let mappedChannelId = computerChannelIdMap[edge.to.channelId] {
                    toChannelId = mappedChannelId
                } else {
                    continue
                }
                
                // Create connection in SwiftData
                let connection = Connection(
                    fromDeviceId: fromDevice.id,
                    fromPortId: fromPortId,
                    fromChannelId: fromChannelId,
                    toDeviceId: toDevice.id,
                    toPortId: toPortId,
                    toChannelId: toChannelId,
                    cable: .other,
                    label: edge.fromName,
                    notes: nil
                )
                if copy.connections == nil {
                    copy.connections = []
                }
                copy.connections?.append(connection)
            }
        }

        // Copy canvas annotations
        copy.canvasDrawingData = source.canvasDrawingData
        
        modelContext.insert(copy)
        copy.markAsModified()
        try? modelContext.save()
        
        // Rebuild ConnectionsStore from the copied connections
        connectionsStore.rebuildFromConnections(studio: copy)
        
        selectedStudioId = copy.id
    }

    private func exportStudio(_ studio: Studio) {
        // Check if export is allowed for free tier
        if !storeManager.canExportImport {
            paywallReason = .exportImport
            isShowingPaywall = true
            return
        }

        // First, clean up any orphaned connections in ConnectionsStore
        connectionsStore.cleanupOrphanedConnections(studio: studio)

        // Then sync connections from ConnectionsStore to SwiftData
        syncConnectionsToSwiftData(studio: studio)

        #if DEBUG
        // Log export statistics
        print("📤 Exporting studio '\(studio.name)':")
        print("   Devices: \(studio.devices?.count ?? 0)")
        print("   Connections in SwiftData: \(studio.connections?.count ?? 0)")
        #endif

        // Create exportable representation
        let exportable = ExportableStudio(from: studio)
        
        #if DEBUG
        print("   Connections in exportable: \(exportable.connections.count)")
        print("   Devices in exportable: \(exportable.devices.count)")
        #endif

        // Create document
        exportDocument = StudioDocument(exportableStudio: exportable)
        isShowingExportPicker = true
    }

    // MARK: - Port Migration

    /// Fixes port types for computer interface and MIDI ports without changing port IDs (preserves connections)
    private func fixComputerInterfacePortTypes(in studio: Studio) {
        // print(
        //     "🔧 Running port type migration for \(studio.devices?.count ?? 0) devices..."
        // )
        for device in studio.devices ?? [] {
            // Fix computer interface ports
            let counts = device.computerInterfaceCounts
            if !counts.isEmpty {
                // print(
                //     "  Device: \(device.nickname), computer interfaces: \(counts)"
                // )

                for (iface, count) in counts {
                    guard count > 0 else { continue }

                    // Determine the correct port type for this interface
                    let correctPortType: PortType
                    switch iface {
                    case .usb, .usbc:
                        correctPortType = .usbAudio
                    case .thunderbolt:
                        correctPortType = .thunderboltAudio
                    case .ethernet:
                        correctPortType = .ethernet
                    case .firewire:
                        correctPortType = .computerHost
                    }

                    // Find and fix ports with matching names but wrong types
                    for i in 0..<count {
                        let suffix = count > 1 ? " \(i + 1)" : ""
                        let expectedName = "\(iface.rawValue)\(suffix)"

                        if let port = device.ports?.first(where: {
                            $0.name == expectedName
                        }) {
                            if port.type != correctPortType {
                                #if DEBUG
                                print(
                                    "    ✅ FIXING port '\(expectedName)' from \(port.type.rawValue) to \(correctPortType.rawValue)"
                                )
                                #endif
                                port.typeRaw = correctPortType.rawValue
                            }
                        }
                    }
                }
            }

            // Fix MIDI ports (legacy devices may have "Digital In/Out (MIDI)" with wrong type)
            for port in device.ports ?? [] {
                if port.name.contains("MIDI") {
                    let expectedType: PortType =
                        port.direction == .input ? .midiIn : .midiOut
                    if port.type != expectedType {
                        #if DEBUG
                        print(
                            "  ✅ FIXING MIDI port '\(port.name)' from \(port.type.rawValue) to \(expectedType.rawValue)"
                        )
                        #endif
                        port.typeRaw = expectedType.rawValue
                    }
                }
            }
        }
    }
    
    private func exportCanvasAsPDF(studio: Studio) {
        guard let devices = studio.devices, !devices.isEmpty else {
            isShowingExportCanvasAlert = true
            return
        }
        
        // Show loading indicator
        isExportingCanvas = true
        
        // Calculate bounds of all devices
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        
        for device in devices {
            minX = min(minX, device.posX - 130) // Half card width
            minY = min(minY, device.posY - 48)  // Half card height
            maxX = max(maxX, device.posX + 130)
            maxY = max(maxY, device.posY + 48)
        }
        
        let padding: Double = 50
        let canvasWidth = maxX - minX + padding * 2
        let canvasHeight = maxY - minY + padding * 2
        let offsetX = -minX + padding
        let offsetY = -minY + padding
        
        // Create printable canvas view
        let printableCanvas = ZStack {
            Rectangle()
                .fill(Color(white: 0.95))
            
            // Draw connection lines with proper colors
            let links = connectionsStore.links(for: studio.id)
            ForEach(links, id: \.id) { link in
                if let fromDevice = devices.first(where: { $0.id == link.fromDeviceId }),
                   let toDevice = devices.first(where: { $0.id == link.toDeviceId }),
                   let bundle = connectionsStore.bundle(for: studio.id, linkId: link.id) {
                    
                    // Determine all connection types for this link (for parallel lines)
                    let connectionTypes: [ConnectionVisualType] = {
                        var typeCounts: [ConnectionVisualType: Int] = [:]
                        
                        for edge in bundle.edges {
                            if let device = devices.first(where: { $0.id == edge.from.deviceId }) {
                                // Check for regular ports first
                                if let port = device.ports?.first(where: { $0.id == edge.from.portId }) {
                                    let type = ConnectionVisualType.from(portType: port.type)
                                    typeCounts[type, default: 0] += 1
                                } else if !device.computerInterfaceCounts.isEmpty {
                                    // Computer interface (virtual port)
                                    typeCounts[.computer, default: 0] += 1
                                }
                            }
                        }
                        
                        let sortedTypes = typeCounts.sorted { $0.value > $1.value }.map { $0.key }
                        return sortedTypes.isEmpty ? [.unknown] : sortedTypes
                    }()
                    
                    // Draw parallel lines if multiple connection types exist
                    ForEach(Array(connectionTypes.enumerated()), id: \.offset) { index, type in
                        let offset = {
                            let spacing: CGFloat = 6.0
                            let total = connectionTypes.count
                            if total == 1 { return CGFloat(0) }
                            if total == 2 {
                                return index == 0 ? -spacing / 2 : spacing / 2
                            }
                            let totalWidth = spacing * CGFloat(total - 1)
                            return CGFloat(index) * spacing - totalWidth / 2
                        }()
                        
                        Path { path in
                            let from = CGPoint(
                                x: fromDevice.posX + offsetX,
                                y: fromDevice.posY + offsetY
                            )
                            let to = CGPoint(
                                x: toDevice.posX + offsetX,
                                y: toDevice.posY + offsetY
                            )
                            
                            let dx = to.x - from.x
                            let dy = to.y - from.y
                            let distance = sqrt(dx * dx + dy * dy)
                            
                            let perpX = -dy / distance * offset
                            let perpY = dx / distance * offset
                            
                            let offsetFrom = CGPoint(x: from.x + perpX, y: from.y + perpY)
                            let offsetTo = CGPoint(x: to.x + perpX, y: to.y + perpY)
                            
                            path.move(to: offsetFrom)
                            path.addLine(to: offsetTo)
                        }
                        .stroke(type.color, lineWidth: 2)
                    }
                }
            }
            
            // Draw devices
            ForEach(devices, id: \.id) { device in
                let deviceColor: Color = {
                    if let customColor = device.customColor {
                        return customColor
                    } else {
                        let categoryColors = CategoryColorSettings.loadCategoryColors()
                        return categoryColors[device.category] ?? .gray
                    }
                }()
                
                VStack(spacing: 4) {
                    Text(device.nickname)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    Text(device.category.rawValue)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    Text(ioSummary(from: device.ports))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(width: 240, height: 80)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(deviceColor, lineWidth: 3)
                        )
                )
                .shadow(radius: 2)
                .position(
                    x: device.posX + offsetX,
                    y: device.posY + offsetY
                )
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        
        // Create full printable view with title and legend
        let fullView = VStack(spacing: 0) {
            Text("Studio Canvas: \(studio.name)")
                .font(.title)
                .fontWeight(.bold)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
            
            printableCanvas
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    Text("Legend:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConnectionVisualType.analog.color)
                            .frame(width: 12, height: 12)
                        Text("Analog")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConnectionVisualType.digital.color)
                            .frame(width: 12, height: 12)
                        Text("Digital (ADAT/MADI/S/PDIF)")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConnectionVisualType.midi.color)
                            .frame(width: 12, height: 12)
                        Text("MIDI")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ConnectionVisualType.computer.color)
                            .frame(width: 12, height: 12)
                        Text("Computer")
                            .font(.caption)
                    }
                }
                HStack(spacing: 8) {
                    Text("WC")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(3)
                    Text("= Word Clock (sync only, not counted in I/O)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
        }
        
        #if os(iOS)
        // Create renderer and generate PDF (must happen on main thread for SwiftUI)
        let renderer = ImageRenderer(content: fullView)
        renderer.scale = 2.0
        
        // Defer actual work slightly to allow loading indicator to show
        DispatchQueue.main.async { [self] in
            if let pdfData = renderer.pdf() {
                let filename = "\(studio.name.replacingOccurrences(of: " ", with: "_"))_Canvas.pdf"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try? pdfData.write(to: tempURL)
                
                // Hide loading indicator
                self.isExportingCanvas = false
                
                // Present share sheet
                let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = windowScene.windows.first?.rootViewController {
                    var presentingVC = rootVC
                    while let presented = presentingVC.presentedViewController {
                        presentingVC = presented
                    }
                    
                    if let popover = activityVC.popoverPresentationController {
                        popover.sourceView = presentingVC.view
                        popover.sourceRect = CGRect(x: presentingVC.view.bounds.midX, y: presentingVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    
                    presentingVC.present(activityVC, animated: true)
                }
            } else {
                // Hide loading indicator on failure
                self.isExportingCanvas = false
            }
        }
        #elseif os(macOS)
        DispatchQueue.main.async { [self] in
            let renderer = ImageRenderer(content: fullView)
            renderer.scale = 2.0
            
            if let pdfData = renderer.pdf() {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.pdf]
                savePanel.nameFieldStringValue = "\(studio.name.replacingOccurrences(of: " ", with: "_"))_Canvas.pdf"
                
                savePanel.begin { response in
                    if response == .OK, let url = savePanel.url {
                        try? pdfData.write(to: url)
                    }
                    // Hide loading indicator after save dialog closes
                    self.isExportingCanvas = false
                }
            } else {
                // Hide loading indicator on failure
                self.isExportingCanvas = false
            }
        }
        #endif
    }
    
    // MARK: - Auto-Arrange (Band-Based Layout)
    
    /// Arranges devices in three horizontal bands: top (outputs), middle (hubs), bottom (inputs)
    /// Signal flow goes from bottom → middle → top
    /// Respects pinned devices - they remain in place
    private func autoArrangeWithHubDetection(in studio: Studio) {
        guard !(studio.devices?.isEmpty ?? true) else { return }

        // Save current positions for undo (only for non-pinned devices)
        savedDevicePositions.removeAll()
        for device in studio.devices ?? [] {
            if !device.isPinned {
                savedDevicePositions[device.id] = (x: device.posX, y: device.posY)
            }
        }
        canUndoAutoArrange = true
        
        // Separate pinned and unpinned devices
        let allDevices = studio.devices ?? []
        let unpinnedDevices = allDevices.filter { !$0.isPinned }
        // Note: Pinned devices remain at their current positions and are not rearranged
        
        // Get connections from the connection store
        let links = connectionsStore.links(for: studio.id)
        
        // Build graph: count incoming and outgoing connections per device (only for unpinned devices)
        var outgoingCounts: [UUID: Int] = [:]
        var incomingCounts: [UUID: Int] = [:]
        var totalConnections: [UUID: Int] = [:]
        
        for device in unpinnedDevices {
            outgoingCounts[device.id] = 0
            incomingCounts[device.id] = 0
            totalConnections[device.id] = 0
        }
        
        for link in links {
            outgoingCounts[link.fromDeviceId, default: 0] += 1
            incomingCounts[link.toDeviceId, default: 0] += 1
            totalConnections[link.fromDeviceId, default: 0] += 1
            totalConnections[link.toDeviceId, default: 0] += 1
        }
        
        // Classify device roles: input, hub, output, neutral
        enum DeviceRole {
            case input      // Sources: more outgoing than incoming
            case hub        // High connection count, central routing
            case output     // Sinks: more incoming than outgoing
            case neutral    // Effects, processors
        }
        
        var deviceRoles: [UUID: DeviceRole] = [:]
        
        for device in unpinnedDevices {
            let outgoing = outgoingCounts[device.id] ?? 0
            let incoming = incomingCounts[device.id] ?? 0
            let total = totalConnections[device.id] ?? 0
            
            // First, classify by category
            let categoryRole: DeviceRole
            switch device.category {
            // Outputs: speakers, monitors
            case .monitor, .videoMonitor:
                categoryRole = .output
                
            // Hubs: interfaces, mixers, DAWs, patchbays
            case .audioInterface, .mixer, .digitalMixer, .patchbay, .computer:
                categoryRole = .hub
                
            // Inputs: sources
            case .synth, .keyboard, .midiDevice, .multi:
                categoryRole = .input
                
            // Neutral: effects, processors, control surfaces
            case .effectsUnit, .compressor, .equalizer, .channelStrip, .busCompressor, .preamp, .controlSurface, .adatExpander, .usbHub, .usbExpander:
                categoryRole = .neutral
                
            default:
                categoryRole = .neutral
            }
            
            // Refine by connection counts
            if total >= 4 {
                // High connection count → likely a hub
                deviceRoles[device.id] = .hub
            } else if outgoing > incoming * 2 && outgoing > 0 {
                // Significantly more outgoing → input/source
                deviceRoles[device.id] = .input
            } else if incoming > outgoing * 2 && incoming > 0 {
                // Significantly more incoming → output/sink
                deviceRoles[device.id] = .output
            } else {
                // Use category-based classification
                deviceRoles[device.id] = categoryRole
            }
        }
        
        // Assign to bands (only unpinned devices)
        var topBand: [DeviceInstance] = []      // Outputs
        var middleBand: [DeviceInstance] = []   // Hubs + Neutral
        var bottomBand: [DeviceInstance] = []   // Inputs
        var unconnectedDevices: [DeviceInstance] = []
        
        for device in unpinnedDevices {
            let hasConnections = (totalConnections[device.id] ?? 0) > 0
            
            if !hasConnections {
                unconnectedDevices.append(device)
                continue
            }
            
            switch deviceRoles[device.id] {
            case .output:
                topBand.append(device)
            case .hub, .neutral:
                middleBand.append(device)
            case .input:
                bottomBand.append(device)
            case .none:
                middleBand.append(device)
            }
        }
        
        // Layout constants
        let deviceCardHeight: Double = 96
        let deviceCardWidth: Double = 260
        let horizontalSpacing: Double = 100
        let padding: Double = 150
        
        // Calculate canvas dimensions based on widest band
        let maxDevicesInBand = max(topBand.count, middleBand.count, bottomBand.count, 1)
        let canvasWidth = Double(maxDevicesInBand) * (deviceCardWidth + horizontalSpacing) + padding * 2
        let canvasHeight: Double = 1200  // Fixed height for three bands
        
        // Band Y positions (signal flow: bottom → middle → top)
        let topBandY = canvasHeight * 0.20      // 20% from top
        let middleBandY = canvasHeight * 0.50   // 50% (middle)
        let bottomBandY = canvasHeight * 0.80   // 80% from top
        
        // Position devices in each band with horizontal spacing
        positionDevicesInBand(
            devices: topBand,
            y: topBandY,
            canvasWidth: canvasWidth,
            cardWidth: deviceCardWidth,
            spacing: horizontalSpacing,
            padding: padding,
            snapToGrid: studio.layoutMode == "snapToGrid",
            gridSize: studio.gridSize
        )
        
        positionDevicesInBand(
            devices: middleBand,
            y: middleBandY,
            canvasWidth: canvasWidth,
            cardWidth: deviceCardWidth,
            spacing: horizontalSpacing,
            padding: padding,
            snapToGrid: studio.layoutMode == "snapToGrid",
            gridSize: studio.gridSize
        )
        
        positionDevicesInBand(
            devices: bottomBand,
            y: bottomBandY,
            canvasWidth: canvasWidth,
            cardWidth: deviceCardWidth,
            spacing: horizontalSpacing,
            padding: padding,
            snapToGrid: studio.layoutMode == "snapToGrid",
            gridSize: studio.gridSize
        )
        
        // Position unconnected devices in far right column
        if !unconnectedDevices.isEmpty {
            let unconnectedX = canvasWidth - padding - deviceCardWidth / 2
            let unconnectedStartY = padding + deviceCardHeight / 2
            
            for (index, device) in unconnectedDevices.enumerated() {
                device.posX = unconnectedX
                device.posY = unconnectedStartY + Double(index) * (deviceCardHeight + 50)
            }
        }
        
        // Normalize all coordinates to ensure they're positive
        var minX = Double.infinity
        var minY = Double.infinity
        
        for device in studio.devices ?? [] {
            minX = min(minX, device.posX - deviceCardWidth / 2)
            minY = min(minY, device.posY - deviceCardHeight / 2)
        }
        
        let targetMin = padding
        let shiftX = minX < targetMin ? (targetMin - minX) : 0
        let shiftY = minY < targetMin ? (targetMin - minY) : 0
        
        if shiftX != 0 || shiftY != 0 {
            for device in studio.devices ?? [] {
                device.posX += shiftX
                device.posY += shiftY
            }
        }
        
        // Mark all modified devices and studio for iCloud sync
        for device in studio.devices ?? [] {
            device.markAsModified()
        }
        studio.markAsModified()
        
        // Save changes
        do {
            try modelContext.save()
        } catch {
            print("Failed to save after auto-arrange: \(error)")
        }
    }
    
    /// Position devices in a horizontal band with even spacing and staggered vertical offsets
    private func positionDevicesInBand(
        devices: [DeviceInstance],
        y: Double,
        canvasWidth: Double,
        cardWidth: Double,
        spacing: Double,
        padding: Double,
        snapToGrid: Bool,
        gridSize: Double
    ) {
        guard !devices.isEmpty else { return }
        
        // Sort devices by nickname for consistent ordering
        let sortedDevices = devices.sorted { $0.nickname < $1.nickname }
        
        // Calculate total width needed
        let totalWidth = Double(sortedDevices.count) * cardWidth + 
                        Double(max(0, sortedDevices.count - 1)) * spacing
        
        // Center the row horizontally
        let startX = (canvasWidth - totalWidth) / 2 + cardWidth / 2
        
        // Stagger pattern: alternate vertical offsets to prevent straight-line overlaps
        // This ensures connection lines are visible even when devices are horizontally aligned
        let verticalOffset: Double = 60  // Offset amount for alternating devices
        
        // Position each device with staggered vertical offsets
        for (index, device) in sortedDevices.enumerated() {
            var posX = startX + Double(index) * (cardWidth + spacing)
            
            // Apply zigzag pattern: even indices at base Y, odd indices offset
            // Pattern: 0=base, 1=+offset, 2=base, 3=+offset, etc.
            let yOffset = (index % 2 == 0) ? 0 : verticalOffset
            var posY = y + yOffset
            
            // Snap to grid if enabled
            if snapToGrid && gridSize > 0 {
                posX = round(posX / gridSize) * gridSize
                posY = round(posY / gridSize) * gridSize
            }
            
            device.posX = posX
            device.posY = posY
        }
    }
    
    /// Snap a coordinate to the nearest grid intersection
    private func snapToGrid(_ value: Double, gridSize: Double) -> Double {
        guard gridSize > 0 else { return value }
        return round(value / gridSize) * gridSize
    }

    
    /// Calculate grid dimensions (columns, rows) for a given device count
    private func calculateGridDimensions(deviceCount: Int, maxColumns: Int) -> (columns: Int, rows: Int) {
        guard deviceCount > 0 else { return (0, 0) }
        let columns = min(maxColumns, deviceCount)
        let rows = (deviceCount + columns - 1) / columns  // Ceiling division
        return (columns, rows)
    }
    
    /// Position devices in a simple centered horizontal row
    private func positionDevicesInSimpleRow(devices: [DeviceInstance], centerX: Double, y: Double, cardWidth: Double, horizontalSpacing: Double) {
        guard !devices.isEmpty else { return }
        
        let sortedDevices = devices.sorted { $0.nickname < $1.nickname }
        let totalWidth = Double(sortedDevices.count) * cardWidth + 
                        Double(max(0, sortedDevices.count - 1)) * horizontalSpacing
        let startX = centerX - totalWidth / 2 + cardWidth / 2
        
        for (index, device) in sortedDevices.enumerated() {
            device.posX = startX + Double(index) * (cardWidth + horizontalSpacing)
            device.posY = y
        }
    }
    
    /// Position devices in a grid layout, grouped by category
    private func positionDevicesInGrid(devices: [DeviceInstance], centerX: Double, baseY: Double, cardWidth: Double, cardHeight: Double, horizontalSpacing: Double, verticalSpacing: Double, maxColumns: Int, anchorTop: Bool) {
        guard !devices.isEmpty else { return }
        
        // Group devices by category and sort
        var categoryGroups: [DeviceCategory: [DeviceInstance]] = [:]
        for device in devices {
            categoryGroups[device.category, default: []].append(device)
        }
        
        // Sort each category group by nickname
        for (category, devicesInCategory) in categoryGroups {
            categoryGroups[category] = devicesInCategory.sorted { $0.nickname < $1.nickname }
        }
        
        // Sort categories by count (largest first)
        let sortedCategories = categoryGroups.keys.sorted { cat1, cat2 in
            (categoryGroups[cat1]?.count ?? 0) > (categoryGroups[cat2]?.count ?? 0)
        }
        
        // Flatten into single ordered array
        var allDevicesOrdered: [DeviceInstance] = []
        for category in sortedCategories {
            if let devicesInCategory = categoryGroups[category] {
                allDevicesOrdered.append(contentsOf: devicesInCategory)
            }
        }
        
        // Calculate grid dimensions
        let columns = min(maxColumns, allDevicesOrdered.count)
        
        // Calculate total grid size
        let totalWidth = Double(columns) * cardWidth + Double(max(0, columns - 1)) * horizontalSpacing
        
        // Calculate starting position
        let startX = centerX - totalWidth / 2 + cardWidth / 2
        let startY: Double
        if anchorTop {
            // Start from baseY and grow downward
            startY = baseY + cardHeight / 2
        } else {
            // Start from baseY and grow downward
            startY = baseY + cardHeight / 2
        }
        
        // Position devices in grid
        for (index, device) in allDevicesOrdered.enumerated() {
            let col = index % columns
            let row = index / columns
            
            device.posX = startX + Double(col) * (cardWidth + horizontalSpacing)
            device.posY = startY + Double(row) * (cardHeight + verticalSpacing)
        }
    }

    private func autoArrangeDevices(in studio: Studio) {
        guard !(studio.devices?.isEmpty ?? true) else { return }

        // Save current positions for undo
        savedDevicePositions.removeAll()
        for device in studio.devices ?? [] {
            savedDevicePositions[device.id] = (x: device.posX, y: device.posY)
        }
        canUndoAutoArrange = true

        // Get connections from the connection store (not SwiftData)
        let links = connectionsStore.links(for: studio.id)
        
        // Build adjacency map: device -> devices it connects to
        var outgoing: [UUID: Set<UUID>] = [:]
        var incoming: [UUID: Set<UUID>] = [:]
        var deviceMap: [UUID: DeviceInstance] = [:]

        // Initialize with all devices
        for device in studio.devices ?? [] {
            outgoing[device.id] = []
            incoming[device.id] = []
            deviceMap[device.id] = device
        }

        // Populate from ConnectionStore links
        for link in links {
            outgoing[link.fromDeviceId, default: []].insert(link.toDeviceId)
            incoming[link.toDeviceId, default: []].insert(link.fromDeviceId)
        }
        
        // Identify unconnected devices (no incoming or outgoing connections)
        var unconnectedDevices: [DeviceInstance] = []
        var connectedDevices: [DeviceInstance] = []
        
        for device in studio.devices ?? [] {
            let hasConnections = !(outgoing[device.id]?.isEmpty ?? true) || !(incoming[device.id]?.isEmpty ?? true)
            if hasConnections {
                connectedDevices.append(device)
            } else {
                unconnectedDevices.append(device)
            }
        }
        
        // Sort unconnected devices by category and name for consistent ordering
        unconnectedDevices.sort { d1, d2 in
            if d1.category != d2.category {
                return d1.category.rawValue < d2.category.rawValue
            }
            return d1.nickname < d2.nickname
        }

        // SIGNAL FLOW LAYOUT
        // Audio signal flows from BOTTOM to TOP
        // Bottom: Source devices (preamps, instruments, mics)
        // Middle: Processing devices (compressors, effects)
        // Upper: Converters (ADAT expanders, audio interfaces)
        // Top: Computers
        
        var deviceLevels: [UUID: Int] = [:]
        
        // Calculate signal flow depth
        // Depth 0 = source devices (no inputs, only outputs)
        // Higher depth = further along signal chain toward destination
        func calculateSignalDepth(for deviceId: UUID, visited: Set<UUID> = []) -> Int {
            if let level = deviceLevels[deviceId] {
                return level
            }
            
            if visited.contains(deviceId) {
                return 0  // Circular reference, treat as source
            }
            
            var newVisited = visited
            newVisited.insert(deviceId)
            
            // Get all devices that this device connects TO (outputs)
            let outputs = outgoing[deviceId] ?? []
            
            if outputs.isEmpty {
                // No outputs - this is a destination device (like computer)
                // Check for special categories
                if let device = deviceMap[deviceId] {
                    if device.category == .computer {
                        return 100  // Top level
                    }
                    if device.category == .audioInterface || device.category == .adatExpander {
                        return 90  // Near top
                    }
                }
                // Other endpoints
                return 50
            }
            
            // Find the minimum depth of output devices and subtract 1
            // (source devices have lower depth than their destinations)
            var minOutputDepth = 100
            for outputId in outputs {
                let outputDepth = calculateSignalDepth(for: outputId, visited: newVisited)
                minOutputDepth = min(minOutputDepth, outputDepth)
            }
            
            return max(0, minOutputDepth - 1)
        }
        
        // Calculate depths for all devices
        for device in studio.devices ?? [] {
            if deviceLevels[device.id] == nil {
                deviceLevels[device.id] = calculateSignalDepth(for: device.id)
            }
        }

        // Invert depths so lower depth = higher on screen
        // Find max depth to invert
        let maxDepth = deviceLevels.values.max() ?? 0
        for (deviceId, depth) in deviceLevels {
            deviceLevels[deviceId] = maxDepth - depth
        }

        // Group devices by level
        var levelGroups: [Int: [DeviceInstance]] = [:]
        for device in studio.devices ?? [] {
            let level = deviceLevels[device.id] ?? 0
            levelGroups[level, default: []].append(device)
        }

        // Sort levels (0 = top of screen)
        let sortedLevels = levelGroups.keys.sorted()
        
        // Category priority for sorting within levels
        func categoryPriority(_ category: DeviceCategory) -> Int {
            switch category {
            case .computer: return 0
            case .audioInterface: return 1
            case .adatExpander: return 2
            case .digitalMixer, .mixer: return 3
            case .patchbay: return 4
            case .preamp: return 5
            case .compressor, .busCompressor: return 6
            case .channelStrip: return 7
            default: return 8
            }
        }
        
        // Within each level, sort devices to keep connected ones together
        for level in sortedLevels {
            guard var devices = levelGroups[level] else { continue }
            
            if devices.count <= 1 {
                continue  // No need to sort
            }
            
            // Sort by category first, then try to group connected devices
            devices.sort { d1, d2 in
                let p1 = categoryPriority(d1.category)
                let p2 = categoryPriority(d2.category)
                if p1 != p2 { return p1 < p2 }
                return d1.nickname < d2.nickname
            }
            
            // Reorder to keep connected devices adjacent
            var orderedDevices: [DeviceInstance] = []
            var remaining = Set(devices.map { $0.id })
            
            // Start with first device
            if let first = devices.first {
                orderedDevices.append(first)
                remaining.remove(first.id)
                
                // Greedily add devices with strongest connection to already-placed devices
                while !remaining.isEmpty {
                    var bestDevice: DeviceInstance?
                    var bestScore = -1
                    
                    for deviceId in remaining {
                        guard let device = deviceMap[deviceId] else { continue }
                        
                        var score = 0
                        let deviceInputs = incoming[deviceId] ?? []
                        let deviceOutputs = outgoing[deviceId] ?? []
                        
                        // Check connectivity to already-placed devices
                        for placedDevice in orderedDevices {
                            // Direct connection gives high score
                            if deviceInputs.contains(placedDevice.id) {
                                score += 10
                            }
                            if deviceOutputs.contains(placedDevice.id) {
                                score += 10
                            }
                            
                            // Shared connections give lower score
                            let placedInputs = incoming[placedDevice.id] ?? []
                            score += deviceInputs.intersection(placedInputs).count * 2
                        }
                        
                        if score > bestScore {
                            bestScore = score
                            bestDevice = device
                        }
                    }
                    
                    if let device = bestDevice, bestScore > 0 {
                        orderedDevices.append(device)
                        remaining.remove(device.id)
                    } else {
                        // No connections, add remaining in category/name order
                        let remainingDevices = devices.filter { remaining.contains($0.id) }
                        orderedDevices.append(contentsOf: remainingDevices)
                        break
                    }
                }
                
                levelGroups[level] = orderedDevices
            }
        }

        // Calculate layout to fit viewport
        let deviceCardHeight: Double = 96
        let deviceCardWidth: Double = 260
        let padding: Double = 50
        let horizontalSpacing: Double = 80
        let verticalSpacing: Double = 150

        // Use actual viewport size
        let targetWidth: Double = max(canvasSize.width - padding * 2, 600)
        let targetHeight: Double = max(canvasSize.height - padding * 2, 600)

        // Calculate required space
        let numLevels = sortedLevels.count
        let maxDevicesInLevel = levelGroups.values.map { $0.count }.max() ?? 1
        
        // For positioning, we need space for cards AND gaps between them
        // Device positions are CENTER points, so spacing = cardWidth + gap
        let requiredWidth = Double(maxDevicesInLevel) * deviceCardWidth + 
                           Double(max(0, maxDevicesInLevel - 1)) * horizontalSpacing
        let requiredHeight = Double(numLevels) * deviceCardHeight + 
                            Double(max(0, numLevels - 1)) * verticalSpacing

        // Scale to fit if needed, but maintain minimum spacing
        let widthScale = min(1.0, targetWidth / requiredWidth)
        let heightScale = min(1.0, targetHeight / requiredHeight)
        let layoutScale = min(widthScale, heightScale)
        
        // Don't scale cards down - keep them full size for readability
        // Only adjust spacing if needed
        let finalCardWidth = deviceCardWidth
        let finalCardHeight = deviceCardHeight
        
        // Calculate actual spacing based on available space
        let finalHorizontalSpacing: Double
        let finalVerticalSpacing: Double
        
        if layoutScale < 1.0 {
            // Need to compress - reduce spacing proportionally
            finalHorizontalSpacing = max(20, horizontalSpacing * layoutScale)
            finalVerticalSpacing = max(30, verticalSpacing * layoutScale)
        } else {
            // Plenty of space - use default spacing
            finalHorizontalSpacing = horizontalSpacing
            finalVerticalSpacing = verticalSpacing
        }

        // SMART COLUMN-BASED POSITIONING TO AVOID LINE CROSSINGS
        // Assign each device to a horizontal column based on its connections
        var deviceColumns: [UUID: Int] = [:]
        var columnsUsed: Set<Int> = []
        
        // Process levels from top to bottom, assigning columns
        for (_, level) in sortedLevels.enumerated() {
            guard let devicesInLevel = levelGroups[level] else { continue }
            
            for device in devicesInLevel {
                if deviceColumns[device.id] != nil {
                    continue // Already assigned
                }
                
                // Find preferred column based on connections to already-positioned devices
                var preferredColumn: Int? = nil
                var columnScores: [Int: Int] = [:]
                
                // Check outputs (devices this connects TO in higher levels)
                let deviceOutputs = outgoing[device.id] ?? []
                for outputId in deviceOutputs {
                    if let targetColumn = deviceColumns[outputId] {
                        columnScores[targetColumn, default: 0] += 10
                    }
                }
                
                // Check inputs (devices that connect FROM this in lower levels)
                let deviceInputs = incoming[device.id] ?? []
                for inputId in deviceInputs {
                    if let sourceColumn = deviceColumns[inputId] {
                        columnScores[sourceColumn, default: 0] += 5
                    }
                }
                
                // Use highest scoring column if available
                if let bestColumn = columnScores.max(by: { $0.value < $1.value })?.key {
                    preferredColumn = bestColumn
                }
                
                // If device connects to multiple levels (skip-level connections), offset it horizontally
                if deviceOutputs.count > 1 {
                    // Check if outputs are at different depth levels
                    let outputLevels = deviceOutputs.compactMap { deviceLevels[$0] }
                    let uniqueLevels = Set(outputLevels)
                    
                    if uniqueLevels.count > 1 {
                        // Device has skip-level connections - force horizontal offset
                        let connectedColumns = deviceOutputs.compactMap { deviceColumns[$0] }
                        if connectedColumns.count >= 2 {
                            let minCol = connectedColumns.min()!
                            let maxCol = connectedColumns.max()!
                            if minCol == maxCol {
                                // All targets in same column but at different levels - offset to the right
                                preferredColumn = minCol + 1
                            } else {
                                // Targets in different columns - position in middle
                                preferredColumn = (minCol + maxCol) / 2
                            }
                        } else if let firstCol = connectedColumns.first {
                            // Single target column at different level - offset to the right
                            preferredColumn = firstCol + 1
                        }
                    } else {
                        // Multiple connections but all at same level - stay in same column as targets
                        let connectedColumns = deviceOutputs.compactMap { deviceColumns[$0] }
                        if connectedColumns.count >= 2 {
                            let minCol = connectedColumns.min()!
                            let maxCol = connectedColumns.max()!
                            preferredColumn = (minCol + maxCol) / 2
                        }
                    }
                }
                
                // Find first available column at or near preferred position
                var finalColumn = 0
                if let preferred = preferredColumn {
                    // Try preferred column first
                    if !isColumnOccupied(preferred, level: level, levelGroups: levelGroups, deviceColumns: deviceColumns) {
                        finalColumn = preferred
                    } else {
                        // Try nearby columns
                        var found = false
                        for offset in 1...10 {
                            let leftCol = preferred - offset
                            let rightCol = preferred + offset
                            
                            if !isColumnOccupied(rightCol, level: level, levelGroups: levelGroups, deviceColumns: deviceColumns) {
                                finalColumn = rightCol
                                found = true
                                break
                            }
                            if leftCol >= 0 && !isColumnOccupied(leftCol, level: level, levelGroups: levelGroups, deviceColumns: deviceColumns) {
                                finalColumn = leftCol
                                found = true
                                break
                            }
                        }
                        if !found {
                            // Find next available column
                            finalColumn = (columnsUsed.max() ?? -1) + 1
                        }
                    }
                } else {
                    // No preference, use next available column
                    finalColumn = (columnsUsed.max() ?? -1) + 1
                }
                
                deviceColumns[device.id] = finalColumn
                columnsUsed.insert(finalColumn)
            }
        }
        
        // Helper function to check if column is occupied at this level
        func isColumnOccupied(_ column: Int, level: Int, levelGroups: [Int: [DeviceInstance]], deviceColumns: [UUID: Int]) -> Bool {
            guard let devicesAtLevel = levelGroups[level] else { return false }
            for device in devicesAtLevel {
                if deviceColumns[device.id] == column {
                    return true
                }
            }
            return false
        }
        
        // Now position devices based on their assigned columns
        let halfCardWidth = finalCardWidth / 2
        let halfCardHeight = finalCardHeight / 2
        
        // Find column range for connected devices
        let minColumn = deviceColumns.values.min() ?? 0
        let maxColumn = deviceColumns.values.max() ?? 0
        let columnRange = max(1, maxColumn - minColumn + 1)
        
        // Calculate total width needed for connected devices
        let totalWidth = Double(columnRange) * finalCardWidth + Double(max(0, columnRange - 1)) * finalHorizontalSpacing
        
        // IMPORTANT: Ensure startX is always visible (never negative or off-left edge)
        // Center if it fits, otherwise start from padding
        let effectiveViewportWidth = max(canvasSize.width, 1024)
        let centeredStartX = (effectiveViewportWidth - totalWidth) / 2
        let startX = max(padding + halfCardWidth, centeredStartX)
        
        // Position connected devices
        for (levelIndex, level) in sortedLevels.enumerated() {
            guard let devicesInLevel = levelGroups[level] else { continue }
            
            let y = padding + halfCardHeight + Double(levelIndex) * (finalCardHeight + finalVerticalSpacing)
            
            for device in devicesInLevel {
                if let column = deviceColumns[device.id] {
                    let columnOffset = column - minColumn
                    let x = startX + Double(columnOffset) * (finalCardWidth + finalHorizontalSpacing)
                    device.posX = x
                    device.posY = y
                }
            }
        }
        
        // Position unconnected devices in a vertical column on the right side
        if !unconnectedDevices.isEmpty {
            // Place unconnected devices to the right of the connected layout
            let rightEdgeOfConnected = startX + Double(columnRange - 1) * (finalCardWidth + finalHorizontalSpacing) + halfCardWidth
            let unconnectedX = rightEdgeOfConnected + finalHorizontalSpacing * 1.5 // Extra spacing to separate
            
            let unconnectedSpacing: Double = 40 // Closer vertical spacing for unconnected devices
            
            for (index, device) in unconnectedDevices.enumerated() {
                device.posX = unconnectedX
                device.posY = padding + halfCardHeight + Double(index) * (finalCardHeight + unconnectedSpacing)
            }
        }

        // Mark all modified devices and studio for iCloud sync
        for device in studio.devices ?? [] {
            device.markAsModified()
        }
        studio.markAsModified()
        
        // Save changes
        try? modelContext.save()
    }
    
    private func undoAutoArrange(in studio: Studio) {
        guard !savedDevicePositions.isEmpty else { return }
        
        // Restore saved positions
        for device in studio.devices ?? [] {
            if let savedPos = savedDevicePositions[device.id] {
                device.posX = savedPos.x
                device.posY = savedPos.y
            }
        }
        
        // Clear saved positions and hide undo button
        savedDevicePositions.removeAll()
        canUndoAutoArrange = false
    }

    private func syncConnectionsToSwiftData(studio: Studio) {
        // Clear existing SwiftData connections
        studio.connections?.removeAll()

        // Get all bundles for this studio from ConnectionsStore
        let bundles = connectionsStore.links(for: studio.id)
            .compactMap {
                connectionsStore.bundle(for: studio.id, linkId: $0.id)
            }

        // Build lookup maps to validate UUIDs
        var deviceIds = Set<UUID>()
        var portIds = Set<UUID>()
        var channelIds = Set<UUID>()

        for device in studio.devices ?? [] {
            deviceIds.insert(device.id)
            
            // Add regular ports
            for port in device.ports ?? [] {
                portIds.insert(port.id)
                for channel in port.channels ?? [] {
                    channelIds.insert(channel.id)
                }
            }
            
            // Add virtual computer interface ports/channels (stable UUIDs)
            let counts = device.computerInterfaceCounts
            for iface in counts.keys {
                let n = max(0, counts[iface] ?? 0)
                if n == 0 { continue }
                for i in 1...n {
                    let pid = stableUUID("computerPort|\(device.id.uuidString)|\(iface.rawValue)|\(i)")
                    let cid = stableUUID("computerCh|\(device.id.uuidString)|\(iface.rawValue)|\(i)")
                    portIds.insert(pid)
                    channelIds.insert(cid)
                }
            }
        }

        // Convert each ConnectionEdge to a SwiftData Connection
        var validCount = 0
        var invalidCount = 0

        for bundle in bundles {
            for edge in bundle.edges {
                // Validate all UUIDs exist in the studio
                let fromDeviceValid = deviceIds.contains(edge.from.deviceId)
                let toDeviceValid = deviceIds.contains(edge.to.deviceId)
                let fromPortValid = portIds.contains(edge.from.portId)
                let toPortValid = portIds.contains(edge.to.portId)
                let fromChannelValid = channelIds.contains(edge.from.channelId)
                let toChannelValid = channelIds.contains(edge.to.channelId)
                
                guard fromDeviceValid, toDeviceValid, fromPortValid, toPortValid, fromChannelValid, toChannelValid else {
                    #if DEBUG
                    print("⚠️ Skipping invalid connection from bundle: \(bundle.fromDeviceId) -> \(bundle.toDeviceId)")
                    if !fromDeviceValid { print("  - fromDevice ID not found: \(edge.from.deviceId)") }
                    if !toDeviceValid { print("  - toDevice ID not found: \(edge.to.deviceId)") }
                    if !fromPortValid { 
                        print("  - fromPort ID not found: \(edge.from.portId)")
                        print("    Available port IDs: \(portIds.prefix(5))")
                    }
                    if !toPortValid { 
                        print("  - toPort ID not found: \(edge.to.portId)")
                        print("    Available port IDs: \(portIds.prefix(5))")
                    }
                    if !fromChannelValid { 
                        print("  - fromChannel ID not found: \(edge.from.channelId)")
                        print("    Available channel IDs: \(channelIds.prefix(5))")
                    }
                    if !toChannelValid { 
                        print("  - toChannel ID not found: \(edge.to.channelId)")
                        print("    Available channel IDs: \(channelIds.prefix(5))")
                    }
                    print("  - Edge direction: \(edge.from.direction.rawValue) -> \(edge.to.direction.rawValue)")
                    #endif
                    invalidCount += 1
                    continue
                }

                let connection = Connection(
                    fromDeviceId: edge.from.deviceId,
                    fromPortId: edge.from.portId,
                    fromChannelId: edge.from.channelId,
                    toDeviceId: edge.to.deviceId,
                    toPortId: edge.to.portId,
                    toChannelId: edge.to.channelId,
                    cable: .other,  // ConnectionEdge doesn't store cable type
                    label: edge.fromName,  // Use the edge name as label
                    notes: nil
                )
                if studio.connections == nil {
                    studio.connections = []
                }
                studio.connections?.append(connection)
                validCount += 1
            }
        }

        #if DEBUG
        // Log summary
        print("✅ syncConnectionsToSwiftData complete:")
        print("   Bundles processed: \(bundles.count)")
        print("   Valid connections: \(validCount)")
        print("   Invalid connections: \(invalidCount)")
        if validCount > 0 {
            print("   ℹ️ Sample connection: \(studio.connections?.first?.label ?? "no label")")
        }
        #endif
        
        // Mark studio as modified to trigger iCloud sync
        if validCount > 0 {
            studio.markAsModified()
        }
        
        // Save to persist the connections
        try? modelContext.save()
    }

    private func importStudio(from url: URL) {
        do {
            // Read file
            let needsScoped = url.startAccessingSecurityScopedResource()
            defer {
                if needsScoped { url.stopAccessingSecurityScopedResource() }
            }

            let jsonData = try Data(contentsOf: url)

            // Decode
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let exportable = try decoder.decode(
                ExportableStudio.self,
                from: jsonData
            )

            // Check for name conflict
            if studios.contains(where: { $0.name == exportable.name }) {
                // Store the pending import and show conflict dialog
                pendingImportURL = url
                pendingImportStudio = exportable
                importConflictStudioName = exportable.name
                importNewName = exportable.name + " (imported)"
                isShowingImportNameConflict = true
                return
            }

            // No conflict, proceed with import
            completeImport(exportable: exportable)

        } catch {
            exportResultMessage = "Import failed: \(error.localizedDescription)"
            isShowingExportResult = true
        }
    }

    private func completeImport(
        exportable: ExportableStudio,
        customName: String? = nil
    ) {
        do {
            // Create new studio
            let studio = Studio(name: customName ?? exportable.name)

            // Import devices
            var deviceMap: [UUID: DeviceInstance] = [:]
            var portMap: [UUID: Port] = [:]
            var channelMap: [UUID: Channel] = [:]
            var computerPortIdMap: [UUID: UUID] = [:]  // old port UUID -> new port UUID
            var computerChannelIdMap: [UUID: UUID] = [:]  // old channel UUID -> new channel UUID

            for exportableDevice in exportable.devices {
                let device = DeviceInstance(
                    manufacturer: exportableDevice.manufacturer,
                    model: exportableDevice.model,
                    nickname: exportableDevice.nickname,
                    category: DeviceCategory(
                        rawValue: exportableDevice.categoryRaw
                    ) ?? .other,
                    serialNumber: exportableDevice.serialNumber,
                    location: exportableDevice.location,
                    audioInputsCount: exportableDevice.audioInputsCount,
                    audioOutputsCount: exportableDevice.audioOutputsCount,
                    adatInputPortsCount: exportableDevice.adatInputPortsCount,
                    adatOutputPortsCount: exportableDevice.adatOutputPortsCount,
                    madiInputPortsCount: exportableDevice.madiInputPortsCount,
                    madiOutputPortsCount: exportableDevice.madiOutputPortsCount,
                    ethernetPortsCount: exportableDevice.ethernetPortsCount,
                    sampleRate: SampleRate(
                        rawValue: exportableDevice.sampleRateRaw
                    ) ?? .hz48000,
                    digitalInputs: exportableDevice.digitalInputsRaw.compactMap
                    { DigitalFormat(rawValue: $0) },
                    digitalOutputs: exportableDevice.digitalOutputsRaw
                        .compactMap { DigitalFormat(rawValue: $0) },
                    computerInterfaces: exportableDevice.computerInterfacesRaw
                        .compactMap { ComputerInterface(rawValue: $0) },
                    posX: exportableDevice.posX,
                    posY: exportableDevice.posY,
                    scale: exportableDevice.scale,
                    zIndex: exportableDevice.zIndex
                )

                device.supportPageURLString =
                    exportableDevice.supportPageURLString
                device.downloadsPageURLString =
                    exportableDevice.downloadsPageURLString

                // Import ports
                for exportablePort in exportableDevice.ports {
                    let port = Port(
                        name: exportablePort.name,
                        type: PortType(rawValue: exportablePort.typeRaw)
                            ?? .usbAudio,
                        direction: PortDirection(
                            rawValue: exportablePort.directionRaw
                        ) ?? .bidirectional
                    )

                    // Import channels
                    for exportableChannel in exportablePort.channels {
                        let channel = Channel(
                            index: exportableChannel.index,
                            nameLong: exportableChannel.nameLong,
                            nameShort: exportableChannel.nameShort,
                            signal: SignalType(
                                rawValue: exportableChannel.signalRaw
                            ) ?? .audio,
                            grouping: ChannelGrouping(
                                rawValue: exportableChannel.groupingRaw
                            ) ?? .mono
                        )
                        if port.channels == nil {
                            port.channels = []
                        }
                        port.channels?.append(channel)
                        // Map old channel UUID to new channel
                        channelMap[exportableChannel.id] = channel
                    }

                    if device.ports == nil {
                        device.ports = []
                    }
                    device.ports?.append(port)
                    // Map old port UUID to new port
                    portMap[exportablePort.id] = port
                }

                // Import docs (manuals, etc.)
                for exportableDoc in exportableDevice.docs {
                    let docLink: DocLink
                    if let bookmarkData = exportableDoc.localBookmarkData {
                        docLink = DocLink(
                            title: exportableDoc.title,
                            kind: DocKind(rawValue: exportableDoc.kindRaw)
                                ?? .other,
                            bookmarkData: bookmarkData
                        )
                    } else if let urlString = exportableDoc.urlString,
                        let url = URL(string: urlString)
                    {
                        docLink = DocLink(
                            title: exportableDoc.title,
                            kind: DocKind(rawValue: exportableDoc.kindRaw)
                                ?? .other,
                            url: url
                        )
                    } else {
                        // Skip docs without valid URL or bookmark
                        continue
                    }
                    if device.docs == nil {
                        device.docs = []
                    }
                    device.docs?.append(docLink)
                }

                if studio.devices == nil {
                    studio.devices = []
                }
                studio.devices?.append(device)
                // Map old device UUID to new device
                deviceMap[exportableDevice.id] = device
                
                // Map virtual computer interface ports/channels (stable UUIDs based on device ID)
                // The exported connections reference the OLD device UUIDs in their stable UUID generation
                // We need to map those to the NEW device's computer interface UUIDs
                let oldDeviceId = exportableDevice.id
                let newDeviceId = device.id
                let computerInterfaces = exportableDevice.computerInterfacesRaw.compactMap { ComputerInterface(rawValue: $0) }
                let counts = device.computerInterfaceCounts
                
                for iface in computerInterfaces {
                    let count = counts[iface] ?? 0
                    if count == 0 { continue }
                    
                    for i in 1...count {
                        // Generate UUIDs using OLD device ID (as they were in the export)
                        let oldPortId = stableUUID("computerPort|\(oldDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                        let oldChannelId = stableUUID("computerCh|\(oldDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                        
                        // Generate UUIDs using NEW device ID (as they will be in the import)
                        let newPortId = stableUUID("computerPort|\(newDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                        let newChannelId = stableUUID("computerCh|\(newDeviceId.uuidString)|\(iface.rawValue)|\(i)")
                        
                        // Store the mapping
                        computerPortIdMap[oldPortId] = newPortId
                        computerChannelIdMap[oldChannelId] = newChannelId
                    }
                }
            }

            // Import connections with UUID remapping
            for exportableConnection in exportable.connections {
                // Look up the new device UUIDs
                guard let fromDevice = deviceMap[exportableConnection.fromDeviceId],
                      let toDevice = deviceMap[exportableConnection.toDeviceId] else {
                    continue
                }
                
                // Look up port and channel UUIDs (check regular ports first, then computer interface maps)
                let fromPortId: UUID
                let toPortId: UUID
                let fromChannelId: UUID
                let toChannelId: UUID
                
                // From port - check regular port first, then computer interface map
                if let port = portMap[exportableConnection.fromPortId] {
                    fromPortId = port.id
                } else if let mappedPortId = computerPortIdMap[exportableConnection.fromPortId] {
                    fromPortId = mappedPortId
                } else {
                    continue
                }
                
                // To port - check regular port first, then computer interface map
                if let port = portMap[exportableConnection.toPortId] {
                    toPortId = port.id
                } else if let mappedPortId = computerPortIdMap[exportableConnection.toPortId] {
                    toPortId = mappedPortId
                } else {
                    continue
                }
                
                // From channel - check regular channel first, then computer interface map
                if let channel = channelMap[exportableConnection.fromChannelId] {
                    fromChannelId = channel.id
                } else if let mappedChannelId = computerChannelIdMap[exportableConnection.fromChannelId] {
                    fromChannelId = mappedChannelId
                } else {
                    continue
                }
                
                // To channel - check regular channel first, then computer interface map
                if let channel = channelMap[exportableConnection.toChannelId] {
                    toChannelId = channel.id
                } else if let mappedChannelId = computerChannelIdMap[exportableConnection.toChannelId] {
                    toChannelId = mappedChannelId
                } else {
                    continue
                }

                let connection = Connection(
                    fromDeviceId: fromDevice.id,
                    fromPortId: fromPortId,
                    fromChannelId: fromChannelId,
                    toDeviceId: toDevice.id,
                    toPortId: toPortId,
                    toChannelId: toChannelId,
                    cable: CableType(rawValue: exportableConnection.cableRaw)
                        ?? .other,
                    label: exportableConnection.label,
                    notes: exportableConnection.notes
                )
                if studio.connections == nil {
                    studio.connections = []
                }
                studio.connections?.append(connection)
            }

            // Import canvas annotations
            studio.canvasDrawingData = exportable.canvasDrawingData
            
            // Save to model context
            modelContext.insert(studio)
            try modelContext.save()

            #if DEBUG
            // Log import statistics
            print("✅ Studio import complete:")
            print("   Devices imported: \(studio.devices?.count ?? 0)")
            print("   Connections imported: \(studio.connections?.count ?? 0)")
            #endif
            
            // Rebuild ConnectionsStore from the imported connections
            connectionsStore.rebuildFromConnections(studio: studio)
            
            #if DEBUG
            // Verify the rebuild worked
            let rebuiltBundles = connectionsStore.links(for: studio.id)
            print("   ConnectionsStore bundles after rebuild: \(rebuiltBundles.count)")
            for link in rebuiltBundles {
                if let bundle = connectionsStore.bundle(for: studio.id, linkId: link.id) {
                    print("   Bundle: \(bundle.fromDeviceId) -> \(bundle.toDeviceId), edges: \(bundle.edges.count)")
                }
            }
            #endif

            // Select the imported studio
            selectedStudioId = studio.id

            exportResultMessage =
                "Studio '\(studio.name)' imported successfully!"
            isShowingExportResult = true

        } catch {
            exportResultMessage = "Import failed: \(error.localizedDescription)"
            isShowingExportResult = true
        }
    }

    private func performImportWithName(_ name: String) {
        guard let exportable = pendingImportStudio else { return }

        // Clear pending state
        pendingImportURL = nil
        pendingImportStudio = nil
        isShowingImportNameConflict = false

        // Complete the import with the chosen name
        completeImport(exportable: exportable, customName: name)
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            exportResultMessage = "Studio exported successfully!"
            isShowingExportResult = true
        case .failure(let error):
            exportResultMessage = "Export failed: \(error.localizedDescription)"
            isShowingExportResult = true
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                importStudio(from: url)
            }
        case .failure(let error):
            exportResultMessage =
                "Import cancelled: \(error.localizedDescription)"
            isShowingExportResult = true
        }
    }

}

// MARK: - File-Level Helper Functions

private func ioSummary(from ports: [Port]?) -> String {
    func chCount(_ type: PortType, _ dir: PortDirection) -> Int {
        (ports ?? [])
            .filter { $0.type == type && $0.direction == dir }
            .reduce(0) { $0 + ($1.channels?.count ?? 0) }
    }

    let ain = chCount(.analogIn, .input)
    let aout = chCount(.analogOut, .output)
    let adatin = chCount(.adatIn, .input)
    let adatout = chCount(.adatOut, .output)
    let madiin = chCount(.madiIn, .input)
    let madiout = chCount(.madiOut, .output)
    let spdifin = chCount(.spdifIn, .input)
    let spdifout = chCount(.spdifOut, .output)

    var parts: [String] = []
    if ain > 0 || aout > 0 { parts.append("Analog \(ain) in / \(aout) out") }
    if adatin > 0 || adatout > 0 { parts.append("ADAT \(adatin)/\(adatout)") }
    if madiin > 0 || madiout > 0 { parts.append("MADI \(madiin)/\(madiout)") }
    if spdifin > 0 || spdifout > 0 {
        parts.append("S/PDIF \(spdifin)/\(spdifout)")
    }

    return parts.isEmpty ? "I/O: None" : parts.joined(separator: " • ")
}

// MARK: - Detail Header Subview

private struct DetailHeader: View {
    @Bindable var studio: Studio
    let onCreateDevice: () -> Void
    let onShowLegend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField(
                "Studio Name",
                text: .init(
                    get: { studio.name },
                    set: { newValue in
                        studio.name = newValue
                        studio.markAsModified()
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .frame(minWidth: 240)

            Spacer()

            Button(action: onCreateDevice) {
                Label("Add Device", systemImage: "plus.rectangle.on.rectangle")
            }

            Button(action: onShowLegend) {
                Label("Connection Legend", systemImage: "key.fill")
            }
        }
    }
}

// MARK: - Detail Canvas Subview

private struct DetailCanvas: View {
    let studio: Studio
    let background: Color
    let connectionsStore: ConnectionsStore
    let isExplosionEnabled: Bool
    let onSelectLink: (ConnectionLinkSummary) -> Void
    let onRequestDeleteLink: (ConnectionLinkSummary) -> Void
    let onArrowTap: ((ConnectionLinkSummary, ArrowDirection) -> Void)?
    let onExplodeDevice: (DeviceInstance) -> Void
    let onClearAutoArrangeUndo: () -> Void
    @Binding var isDrawingMode: Bool
    @Binding var isPlacingDeviceFromLocker: Bool
    let onPlaceDevice: ((CGPoint) -> Void)?
    @EnvironmentObject var selectionState: SelectionState
    @Binding var canvasSize: CGSize

    var body: some View {
        CanvasSurfaceView(
            studio: studio,
            background: background,
            iconForDevice: { (d: DeviceInstance) -> String in
                d.categorySymbolName
            },
            subtitleForDevice: { (d: DeviceInstance) -> String in
                ioSummary(from: d.ports)
            },
            connectionsStore: connectionsStore,
            onSelectLink: onSelectLink,
            onRequestDeleteLink: onRequestDeleteLink,
            onArrowTap: onArrowTap,
            onExplodeDevice: onExplodeDevice,
            isExplosionEnabled: isExplosionEnabled,
            onClearAutoArrangeUndo: onClearAutoArrangeUndo,
            isDrawingMode: $isDrawingMode,
            isPlacingDeviceFromLocker: $isPlacingDeviceFromLocker,
            onPlaceDevice: onPlaceDevice
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(CanvasSizePreferenceKey.self) { newSize in
            if newSize != .zero { canvasSize = newSize }
        }
    }
}

// MARK: - Studios List Subview

private struct StudiosList: View {
    let studios: [Studio]
    @Binding var selectedStudioId: UUID?
    let onDuplicate: (Studio) -> Void
    let onExport: (Studio) -> Void
    let onRequestDelete: (Studio) -> Void

    var body: some View {
        List(selection: $selectedStudioId) {
            // System section - shows Gear Locker
            if !systemStudios.isEmpty {
                Section("System") {
                    ForEach(systemStudios, id: \.id) { studio in
                        HStack {
                            Image(systemName: "archivebox.fill")
                                .foregroundColor(.accentColor)
                            Text(studio.name)
                                .fontWeight(.medium)
                        }
                        .tag(studio.id)
                    }
                }
            }
            
            Section("Studios/Sessions") {
                ForEach(userStudios, id: \.id) { studio in
                    Text(studio.name)
                        .tag(studio.id)
                        .contextMenu {
                            Button {
                                onDuplicate(studio)
                            } label: {
                                Label(
                                    "Duplicate Studio",
                                    systemImage: "plus.square.on.square"
                                )
                            }
                            Button {
                                onExport(studio)
                            } label: {
                                Label(
                                    "Export Studio",
                                    systemImage: "square.and.arrow.up"
                                )
                            }
                            Divider()
                            Button(role: .destructive) {
                                onRequestDelete(studio)
                            } label: {
                                Label("Delete Studio", systemImage: "trash")
                            }
                        }
                        #if os(iOS)
                            .swipeActions(
                                edge: .leading,
                                allowsFullSwipe: false
                            ) {
                                Button {
                                    onDuplicate(studio)
                                } label: {
                                    Label(
                                        "Duplicate",
                                        systemImage: "plus.square.on.square"
                                    )
                                }
                                .tint(.blue)

                                Button {
                                    onExport(studio)
                                } label: {
                                    Label(
                                        "Export",
                                        systemImage: "square.and.arrow.up"
                                    )
                                }
                                .tint(.green)
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: true
                            ) {
                                Button(role: .destructive) {
                                    onRequestDelete(studio)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        #endif
                }
                .onDelete { indexSet in
                    if let first = indexSet.first,
                        userStudios.indices.contains(first)
                    {
                        onRequestDelete(userStudios[first])
                    }
                }
            }
        }
    }
    
    // Filter system studios (Gear Locker)
    private var systemStudios: [Studio] {
        studios.filter { $0.isSystemStudio }
    }
    
    // Filter user studios (regular studios)
    private var userStudios: [Studio] {
        studios.filter { !$0.isSystemStudio }
    }
}

// MARK: - Canvas Size Preference

private struct CanvasSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Connection Handle Tip Preference

private struct ConnectionHandleTipPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGPoint] = [:]
    static func reduce(
        value: inout [UUID: CGPoint],
        nextValue: () -> [UUID: CGPoint]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Canvas

private struct CanvasSurfaceView: View {
    let studio: Studio
    let background: Color
    let iconForDevice: (DeviceInstance) -> String
    let subtitleForDevice: (DeviceInstance) -> String
    let connectionsStore: ConnectionsStore
    let onSelectLink: (ConnectionLinkSummary) -> Void
    let onRequestDeleteLink: (ConnectionLinkSummary) -> Void
    let onArrowTap: ((ConnectionLinkSummary, ArrowDirection) -> Void)?
    let onExplodeDevice: (DeviceInstance) -> Void
    let isExplosionEnabled: Bool
    let onClearAutoArrangeUndo: () -> Void
    @Binding var isDrawingMode: Bool
    @Binding var isPlacingDeviceFromLocker: Bool
    let onPlaceDevice: ((CGPoint) -> Void)?
    @EnvironmentObject var selection: SelectionState

    @State private var dragOrigin: (id: UUID, x: Double, y: Double)?
    @State private var activeConnectionDrag:
        (fromId: UUID, start: CGPoint, location: CGPoint)? = nil
    @State private var hoveredConnectionTargetId: UUID? = nil
    @State private var connectionHandleTips: [UUID: CGPoint] = [:]
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var lastKnownWidth: CGFloat = 0

    private var links: [ConnectionLinkSummary] {
        connectionsStore.links(for: studio.id)
    }

    var body: some View {
        GeometryReader { geo in
            let canvasBounds = calculateCanvasBounds(devices: studio.devices ?? [], viewport: geo.size)
            
            // Calculate lane offsets for connection routing
            let laneOffsets = ConnectionRouter.assignLaneOffsets(for: links)
            
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    // Main canvas content (everything except annotations)
                    ZStack {
                        Rectangle()
                            .fill(background)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(
                                        Color.primary.opacity(0.1),
                                        lineWidth: 2,
                                        antialiased: true
                                    )
                            )
                        
                        // Grid overlay (if enabled)
                        if studio.showGridOverlay {
                            gridOverlay(bounds: canvasBounds, gridSize: studio.gridSize)
                        }

                        // Connections - rendered without drawingGroup to prevent glitches on Mac
                        ForEach(links, id: \.id) { link in
                            linkRow(link, laneOffset: laneOffsets[link.id] ?? 0)
                        }

                        // Devices
                        ForEach(studio.devices ?? [], id: \.id) { d in
                            deviceCard(d, canvasSize: geo.size)
                        }

                        if let temp = activeConnectionDrag {
                            ConnectionLineView(
                                from: temp.start,
                                to: temp.location,
                                isSelected: true
                            )
                            .allowsHitTesting(false)
                            .zIndex(10)
                        }
                    }
                    .coordinateSpace(name: "canvasContent")
                    .frame(width: canvasBounds.width, height: canvasBounds.height)
                    .scaleEffect(canvasScale)
                    .frame(
                        width: canvasBounds.width * canvasScale,
                        height: canvasBounds.height * canvasScale
                    )
                    
                    // Canvas annotations layer (drawing overlay) - overlaid on top with scaled frame
                    CanvasAnnotationOverlay(studio: studio, isDrawingMode: $isDrawingMode, canvasScale: canvasScale, canvasBounds: canvasBounds)
                        .frame(width: canvasBounds.width * canvasScale, height: canvasBounds.height * canvasScale)
                        .allowsHitTesting(isDrawingMode)
                        .zIndex(5)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    if isPlacingDeviceFromLocker {
                        // In click-to-place mode, place the device at tap location
                        onPlaceDevice?(location)
                    } else {
                        // Normal mode: clear selection
                        selection.selection = nil
                    }
                }
                .preference(
                    key: CanvasSizePreferenceKey.self,
                    value: geo.size
                )
                .coordinateSpace(name: "canvas")
                .onPreferenceChange(ConnectionHandleTipPreferenceKey.self) {
                    connectionHandleTips = $0
                }
            }
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value
                        canvasScale = min(max(newScale, 0.5), 3.0)
                    }
                    .onEnded { value in
                        let newScale = lastScale * value
                        canvasScale = min(max(newScale, 0.5), 3.0)
                        lastScale = canvasScale
                    }
            )
            .onChange(of: geo.size) { oldSize, newSize in
                // Reset scale on significant geometry changes (like rotation)
                // to prevent distortion and hangs
                if abs(oldSize.width - newSize.width) > 100 || abs(oldSize.height - newSize.height) > 100 {
                    // Use a smooth animation to make the transition less jarring
                    withAnimation(.easeInOut(duration: 0.2)) {
                        canvasScale = 1.0
                        lastScale = 1.0
                    }
                    lastKnownWidth = newSize.width
                }
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ link: ConnectionLinkSummary, laneOffset: CGFloat) -> some View {
        ConnectionLineRow(
            link: link,
            studio: studio,
            connectionsStore: connectionsStore,
            handleTips: connectionHandleTips,
            laneOffset: laneOffset,
            isSelected: isSelectedConnection(linkId: link.id),
            onSelect: { onSelectLink(link) },
            onDelete: { onRequestDeleteLink(link) },
            onArrowTap: { direction in
                onArrowTap?(link, direction)
            }
        )
    }

    @ViewBuilder
    private func deviceCard(_ d: DeviceInstance, canvasSize: CGSize)
        -> some View
    {
        let tip = connectionHandleTips[d.id]
        let isTarget =
            (hoveredConnectionTargetId == d.id)
            && (activeConnectionDrag?.fromId != d.id)
        let icon = iconForDevice(d)
        let subtitle = subtitleForDevice(d)

        DeviceCardView(
            device: d,
            iconName: icon,
            subtitle: subtitle,
            studioId: studio.id,
            connectionsStore: connectionsStore,
            isSelected: isSelected(d.id),
            isConnectionTarget: isTarget,
            canvasSize: canvasSize,
            connectionHandleTip: tip,
            isExplosionEnabled: isExplosionEnabled,
            onExplode: { onExplodeDevice(d) },
            snapToGrid: studio.layoutMode == "snapToGrid",
            gridSize: studio.gridSize,
            dragOrigin: $dragOrigin,
            beginDragIfNeeded: { device in
                if dragOrigin?.id != device.id {
                    dragOrigin = (device.id, device.posX, device.posY)
                    // Clear undo when user manually moves a device
                    onClearAutoArrangeUndo()
                }
            },
            onBeginConnectionDrag: { device, startPoint in
                activeConnectionDrag = (
                    fromId: device.id, start: startPoint, location: startPoint
                )
                hoveredConnectionTargetId = nil
            },
            onUpdateConnectionDrag: { fromDevice, point in
                guard activeConnectionDrag != nil else { return }
                activeConnectionDrag!.location = point

                // Determine which device card (if any) the drag is currently over.
                let target = deviceId(at: point, excluding: fromDevice.id)
                hoveredConnectionTargetId = target
            },
            onEndConnectionDrag: {
                if let drag = activeConnectionDrag,
                    let targetId = hoveredConnectionTargetId
                {
                    connectionsStore.ensureLinkSummary(
                        studioId: studio.id,
                        fromId: drag.fromId,
                        toId: targetId
                    )
                }
                hoveredConnectionTargetId = nil
                activeConnectionDrag = nil
            },
            onEndDeviceDrag: {
                // Normalize coordinates immediately on main thread to prevent devices going off-canvas
                guard let devices = studio.devices, !devices.isEmpty else { return }
                
                let cardWidth: CGFloat = 260
                let cardHeight: CGFloat = 96
                let padding: CGFloat = 100
                
                var minX = CGFloat.infinity
                var minY = CGFloat.infinity
                
                for device in devices {
                    minX = min(minX, CGFloat(device.posX) - cardWidth / 2)
                    minY = min(minY, CGFloat(device.posY) - cardHeight / 2)
                }
                
                let targetMin = padding
                var shiftX: Double = 0
                var shiftY: Double = 0
                
                if minX < targetMin {
                    shiftX = Double(targetMin - minX)
                }
                if minY < targetMin {
                    shiftY = Double(targetMin - minY)
                }
                
                if shiftX != 0 || shiftY != 0 {
                    for device in devices {
                        device.posX += shiftX
                        device.posY += shiftY
                    }
                }
            }
        )
        .environmentObject(selection)
    }

    private func isSelected(_ id: UUID) -> Bool {
        if case .device(let did) = selection.selection { return did == id }
        return false
    }

    private func isSelectedConnection(linkId: UUID) -> Bool {
        if case .connection(let selectedId) = selection.selection {
            return selectedId == linkId
        }
        return false
    }

    // Helper to find which device (if any) is under the given point, excluding a device.
    private func deviceId(at point: CGPoint, excluding excludedId: UUID)
        -> UUID?
    {
        // Must match the card frame used by DeviceCardView.
        let cardSize = CGSize(width: 260, height: 96)
        let halfW = Double(cardSize.width / 2)
        let halfH = Double(cardSize.height / 2)

        for d in studio.devices ?? [] {
            if d.id == excludedId { continue }
            let rect = CGRect(
                x: d.posX - halfW,
                y: d.posY - halfH,
                width: Double(cardSize.width),
                height: Double(cardSize.height)
            )
            if rect.contains(point) { return d.id }
        }
        return nil
    }
    
    // Draw grid overlay
    @ViewBuilder
    private func gridOverlay(bounds: CGSize, gridSize: Double) -> some View {
        Canvas { context, size in
            let spacing = CGFloat(gridSize)
            
            // Use gray color that works in both light and dark mode
            let gridColor = Color.gray.opacity(0.5)
            
            // Draw vertical lines
            var x: CGFloat = 0
            while x <= bounds.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: bounds.height))
                }
                context.stroke(
                    path,
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
                x += spacing
            }
            
            // Draw horizontal lines
            var y: CGFloat = 0
            while y <= bounds.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: bounds.width, y: y))
                }
                context.stroke(
                    path,
                    with: .color(gridColor),
                    lineWidth: 0.5
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
    
    // Calculate canvas bounds - PURE FUNCTION, no state modification
    private func calculateCanvasBounds(devices: [DeviceInstance], viewport: CGSize) -> CGSize {
        guard !devices.isEmpty else {
            // For empty studios, use a fixed minimum size instead of viewport
            return CGSize(width: 2000, height: 2000)
        }
        
        let cardWidth: CGFloat = 260
        let cardHeight: CGFloat = 96
        let padding: CGFloat = 100
        let minCanvasSize: CGFloat = 2000  // Minimum canvas size for consistency
        
        // Always use 0,0 as the fixed top-left origin
        // Only expand canvas to the right and down based on device positions
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        
        for device in devices {
            let x = CGFloat(device.posX)
            let y = CGFloat(device.posY)
            
            // Find the rightmost and bottommost edges
            maxX = max(maxX, x + cardWidth / 2)
            maxY = max(maxY, y + cardHeight / 2)
        }
        
        // Add padding to the content bounds
        let contentWidth = maxX + padding
        let contentHeight = maxY + padding
        
        // Use content size or minimum, whichever is larger
        // This ensures consistent canvas size across all devices regardless of viewport
        let canvasWidth = max(contentWidth, minCanvasSize)
        let canvasHeight = max(contentHeight, minCanvasSize)
        
        return CGSize(width: canvasWidth, height: canvasHeight)
    }
    
    // Normalize device coordinates so they're all positive
    // Call this ONLY when drag ends
    private func normalizeDeviceCoordinates() {
        guard let devices = studio.devices, !devices.isEmpty else { return }
        
        let cardWidth: CGFloat = 260
        let cardHeight: CGFloat = 96
        let padding: CGFloat = 100
        
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        
        for device in devices {
            minX = min(minX, CGFloat(device.posX) - cardWidth / 2)
            minY = min(minY, CGFloat(device.posY) - cardHeight / 2)
        }
        
        let targetMin = padding
        var shiftX: Double = 0
        var shiftY: Double = 0
        
        if minX < targetMin {
            shiftX = Double(targetMin - minX)
        }
        if minY < targetMin {
            shiftY = Double(targetMin - minY)
        }
        
        if shiftX != 0 || shiftY != 0 {
            for device in devices {
                device.posX += shiftX
                device.posY += shiftY
            }
        }
    }
}
// MARK: - Device Card (extracted to reduce SwiftUI type-check complexity)

private struct DeviceCardView: View {
    let device: DeviceInstance
    let iconName: String
    let subtitle: String
    let studioId: UUID
    let connectionsStore: ConnectionsStore
    let isSelected: Bool
    let isConnectionTarget: Bool
    let canvasSize: CGSize
    let connectionHandleTip: CGPoint?
    let isExplosionEnabled: Bool
    let onExplode: () -> Void
    let snapToGrid: Bool
    let gridSize: Double

    @Binding var dragOrigin: (id: UUID, x: Double, y: Double)?
    let beginDragIfNeeded: (DeviceInstance) -> Void
    let onBeginConnectionDrag: (DeviceInstance, CGPoint) -> Void
    let onUpdateConnectionDrag: (DeviceInstance, CGPoint) -> Void
    let onEndConnectionDrag: () -> Void
    let onEndDeviceDrag: () -> Void

    @EnvironmentObject var selection: SelectionState
    @State private var isDraggingConnection: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var deviceColor: Color {
        let categoryColors = CategoryColorSettings.loadCategoryColors()
        return device.resolvedColor(categoryColors: categoryColors)
    }
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(deviceColor.opacity(0.1))
            )
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? Color.accentColor : deviceColor.opacity(0.6),
                    lineWidth: isSelected ? 3 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(deviceColor)
                Text(device.nickname)
                    .font(.headline)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .overlay(alignment: .topTrailing) {
            // Handle is visually anchored to the card corner.
            // We compute the drag line start point using device position directly.
            DeviceConnectionHandle(deviceId: device.id, color: deviceColor)
                .offset(x: 6, y: -6)
                .background(
                    GeometryReader { proxy in
                        // Get position in the ZStack's local coordinate space
                        let frame = proxy.frame(in: .named("canvasContent"))

                        // DeviceConnectionHandle is Triangle(16x14) + padding(8).
                        // Rotated to point right, the tip is at right edge, midY of the 16x14.
                        let tip = CGPoint(
                            x: frame.minX + 24,
                            y: frame.minY + 15
                        )

                        Color.clear
                            .preference(
                                key: ConnectionHandleTipPreferenceKey.self,
                                value: [device.id: tip]
                            )
                    }
                )
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 0,
                        coordinateSpace: .named("canvasContent")
                    )
                    .onChanged { value in
                        let start =
                            connectionHandleTip
                            ?? CGPoint(x: device.posX, y: device.posY)
                        if !isDraggingConnection {
                            isDraggingConnection = true
                            onBeginConnectionDrag(device, start)
                        }
                        onUpdateConnectionDrag(device, value.location)
                    }
                    .onEnded { _ in
                        isDraggingConnection = false
                        onEndConnectionDrag()
                    }
                )
        }
        .overlay {
            if isConnectionTarget {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                    .shadow(radius: 2)
                    .transition(.opacity)
            }
        }
        .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            item.loadObject(ofClass: NSString.self) { obj, _ in
                guard let ns = obj as? NSString else { return }
                let s = String(ns)
                guard let fromId = UUID(uuidString: s) else { return }
                if fromId == device.id { return }
                DispatchQueue.main.async {
                    connectionsStore.ensureLinkSummary(
                        studioId: studioId,
                        fromId: fromId,
                        toId: device.id
                    )
                }
            }
            return true
        }
        .position(x: device.posX, y: device.posY)
        .onTapGesture {
            selection.selection = .device(device.id)
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            guard isExplosionEnabled else { return }
            selection.selection = .device(device.id)
            onExplode()
        }
        // Update all call sites of buildPorts to include computerInterfaceCounts argument:
        .onDisappear {
            isDraggingConnection = false
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { v in
                    // Capture original pos for this drag
                    beginDragIfNeeded(device)

                    guard let origin = dragOrigin, origin.id == device.id else {
                        return
                    }

                    // Allow free movement across large virtual canvas
                    var newX = origin.x + Double(v.translation.width)
                    var newY = origin.y + Double(v.translation.height)
                    
                    // Apply snap-to-grid if enabled
                    if snapToGrid && gridSize > 0 {
                        newX = round(newX / gridSize) * gridSize
                        newY = round(newY / gridSize) * gridSize
                    }
                    
                    // Prevent negative coordinates to avoid canvas origin shifts
                    // This prevents the shaking/glitching on all edges
                    // Apply this AFTER snap-to-grid to ensure snapping doesn't violate bounds
                    let cardWidth: Double = 260
                    let cardHeight: Double = 96
                    let minPadding: Double = 100
                    
                    newX = max(newX, cardWidth / 2 + minPadding)
                    newY = max(newY, cardHeight / 2 + minPadding)

                    device.posX = newX
                    device.posY = newY
                }
                .onEnded { _ in
                    dragOrigin = nil
                    onEndDeviceDrag()
                }
        )
    }
}

// MARK: - Inspector

private struct InspectorPanel: View {
    let studio: Studio
    let onEditDevice: (DeviceInstance) -> Void
    let onRequestDeleteDevice: (DeviceInstance) -> Void
    let onCloneDevice: (DeviceInstance) -> Void
    let onRequestMoveDevice: (DeviceInstance) -> Void
    @EnvironmentObject var selection: SelectionState

    @State private var isImportingManual: Bool = false
    @State private var manualViewerItem: IdentifiableURL? = nil

    var body: some View {
        Group {
            switch selection.selection {
            case .none:
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Selection")
                        .font(.title3)
                    Text("Select a device.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()

            case .device(let id):
                if let d = studio.devices?.first(where: { $0.id == id }) {
                    Form {
                        Section("Device") {
                            LabeledContent("Nickname", value: d.nickname)

                            if !d.manufacturer.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent(
                                    "Manufacturer",
                                    value: d.manufacturer
                                )
                            }

                            if !d.model.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent("Product ID", value: d.model)
                            }

                            LabeledContent(
                                "Category",
                                value: d.category.rawValue
                            )

                            if !d.serialNumber.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent(
                                    "Serial Number",
                                    value: d.serialNumber
                                )
                            }

                            if !d.location.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent("Location", value: d.location)
                            }

                            if let url = d.supportPageURL {
                                HStack {
                                    Text("Support Page")
                                    Spacer()
                                    Text(url.absoluteString)
                                        .lineLimit(1)
                                        .foregroundStyle(.blue)
                                        .underline()
                                        .onTapGesture {
                                            let validURL = ensureURLScheme(url)
                                            #if os(macOS)
                                            NSWorkspace.shared.open(validURL)
                                            #else
                                            UIApplication.shared.open(validURL)
                                            #endif
                                        }
                                }
                            }

                            if let url = d.downloadsPageURL {
                                HStack {
                                    Text("Downloads Page")
                                    Spacer()
                                    Text(url.absoluteString)
                                        .lineLimit(1)
                                        .foregroundStyle(.blue)
                                        .underline()
                                        .onTapGesture {
                                            let validURL = ensureURLScheme(url)
                                            #if os(macOS)
                                            NSWorkspace.shared.open(validURL)
                                            #else
                                            UIApplication.shared.open(validURL)
                                            #endif
                                        }
                                }
                            }
                        }

                        Section("Ports") {
                            if d.ports?.isEmpty ?? true {
                                Text("No ports defined yet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach((d.ports ?? []).sorted(by: portSort), id: \.id) {
                                p in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(p.name)
                                        Spacer()
                                        Text("\(p.channels?.count ?? 0) ch")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)

                                    if !(p.channels?.isEmpty ?? true) {
                                        Text(
                                            (p.channels ?? [])
                                                .sorted(by: {
                                                    $0.index < $1.index
                                                })
                                                .map { ch in
                                                    ch.nameShort.isEmpty
                                                        ? "\(ch.index)"
                                                        : ch.nameShort
                                                }
                                                .joined(separator: ", ")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            let ifaceCounts = d.computerInterfaceCounts
                            if !ifaceCounts.isEmpty {
                                Divider().padding(.vertical, 4)
                                Text("Computer Interfaces")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ForEach(
                                    ifaceCounts.keys.sorted(by: {
                                        $0.rawValue < $1.rawValue
                                    }),
                                    id: \.self
                                ) { iface in
                                    Text(
                                        "\(iface.rawValue) ×\(ifaceCounts[iface] ?? 0)"
                                    )
                                }
                            }
                        }

                        Section("Manuals") {
                            Button {
                                isImportingManual = true
                            } label: {
                                Label(
                                    "Add Manual",
                                    systemImage: "doc.badge.plus"
                                )
                            }

                            if d.docs?.isEmpty ?? true {
                                Text("No manuals attached.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(d.docs ?? [], id: \.id) { doc in
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                            .foregroundStyle(.secondary)
                                        Text(doc.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(role: .destructive) {
                                            if let idx = d.docs?.firstIndex(
                                                where: { $0.id == doc.id })
                                            {
                                                d.docs?.remove(at: idx)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Try to migrate to iCloud if needed (one-time automatic migration)
                                        _ = iCloudDocumentManager.migrateDocLinkToiCloud(doc)
                                        
                                        do {
                                            let url = try ManualStorage.resolveDocLink(doc)
                                            manualViewerItem = IdentifiableURL(url: url, title: doc.title)
                                        } catch {
                                            print("❌ Failed to resolve manual: \(error)")
                                        }
                                    }
                                }
                            }
                        }
                        Section {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    Button {
                                        onEditDevice(d)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button(role: .destructive) {
                                        onRequestDeleteDevice(d)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        onCloneDevice(d)
                                    } label: {
                                        Label(
                                            "Clone",
                                            systemImage: "plus.square.on.square"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        onRequestMoveDevice(d)
                                    } label: {
                                        Label(
                                            "Move",
                                            systemImage:
                                                "arrowshape.turn.up.right"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                HStack(spacing: 12) {
                                    Button {
                                        d.isPinned.toggle()
                                        d.markAsModified()
                                        studio.markAsModified()
                                    } label: {
                                        Label(
                                            d.isPinned ? "Unpin" : "Pin",
                                            systemImage: d.isPinned ? "pin.slash" : "pin"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(d.isPinned ? .orange : .blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .formStyle(.grouped)
                    .scrollIndicators(.visible)
                    .fileImporter(
                        isPresented: $isImportingManual,
                        allowedContentTypes: [.pdf],
                        allowsMultipleSelection: false
                    ) { result in
                        guard case .success(let urls) = result,
                            let pickedURL = urls.first,
                            let device = studio.devices?.first(where: {
                                $0.id == id
                            })
                        else { return }

                        do {
                            let (storedURL, bookmarkData) =
                                try ManualStorage.copyPDFIntoAppSupport(
                                    pickedURL: pickedURL,
                                    deviceId: device.id
                                )

                            let doc: DocLink
                            // Check if this is an iCloud-stored document (path starts with /iCloud/)
                            if storedURL.path.hasPrefix("/iCloud/") {
                                let iCloudPath = String(storedURL.path.dropFirst("/iCloud/".count))
                                // Extract original filename (removes UUID prefix) and remove extension
                                let fullFilename = iCloudDocumentManager.extractOriginalFilename(from: iCloudPath)
                                let title = (fullFilename as NSString).deletingPathExtension
                                doc = DocLink(
                                    title: title,
                                    kind: .manual,
                                    iCloudPath: iCloudPath
                                )
                            } else {
                                // Legacy local storage
                                doc = DocLink(
                                    title: storedURL.lastPathComponent,
                                    kind: .manual,
                                    bookmarkData: bookmarkData
                                )
                            }
                            
                            if device.docs == nil {
                                device.docs = []
                            }
                            device.docs?.append(doc)
                            
                            // Mark device and studio as modified
                            device.markAsModified()
                            studio.markAsModified()
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                        .fullScreenCover(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.title
                            )
                        }
                    #else
                        .sheet(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.title
                            )
                        }
                    #endif
                } else {
                    Text("Device not found")
                        .padding()
                }

            case .connection(_):
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.rays")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Selection")
                        .font(.title3)
                    Text("Select a device.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }
}

#if os(iOS)
    private typealias PlatformImage = UIImage
#elseif os(macOS)
    private typealias PlatformImage = NSImage
#endif

private enum PlatformImageLoader {
    static func load(path: String) -> PlatformImage? {
        #if os(iOS)
            return UIImage(contentsOfFile: path)
        #else
            return NSImage(contentsOfFile: path)
        #endif
    }
}

private struct DiagramThumb: View {
    let image: PlatformImage

    @State private var isShowingZoom = false

    init(_ image: PlatformImage) {
        self.image = image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if os(iOS)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            #else
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            #endif
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            isShowingZoom = true
        }
        .sheet(isPresented: $isShowingZoom) {
            DiagramZoomView(image: image)
        }
    }
}

private struct DiagramZoomView: View {
    @Environment(\.dismiss) private var dismiss
    let image: PlatformImage

    @State private var scale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZoomableScrollView(scale: $scale) {
                Group {
                    #if os(iOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    #else
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    #endif
                }
                .padding()
            }
            .navigationTitle("Diagram")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reset") { scale = 1 }
                }
            }
        }
    }
}

private struct ZoomableScrollView<Content: View>: View {
    @Binding var scale: CGFloat
    let content: Content

    init(scale: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        self._scale = scale
        self.content = content()
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            content
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(0.5, min(6.0, value))
                        }
                )
        }
    }
}

// MARK: - Selection State and CanvasSelection

// MARK: - Connection Routing Engine

/// Groups connections and assigns lane offsets to prevent overlapping
struct ConnectionRouter {
    struct ConnectionGroup {
        let devicePair: Set<UUID>  // Unordered pair of device IDs
        var linkIds: [UUID]
        
        init(fromId: UUID, toId: UUID, linkId: UUID) {
            self.devicePair = Set([fromId, toId])
            self.linkIds = [linkId]
        }
        
        mutating func addLink(_ linkId: UUID) {
            linkIds.append(linkId)
        }
    }
    
    /// Group connections by device pairs and assign lane offsets
    static func assignLaneOffsets(
        for links: [ConnectionLinkSummary]
    ) -> [UUID: CGFloat] {
        var groups: [Set<UUID>: ConnectionGroup] = [:]
        
        // Group connections by device pairs
        for link in links {
            let pair = Set([link.fromDeviceId, link.toDeviceId])
            
            if var existingGroup = groups[pair] {
                existingGroup.addLink(link.id)
                groups[pair] = existingGroup
            } else {
                groups[pair] = ConnectionGroup(
                    fromId: link.fromDeviceId,
                    toId: link.toDeviceId,
                    linkId: link.id
                )
            }
        }
        
        // Assign lane offsets based on group size
        var laneOffsets: [UUID: CGFloat] = [:]
        
        for group in groups.values {
            let linkCount = group.linkIds.count
            
            if linkCount == 1 {
                // Single connection: no offset
                laneOffsets[group.linkIds[0]] = 0
            } else if linkCount == 2 {
                // Two connections: offset symmetrically
                laneOffsets[group.linkIds[0]] = -6
                laneOffsets[group.linkIds[1]] = 6
            } else if linkCount == 3 {
                // Three connections: center one at 0, others offset
                laneOffsets[group.linkIds[0]] = -8
                laneOffsets[group.linkIds[1]] = 0
                laneOffsets[group.linkIds[2]] = 8
            } else {
                // 4+ connections: distribute evenly
                let spacing: CGFloat = 6.0
                let totalWidth = spacing * CGFloat(linkCount - 1)
                
                for (index, linkId) in group.linkIds.enumerated() {
                    laneOffsets[linkId] = CGFloat(index) * spacing - totalWidth / 2
                }
            }
        }
        
        return laneOffsets
    }
}

// MARK: - Connection Line Row Helper

private struct ConnectionLineRow: View {
    let link: ConnectionLinkSummary
    let studio: Studio
    let connectionsStore: ConnectionsStore
    let handleTips: [UUID: CGPoint]
    let laneOffset: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onArrowTap: ((ArrowDirection) -> Void)?

    // Calculate connection point on device card border
    private func cardBorderPoint(
        from center: CGPoint,
        to otherCenter: CGPoint,
        cardSize: CGSize
    ) -> CGPoint {
        let halfWidth = cardSize.width / 2
        let halfHeight = cardSize.height / 2
        
        // No extension - we'll use straight segments to connect to the edge
        let extendAmount: CGFloat = 0.0
        
        // Define 8 anchor points: 4 corners + 4 edge midpoints
        // Each point is extended slightly beyond the edge
        let anchorPoints: [(point: CGPoint, direction: CGPoint)] = [
            // Corners (extended diagonally)
            (CGPoint(x: center.x - halfWidth, y: center.y - halfHeight), 
             CGPoint(x: -1, y: -1)),  // Top-left
            (CGPoint(x: center.x + halfWidth, y: center.y - halfHeight), 
             CGPoint(x: 1, y: -1)),   // Top-right
            (CGPoint(x: center.x - halfWidth, y: center.y + halfHeight), 
             CGPoint(x: -1, y: 1)),   // Bottom-left
            (CGPoint(x: center.x + halfWidth, y: center.y + halfHeight), 
             CGPoint(x: 1, y: 1)),    // Bottom-right
            // Edge midpoints (extended perpendicular to edge)
            (CGPoint(x: center.x, y: center.y - halfHeight), 
             CGPoint(x: 0, y: -1)),   // Top-center
            (CGPoint(x: center.x, y: center.y + halfHeight), 
             CGPoint(x: 0, y: 1)),    // Bottom-center
            (CGPoint(x: center.x - halfWidth, y: center.y), 
             CGPoint(x: -1, y: 0)),   // Left-center
            (CGPoint(x: center.x + halfWidth, y: center.y), 
             CGPoint(x: 1, y: 0))     // Right-center
        ]
        
        // Calculate direction to other device
        let dx = otherCenter.x - center.x
        let dy = otherCenter.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0 else { return center }
        
        // Find the anchor point that is most aligned with the direction to the other device
        var bestAnchor = anchorPoints[0].point
        var bestDirection = anchorPoints[0].direction
        var bestAlignment: CGFloat = -1.0
        
        for (anchor, direction) in anchorPoints {
            let anchorDx = anchor.x - center.x
            let anchorDy = anchor.y - center.y
            let anchorDist = sqrt(anchorDx * anchorDx + anchorDy * anchorDy)
            
            guard anchorDist > 0 else { continue }
            
            // Calculate dot product (alignment) between anchor direction and target direction
            let alignment = (anchorDx * dx + anchorDy * dy) / (anchorDist * distance)
            
            if alignment > bestAlignment {
                bestAlignment = alignment
                bestAnchor = anchor
                bestDirection = direction
            }
        }
        
        // Extend the anchor point outward along its direction
        let dirLength = sqrt(bestDirection.x * bestDirection.x + bestDirection.y * bestDirection.y)
        let extendedPoint = CGPoint(
            x: bestAnchor.x + (bestDirection.x / dirLength) * extendAmount,
            y: bestAnchor.y + (bestDirection.y / dirLength) * extendAmount
        )
        
        return extendedPoint
    }

    // Analyze connections to determine connection types and total channel count
    private var connectionMetadata:
        (types: [ConnectionVisualType], channelCount: Int, hasForward: Bool, hasReverse: Bool)
    {
        // Get the connection bundle from ConnectionsStore (UserDefaults-based storage)
        guard
            let bundle = connectionsStore.bundle(
                for: studio.id,
                linkId: link.id
            )
        else {
            // print("⚠️ No bundle found for link \(link.id)")
            return ([.unknown], 1, false, false)
        }

        // print("🔍 Analyzing bundle with \(bundle.edges.count) edges")

        guard !bundle.edges.isEmpty else {
            // print("⚠️ Bundle has no edges")
            return ([.unknown], 1, false, false)
        }

        // Count connections by type and track directionality
        var typeCounts: [ConnectionVisualType: Int] = [:]
        var portsNotFound = 0
        var hasForward = false  // link.fromDeviceId -> link.toDeviceId
        var hasReverse = false  // link.toDeviceId -> link.fromDeviceId

        for edge in bundle.edges {
            // Check direction of this edge
            if edge.from.deviceId == link.fromDeviceId {
                hasForward = true
            } else {
                hasReverse = true
            }
            
            // Look up the port type from the source device using the edge's endpoint
            if let device = studio.devices?.first(where: {
                $0.id == edge.from.deviceId
            }) {
                // First try to find in regular ports
                if let port = device.ports?.first(where: {
                    $0.id == edge.from.portId
                }) {
                    let visualType = ConnectionVisualType.from(
                        portType: port.type
                    )
                    // print(
                    //     "  📍 Port '\(port.name)' type: \(port.type.rawValue) -> visual: \(visualType)"
                    // )
                    typeCounts[visualType, default: 0] += 1
                } else if !device.computerInterfaceCounts.isEmpty {
                    // Port not found in device.ports - likely a computer interface virtual port
                    // All computer interfaces (USB, Thunderbolt, Ethernet) use orange color
                    // print(
                    //     "  📍 Computer interface port (virtual) -> visual: computer"
                    // )
                    typeCounts[.computer, default: 0] += 1
                } else {
                    // print(
                    //     "  ⚠️ Could not find port for edge: deviceId=\(edge.from.deviceId), portId=\(edge.from.portId)"
                    // )
                    portsNotFound += 1
                }
            } else {
                // print("  ⚠️ Could not find device: \(edge.from.deviceId)")
                portsNotFound += 1
            }
        }

        // Return all unique types sorted by count (most common first)
        let sortedTypes = typeCounts.sorted { $0.value > $1.value }.map {
            $0.key
        }
        let types = sortedTypes.isEmpty ? [.unknown] : sortedTypes
        let totalChannels = bundle.edges.count

        // print(
        //     "  Result: \(types.count) types, \(portsNotFound) ports not found"
        // )

        return (types, totalChannels, hasForward, hasReverse)
    }

    var body: some View {
        Group {
            if let fromDevice = studio.devices?.first(where: {
                $0.id == link.fromDeviceId
            }),
                let toDevice = studio.devices?.first(where: {
                    $0.id == link.toDeviceId
                })
            {
                // Device centers - draw lines to center, device cards will occlude the inner portion
                let fromCenter = CGPoint(x: fromDevice.posX, y: fromDevice.posY)
                let toCenter = CGPoint(x: toDevice.posX, y: toDevice.posY)

                let metadata = connectionMetadata

                ConnectionLineView(
                    from: fromCenter,
                    to: toCenter,
                    laneOffset: laneOffset,
                    isSelected: isSelected,
                    connectionTypes: metadata.types,
                    channelCount: metadata.channelCount,
                    hasForwardConnection: metadata.hasForward,
                    hasReverseConnection: metadata.hasReverse,
                    onArrowTap: onArrowTap
                )
                // IMPORTANT: give the line a full-size layout box so macOS can attach a context menu
                // while hit-testing still remains constrained to the stroked curve via ConnectionLineView.contentShape.
                // On iOS, skip this frame modifier to prevent visual glitch during long press gesture.
                #if os(macOS)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                #endif
                // Double-click (macOS) / double-tap (iOS) to delete
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded { onDelete() }
                )
                // Single click/tap selects
                .onTapGesture {
                    onSelect()
                }
                // Long-press on iPad/iPhone to delete (we use the same confirm flow via onDelete())
                .onLongPressGesture(minimumDuration: 0.5) {
                    onDelete()
                }
                // Right-click on macOS (context menu causes visual glitch with long press on iOS)
                #if os(macOS)
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Connection", systemImage: "trash")
                    }
                }
                #endif
            }
        }
    }
}

// MARK: - Connection Line View

enum ConnectionVisualType {
    case analog  // Blue
    case digital  // Green
    case midi  // Purple
    case computer  // Orange
    case unknown  // Gray

    var color: Color {
        switch self {
        case .analog: return .blue
        case .digital: return .green
        case .midi: return .purple
        case .computer: return .orange
        case .unknown: return .secondary
        }
    }

    static func from(portType: PortType) -> ConnectionVisualType {
        switch portType {
        case .analogIn, .analogOut, .headphoneOut:
            return .analog
        case .adatIn, .adatOut, .madiIn, .madiOut, .spdifIn, .spdifOut, .aesIn,
            .aesOut, .wordClockIn, .wordClockOut:
            return .digital
        case .midiIn, .midiOut:
            return .midi
        case .usbAudio, .thunderboltAudio, .ethernet, .computerHost:
            return .computer
        }
    }
}

enum ArrowDirection {
    case forward  // from -> to (left to right on canvas)
    case reverse  // to -> from (right to left on canvas)
}

private struct ConnectionLineView: View {
    let from: CGPoint
    let to: CGPoint
    var laneOffset: CGFloat = 0
    let isSelected: Bool
    var connectionTypes: [ConnectionVisualType] = [.unknown]
    var channelCount: Int = 1
    var hasForwardConnection: Bool = false
    var hasReverseConnection: Bool = false
    var onArrowTap: ((ArrowDirection) -> Void)?

    private var path: Path {
        // If there's a lane offset, use the offset path instead
        if laneOffset != 0 {
            return offsetPath(by: laneOffset)
        }
        
        // Standard path (no offset)
        var p = Path()
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Length of straight segments at each end
        let straightLength: CGFloat = 15.0
        
        if distance < straightLength * 2 {
            // Too short for curved connection, just draw straight line
            p.move(to: from)
            p.addLine(to: to)
        } else {
            // Start with a straight segment perpendicular from the edge
            let normalizedDx = dx / distance
            let normalizedDy = dy / distance
            
            let fromStraightEnd = CGPoint(
                x: from.x + normalizedDx * straightLength,
                y: from.y + normalizedDy * straightLength
            )
            
            let toStraightStart = CGPoint(
                x: to.x - normalizedDx * straightLength,
                y: to.y - normalizedDy * straightLength
            )
            
            // Draw: straight segment -> curve -> straight segment
            p.move(to: from)
            p.addLine(to: fromStraightEnd)
            
            // Bezier curve in the middle
            let curveDx = toStraightStart.x - fromStraightEnd.x
            let curveDy = toStraightStart.y - fromStraightEnd.y
            let c1 = CGPoint(
                x: fromStraightEnd.x + curveDx * 0.35,
                y: fromStraightEnd.y + curveDy * 0.35
            )
            let c2 = CGPoint(
                x: fromStraightEnd.x + curveDx * 0.65,
                y: fromStraightEnd.y + curveDy * 0.65
            )
            
            p.addCurve(to: toStraightStart, control1: c1, control2: c2)
            p.addLine(to: to)
        }
        
        return p
    }

    private var lineWidth: CGFloat {
        // Base width 2, increase for multi-channel connections
        let baseWidth: CGFloat = 2.0
        if channelCount > 8 {
            return baseWidth + 3.0  // Thick for 16+ channels
        } else if channelCount > 2 {
            return baseWidth + 1.5  // Medium for 3-8 channels
        } else {
            return baseWidth  // Thin for 1-2 channels
        }
    }

    private var lineColor: Color {
        // Use first (dominant) type color
        let baseColor = connectionTypes.first?.color ?? Color.secondary
        
        // When selected, use full opacity instead of changing color
        return isSelected ? baseColor : baseColor.opacity(0.7)
    }

    // Calculate perpendicular offset for parallel lines
    private func offsetForLine(at index: Int, total: Int) -> CGFloat {
        let spacing: CGFloat = 6.0  // Space between parallel lines
        if total == 1 { return 0 }
        if total == 2 {
            return index == 0 ? -spacing / 2 : spacing / 2
        }
        // For 3+ lines, distribute evenly
        let totalWidth = spacing * CGFloat(total - 1)
        return CGFloat(index) * spacing - totalWidth / 2
    }
    
    // Create path offset perpendicular to the line
    private func offsetPath(by offset: CGFloat) -> Path {
        guard offset != 0 else { return path }
        
        var p = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Calculate perpendicular offset direction
        let perpX = -dy / distance * offset
        let perpY = dx / distance * offset
        
        let offsetFrom = CGPoint(x: from.x + perpX, y: from.y + perpY)
        let offsetTo = CGPoint(x: to.x + perpX, y: to.y + perpY)
        
        let straightLength: CGFloat = 15.0
        
        if distance < straightLength * 2 {
            p.move(to: offsetFrom)
            p.addLine(to: offsetTo)
        } else {
            let normalizedDx = dx / distance
            let normalizedDy = dy / distance
            
            let fromStraightEnd = CGPoint(
                x: offsetFrom.x + normalizedDx * straightLength,
                y: offsetFrom.y + normalizedDy * straightLength
            )
            
            let toStraightStart = CGPoint(
                x: offsetTo.x - normalizedDx * straightLength,
                y: offsetTo.y - normalizedDy * straightLength
            )
            
            p.move(to: offsetFrom)
            p.addLine(to: fromStraightEnd)
            
            let curveDx = toStraightStart.x - fromStraightEnd.x
            let curveDy = toStraightStart.y - fromStraightEnd.y
            let c1 = CGPoint(
                x: fromStraightEnd.x + curveDx * 0.35,
                y: fromStraightEnd.y + curveDy * 0.35
            )
            let c2 = CGPoint(
                x: fromStraightEnd.x + curveDx * 0.65,
                y: fromStraightEnd.y + curveDy * 0.65
            )
            
            p.addCurve(to: toStraightStart, control1: c1, control2: c2)
            p.addLine(to: offsetTo)
        }
        
        return p
    }
    
    // Create arrowheads offset perpendicular to the line
    private func offsetArrowheads(by offset: CGFloat, isBidirectional: Bool) -> [(path: Path, isActive: Bool, direction: ArrowDirection)] {
        guard offset != 0 else { return arrowheads() }
        
        var result: [(path: Path, isActive: Bool, direction: ArrowDirection)] = []
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        
        // Calculate perpendicular offset
        let perpX = -dy / distance * offset
        let perpY = dx / distance * offset
        
        let offsetFrom = CGPoint(x: from.x + perpX, y: from.y + perpY)
        let normalizedDx = dx / distance
        let normalizedDy = dy / distance
        
        if !isBidirectional {
            // Forward arrow at 35%
            let forwardPoint = CGPoint(
                x: offsetFrom.x + normalizedDx * distance * 0.35,
                y: offsetFrom.y + normalizedDy * distance * 0.35
            )
            let forwardAngle = atan2(dy, dx)
            var forwardPath = Path()
            forwardPath.addPath(makeArrow(at: forwardPoint, angle: forwardAngle))
            result.append((forwardPath, hasForwardConnection, .forward))
            
            // Reverse arrow at 65%
            let reversePoint = CGPoint(
                x: offsetFrom.x + normalizedDx * distance * 0.65,
                y: offsetFrom.y + normalizedDy * distance * 0.65
            )
            let reverseAngle = atan2(dy, dx) + .pi
            var reversePath = Path()
            reversePath.addPath(makeArrow(at: reversePoint, angle: reverseAngle))
            result.append((reversePath, hasReverseConnection, .reverse))
        } else {
            // Computer connections
            let point1 = CGPoint(
                x: offsetFrom.x + normalizedDx * distance * 0.35,
                y: offsetFrom.y + normalizedDy * distance * 0.35
            )
            let angle1 = atan2(dy, dx)
            var path1 = Path()
            path1.addPath(makeArrow(at: point1, angle: angle1))
            result.append((path1, true, .forward))
            
            let point2 = CGPoint(
                x: offsetFrom.x + normalizedDx * distance * 0.65,
                y: offsetFrom.y + normalizedDy * distance * 0.65
            )
            let angle2 = atan2(dy, dx) + .pi
            var path2 = Path()
            path2.addPath(makeArrow(at: point2, angle: angle2))
            result.append((path2, true, .reverse))
        }
        
        return result
    }

    // Check if connection type is bidirectional (USB, Thunderbolt, Ethernet)
    private var isBidirectional: Bool {
        connectionTypes.contains(.computer)
    }

    // Calculate point on bezier curve at t (0 to 1)
    private func pointOnCurve(t: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let c1 = CGPoint(x: from.x + dx * 0.25, y: from.y + dy * 0.1)
        let c2 = CGPoint(x: from.x + dx * 0.75, y: from.y + dy * 0.9)

        // Cubic bezier formula
        let mt = 1 - t
        let mt2 = mt * mt
        let mt3 = mt2 * mt
        let t2 = t * t
        let t3 = t2 * t

        return CGPoint(
            x: mt3 * from.x + 3 * mt2 * t * c1.x + 3 * mt * t2 * c2.x + t3
                * to.x,
            y: mt3 * from.y + 3 * mt2 * t * c1.y + 3 * mt * t2 * c2.y + t3
                * to.y
        )
    }

    // Calculate tangent direction at t
    private func tangentAngle(t: CGFloat) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let c1 = CGPoint(x: from.x + dx * 0.25, y: from.y + dy * 0.1)
        let c2 = CGPoint(x: from.x + dx * 0.75, y: from.y + dy * 0.9)

        let mt = 1 - t
        let mt2 = mt * mt
        let t2 = t * t

        // Derivative of cubic bezier
        let tangentX =
            3 * mt2 * (c1.x - from.x) + 6 * mt * t * (c2.x - c1.x) + 3 * t2
            * (to.x - c2.x)
        let tangentY =
            3 * mt2 * (c1.y - from.y) + 6 * mt * t * (c2.y - c1.y) + 3 * t2
            * (to.y - c2.y)

        return atan2(tangentY, tangentX)
    }

    // Create arrowhead at specified position and angle
    private func makeArrow(at point: CGPoint, angle: CGFloat) -> Path {
        // Make arrows larger and more visible (increased from lineWidth * 3 to * 5)
        let arrowLength: CGFloat = lineWidth * 5

        var arrow = Path()
        arrow.move(to: point)

        // Left wing
        let leftAngle = angle + .pi * 0.75
        arrow.addLine(
            to: CGPoint(
                x: point.x + cos(leftAngle) * arrowLength,
                y: point.y + sin(leftAngle) * arrowLength
            )
        )

        arrow.move(to: point)

        // Right wing
        let rightAngle = angle - .pi * 0.75
        arrow.addLine(
            to: CGPoint(
                x: point.x + cos(rightAngle) * arrowLength,
                y: point.y + sin(rightAngle) * arrowLength
            )
        )

        return arrow
    }

    // Generate arrowheads with dual-directional support
    private func arrowheads() -> [(path: Path, isActive: Bool, direction: ArrowDirection)] {
        var result: [(path: Path, isActive: Bool, direction: ArrowDirection)] = []
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        let normalizedDx = dx / distance
        let normalizedDy = dy / distance

        // Always render both arrows for non-computer connections
        // Computer connections continue to use the old bidirectional rendering
        if !isBidirectional {
            // Forward arrow (from -> to) at 35% along the line
            let forwardPoint = CGPoint(
                x: from.x + normalizedDx * distance * 0.35,
                y: from.y + normalizedDy * distance * 0.35
            )
            let forwardAngle = atan2(dy, dx)
            var forwardPath = Path()
            forwardPath.addPath(makeArrow(at: forwardPoint, angle: forwardAngle))
            result.append((forwardPath, hasForwardConnection, .forward))
            
            // Reverse arrow (to -> from) at 65% along the line
            let reversePoint = CGPoint(
                x: from.x + normalizedDx * distance * 0.65,
                y: from.y + normalizedDy * distance * 0.65
            )
            let reverseAngle = atan2(dy, dx) + .pi
            var reversePath = Path()
            reversePath.addPath(makeArrow(at: reversePoint, angle: reverseAngle))
            result.append((reversePath, hasReverseConnection, .reverse))
        } else {
            // Computer connections: use existing bidirectional rendering
            let point1 = CGPoint(
                x: from.x + normalizedDx * distance * 0.35,
                y: from.y + normalizedDy * distance * 0.35
            )
            let angle1 = atan2(dy, dx)
            var path1 = Path()
            path1.addPath(makeArrow(at: point1, angle: angle1))
            result.append((path1, true, .forward))
            
            let point2 = CGPoint(
                x: from.x + normalizedDx * distance * 0.65,
                y: from.y + normalizedDy * distance * 0.65
            )
            let angle2 = atan2(dy, dx) + .pi
            var path2 = Path()
            path2.addPath(makeArrow(at: point2, angle: angle2))
            result.append((path2, true, .reverse))
        }

        return result
    }

    var body: some View {
        ZStack {
            // Wide invisible stroke for easy hit-testing
            path
                .stroke(
                    Color.clear,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )

            // Draw separate parallel lines for multiple connection types
            if connectionTypes.count > 1 {
                ForEach(Array(connectionTypes.enumerated()), id: \.offset) { index, type in
                    let offset = offsetForLine(at: index, total: connectionTypes.count)
                    offsetPath(by: offset)
                        .stroke(
                            type.color.opacity(isSelected ? 1.0 : 0.7),
                            style: StrokeStyle(
                                lineWidth: isSelected ? lineWidth + 1 : lineWidth,
                                lineCap: .round
                            )
                        )
                    
                    // Draw arrowheads with individual coloring and hit-testing
                    ForEach(Array(offsetArrowheads(by: offset, isBidirectional: type == .computer).enumerated()), id: \.offset) { arrowIndex, arrowInfo in
                        arrowInfo.path
                            .stroke(
                                arrowInfo.isActive 
                                    ? type.color.opacity(isSelected ? 1.0 : 0.7)
                                    : Color.secondary.opacity(0.5),
                                style: StrokeStyle(
                                    lineWidth: arrowInfo.isActive ? 2.0 : 1.5,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                            .contentShape(arrowInfo.path.strokedPath(StrokeStyle(lineWidth: 20)))
                            .onTapGesture {
                                onArrowTap?(arrowInfo.direction)
                            }
                    }
                }
            } else {
                // Single connection type - draw one line
                path
                    .stroke(
                        lineColor,
                        style: StrokeStyle(
                            lineWidth: isSelected ? lineWidth + 1 : lineWidth,
                            lineCap: .round
                        )
                    )
                
                // Draw arrowheads with individual coloring and hit-testing
                ForEach(Array(arrowheads().enumerated()), id: \.offset) { index, arrowInfo in
                    arrowInfo.path
                        .stroke(
                            arrowInfo.isActive 
                                ? lineColor
                                : Color.secondary.opacity(0.5),
                            style: StrokeStyle(
                                lineWidth: arrowInfo.isActive ? 2.0 : 1.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .contentShape(arrowInfo.path.strokedPath(StrokeStyle(lineWidth: 20)))
                        .onTapGesture {
                            onArrowTap?(arrowInfo.direction)
                        }
                }
            }
        }
        // IMPORTANT: hit-test only the stroked curve, not the whole rectangular area.
        .contentShape(
            path.strokedPath(StrokeStyle(lineWidth: 18, lineCap: .round))
        )
    }
}
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct DeviceConnectionHandle: View {
    let deviceId: UUID
    var color: Color = .accentColor

    var body: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color.opacity(0.8))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
            )
            .contentShape(Rectangle())
            .accessibilityLabel("Drag to connect")
    }
}
// MARK: - DeviceInstance UI Helpers

extension DeviceInstance {
    fileprivate var categorySymbolName: String {
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
        case .midiInterface: return "cable.connector.horizontal"
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

// MARK: - Device Editor Sheet

private struct DeviceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String

    @Binding var nickname: String
    @Binding var manufacturer: String
    @Binding var productId: String
    @Binding var category: DeviceCategory
    @Binding var serialNumber: String
    @Binding var location: String
    @Binding var customColor: Color?

    @Binding var supportPageURL: String
    @Binding var downloadsPageURL: String

    @Binding var audioInputs: Int
    @Binding var audioOutputs: Int
    @Binding var adatInputPorts: Int
    @Binding var adatOutputPorts: Int
    @Binding var madiInputPorts: Int
    @Binding var madiOutputPorts: Int
    @Binding var midiInputPorts: Int
    @Binding var midiOutputPorts: Int
    @Binding var sampleRate: SampleRate

    @Binding var digitalInputs: Set<DigitalFormat>
    @Binding var digitalOutputs: Set<DigitalFormat>
    @Binding var computerInterfaceCounts: [ComputerInterface: Int]

    @Binding var errorMessage: String?
    
    @Binding var manualURLs: [URL]
    @Binding var isSelectingManual: Bool
    
    @Binding var deviceLocation: DeviceLocation
    var canAccessGearLocker: Bool
    
    // Asset Inventory bindings
    @Binding var purchasePrice: Double
    @Binding var purchaseDate: Date?
    @Binding var purchaseLocation: String
    @Binding var warrantyExpirationDate: Date?
    @Binding var insurancePolicyNumber: String
    @Binding var currentEstimatedValue: Double
    @Binding var assetNotes: String

    let onCancel: () -> Void
    let onSave: () -> Void

    private func syncCountBasedDigitalFormats() {
        // ADAT is count-based
        if adatInputPorts > 0 {
            digitalInputs.insert(.adat)
        } else {
            digitalInputs.remove(.adat)
        }
        if adatOutputPorts > 0 {
            digitalOutputs.insert(.adat)
        } else {
            digitalOutputs.remove(.adat)
        }

        // MADI is count-based
        if madiInputPorts > 0 {
            digitalInputs.insert(.madi)
        } else {
            digitalInputs.remove(.madi)
        }
        if madiOutputPorts > 0 {
            digitalOutputs.insert(.madi)
        } else {
            digitalOutputs.remove(.madi)
        }
    }

    private var digitalInputFormatChoices: [DigitalFormat] {
        // Count-based formats configured via steppers
        DigitalFormat.allCases.filter { $0 != .adat && $0 != .madi }
    }

    private var digitalOutputFormatChoices: [DigitalFormat] {
        DigitalFormat.allCases.filter { $0 != .adat && $0 != .madi }
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        if canAccessGearLocker {
                            GroupBox("Location") {
                                Picker("Store Device In", selection: $deviceLocation) {
                                    Text("Current Studio").tag(DeviceLocation.currentStudio)
                                    Text("Gear Locker").tag(DeviceLocation.gearLocker)
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        GroupBox("Basics") {
                            Grid(
                                alignment: .leading,
                                horizontalSpacing: 12,
                                verticalSpacing: 10
                            ) {
                                GridRow {
                                    Text("Nickname")
                                    TextField("", text: $nickname)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Manufacturer")
                                    TextField("", text: $manufacturer)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Product ID")
                                    TextField("", text: $productId)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Category")
                                    Picker("", selection: $category) {
                                        ForEach(
                                            DeviceCategory.allCases,
                                            id: \.self
                                        ) { c in
                                            Text(c.rawValue).tag(c)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                                GridRow {
                                    Text("Serial Number")
                                    TextField("", text: $serialNumber)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Location")
                                    TextField("", text: $location)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Custom Color")
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            if let color = customColor {
                                                ColorPicker("Custom Color", selection: Binding(
                                                    get: { color },
                                                    set: { customColor = $0 }
                                                ))

                                                Button("Reset") {
                                                    customColor = nil
                                                }
                                                .buttonStyle(.borderless)
                                            } else {
                                                let categoryColors = CategoryColorSettings.loadCategoryColors()
                                                let categoryColor = categoryColors[category] ?? .gray

                                                ColorPicker("Set Custom Color", selection: Binding(
                                                    get: { categoryColor },
                                                    set: { customColor = $0 }
                                                ))
                                            }
                                        }

                                        if customColor == nil {
                                            Text("Using category default color")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(8)
                        }

                        GroupBox("Links") {
                            Grid(
                                alignment: .leading,
                                horizontalSpacing: 12,
                                verticalSpacing: 10
                            ) {
                                GridRow {
                                    Text("Support Page")
                                    TextField(
                                        "https://…",
                                        text: $supportPageURL
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Downloads Page")
                                    TextField(
                                        "https://…",
                                        text: $downloadsPageURL
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox("Manuals") {
                            VStack(alignment: .leading, spacing: 10) {
                                if manualURLs.isEmpty {
                                    Text("No manuals attached")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                } else {
                                    ForEach(Array(manualURLs.enumerated()), id: \.offset) { index, url in
                                        HStack {
                                            Image(systemName: "doc.richtext.fill")
                                                .foregroundStyle(.blue)
                                            Text(url.lastPathComponent)
                                                .lineLimit(1)
                                            Spacer()
                                            Button(role: .destructive) {
                                                manualURLs.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                                
                                Button {
                                    isSelectingManual = true
                                } label: {
                                    Label("Add PDF Manual", systemImage: "doc.badge.plus")
                                }
                            }
                            .padding(8)
                        }

                        GroupBox("Analog I/O") {
                            VStack(alignment: .leading, spacing: 10) {
                                Stepper(value: $audioInputs, in: 0...128) {
                                    HStack {
                                        Text("Analog Inputs")
                                        Spacer()
                                        Text("\(audioInputs)").foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                                Stepper(value: $audioOutputs, in: 0...128) {
                                    HStack {
                                        Text("Analog Outputs")
                                        Spacer()
                                        Text("\(audioOutputs)").foregroundStyle(
                                            .secondary
                                        )
                                    }
                                }
                            }
                            .padding(8)
                        }

                        GroupBox("Digital I/O") {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Sample Rate", selection: $sampleRate) {
                                    ForEach(SampleRate.allCases, id: \.self) {
                                        r in
                                        Text(r.displayName).tag(r)
                                    }
                                }
                                .pickerStyle(.segmented)

                                Divider().padding(.vertical, 4)

                                Stepper(value: $adatInputPorts, in: 0...8) {
                                    HStack {
                                        Text("ADAT Input Ports")
                                        Spacer()
                                        Text("\(adatInputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: $adatOutputPorts, in: 0...8) {
                                    HStack {
                                        Text("ADAT Output Ports")
                                        Spacer()
                                        Text("\(adatOutputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: $madiInputPorts, in: 0...8) {
                                    HStack {
                                        Text("MADI Input Ports")
                                        Spacer()
                                        Text("\(madiInputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: $madiOutputPorts, in: 0...8) {
                                    HStack {
                                        Text("MADI Output Ports")
                                        Spacer()
                                        Text("\(madiOutputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: $midiInputPorts, in: 0...32) {
                                    HStack {
                                        Text("MIDI Input Ports")
                                        Spacer()
                                        Text("\(midiInputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Stepper(value: $midiOutputPorts, in: 0...32) {
                                    HStack {
                                        Text("MIDI Output Ports")
                                        Spacer()
                                        Text("\(midiOutputPorts)")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                            }
                            .padding(8)
                        }

                        GroupBox("Digital Inputs") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(digitalInputFormatChoices, id: \.self) {
                                    f in
                                    Toggle(
                                        f.rawValue,
                                        isOn: Binding(
                                            get: { digitalInputs.contains(f) },
                                            set: { isOn in
                                                if isOn {
                                                    digitalInputs.insert(f)
                                                    // MIDI over USB is bidirectional - auto-add to outputs
                                                    if f == .midi {
                                                        digitalOutputs.insert(f)
                                                    }
                                                } else {
                                                    digitalInputs.remove(f)
                                                    // MIDI over USB is bidirectional - auto-remove from outputs
                                                    if f == .midi {
                                                        digitalOutputs.remove(f)
                                                    }
                                                }
                                            }
                                        )
                                    )
                                }
                            }
                            .padding(8)
                        }

                        GroupBox("Digital Outputs") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(digitalOutputFormatChoices, id: \.self)
                                { f in
                                    Toggle(
                                        f.rawValue,
                                        isOn: Binding(
                                            get: { digitalOutputs.contains(f) },
                                            set: { isOn in
                                                if isOn {
                                                    digitalOutputs.insert(f)
                                                    // MIDI over USB is bidirectional - auto-add to inputs
                                                    if f == .midi {
                                                        digitalInputs.insert(f)
                                                    }
                                                } else {
                                                    digitalOutputs.remove(f)
                                                    // MIDI over USB is bidirectional - auto-remove from inputs
                                                    if f == .midi {
                                                        digitalInputs.remove(f)
                                                    }
                                                }
                                            }
                                        )
                                    )
                                }
                            }
                            .padding(8)
                        }

                        GroupBox("Computer I/O") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(ComputerInterface.allCases, id: \.self)
                                { f in
                                    Stepper(
                                        value: Binding(
                                            get: {
                                                max(
                                                    0,
                                                    computerInterfaceCounts[f]
                                                        ?? 0
                                                )
                                            },
                                            set: { newValue in
                                                let v = max(0, newValue)
                                                if v == 0 {
                                                    computerInterfaceCounts
                                                        .removeValue(forKey: f)
                                                } else {
                                                    computerInterfaceCounts[f] =
                                                        v
                                                }
                                            }
                                        ),
                                        in: 0...8
                                    ) {
                                        HStack {
                                            Text(f.rawValue)
                                            Spacer()
                                            Text(
                                                "\(computerInterfaceCounts[f] ?? 0)"
                                            )
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                        }
                        
                        GroupBox("Asset Inventory") {
                            Grid(
                                alignment: .leading,
                                horizontalSpacing: 12,
                                verticalSpacing: 10
                            ) {
                                GridRow {
                                    Text("Purchase Price")
                                    TextField("", value: $purchasePrice, format: .currency(code: "USD"))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Purchase Date")
                                    DatePicker("", selection: Binding(
                                        get: { purchaseDate ?? Date() },
                                        set: { purchaseDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if purchaseDate != nil {
                                        Button("Clear") {
                                            purchaseDate = nil
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                GridRow {
                                    Text("Purchase Location")
                                    TextField("Store or website", text: $purchaseLocation)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Warranty Expires")
                                    DatePicker("", selection: Binding(
                                        get: { warrantyExpirationDate ?? Date() },
                                        set: { warrantyExpirationDate = $0 }
                                    ), displayedComponents: .date)
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if warrantyExpirationDate != nil {
                                        Button("Clear") {
                                            warrantyExpirationDate = nil
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                GridRow {
                                    Text("Insurance Policy")
                                    TextField("Policy number", text: $insurancePolicyNumber)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Current Value")
                                    TextField("", value: $currentEstimatedValue, format: .currency(code: "USD"))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: .infinity)
                                }
                                GridRow {
                                    Text("Notes")
                                    TextEditor(text: $assetNotes)
                                        .frame(height: 60)
                                        .border(Color.gray.opacity(0.3))
                                }
                            }
                            .padding(8)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                }
                .onAppear { syncCountBasedDigitalFormats() }
                .onChange(of: adatInputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: adatOutputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: madiInputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: madiOutputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .scrollIndicators(.visible)
                .frame(
                    minWidth: 560,
                    idealWidth: 640,
                    maxWidth: .infinity,
                    minHeight: 640,
                    idealHeight: 720,
                    maxHeight: .infinity
                )
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isSelectingManual,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: true
                ) { result in
                    guard case .success(let urls) = result else { return }
                    
                    // Append all selected URLs - they will be processed when saving
                    manualURLs.append(contentsOf: urls)
                }
            #else
                Form {
                    if canAccessGearLocker {
                        Section("Location") {
                            Picker("Store Device In", selection: $deviceLocation) {
                                Text("Current Studio").tag(DeviceLocation.currentStudio)
                                Text("Gear Locker").tag(DeviceLocation.gearLocker)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    Section("Basics") {
                        TextField("Nickname", text: $nickname)
                        TextField("Manufacturer", text: $manufacturer)
                        TextField("Product ID", text: $productId)

                        Picker("Category", selection: $category) {
                            ForEach(DeviceCategory.allCases, id: \.self) { c in
                                Text(c.rawValue).tag(c)
                            }
                        }

                        TextField("Serial Number", text: $serialNumber)
                        TextField("Location", text: $location)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if let color = customColor {
                                    ColorPicker("Custom Color", selection: Binding(
                                        get: { color },
                                        set: { customColor = $0 }
                                    ))

                                    Button("Reset") {
                                        customColor = nil
                                    }
                                    .buttonStyle(.borderless)
                                } else {
                                    let categoryColors = CategoryColorSettings.loadCategoryColors()
                                    let categoryColor = categoryColors[category] ?? .gray

                                    ColorPicker("Set Custom Color", selection: Binding(
                                        get: { categoryColor },
                                        set: { customColor = $0 }
                                    ))
                                }
                            }

                            if customColor == nil {
                                Text("Using category default color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section("Links") {
                        TextField("Support Page (URL)", text: $supportPageURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        TextField(
                            "Downloads Page (URL)",
                            text: $downloadsPageURL
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    }
                    
                    Section("Manuals") {
                        if manualURLs.isEmpty {
                            Text("No manuals attached")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(Array(manualURLs.enumerated()), id: \.offset) { index, url in
                                HStack {
                                    Image(systemName: "doc.richtext.fill")
                                        .foregroundStyle(.blue)
                                    Text(url.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(role: .destructive) {
                                        manualURLs.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Button {
                            isSelectingManual = true
                        } label: {
                            Label("Add PDF Manual", systemImage: "doc.badge.plus")
                        }
                    }

                    Section("Analog I/O") {
                        Stepper(value: $audioInputs, in: 0...128) {
                            HStack {
                                Text("Analog Inputs")
                                Spacer()
                                Text("\(audioInputs)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        Stepper(value: $audioOutputs, in: 0...128) {
                            HStack {
                                Text("Analog Outputs")
                                Spacer()
                                Text("\(audioOutputs)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                    }

                    Section("Digital I/O") {
                        Picker("Sample Rate", selection: $sampleRate) {
                            ForEach(SampleRate.allCases, id: \.self) { r in
                                Text(r.displayName).tag(r)
                            }
                        }

                        Stepper(value: $adatInputPorts, in: 0...8) {
                            HStack {
                                Text("ADAT Input Ports")
                                Spacer()
                                Text("\(adatInputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        Stepper(value: $adatOutputPorts, in: 0...8) {
                            HStack {
                                Text("ADAT Output Ports")
                                Spacer()
                                Text("\(adatOutputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        Stepper(value: $madiInputPorts, in: 0...8) {
                            HStack {
                                Text("MADI Input Ports")
                                Spacer()
                                Text("\(madiInputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }
                        Stepper(value: $madiOutputPorts, in: 0...8) {
                            HStack {
                                Text("MADI Output Ports")
                                Spacer()
                                Text("\(madiOutputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        Stepper(value: $midiInputPorts, in: 0...32) {
                            HStack {
                                Text("MIDI Input Ports")
                                Spacer()
                                Text("\(midiInputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                        Stepper(value: $midiOutputPorts, in: 0...32) {
                            HStack {
                                Text("MIDI Output Ports")
                                Spacer()
                                Text("\(midiOutputPorts)").foregroundStyle(
                                    .secondary
                                )
                            }
                        }

                    }

                    Section("Digital Inputs") {
                        ForEach(digitalInputFormatChoices, id: \.self) { f in
                            Toggle(
                                f.rawValue,
                                isOn: Binding(
                                    get: { digitalInputs.contains(f) },
                                    set: { isOn in
                                        if isOn {
                                            digitalInputs.insert(f)
                                            // MIDI over USB is bidirectional - auto-add to outputs
                                            if f == .midi {
                                                digitalOutputs.insert(f)
                                            }
                                        } else {
                                            digitalInputs.remove(f)
                                            // MIDI over USB is bidirectional - auto-remove from outputs
                                            if f == .midi {
                                                digitalOutputs.remove(f)
                                            }
                                        }
                                    }
                                )
                            )
                        }
                    }

                    Section("Digital Outputs") {
                        ForEach(digitalOutputFormatChoices, id: \.self) { f in
                            Toggle(
                                f.rawValue,
                                isOn: Binding(
                                    get: { digitalOutputs.contains(f) },
                                    set: { isOn in
                                        if isOn {
                                            digitalOutputs.insert(f)
                                            // MIDI over USB is bidirectional - auto-add to inputs
                                            if f == .midi {
                                                digitalInputs.insert(f)
                                            }
                                        } else {
                                            digitalOutputs.remove(f)
                                            // MIDI over USB is bidirectional - auto-remove from inputs
                                            if f == .midi {
                                                digitalInputs.remove(f)
                                            }
                                        }
                                    }
                                )
                            )
                        }
                    }

                    Section("Computer I/O") {
                        ForEach(ComputerInterface.allCases, id: \.self) { f in
                            Stepper(
                                value: Binding(
                                    get: {
                                        max(0, computerInterfaceCounts[f] ?? 0)
                                    },
                                    set: { newValue in
                                        let v = max(0, newValue)
                                        if v == 0 {
                                            computerInterfaceCounts.removeValue(
                                                forKey: f
                                            )
                                        } else {
                                            computerInterfaceCounts[f] = v
                                        }
                                    }
                                ),
                                in: 0...8
                            ) {
                                HStack {
                                    Text(f.rawValue)
                                    Spacer()
                                    Text("\(computerInterfaceCounts[f] ?? 0)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    Section("Asset Inventory") {
                        HStack {
                            Text("Purchase Price")
                            Spacer()
                            TextField("Amount", value: $purchasePrice, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        
                        HStack {
                            Text("Purchase Date")
                            Spacer()
                            if let date = purchaseDate {
                                DatePicker("", selection: Binding(
                                    get: { date },
                                    set: { purchaseDate = $0 }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                Button("Clear") {
                                    purchaseDate = nil
                                }
                            } else {
                                Button("Set Date") {
                                    purchaseDate = Date()
                                }
                            }
                        }
                        
                        HStack {
                            Text("Purchase Location")
                            TextField("Store or website", text: $purchaseLocation)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("Warranty Expires")
                            Spacer()
                            if let date = warrantyExpirationDate {
                                DatePicker("", selection: Binding(
                                    get: { date },
                                    set: { warrantyExpirationDate = $0 }
                                ), displayedComponents: .date)
                                .labelsHidden()
                                Button("Clear") {
                                    warrantyExpirationDate = nil
                                }
                            } else {
                                Button("Set Date") {
                                    warrantyExpirationDate = Date()
                                }
                            }
                        }
                        
                        HStack {
                            Text("Insurance Policy")
                            TextField("Policy number", text: $insurancePolicyNumber)
                                .multilineTextAlignment(.trailing)
                        }
                        
                        HStack {
                            Text("Current Value")
                            Spacer()
                            TextField("Amount", value: $currentEstimatedValue, format: .currency(code: "USD"))
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $assetNotes)
                                .frame(minHeight: 80)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .onAppear { syncCountBasedDigitalFormats() }
                .onChange(of: adatInputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: adatOutputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: madiInputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .onChange(of: madiOutputPorts) { _, _ in
                    syncCountBasedDigitalFormats()
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave()
                            dismiss()
                        }
                    }
                }
                .fileImporter(
                    isPresented: $isSelectingManual,
                    allowedContentTypes: [.pdf],
                    allowsMultipleSelection: true
                ) { result in
                    guard case .success(let urls) = result else { return }
                    
                    // Append all selected URLs - they will be processed when saving
                    manualURLs.append(contentsOf: urls)
                }
            #endif
        }
    }
}

// Helper for sheet binding
private struct IdentifiableUUID: Identifiable {
    let id: UUID
}

// Helper for sheet binding
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

private struct DeviceInspectorOverlay: View {
    let studio: Studio
    let deviceId: UUID
    let onEditDevice: (DeviceInstance) -> Void
    let onRequestDeleteDevice: (DeviceInstance) -> Void
    let onCloneDevice: (DeviceInstance) -> Void
    let onRequestMoveDevice: (DeviceInstance) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isImportingManual: Bool = false
    @State private var manualViewerItem: IdentifiableURL? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let d = studio.devices?.first(where: { $0.id == deviceId }) {
                    Form {
                        Section("Device") {
                            LabeledContent("Nickname", value: d.nickname)

                            if !d.manufacturer.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent(
                                    "Manufacturer",
                                    value: d.manufacturer
                                )
                            }

                            if !d.model.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent("Product ID", value: d.model)
                            }

                            LabeledContent(
                                "Category",
                                value: d.category.rawValue
                            )

                            if !d.serialNumber.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent(
                                    "Serial Number",
                                    value: d.serialNumber
                                )
                            }

                            if !d.location.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty {
                                LabeledContent("Location", value: d.location)
                            }

                            if let url = d.supportPageURL {
                                HStack {
                                    Text("Support Page")
                                    Spacer()
                                    Text(url.absoluteString)
                                        .lineLimit(1)
                                        .foregroundStyle(.blue)
                                        .underline()
                                        .onTapGesture {
                                            let validURL = ensureURLScheme(url)
                                            #if os(macOS)
                                            NSWorkspace.shared.open(validURL)
                                            #else
                                            UIApplication.shared.open(validURL)
                                            #endif
                                        }
                                }
                            }

                            if let url = d.downloadsPageURL {
                                HStack {
                                    Text("Downloads Page")
                                    Spacer()
                                    Text(url.absoluteString)
                                        .lineLimit(1)
                                        .foregroundStyle(.blue)
                                        .underline()
                                        .onTapGesture {
                                            let validURL = ensureURLScheme(url)
                                            #if os(macOS)
                                            NSWorkspace.shared.open(validURL)
                                            #else
                                            UIApplication.shared.open(validURL)
                                            #endif
                                        }
                                }
                            }
                        }

                        Section("Ports") {
                            if d.ports?.isEmpty ?? true {
                                Text("No ports defined yet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach((d.ports ?? []).sorted(by: portSort), id: \.id) {
                                p in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(p.name)
                                        Spacer()
                                        Text("\(p.channels?.count ?? 0) ch")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)

                                    if !(p.channels?.isEmpty ?? true) {
                                        Text(
                                            (p.channels ?? [])
                                                .sorted(by: {
                                                    $0.index < $1.index
                                                })
                                                .map { ch in
                                                    ch.nameShort.isEmpty
                                                        ? "\(ch.index)"
                                                        : ch.nameShort
                                                }
                                                .joined(separator: ", ")
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            if !d.computerInterfaces.isEmpty {
                                Divider().padding(.vertical, 4)
                                Text("Computer Interfaces")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ForEach(
                                    d.computerInterfaces.sorted(by: {
                                        $0.rawValue < $1.rawValue
                                    }),
                                    id: \.self
                                ) { iface in
                                    Text(iface.rawValue)
                                }
                            }
                        }

                        Section("Manuals") {
                            Button {
                                isImportingManual = true
                            } label: {
                                Label(
                                    "Add Manual",
                                    systemImage: "doc.badge.plus"
                                )
                            }

                            if d.docs?.isEmpty ?? true {
                                Text("No manuals attached.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(d.docs ?? [], id: \.id) { doc in
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                            .foregroundStyle(.secondary)
                                        Text(doc.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(role: .destructive) {
                                            if let idx = d.docs?.firstIndex(
                                                where: { $0.id == doc.id })
                                            {
                                                d.docs?.remove(at: idx)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Try to migrate to iCloud if needed (one-time automatic migration)
                                        _ = iCloudDocumentManager.migrateDocLinkToiCloud(doc)
                                        
                                        do {
                                            let url = try ManualStorage.resolveDocLink(doc)
                                            manualViewerItem = IdentifiableURL(url: url, title: doc.title)
                                        } catch {
                                            print("❌ Failed to resolve manual: \(error)")
                                        }
                                    }
                                }
                            }
                        }

                        Section {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    Button {
                                        onEditDevice(d)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button(role: .destructive) {
                                        onRequestDeleteDevice(d)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }

                                HStack(spacing: 12) {
                                    Button {
                                        onCloneDevice(d)
                                    } label: {
                                        Label(
                                            "Clone",
                                            systemImage: "plus.square.on.square"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        onRequestMoveDevice(d)
                                    } label: {
                                        Label(
                                            "Move",
                                            systemImage:
                                                "arrowshape.turn.up.right"
                                        )
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .formStyle(.grouped)
                    .fileImporter(
                        isPresented: $isImportingManual,
                        allowedContentTypes: [.pdf],
                        allowsMultipleSelection: false
                    ) { result in
                        guard case .success(let urls) = result,
                            let pickedURL = urls.first,
                            let device = studio.devices?.first(where: {
                                $0.id == deviceId
                            })
                        else { return }

                        do {
                            let (storedURL, bookmarkData) =
                                try ManualStorage.copyPDFIntoAppSupport(
                                    pickedURL: pickedURL,
                                    deviceId: device.id
                                )

                            let doc: DocLink
                            // Check if this is an iCloud-stored document (path starts with /iCloud/)
                            if storedURL.path.hasPrefix("/iCloud/") {
                                let iCloudPath = String(storedURL.path.dropFirst("/iCloud/".count))
                                // Extract original filename (removes UUID prefix) and remove extension
                                let fullFilename = iCloudDocumentManager.extractOriginalFilename(from: iCloudPath)
                                let title = (fullFilename as NSString).deletingPathExtension
                                doc = DocLink(
                                    title: title,
                                    kind: .manual,
                                    iCloudPath: iCloudPath
                                )
                            } else {
                                // Legacy local storage
                                doc = DocLink(
                                    title: storedURL.lastPathComponent,
                                    kind: .manual,
                                    bookmarkData: bookmarkData
                                )
                            }
                            
                            if device.docs == nil {
                                device.docs = []
                            }
                            device.docs?.append(doc)
                            
                            // Mark device and studio as modified
                            device.markAsModified()
                            studio.markAsModified()
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                        .fullScreenCover(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.title
                            )
                        }
                    #else
                        .sheet(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.title
                            )
                        }
                    #endif
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Device not found")
                            .font(.title3)
                        Text("This device may have been deleted.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                
                if let device = studio.devices?.first(where: { $0.id == deviceId }) {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            exportDeviceDetailAsPDF(device: device)
                        } label: {
                            Label("Export PDF", systemImage: "square.and.arrow.up")
                        }
                        .help("Export device details as PDF")
                    }
                }
            }
        }
    }
    
    private func exportDeviceDetailAsPDF(device: DeviceInstance) {
        // Create printable device detail view
        let printableView = VStack(alignment: .leading, spacing: 16) {
            Text("Device Details: \(device.nickname)")
                .font(.title)
                .fontWeight(.bold)
                .padding(.bottom, 8)
            
            Group {
                Text("Basic Information")
                    .font(.headline)
                
                if !device.manufacturer.isEmpty {
                    HStack {
                        Text("Manufacturer:")
                            .fontWeight(.medium)
                        Text(device.manufacturer)
                    }
                }
                
                if !device.model.isEmpty {
                    HStack {
                        Text("Product ID:")
                            .fontWeight(.medium)
                        Text(device.model)
                    }
                }
                
                HStack {
                    Text("Category:")
                        .fontWeight(.medium)
                    Text(device.category.rawValue)
                }
                
                if !device.serialNumber.isEmpty {
                    HStack {
                        Text("Serial Number:")
                            .fontWeight(.medium)
                        Text(device.serialNumber)
                    }
                }
                
                if !device.location.isEmpty {
                    HStack {
                        Text("Location:")
                            .fontWeight(.medium)
                        Text(device.location)
                    }
                }
            }
            .padding(.leading, 8)
            
            Divider()
            
            Group {
                Text("I/O Configuration")
                    .font(.headline)
                
                if device.audioInputsCount > 0 || device.audioOutputsCount > 0 {
                    HStack {
                        Text("Analog I/O:")
                            .fontWeight(.medium)
                        Text("\(device.audioInputsCount) inputs / \(device.audioOutputsCount) outputs")
                    }
                }
                
                if device.adatInputPortsCount > 0 || device.adatOutputPortsCount > 0 {
                    HStack {
                        Text("ADAT Ports:")
                            .fontWeight(.medium)
                        Text("\(device.adatInputPortsCount) in / \(device.adatOutputPortsCount) out")
                    }
                }
                
                if device.madiInputPortsCount > 0 || device.madiOutputPortsCount > 0 {
                    HStack {
                        Text("MADI Ports:")
                            .fontWeight(.medium)
                        Text("\(device.madiInputPortsCount) in / \(device.madiOutputPortsCount) out")
                    }
                }
                
                if !device.digitalInputs.isEmpty || !device.digitalOutputs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Digital Formats:")
                            .fontWeight(.medium)
                        if !device.digitalInputs.isEmpty {
                            Text("  Inputs: \(device.digitalInputs.map { $0.rawValue }.joined(separator: ", "))")
                        }
                        if !device.digitalOutputs.isEmpty {
                            Text("  Outputs: \(device.digitalOutputs.map { $0.rawValue }.joined(separator: ", "))")
                        }
                    }
                }
                
                if !device.computerInterfaces.isEmpty {
                    HStack {
                        Text("Computer Interfaces:")
                            .fontWeight(.medium)
                        Text(device.computerInterfaces.map { $0.rawValue }.joined(separator: ", "))
                    }
                }
            }
            .padding(.leading, 8)
            
            if let ports = device.ports, !ports.isEmpty {
                Divider()
                
                Text("Ports")
                    .font(.headline)
                
                ForEach(ports.sorted(by: portSort), id: \.id) { port in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(port.name)
                            .fontWeight(.medium)
                        if let channels = port.channels, !channels.isEmpty {
                            Text(channels.sorted(by: { $0.index < $1.index })
                                .map { $0.nameShort.isEmpty ? "\($0.index)" : $0.nameShort }
                                .joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
            
            if let docs = device.docs, !docs.isEmpty {
                Divider()
                
                Text("Documentation")
                    .font(.headline)
                
                ForEach(docs, id: \.id) { doc in
                    Text("• \(doc.title) (\(doc.kind.rawValue))")
                        .padding(.leading, 8)
                }
            }
        }
        .padding()
        
        #if os(iOS)
        let renderer = ImageRenderer(content: printableView)
        renderer.scale = 2.0
        
        if let pdfData = renderer.pdf() {
            let filename = "\(device.nickname.replacingOccurrences(of: " ", with: "_"))_Details.pdf"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? pdfData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presentingVC = rootVC
                while let presented = presentingVC.presentedViewController {
                    presentingVC = presented
                }
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presentingVC.view
                    popover.sourceRect = CGRect(x: presentingVC.view.bounds.midX, y: presentingVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                presentingVC.present(activityVC, animated: true)
            }
        }
        #elseif os(macOS)
        let renderer = ImageRenderer(content: printableView)
        renderer.scale = 2.0
        
        if let pdfData = renderer.pdf() {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "\(device.nickname.replacingOccurrences(of: " ", with: "_"))_Details.pdf"
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    try? pdfData.write(to: url)
                }
            }
        }
        #endif
    }
    
    private func portSort(_ p1: Port, _ p2: Port) -> Bool {
        if p1.direction != p2.direction {
            return p1.direction == .input
        }
        return p1.name < p2.name
    }
}

// MARK: - DeviceExplosionDetailView

private struct DeviceExplosionDetailView: View {
    let studio: Studio
    let device: DeviceInstance
    let connectionsStore: ConnectionsStore

    private func endpoint(for port: Port, channel: Channel) -> IOEndpointRef {
        let dir: IOEndpointRef.Direction =
            (port.direction == .input) ? .input : .output
        return IOEndpointRef(
            deviceId: device.id,
            portId: port.id,
            channelId: channel.id,
            direction: dir
        )
    }

    private func rowLabel(port: Port, channel: Channel) -> String {
        let short = channel.nameShort.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if short.isEmpty {
            return port.name
        }
        // Prefer the short label if it already implies index (e.g. "In1"), otherwise keep it readable.
        return "\(port.name) \(short)"
    }

    private func statusText(for endpoint: IOEndpointRef) -> String {
        connectionsStore.connectedToText(
            studio: studio,
            studioId: studio.id,
            endpoint: endpoint
        ) ?? "open"
    }

    private func isOpen(_ endpoint: IOEndpointRef) -> Bool {
        connectionsStore.occupancyForEndpoint(
            studioId: studio.id,
            endpoint: endpoint
        ) == nil
    }

    private func isComputerInterfacePort(_ p: Port) -> Bool {
        // Computer interface ports are synthesized from `device.computerInterfaceCounts`.
        // Their names are the interface rawValue, optionally with a numeric suffix, e.g. "USB 2".
        let prefixes = device.computerInterfaceCounts.keys.map { $0.rawValue }
        for prefix in prefixes {
            if p.name == prefix { return true }
            if p.name.hasPrefix(prefix + " ") { return true }
        }
        return false
    }

    private var inputPorts: [Port] {
        (device.ports ?? [])
            .filter { $0.direction == .input && !isComputerInterfacePort($0) }
            .sorted(by: portSort)
    }

    private var outputPorts: [Port] {
        (device.ports ?? [])
            .filter { $0.direction == .output && !isComputerInterfacePort($0) }
            .sorted(by: portSort)
    }

    private struct ComputerInterfaceRow: Identifiable {
        let id: String
        let label: String
        let inputEndpoint: IOEndpointRef
        let outputEndpoint: IOEndpointRef
    }

    private var computerInterfaceRows: [ComputerInterfaceRow] {
        let counts = device.computerInterfaceCounts
        let keys = counts.keys.sorted(by: { $0.rawValue < $1.rawValue })

        var rows: [ComputerInterfaceRow] = []
        for iface in keys {
            let n = max(0, counts[iface] ?? 0)
            if n == 0 { continue }
            for idx in 1...n {
                let label =
                    (n > 1) ? "\(iface.rawValue) \(idx)" : iface.rawValue
                let portId = stableComputerPortId(
                    deviceId: device.id,
                    iface: iface,
                    index: idx
                )
                let channelId = stableComputerChannelId(
                    deviceId: device.id,
                    iface: iface,
                    index: idx
                )
                rows.append(
                    ComputerInterfaceRow(
                        id: "\(iface.rawValue)|\(idx)",
                        label: label,
                        inputEndpoint: IOEndpointRef(
                            deviceId: device.id,
                            portId: portId,
                            channelId: channelId,
                            direction: .input
                        ),
                        outputEndpoint: IOEndpointRef(
                            deviceId: device.id,
                            portId: portId,
                            channelId: channelId,
                            direction: .output
                        )
                    )
                )
            }
        }
        return rows
    }

    var body: some View {
        Group {
            #if os(macOS)
                Form {
                    explosionContent
                }
                .formStyle(.grouped)
            #else
                List {
                    explosionContent
                }
            #endif
        }
        .navigationTitle("Device I/O")
    }

    @ViewBuilder
    private var explosionContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.nickname)
                    .font(.title2)
                    .bold()
                let used = (inputPorts + outputPorts).flatMap { p in
                    (p.channels ?? []).map { endpoint(for: p, channel: $0) }
                }
                .filter { !isOpen($0) }
                .count
                let total = (inputPorts + outputPorts).reduce(0) {
                    $0 + ($1.channels?.count ?? 0)
                }
                Text("\(used) in use • \(max(0, total - used)) open")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }

        // Computer Interfaces: render the actual generated ports (USB In/Out etc) so we can show connection status.

        if !computerInterfaceRows.isEmpty {
            Section("Computer Interfaces") {
                ForEach(computerInterfaceRows) { row in
                    let connectedText =
                        connectionsStore.connectedToText(
                            studio: studio,
                            studioId: studio.id,
                            endpoint: row.inputEndpoint
                        )
                        ?? connectionsStore.connectedToText(
                            studio: studio,
                            studioId: studio.id,
                            endpoint: row.outputEndpoint
                        )
                    let isOpen = (connectedText == nil)

                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label)
                            Text(connectedText ?? "open")
                                .font(.caption)
                                .foregroundStyle(isOpen ? .secondary : .primary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(
                            systemName: isOpen
                                ? "circle" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }

        if !inputPorts.isEmpty {
            Section("Inputs") {
                ForEach(inputPorts, id: \.id) { p in
                    ForEach(
                        (p.channels ?? []).sorted(by: { $0.index < $1.index }),
                        id: \.id
                    ) { ch in
                        let ep = endpoint(for: p, channel: ch)
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rowLabel(port: p, channel: ch))
                                Text(statusText(for: ep))
                                    .font(.caption)
                                    .foregroundStyle(
                                        isOpen(ep) ? .secondary : .primary
                                    )
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(
                                systemName: isOpen(ep)
                                    ? "circle" : "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }

        if !outputPorts.isEmpty {
            Section("Outputs") {
                ForEach(outputPorts, id: \.id) { p in
                    ForEach(
                        (p.channels ?? []).sorted(by: { $0.index < $1.index }),
                        id: \.id
                    ) { ch in
                        let ep = endpoint(for: p, channel: ch)
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rowLabel(port: p, channel: ch))
                                Text(statusText(for: ep))
                                    .font(.caption)
                                    .foregroundStyle(
                                        isOpen(ep) ? .secondary : .primary
                                    )
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(
                                systemName: isOpen(ep)
                                    ? "circle" : "checkmark.circle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }

        if inputPorts.isEmpty && outputPorts.isEmpty {
            Section {
                Text("No I/O endpoints found for this device yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ExplosionOverviewView

private struct ExplosionOverviewView: View {
    let studio: Studio
    let centerDevice: DeviceInstance
    let connectionsStore: ConnectionsStore
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            DeviceExplosionDetailView(
                studio: studio,
                device: centerDevice,
                connectionsStore: connectionsStore
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}

// MARK: - UI Helpers for SampleRate

private func sampleRateRawHz(_ rate: SampleRate) -> Int {
    // Prefer rawValue if it already encodes Hz (common pattern).
    // If rawValue is an index (0,1,2...), this still returns a small number and will default to 8ch ADAT.
    return rate.rawValue
}

// MARK: - Port Sorting Helper

private func portSort(_ a: Port, _ b: Port) -> Bool {
    func dirRank(_ d: PortDirection) -> Int { d == .input ? 0 : 1 }

    func typeRank(_ t: PortType) -> Int {
        switch t {
        case .analogIn: return 0
        case .analogOut: return 1
        case .adatIn: return 2
        case .adatOut: return 3
        case .spdifIn: return 4
        case .spdifOut: return 5
        default: return 99
        }
    }

    let da = dirRank(a.direction)
    let db = dirRank(b.direction)
    if da != db { return da < db }

    let ta = typeRank(a.type)
    let tb = typeRank(b.type)
    if ta != tb { return ta < tb }

    return a.name.localizedStandardCompare(b.name) == .orderedAscending
}

private func stableComputerPortId(
    deviceId: UUID,
    iface: ComputerInterface,
    index: Int
) -> UUID {
    stableUUID("computerPort|\(deviceId.uuidString)|\(iface.rawValue)|\(index)")
}

private func stableComputerChannelId(
    deviceId: UUID,
    iface: ComputerInterface,
    index: Int
) -> UUID {
    stableUUID("computerCh|\(deviceId.uuidString)|\(iface.rawValue)|\(index)")
}
private func stableUUID(_ s: String) -> UUID {
    let digest = SHA256.hash(data: Data(s.utf8))
    let bytes = Array(digest)
    let uuidBytes = Array(bytes.prefix(16))
    return UUID(
        uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )
    )
}

// MARK: - Connection Legend View

private struct ConnectionLegendView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Colors") {
                    LegendRow(
                        color: .blue,
                        title: "Analog",
                        description: "Analog I/O, headphone outputs"
                    )
                    LegendRow(
                        color: .green,
                        title: "Digital",
                        description: "ADAT, MADI, S/PDIF, AES, Word Clock"
                    )
                    LegendRow(
                        color: .purple,
                        title: "MIDI",
                        description: "MIDI In/Out connections"
                    )
                    LegendRow(
                        color: .orange,
                        title: "Computer / Bidirectional",
                        description: "USB, Thunderbolt, Bluetooth, Ethernet (two arrows)"
                    )
                }

                Section("Line Thickness") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 60, height: 2)
                            Text("1-2 channels")
                                .font(.subheadline)
                        }

                        HStack {
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 60, height: 3.5)
                            Text("3-8 channels")
                                .font(.subheadline)
                        }

                        HStack {
                            Rectangle()
                                .fill(Color.secondary)
                                .frame(width: 60, height: 5)
                            Text("9+ channels (ADAT/MADI)")
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Signal Flow") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("• Arrows indicate signal direction")
                        Text(
                            "• Computer connections show two arrows (bidirectional)"
                        )
                        Text(
                            "• Use Auto-Arrange to organize devices by signal flow"
                        )
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connection Legend")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Connection Matrix View

private struct ConnectionMatrixView: View {
    let studio: Studio
    let connectionsStore: ConnectionsStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isPanEnabled: Bool = false
    @State private var lastKnownWidth: CGFloat = 0
    
    private var links: [ConnectionLinkSummary] {
        connectionsStore.links(for: studio.id)
    }
    
    // Devices that are actually used as sources in connections
    private var fromDevices: [DeviceInstance] {
        // Get all device IDs that appear as "from" by checking connectionMap keys
        var fromDeviceIds = Set<UUID>()
        for key in connectionMap.keys {
            let components = key.split(separator: "_")
            if components.count == 2, let fromId = UUID(uuidString: String(components[0])) {
                fromDeviceIds.insert(fromId)
            }
        }
        
        return (studio.devices ?? []).filter { device in
            fromDeviceIds.contains(device.id)
        }.sorted { $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending }
    }
    
    // Devices that are actually used as destinations in connections
    private var toDevices: [DeviceInstance] {
        // Get all device IDs that appear as "to" by checking connectionMap keys
        var toDeviceIds = Set<UUID>()
        for key in connectionMap.keys {
            let components = key.split(separator: "_")
            if components.count == 2, let toId = UUID(uuidString: String(components[1])) {
                toDeviceIds.insert(toId)
            }
        }
        
        return (studio.devices ?? []).filter { device in
            toDeviceIds.contains(device.id)
        }.sorted { $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending }
    }
    
    // Build a map of device pairs to their connection info
    private var connectionMap: [String: ConnectionInfo] {
        var map: [String: ConnectionInfo] = [:]
        
        // First pass: build map with all connections
        for link in links {
            guard let bundle = connectionsStore.bundle(for: studio.id, linkId: link.id),
                  !bundle.edges.isEmpty else { continue }
            
            // Analyze edges to separate forward and reverse connections
            var forwardEdges: [ConnectionEdge] = []
            var reverseEdges: [ConnectionEdge] = []
            
            for edge in bundle.edges {
                if edge.from.deviceId == link.fromDeviceId {
                    forwardEdges.append(edge)
                } else {
                    reverseEdges.append(edge)
                }
            }
            
            // Process forward direction (link.fromDeviceId → link.toDeviceId)
            if !forwardEdges.isEmpty {
                let key = "\(link.fromDeviceId)_\(link.toDeviceId)"
                var typeCounts: [ConnectionVisualType: Int] = [:]
                var uniqueChannels: Set<String> = []
                var hasWordClock = false
                
                for edge in forwardEdges {
                    if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                       let port = device.ports?.first(where: { $0.id == edge.from.portId }) {
                        let visualType = ConnectionVisualType.from(portType: port.type)
                        typeCounts[visualType, default: 0] += 1
                        
                        if port.type == .wordClockIn || port.type == .wordClockOut {
                            hasWordClock = true
                        } else {
                            uniqueChannels.insert(edge.from.channelId.uuidString)
                        }
                    } else if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                              !device.computerInterfaceCounts.isEmpty {
                        typeCounts[.computer, default: 0] += 1
                        uniqueChannels.insert(edge.from.channelId.uuidString)
                    }
                }
                
                let types = typeCounts.sorted { $0.value > $1.value }.map { $0.key }
                let channelCount = uniqueChannels.isEmpty ? forwardEdges.count : uniqueChannels.count
                map[key] = ConnectionInfo(
                    types: types.isEmpty ? [.unknown] : types,
                    channelCount: channelCount,
                    hasWordClock: hasWordClock,
                    hasReverseConnection: false  // Will update in second pass
                )
            }
            
            // Process reverse direction (link.toDeviceId → link.fromDeviceId)
            if !reverseEdges.isEmpty {
                let reverseKey = "\(link.toDeviceId)_\(link.fromDeviceId)"
                var typeCounts: [ConnectionVisualType: Int] = [:]
                var uniqueChannels: Set<String> = []
                var hasWordClock = false
                
                for edge in reverseEdges {
                    if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                       let port = device.ports?.first(where: { $0.id == edge.from.portId }) {
                        let visualType = ConnectionVisualType.from(portType: port.type)
                        typeCounts[visualType, default: 0] += 1
                        
                        if port.type == .wordClockIn || port.type == .wordClockOut {
                            hasWordClock = true
                        } else {
                            uniqueChannels.insert(edge.from.channelId.uuidString)
                        }
                    } else if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                              !device.computerInterfaceCounts.isEmpty {
                        typeCounts[.computer, default: 0] += 1
                        uniqueChannels.insert(edge.from.channelId.uuidString)
                    }
                }
                
                let types = typeCounts.sorted { $0.value > $1.value }.map { $0.key }
                let channelCount = uniqueChannels.isEmpty ? reverseEdges.count : uniqueChannels.count
                map[reverseKey] = ConnectionInfo(
                    types: types.isEmpty ? [.unknown] : types,
                    channelCount: channelCount,
                    hasWordClock: hasWordClock,
                    hasReverseConnection: false  // Will update in second pass
                )
            }
        }
        
        // Second pass: mark bidirectional connections
        var updatedMap = map
        for (key, info) in map {
            let components = key.split(separator: "_")
            if components.count == 2 {
                let reverseKey = "\(components[1])_\(components[0])"
                if map[reverseKey] != nil {
                    // This connection has a reverse - mark it
                    updatedMap[key] = ConnectionInfo(
                        types: info.types,
                        channelCount: info.channelCount,
                        hasWordClock: info.hasWordClock,
                        hasReverseConnection: true
                    )
                }
            }
        }
        
        return updatedMap
    }
    
    var body: some View {
        GeometryReader { geo in
            NavigationStack {
                VStack(spacing: 0) {
                    // Main scrollable matrix with zoom support
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                // Top-left corner cell
                                Text("From \\ To")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .frame(width: 120, height: 60, alignment: .center)
                                    .background(Color(white: 0.15).opacity(0.2))
                                    .border(Color.secondary.opacity(0.3))
                                
                                // Column headers (destination devices)
                                ForEach(toDevices, id: \.id) { device in
                                    let categoryColors = CategoryColorSettings.loadCategoryColors()
                                    let deviceColor = device.resolvedColor(categoryColors: categoryColors)
                                    
                                    VStack(spacing: 2) {
                                        Text(device.nickname)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Text(ioSummary(for: device))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 100, height: 60, alignment: .center)
                                    .background(deviceColor.opacity(0.15))
                                    .border(deviceColor.opacity(0.5))
                                }
                            }
                            
                            // Data rows
                            ForEach(fromDevices, id: \.id) { fromDevice in
                                HStack(spacing: 0) {
                                    // Row header (source device)
                                    let categoryColors = CategoryColorSettings.loadCategoryColors()
                                    let deviceColor = fromDevice.resolvedColor(categoryColors: categoryColors)
                                    
                                    VStack(spacing: 2) {
                                        Text(fromDevice.nickname)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Text(ioSummary(for: fromDevice))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(width: 120, height: 60, alignment: .center)
                                    .background(deviceColor.opacity(0.15))
                                    .border(deviceColor.opacity(0.5))
                                    
                                    // Connection cells
                                    ForEach(toDevices, id: \.id) { toDevice in
                                        connectionCell(from: fromDevice, to: toDevice)
                                    }
                                }
                            }
                        }
                        .padding()
                        .drawingGroup()
                        .scaleEffect(canvasScale, anchor: .center)
                    }
                    .scrollDisabled(!isPanEnabled)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                canvasScale = lastScale * value
                            }
                            .onEnded { value in
                                // Clamp scale between 0.5x and 5x
                                canvasScale = min(
                                    max(lastScale * value, 0.5),
                                    5.0
                                )
                                lastScale = canvasScale
                                
                                // Auto-enable pan mode when zoomed in significantly
                                if canvasScale > 1.2 {
                                    isPanEnabled = true
                                } else if canvasScale <= 1.0 {
                                    isPanEnabled = false
                                }
                            }
                    )
                    .onChange(of: geo.size) { oldSize, newSize in
                        // Reset scale on significant geometry changes (like rotation)
                        // to prevent distortion and hangs
                        if abs(oldSize.width - newSize.width) > 100 || abs(oldSize.height - newSize.height) > 100 {
                            // Reset immediately without animation to prevent visual distortion
                            canvasScale = 1.0
                            lastScale = 1.0
                            isPanEnabled = false
                            lastKnownWidth = newSize.width
                        }
                    }
                
                // Color legend at bottom
                Divider()
                
                VStack(spacing: 8) {
                    HStack(spacing: 24) {
                        legendItem(color: .blue, label: "Analog")
                        legendItem(color: .green, label: "Digital (ADAT/MADI/S/PDIF)")
                        legendItem(color: .purple, label: "MIDI")
                        legendItem(color: .orange, label: "Computer (USB/Thunderbolt/Ethernet)")
                    }
                    HStack {
                        Text("WC")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                        Text("= Word Clock (sync only, not counted in I/O)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
            }
            .navigationTitle("Connection Matrix")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportMatrixAsPDF()
                        } label: {
                            Label("Export as PDF", systemImage: "doc.fill")
                        }
                        
                        Button {
                            exportMatrixAsSpreadsheet()
                        } label: {
                            Label("Export as Spreadsheet", systemImage: "tablecells")
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export connection matrix")
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if canvasScale > 1.0 {
                        Menu {
                            Button {
                                isPanEnabled.toggle()
                            } label: {
                                Label(
                                    isPanEnabled ? "Pan Mode" : "Zoom Mode",
                                    systemImage: isPanEnabled ? "hand.draw" : "magnifyingglass"
                                )
                            }
                            
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    canvasScale = 1.0
                                    lastScale = 1.0
                                    isPanEnabled = false
                                }
                            } label: {
                                Label("Reset Zoom", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: isPanEnabled ? "hand.draw" : "magnifyingglass")
                        }
                    }
                }
            }
        }
        }
    }
    
    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption)
        }
    }
    
    private func ioSummary(for device: DeviceInstance) -> String {
        var parts: [String] = []
        
        // Analog I/O
        if device.audioInputsCount > 0 || device.audioOutputsCount > 0 {
            parts.append("Analog \(device.audioInputsCount)/\(device.audioOutputsCount)")
        }
        
        // ADAT
        let adatIn = device.adatInputPortsCount * 8
        let adatOut = device.adatOutputPortsCount * 8
        if adatIn > 0 || adatOut > 0 {
            parts.append("ADAT \(adatIn)/\(adatOut)")
        }
        
        // MADI
        let madiIn = device.madiInputPortsCount * 64
        let madiOut = device.madiOutputPortsCount * 64
        if madiIn > 0 || madiOut > 0 {
            parts.append("MADI \(madiIn)/\(madiOut)")
        }
        
        // Digital I/O (MIDI, S/PDIF, etc.) - exclude word clock as it's sync only
        var digitalIns = 0
        var digitalOuts = 0
        var hasWordClock = false
        for input in device.digitalInputs {
            switch input {
            case .spdif: digitalIns += 2
            case .aesebu: digitalIns += 2
            case .midi: digitalIns += 1
            case .wordClock: hasWordClock = true
            default: break
            }
        }
        for output in device.digitalOutputs {
            switch output {
            case .spdif: digitalOuts += 2
            case .aesebu: digitalOuts += 2
            case .midi: digitalOuts += 1
            case .wordClock: hasWordClock = true
            default: break
            }
        }
        if digitalIns > 0 || digitalOuts > 0 {
            parts.append("Digital \(digitalIns)/\(digitalOuts)")
        }
        
        // Word Clock (sync only, not audio channels)
        if hasWordClock {
            parts.append("WC")
        }
        
        return parts.isEmpty ? "I/O: Unknown" : parts.joined(separator: " • ")
    }
    
    @ViewBuilder
    private func connectionCell(from fromDevice: DeviceInstance, to toDevice: DeviceInstance) -> some View {
        let key = "\(fromDevice.id)_\(toDevice.id)"
        
        if let info = connectionMap[key] {
            // Has connection
            VStack(spacing: 2) {
                // Connection type indicator
                HStack(spacing: 2) {
                    ForEach(Array(info.types.prefix(3)), id: \.self) { type in
                        Circle()
                            .fill(type.color)
                            .frame(width: 8, height: 8)
                    }
                }
                
                // Channel count (audio only) and word clock indicator
                if info.channelCount > 0 {
                    Text("\(info.channelCount)ch")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 4) {
                    if info.hasWordClock {
                        Text("WC")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(3)
                    }
                    
                    // Bidirectional indicator
                    if info.hasReverseConnection {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
            }
            .frame(width: 100, height: 60)
            .background(info.types.first?.color.opacity(0.15) ?? Color.clear)
            .border(Color.secondary.opacity(0.3))
        } else if fromDevice.id == toDevice.id {
            // Diagonal - same device
            Rectangle()
                .fill(Color.secondary.opacity(0.05))
                .frame(width: 100, height: 60)
                .border(Color.secondary.opacity(0.3))
        } else {
            // No connection
            Rectangle()
                .fill(Color.clear)
                .frame(width: 100, height: 60)
                .border(Color.secondary.opacity(0.3))
        }
    }
    
    private func exportMatrixAsPDF() {
        // Create a printable version without zoom controls
        let printableMatrix = VStack(alignment: .leading, spacing: 0) {
            // Title
            Text("Connection Matrix: \(studio.name)")
                .font(.title)
                .fontWeight(.bold)
                .padding()
            
            // Matrix table
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("From \\ To")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(width: 120, height: 60, alignment: .center)
                        .background(Color(white: 0.15).opacity(0.2))
                        .border(Color.secondary.opacity(0.3))
                    
                    ForEach(toDevices, id: \.id) { device in
                        VStack(spacing: 2) {
                            Text(device.nickname)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(ioSummary(for: device))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 100, height: 60, alignment: .center)
                        .background(Color(white: 0.15).opacity(0.1))
                        .border(Color.secondary.opacity(0.3))
                    }
                }
                
                // Data rows
                ForEach(fromDevices, id: \.id) { fromDevice in
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            Text(fromDevice.nickname)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Text(ioSummary(for: fromDevice))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 120, height: 60, alignment: .center)
                        .background(Color(white: 0.15).opacity(0.1))
                        .border(Color.secondary.opacity(0.3))
                        
                        ForEach(toDevices, id: \.id) { toDevice in
                            connectionCell(from: fromDevice, to: toDevice)
                        }
                    }
                }
            }
            
            // Legend
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 20) {
                    Text("Legend:")
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    legendItem(color: ConnectionVisualType.analog.color, label: "Analog")
                    legendItem(color: ConnectionVisualType.digital.color, label: "Digital")
                    legendItem(color: ConnectionVisualType.midi.color, label: "MIDI")
                    legendItem(color: ConnectionVisualType.computer.color, label: "Computer")
                }
                HStack(spacing: 8) {
                    Text("WC")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(3)
                    Text("= Word Clock (sync only, not counted in I/O)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        
        #if os(iOS)
        let renderer = ImageRenderer(content: printableMatrix)
        renderer.scale = 2.0
        
        if let pdfData = renderer.pdf() {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectionMatrix.pdf")
            try? pdfData.write(to: tempURL)
            
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presentingVC = rootVC
                while let presented = presentingVC.presentedViewController {
                    presentingVC = presented
                }
                
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presentingVC.view
                    popover.sourceRect = CGRect(x: presentingVC.view.bounds.midX, y: presentingVC.view.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                presentingVC.present(activityVC, animated: true)
            }
        }
        #elseif os(macOS)
        let renderer = ImageRenderer(content: printableMatrix)
        renderer.scale = 2.0
        
        if let pdfData = renderer.pdf() {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.pdf]
            savePanel.nameFieldStringValue = "ConnectionMatrix.pdf"
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    try? pdfData.write(to: url)
                }
            }
        }
        #endif
    }
    
    private func exportMatrixAsSpreadsheet() {
        // Create HTML table with proper Excel XML namespace for compatibility
        var html = """
        <html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
        <head>
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
            <meta name="ProgId" content="Excel.Sheet">
            <meta name="Generator" content="Studio Guru">
            <!--[if gte mso 9]>
            <xml>
                <x:ExcelWorkbook>
                    <x:ExcelWorksheets>
                        <x:ExcelWorksheet>
                            <x:Name>Connection Matrix</x:Name>
                            <x:WorksheetOptions>
                                <x:Print>
                                    <x:ValidPrinterInfo/>
                                </x:Print>
                            </x:WorksheetOptions>
                        </x:ExcelWorksheet>
                    </x:ExcelWorksheets>
                </x:ExcelWorkbook>
            </xml>
            <![endif]-->
        </head>
        <body>
            <h1 style="font-family: Arial, sans-serif; font-size: 24px; margin: 20px 0;">Connection Matrix: \(studio.name)</h1>
            <table border="1" cellpadding="8" cellspacing="0" style="border-collapse: collapse; font-family: Arial, sans-serif;">
                <tr>
                    <th style="background-color: #d0d0d0; font-weight: bold; text-align: center; padding: 12px; border: 1px solid #999;">From \\ To</th>
        """
        
        // Column headers
        for device in toDevices {
            let ioSummaryText = ioSummary(for: device)
            html += """
                    <th style="background-color: #e8e8e8; font-weight: bold; text-align: center; padding: 12px; border: 1px solid #999; min-width: 150px;">\(device.nickname.htmlEscaped)<br><span style="font-size: 11px; color: #666; font-weight: normal;">\(ioSummaryText.htmlEscaped)</span></th>
            """
        }
        html += "</tr>\n"
        
        // Data rows
        for fromDevice in fromDevices {
            let fromIOSummary = ioSummary(for: fromDevice)
            html += """
                <tr>
                    <td style="background-color: #f0f0f0; font-weight: bold; text-align: left; padding: 12px; border: 1px solid #999;">\(fromDevice.nickname.htmlEscaped)<br><span style="font-size: 11px; color: #666; font-weight: normal;">\(fromIOSummary.htmlEscaped)</span></td>
            """
            
            for toDevice in toDevices {
                let key = "\(fromDevice.id)_\(toDevice.id)"
                
                if let info = connectionMap[key] {
                    // Has connection - use inline styles for colors
                    let primaryType = info.types.first ?? .unknown
                    let (bgColor, textColor): (String, String)
                    switch primaryType {
                    case .analog: 
                        bgColor = "#bbdefb"  // Light blue
                        textColor = "#0d47a1"  // Dark blue
                    case .digital: 
                        bgColor = "#c8e6c9"  // Light green
                        textColor = "#1b5e20"  // Dark green
                    case .midi: 
                        bgColor = "#e1bee7"  // Light purple
                        textColor = "#4a148c"  // Dark purple
                    case .computer: 
                        bgColor = "#ffe0b2"  // Light orange
                        textColor = "#e65100"  // Dark orange
                    case .unknown:
                        bgColor = "#f5f5f5"
                        textColor = "#666666"
                    }
                    
                    let typeNames = info.types.map { type -> String in
                        switch type {
                        case .analog: return "Analog"
                        case .digital: return "Digital"
                        case .midi: return "MIDI"
                        case .computer: return "Computer"
                        case .unknown: return "Unknown"
                        }
                    }.joined(separator: " + ")
                    
                    var cellContent = "<b>\(typeNames)</b>"
                    if info.channelCount > 0 {
                        cellContent += "<br>\(info.channelCount) ch"
                    }
                    if info.hasWordClock {
                        cellContent += "<br><span style=\"background-color: #ff9800; color: white; padding: 2px 6px; font-weight: bold; font-size: 10px;\">WC</span>"
                    }
                    
                    html += "<td style=\"background-color: \(bgColor); color: \(textColor); text-align: center; padding: 12px; border: 1px solid #999;\">\(cellContent)</td>"
                } else if fromDevice.id == toDevice.id {
                    // Diagonal - same device
                    html += "<td style=\"background-color: #f9f9f9; text-align: center; padding: 12px; border: 1px solid #999;\">—</td>"
                } else {
                    // No connection
                    html += "<td style=\"background-color: white; text-align: center; padding: 12px; border: 1px solid #999;\"></td>"
                }
            }
            html += "</tr>\n"
        }
        
        html += """
            </table>
            
            <br><br>
            <table border="0" cellpadding="8" style="font-family: Arial, sans-serif;">
                <tr><td colspan="4" style="font-weight: bold; font-size: 14px;">Legend:</td></tr>
                <tr>
                    <td style="background-color: #bbdefb; color: #0d47a1; padding: 8px 12px; font-weight: bold;">Analog</td>
                    <td style="background-color: #c8e6c9; color: #1b5e20; padding: 8px 12px; font-weight: bold;">Digital</td>
                    <td style="background-color: #e1bee7; color: #4a148c; padding: 8px 12px; font-weight: bold;">MIDI</td>
                    <td style="background-color: #ffe0b2; color: #e65100; padding: 8px 12px; font-weight: bold;">Computer</td>
                </tr>
                <tr>
                    <td colspan="4"><span style="background-color: #ff9800; color: white; padding: 2px 6px; font-weight: bold; font-size: 10px;">WC</span> = Word Clock (sync only, not counted in I/O)</td>
                </tr>
            </table>
        </body>
        </html>
        """
        
        let htmlData = Data(html.utf8)
        
        #if os(iOS)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectionMatrix.xls")
        try? htmlData.write(to: tempURL)
        
        let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presentingVC = rootVC
            while let presented = presentingVC.presentedViewController {
                presentingVC = presented
            }
            
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = presentingVC.view
                popover.sourceRect = CGRect(x: presentingVC.view.bounds.midX, y: presentingVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            presentingVC.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let savePanel = NSSavePanel()
        // Save as .html but Excel will recognize it due to proper XML namespace
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = "ConnectionMatrix.html"
        savePanel.message = "This HTML file will open directly in Excel"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? htmlData.write(to: url)
            }
        }
        #endif
    }
}

extension String {
    var htmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension ImageRenderer {
    @MainActor func pdf() -> Data? {
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            return nil
        }
        
        render { size, renderer in
            var mediaBox = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &mediaBox)
            renderer(context)
            context.endPage()
        }
        
        context.closePDF()
        
        return pdfData as Data
    }
}

private struct ConnectionInfo {
    let types: [ConnectionVisualType]
    let channelCount: Int
    let hasWordClock: Bool
    let hasReverseConnection: Bool  // Track if reverse direction also exists
}

// MARK: - Help View

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let helpItems: [(String, String)] = [
        ("1", "Create your first studio and name it"),
        ("2", "Add your devices and their manuals"),
        ("3", "Drag connections between devices"),
        ("4", "Click on the connections to define the details"),
        ("5", "Click on a device to review it, edit or delete"),
        ("6", "Long click on a device to see all its connection details"),
        ("7", "Hold or right click a connection to delete it"),
        ("8", "Press auto-arrange to tidy up the screen or drag devices manually"),
        ("9", "Use pinch gesture to zoom or expand device canvas as needed"),
        ("10", "Select Matrix to view a structured from→to diagram")
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Welcome header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Studio Guru")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Your studio connection management tool")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 8)
                    
                    Divider()
                    
                    // Help items
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Getting Started")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        ForEach(helpItems, id: \.0) { item in
                            HStack(alignment: .top, spacing: 12) {
                                // Number badge
                                Text(item.0)
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(Color.accentColor)
                                    )
                                
                                // Help text
                                Text(item.1)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Spacer()
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Working with the canvas
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Working with the canvas")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The canvas in Studio Guru Pro is designed to accommodate studios of any size with unlimited devices. A light grey border shows the current bounds of the canvas.")
                                .font(.body)
                            
                            Text("The canvas can be expanded by dragging devices to the right or downwards on the canvas. The top and the left borders are fixed points of reference.")
                                .font(.body)
                            
                            Text("The canvas can be displayed as a blank workspace or as a grid. Select the # icon to turn on the grid, define its size and to enable a \"snap to grid\" function to ease lining devices up.")
                                .font(.body)
                            
                            Text("There is an \"auto-arrange\" function that will place output devices towards the top of the screen (speakers for example), hub devices (the ones with the most connections such as audio interfaces) in the middle of the canvas, and input devices (such as a synth) at the bottom of the screen. It will also offset devices so they are not parallel to enable visibility of the connection lines.")
                                .font(.body)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Working with color
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Working with color")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The device categories (e.g. computer, mixer etc.) all have default colors set in the settings screen (the gearwheel). These can be edited there at a category level. However, any device can also be given an override color when it is set up or edited.")
                                .font(.body)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Working with annotations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Working with annotations")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("The app supports drawing with the Apple Pencil or your fingers. Annotations are great for educators who want to illustrate a point to audio students, or for studio engineers who simply want to make notes on a studio design. They are saved with the studio canvas but there is also a delete button that removes all annotations for a canvas.")
                                .font(.body)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Working with sessions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Working with sessions")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A studio is a foundational datapoint but as work is done, the studio will have additional equipment added or different connections made. For example, a live band setup will be very different from an in-the-box synth session. To capture a session, use the \"duplicate studio\" function and name the duplicate for the session. You then have your foundational studio design and your session notes saved for subsequent recall as needed.")
                                .font(.body)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()

                    // Free vs Pro
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Free vs Pro")
                            .font(.title2)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Studio Guru offers both a free version and a Pro upgrade:")
                                .font(.body)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("**Free Version**")
                                    .font(.headline)
                                Text("• Up to \(StoreManager.freeDeviceLimit) devices per studio")
                                    .font(.body)
                                Text("• \(StoreManager.freeStudioLimit) studio")
                                    .font(.body)
                                Text("• Local storage only (no iCloud sync)")
                                    .font(.body)
                                Text("• All other core features including annotations")
                                    .font(.body)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("**Pro Version**")
                                    .font(.headline)
                                Text("• Unlimited devices")
                                    .font(.body)
                                Text("• Unlimited studios")
                                    .font(.body)
                                Text("• iCloud sync across all devices")
                                    .font(.body)
                                Text("• Export and import studios")
                                    .font(.body)
                                Text("• Support ongoing development")
                                    .font(.body)
                            }

                            Text("Upgrade to Pro anytime from the Settings screen.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Additional tips
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tips")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Use iCloud sync to keep your studios in sync across devices", systemImage: "icloud")
                            Label("Export studios to share your configurations with others", systemImage: "square.and.arrow.up")
                            Label("Add device manuals for quick reference while working", systemImage: "doc")
                        }
                        .font(.body)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }
}
