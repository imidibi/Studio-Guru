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

struct StudioCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Studio.name, order: .forward) private var studios: [Studio]

    @State private var selectedStudioId: UUID?

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

    // Selection (devices/connections)
    @StateObject private var selectionState = SelectionState()
    // Connections (persisted in UserDefaults)
    @StateObject private var connectionsStore = ConnectionsStore()

    @State private var isShowingConnectionsEditor: Bool = false
    @State private var connectionEditorLinkId: UUID? = nil

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

    @State private var draftSupportPageURL: String = ""
    @State private var draftDownloadsPageURL: String = ""

    @State private var draftAudioInputs: Int = 0
    @State private var draftAudioOutputs: Int = 0
    @State private var draftAdatInputPorts: Int = 0
    @State private var draftAdatOutputPorts: Int = 0
    @State private var draftMadiInputPorts: Int = 0
    @State private var draftMadiOutputPorts: Int = 0
    @State private var draftSampleRate: SampleRate =
        SampleRate.allCases.first ?? SampleRate(rawValue: 0)!

    @State private var draftDigitalInputs: Set<DigitalFormat> = []
    @State private var draftDigitalOutputs: Set<DigitalFormat> = []
    /// Quantities for host interfaces (USB/Thunderbolt/Ethernet etc.).
    @State private var draftComputerInterfaceCounts: [ComputerInterface: Int] =
        [:]
    @State private var deviceEditorError: String? = nil

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

    // When saving from the device editor we often set selection to the saved device.
    // That should NOT immediately pop the inspector overlay.
    @State private var suppressNextInspectorPresentation: Bool = false

    // Delete connection confirm
    @State private var isShowingDeleteConnectionConfirm: Bool = false
    @State private var connectionPendingDelete: Connection? = nil

    var body: some View {
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
        .onAppear {
            // Set up model context for ConnectionsStore (enables iCloud sync)
            connectionsStore.setModelContext(modelContext)
            
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
            if let sid = selectedStudioId,
                let studio = studios.first(where: { $0.id == sid })
            {
                // One-time migration: fix computer interface port types without breaking connections
                fixComputerInterfacePortTypes(in: studio)
                connectionsStore.load(studioId: sid)
                connectionsStore.cleanupOrphanedConnections(studio: studio)
            }
        }
        .onChange(of: selectedStudioId) { _, newValue in
            selectionState.selection = nil
            if let sid = newValue,
                let studio = studios.first(where: { $0.id == sid })
            {
                // Fix computer interface port types when switching studios
                fixComputerInterfacePortTypes(in: studio)
                connectionsStore.load(studioId: sid)
                connectionsStore.cleanupOrphanedConnections(studio: studio)
            }
        }
    }

    // MARK: - Sidebar
    // Removed - replaced with StudiosList subview

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let studio = currentStudio {
                studioDetailView(studio)
            } else {
                noStudioSelectedView
            }
        }
        .toolbar {
            // Left side: New Studio + Duplicate
            ToolbarItem(placement: .navigation) {
                Button {
                    newStudioNameDraft = "My Studio"
                    isShowingNewStudioPrompt = true
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
                    Button {
                        autoArrangeDevices(in: studio)
                    } label: {
                        Label("Auto-Arrange", systemImage: "square.grid.3x2")
                    }
                    .help("Automatically arrange devices by signal flow")
                }
                
                ToolbarItem(placement: .navigation) {
                    Button {
                        exportCanvasAsPDF(studio: studio)
                    } label: {
                        Label("Export Canvas", systemImage: "photo")
                    }
                    .help("Export studio canvas as PDF")
                }
                
                ToolbarItem(placement: .navigation) {
                    Button {
                        isShowingMatrixView.toggle()
                    } label: {
                        Label("Connection Matrix", systemImage: "tablecells")
                    }
                    .help("View connections in spreadsheet format")
                }
                
                ToolbarItem(placement: .navigation) {
                    Button {
                        isShowingHelp = true
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                    .help("How to use Studio Guru")
                }
                
                ToolbarItem(placement: .navigation) {
                    Button {
                        isShowingGuru = true
                    } label: {
                        Label("Guru", systemImage: "lightbulb")
                    }
                    .help("Quick setup suggestions for common devices")
                }
            }

            // Right side: Import, Export, Delete, Settings
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a studio from file")
            }

            if let studio = currentStudio {
                ToolbarItem(placement: .automatic) {
                    Button {
                        exportStudio(studio)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export this studio to share with others")
                }

                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        studioIdPendingDelete = studio.id
                        isShowingDeleteStudioConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .help("Delete this studio")
                    #if os(macOS)
                        .keyboardShortcut(.delete, modifiers: [])
                    #endif
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("App settings and sync information")
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

    private func studioDetailBase(for studio: Studio) -> some View {
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
                    isShowingConnectionsEditor = true
                },
                onRequestDeleteLink: { link in
                    connectionEditorLinkId = link.id
                    isShowingDeleteConnectionConfirm = true
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
                canvasSize: $canvasSize
            )
            .environmentObject(selectionState)
        }
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
            ConnectionsDialogView(
                studio: studio,
                fromDeviceId: bundle.fromDeviceId,
                toDeviceId: bundle.toDeviceId,
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
                supportPageURL: $draftSupportPageURL,
                downloadsPageURL: $draftDownloadsPageURL,
                audioInputs: $draftAudioInputs,
                audioOutputs: $draftAudioOutputs,
                adatInputPorts: $draftAdatInputPorts,
                adatOutputPorts: $draftAdatOutputPorts,
                madiInputPorts: $draftMadiInputPorts,
                madiOutputPorts: $draftMadiOutputPorts,
                sampleRate: $draftSampleRate,
                digitalInputs: $draftDigitalInputs,
                digitalOutputs: $draftDigitalOutputs,
                computerInterfaceCounts: $draftComputerInterfaceCounts,
                errorMessage: $deviceEditorError,
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
        if let first = SampleRate.allCases.first { draftSampleRate = first }
        draftDigitalInputs = []
        draftDigitalOutputs = []
        draftComputerInterfaceCounts = [:]

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

        draftSupportPageURL = d.supportPageURLString ?? ""
        draftDownloadsPageURL = d.downloadsPageURLString ?? ""

        draftAudioInputs = max(0, d.audioInputsCount)
        draftAudioOutputs = max(0, d.audioOutputsCount)
        draftAdatInputPorts = max(0, d.adatInputPortsCount)
        draftAdatOutputPorts = max(0, d.adatOutputPortsCount)
        draftMadiInputPorts = max(0, d.madiInputPortsCount)
        draftMadiOutputPorts = max(0, d.madiOutputPortsCount)
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
    @MainActor
    private func saveDeviceEdits(into studio: Studio) {
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

        // Warn if another device in this studio already uses the same serial number
        if !serialNumber.isEmpty {
            let duplicate = studio.devices?.first { other in
                other.serialNumber.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .localizedCaseInsensitiveCompare(serialNumber) == .orderedSame
                    && other.id != editingDeviceId
            }

            if duplicate != nil {
                deviceEditorError =
                    "Another device in this studio already uses this serial number."
                return
            }
        }

        let device: DeviceInstance
        if let id = editingDeviceId,
            let existing = studio.devices?.first(where: { $0.id == id })
        {
            device = existing
        } else {
            let pos = findAvailableDevicePosition(
                in: studio,
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
            if studio.devices == nil {
                studio.devices = []
            }
            studio.devices?.append(device)
        }

        device.nickname = nickname
        if !manufacturer.isEmpty { device.manufacturer = manufacturer }
        device.model = productId
        device.category = draftCategory
        device.serialNumber = serialNumber
        device.location = location

        device.supportPageURLString = supportURL.isEmpty ? nil : supportURL
        device.downloadsPageURLString =
            downloadsURL.isEmpty ? nil : downloadsURL
        device.audioInputsCount = max(0, draftAudioInputs)
        device.audioOutputsCount = max(0, draftAudioOutputs)
        device.adatInputPortsCount = max(0, draftAdatInputPorts)
        device.adatOutputPortsCount = max(0, draftAdatOutputPorts)
        device.madiInputPortsCount = max(0, draftMadiInputPorts)
        device.madiOutputPortsCount = max(0, draftMadiOutputPorts)
        device.sampleRateRaw = draftSampleRate.rawValue
        device.digitalInputs = Array(draftDigitalInputs)
        device.digitalOutputs = Array(draftDigitalOutputs)
        device.computerInterfaces = expandComputerInterfaces(
            from: draftComputerInterfaceCounts
        )

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
            computerInterfaceCounts: device.computerInterfaceCounts,
            sampleRate: draftSampleRate
        )

        // Keep selection for highlighting, but do not pop the inspector immediately after saving.
        suppressNextInspectorPresentation = true
        selectionState.selection = .device(device.id)
        isShowingDeviceEditor = false
    }

    private func deletePendingDevice() {
        guard let studio = currentStudio else { return }
        guard let id = deviceIdPendingDelete else { return }
        guard let idx = studio.devices?.firstIndex(where: { $0.id == id }) else {
            return
        }

        studio.devices?.remove(at: idx)
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
        selectionState.selection = .device(newDevice.id)
    }

    private func moveDevice(
        _ device: DeviceInstance,
        from source: Studio,
        to destination: Studio
    ) {
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
                ports.append(
                    digitalPort(
                        type: .midiIn,
                        name: "MIDI In",
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
                ports.append(
                    digitalPort(
                        type: .midiOut,
                        name: "MIDI Out",
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
        let copy = Studio(name: "\(source.name) Copy")
        for d in source.devices ?? [] {
            let newDevice = DeviceInstance(
                manufacturer: d.manufacturer,
                model: d.model,
                nickname: d.nickname,
                posX: d.posX + 30,
                posY: d.posY + 30,
                scale: d.scale,
                zIndex: d.zIndex
            )
            newDevice.frontImagePath = d.frontImagePath
            newDevice.rearImagePath = d.rearImagePath

            for p in d.ports ?? [] {
                let newPort = Port(
                    name: p.name,
                    type: p.type,
                    direction: p.direction
                )
                for ch in p.channels ?? [] {
                    if newPort.channels == nil {
                        newPort.channels = []
                    }
                    newPort.channels?.append(
                        Channel(
                            index: ch.index,
                            nameLong: ch.nameLong,
                            nameShort: ch.nameShort,
                            signal: ch.signal,
                            grouping: ch.grouping
                        )
                    )
                }
                if newDevice.ports == nil {
                    newDevice.ports = []
                }
                newDevice.ports?.append(newPort)
            }

            if copy.devices == nil {
                copy.devices = []
            }
            copy.devices?.append(newDevice)
        }

        modelContext.insert(copy)
        selectedStudioId = copy.id
    }

    private func exportStudio(_ studio: Studio) {
        // First, sync connections from ConnectionsStore to SwiftData
        syncConnectionsToSwiftData(studio: studio)

        // Create exportable representation
        let exportable = ExportableStudio(from: studio)

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
                                print(
                                    "    ✅ FIXING port '\(expectedName)' from \(port.type.rawValue) to \(correctPortType.rawValue)"
                                )
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
                        print(
                            "  ✅ FIXING MIDI port '\(port.name)' from \(port.type.rawValue) to \(expectedType.rawValue)"
                        )
                        port.typeRaw = expectedType.rawValue
                    }
                }
            }
        }
    }
    
    private func exportCanvasAsPDF(studio: Studio) {
        guard let devices = studio.devices, !devices.isEmpty else { return }
        
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
                    
                    // Determine connection color based on connection type
                    let connectionColor: Color = {
                        // Get the first edge to determine connection type
                        guard let firstEdge = bundle.edges.first,
                              let device = devices.first(where: { $0.id == firstEdge.from.deviceId }) else {
                            return ConnectionVisualType.unknown.color
                        }
                        
                        // Check for regular ports first
                        if let port = device.ports?.first(where: { $0.id == firstEdge.from.portId }) {
                            return ConnectionVisualType.from(portType: port.type).color
                        }
                        
                        // Check for computer interface (virtual port)
                        if !device.computerInterfaceCounts.isEmpty {
                            return ConnectionVisualType.computer.color
                        }
                        
                        return ConnectionVisualType.unknown.color
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
                        path.move(to: from)
                        path.addLine(to: to)
                    }
                    .stroke(connectionColor, lineWidth: 2)
                }
            }
            
            // Draw devices
            ForEach(devices, id: \.id) { device in
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
                .background(Color.white)
                .cornerRadius(8)
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
        let renderer = ImageRenderer(content: fullView)
        renderer.scale = 2.0
        
        if let pdfData = renderer.pdf() {
            let filename = "\(studio.name.replacingOccurrences(of: " ", with: "_"))_Canvas.pdf"
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
            }
        }
        #endif
    }

    private func autoArrangeDevices(in studio: Studio) {
        guard !(studio.devices?.isEmpty ?? true) else { return }

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
        for (levelIndex, level) in sortedLevels.enumerated() {
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
        
        // Find column range
        let minColumn = deviceColumns.values.min() ?? 0
        let maxColumn = deviceColumns.values.max() ?? 0
        let columnRange = maxColumn - minColumn + 1
        
        // Calculate total width needed
        let totalWidth = Double(columnRange) * finalCardWidth + Double(max(0, columnRange - 1)) * finalHorizontalSpacing
        let startX = padding + (targetWidth - totalWidth) / 2 + halfCardWidth
        
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

        // Save changes
        try? modelContext.save()
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
                    print("⚠️ Skipping invalid connection:")
                    if !fromDeviceValid { print("  - fromDevice ID not found: \(edge.from.deviceId)") }
                    if !toDeviceValid { print("  - toDevice ID not found: \(edge.to.deviceId)") }
                    if !fromPortValid { print("  - fromPort ID not found: \(edge.from.portId)") }
                    if !toPortValid { print("  - toPort ID not found: \(edge.to.portId)") }
                    if !fromChannelValid { print("  - fromChannel ID not found: \(edge.from.channelId)") }
                    if !toChannelValid { print("  - toChannel ID not found: \(edge.to.channelId)") }
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

        // Log summary
        print("✅ syncConnectionsToSwiftData complete:")
        print("   Valid connections: \(validCount)")
        print("   Invalid connections: \(invalidCount)")
        
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

            // Save to model context
            modelContext.insert(studio)
            try modelContext.save()

            // Rebuild ConnectionsStore from the imported connections
            connectionsStore.rebuildFromConnections(studio: studio)

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

    return parts.isEmpty ? "I/O: Unknown" : parts.joined(separator: " • ")
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
                text: .init(get: { studio.name }, set: { studio.name = $0 })
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
    let onExplodeDevice: (DeviceInstance) -> Void
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
            onExplodeDevice: onExplodeDevice,
            isExplosionEnabled: isExplosionEnabled
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
            Section("Studios") {
                ForEach(studios, id: \.id) { studio in
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
                        studios.indices.contains(first)
                    {
                        onRequestDelete(studios[first])
                    }
                }
            }
        }
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
    let onExplodeDevice: (DeviceInstance) -> Void
    let isExplosionEnabled: Bool
    @EnvironmentObject var selection: SelectionState

    @State private var dragOrigin: (id: UUID, x: Double, y: Double)?
    @State private var activeConnectionDrag:
        (fromId: UUID, start: CGPoint, location: CGPoint)? = nil
    @State private var hoveredConnectionTargetId: UUID? = nil
    @State private var connectionHandleTips: [UUID: CGPoint] = [:]
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var isPanEnabled: Bool = false

    private var links: [ConnectionLinkSummary] {
        connectionsStore.links(for: studio.id)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Rectangle().fill(background)

                        ForEach(links, id: \.id) { link in
                            linkRow(link)
                        }

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
                    .frame(
                        width: geo.size.width * 1.5,
                        height: geo.size.height * 1.5
                    )
                    .scaleEffect(canvasScale, anchor: .center)
                    .frame(
                        width: geo.size.width * 1.5 * canvasScale,
                        height: geo.size.height * 1.5 * canvasScale
                    )
                    .onChange(of: canvasScale) { _, newValue in
                        // print("🔍 Canvas scale changed to: \(newValue)")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isPanEnabled {
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
                .scrollDisabled(!isPanEnabled)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if !isPanEnabled {
                                canvasScale = lastScale * value
                            }
                        }
                        .onEnded { value in
                            if !isPanEnabled {
                                // Clamp scale between 0.5x and 3x
                                canvasScale = min(
                                    max(lastScale * value, 0.5),
                                    3.0
                                )
                                lastScale = canvasScale

                                // Auto-enable pan mode when zoomed in
                                if canvasScale > 1.0 {
                                    isPanEnabled = true
                                }
                            }
                        }
                )

                // Pan mode toggle button - shown when zoomed
                if canvasScale > 1.0 {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                isPanEnabled.toggle()
                            }) {
                                HStack(spacing: 6) {
                                    Image(
                                        systemName: isPanEnabled
                                            ? "hand.draw.fill"
                                            : "magnifyingglass"
                                    )
                                    Text(
                                        isPanEnabled ? "Pan Mode" : "Zoom Mode"
                                    )
                                }
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    .ultraThickMaterial,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .padding()
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ link: ConnectionLinkSummary) -> some View {
        ConnectionLineRow(
            link: link,
            studio: studio,
            connectionsStore: connectionsStore,
            handleTips: connectionHandleTips,
            isSelected: isSelectedConnection(linkId: link.id),
            onSelect: { onSelectLink(link) },
            onDelete: { onRequestDeleteLink(link) }
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
            dragOrigin: $dragOrigin,
            beginDragIfNeeded: { device in
                if dragOrigin?.id != device.id {
                    dragOrigin = (device.id, device.posX, device.posY)
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

    @Binding var dragOrigin: (id: UUID, x: Double, y: Double)?
    let beginDragIfNeeded: (DeviceInstance) -> Void
    let onBeginConnectionDrag: (DeviceInstance, CGPoint) -> Void
    let onUpdateConnectionDrag: (DeviceInstance, CGPoint) -> Void
    let onEndConnectionDrag: () -> Void

    @EnvironmentObject var selection: SelectionState
    @State private var isDraggingConnection: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                    lineWidth: isSelected ? 3 : 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
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
            DeviceConnectionHandle(deviceId: device.id)
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
                    // No clamping - devices can be positioned anywhere for scrolling
                    let newX = origin.x + Double(v.translation.width)
                    let newY = origin.y + Double(v.translation.height)

                    device.posX = newX
                    device.posY = newY
                }
                .onEnded { _ in
                    dragOrigin = nil
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
                                LabeledContent("Support Page") {
                                    Link(url.absoluteString, destination: url)
                                        .lineLimit(1)
                                }
                            }

                            if let url = d.downloadsPageURL {
                                LabeledContent("Downloads Page") {
                                    Link(url.absoluteString, destination: url)
                                        .lineLimit(1)
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
                                        // print("📱 Manual tapped: \(doc.title)")
                                        // print("📱 Has bookmark: \(doc.localBookmarkData != nil)")
                                        // print("📱 Has URL string: \(doc.urlString != nil)")

                                        // Try bookmark first, fall back to URL string for legacy docs
                                        if let bookmarkData = doc
                                            .localBookmarkData
                                        {
                                            // print("📱 Attempting to resolve bookmark...")
                                            do {
                                                let url =
                                                    try ManualStorage
                                                    .resolveBookmark(
                                                        bookmarkData
                                                    )
                                                // print("📱 ✅ Bookmark resolved to: \(url.path)")
                                                manualViewerItem =
                                                    IdentifiableURL(url: url)
                                            } catch {
                                                print(
                                                    "📱 ❌ Bookmark resolution failed: \(error)"
                                                )
                                            }
                                        } else if let urlString = doc.urlString,
                                            let url = URL(string: urlString)
                                        {
                                            // print("📱 Using legacy URL string: \(urlString)")
                                            manualViewerItem = IdentifiableURL(
                                                url: url
                                            )
                                        } else {
                                            print(
                                                "📱 ❌ No bookmark or URL available"
                                            )
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
                                $0.id == id
                            })
                        else { return }

                        do {
                            let (storedURL, bookmarkData) =
                                try ManualStorage.copyPDFIntoAppSupport(
                                    pickedURL: pickedURL,
                                    deviceId: device.id
                                )

                            let doc = DocLink(
                                title: storedURL.lastPathComponent,
                                kind: .manual,
                                bookmarkData: bookmarkData
                            )
                            if device.docs == nil {
                                device.docs = []
                            }
                            device.docs?.append(doc)
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                        .fullScreenCover(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.url.lastPathComponent
                            )
                        }
                    #else
                        .sheet(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.url.lastPathComponent
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

// MARK: - Connection Line Row Helper

private struct ConnectionLineRow: View {
    let link: ConnectionLinkSummary
    let studio: Studio
    let connectionsStore: ConnectionsStore
    let handleTips: [UUID: CGPoint]
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

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
        (types: [ConnectionVisualType], channelCount: Int)
    {
        // Get the connection bundle from ConnectionsStore (UserDefaults-based storage)
        guard
            let bundle = connectionsStore.bundle(
                for: studio.id,
                linkId: link.id
            )
        else {
            // print("⚠️ No bundle found for link \(link.id)")
            return ([.unknown], 1)
        }

        // print("🔍 Analyzing bundle with \(bundle.edges.count) edges")

        guard !bundle.edges.isEmpty else {
            // print("⚠️ Bundle has no edges")
            return ([.unknown], 1)
        }

        // Count connections by type
        var typeCounts: [ConnectionVisualType: Int] = [:]
        var portsNotFound = 0

        for edge in bundle.edges {
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

        return (types, totalChannels)
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
                    isSelected: isSelected,
                    connectionTypes: metadata.types,
                    channelCount: metadata.channelCount
                )
                // IMPORTANT: give the line a full-size layout box so macOS can attach a context menu
                // while hit-testing still remains constrained to the stroked curve via ConnectionLineView.contentShape.
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
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
                .onLongPressGesture {
                    onDelete()
                }
                // Right-click on macOS / long-press menu on iOS (kept for discoverability)
                .contextMenu {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete Connection", systemImage: "trash")
                    }
                }
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

private struct ConnectionLineView: View {
    let from: CGPoint
    let to: CGPoint
    let isSelected: Bool
    var connectionTypes: [ConnectionVisualType] = [.unknown]
    var channelCount: Int = 1

    private var path: Path {
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

    // Linear gradient for multi-type connections
    private var lineGradient: LinearGradient? {
        guard !isSelected && connectionTypes.count > 1 else { return nil }
        let colors = connectionTypes.map { $0.color.opacity(0.7) }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .leading,
            endPoint: .trailing
        )
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
        let arrowLength: CGFloat = lineWidth * 3

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

    // Generate arrowheads (one or two depending on directionality)
    private func arrowheads() -> Path {
        var arrows = Path()
        
        let dx = to.x - from.x
        let dy = to.y - from.y
        let distance = sqrt(dx * dx + dy * dy)

        if isBidirectional {
            // Two arrows positioned along the actual line
            // For bidirectional, place them at 35% and 65% of total distance
            let normalizedDx = dx / distance
            let normalizedDy = dy / distance
            
            let point1 = CGPoint(
                x: from.x + normalizedDx * distance * 0.35,
                y: from.y + normalizedDy * distance * 0.35
            )
            let angle1 = atan2(dy, dx)
            arrows.addPath(makeArrow(at: point1, angle: angle1))
            
            let point2 = CGPoint(
                x: from.x + normalizedDx * distance * 0.65,
                y: from.y + normalizedDy * distance * 0.65
            )
            let angle2 = atan2(dy, dx) + .pi  // Reverse direction
            arrows.addPath(makeArrow(at: point2, angle: angle2))
        } else {
            // Single arrow at midpoint
            let midPoint = CGPoint(
                x: from.x + dx * 0.5,
                y: from.y + dy * 0.5
            )
            let angle = atan2(dy, dx)
            arrows.addPath(makeArrow(at: midPoint, angle: angle))
        }

        return arrows
    }

    var body: some View {
        ZStack {
            // Wide invisible stroke for easy hit-testing
            path
                .stroke(
                    Color.clear,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )

            // Visible line (gradient if multiple types, solid color otherwise)
            if let gradient = lineGradient {
                path
                    .stroke(
                        gradient,
                        style: StrokeStyle(
                            lineWidth: isSelected ? lineWidth + 1 : lineWidth,
                            lineCap: .round
                        )
                    )
            } else {
                path
                    .stroke(
                        lineColor,
                        style: StrokeStyle(
                            lineWidth: isSelected ? lineWidth + 1 : lineWidth,
                            lineCap: .round
                        )
                    )
            }

            // Arrowhead(s) showing signal direction
            arrowheads()
                .stroke(
                    lineColor,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
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

    var body: some View {
        Image(systemName: "arrow.up.arrow.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Color.accentColor.opacity(0.8))
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.15))
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
        case .digitalMixer: return "music.mic"
        case .effectsUnit: return "sparkles"
        case .equalizer: return "slider.horizontal.3"
        case .keyboard: return "pianokeys"
        case .midiDevice: return "pianokeys.inverse"
        case .mixer: return "dial.medium"
        case .multi: return "square.stack.3d.up"
        case .patchbay: return "square.grid.3x3"
        case .preamp: return "waveform.circle"
        case .usbHub: return "hub"
        case .usbExpander: return "rectangle.connected.to.line.below"
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

    @Binding var supportPageURL: String
    @Binding var downloadsPageURL: String

    @Binding var audioInputs: Int
    @Binding var audioOutputs: Int
    @Binding var adatInputPorts: Int
    @Binding var adatOutputPorts: Int
    @Binding var madiInputPorts: Int
    @Binding var madiOutputPorts: Int
    @Binding var sampleRate: SampleRate

    @Binding var digitalInputs: Set<DigitalFormat>
    @Binding var digitalOutputs: Set<DigitalFormat>
    @Binding var computerInterfaceCounts: [ComputerInterface: Int]

    @Binding var errorMessage: String?

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
                                                } else {
                                                    digitalInputs.remove(f)
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
                                                } else {
                                                    digitalOutputs.remove(f)
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
            #else
                Form {
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
                                        } else {
                                            digitalInputs.remove(f)
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
                                        } else {
                                            digitalOutputs.remove(f)
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

                    if let errorMessage {
                        Section {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
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
                                LabeledContent("Support Page") {
                                    Link(url.absoluteString, destination: url)
                                        .lineLimit(1)
                                }
                            }

                            if let url = d.downloadsPageURL {
                                LabeledContent("Downloads Page") {
                                    Link(url.absoluteString, destination: url)
                                        .lineLimit(1)
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
                                        // print("📱 Manual tapped: \(doc.title)")
                                        // print("📱 Has bookmark: \(doc.localBookmarkData != nil)")
                                        // print("📱 Has URL string: \(doc.urlString != nil)")

                                        // Try bookmark first, fall back to URL string for legacy docs
                                        if let bookmarkData = doc
                                            .localBookmarkData
                                        {
                                            // print("📱 Attempting to resolve bookmark...")
                                            do {
                                                let url =
                                                    try ManualStorage
                                                    .resolveBookmark(
                                                        bookmarkData
                                                    )
                                                // print("📱 ✅ Bookmark resolved to: \(url.path)")
                                                manualViewerItem =
                                                    IdentifiableURL(url: url)
                                            } catch {
                                                print(
                                                    "📱 ❌ Bookmark resolution failed: \(error)"
                                                )
                                            }
                                        } else if let urlString = doc.urlString,
                                            let url = URL(string: urlString)
                                        {
                                            // print("📱 Using legacy URL string: \(urlString)")
                                            manualViewerItem = IdentifiableURL(
                                                url: url
                                            )
                                        } else {
                                            print(
                                                "📱 ❌ No bookmark or URL available"
                                            )
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

                            let doc = DocLink(
                                title: storedURL.lastPathComponent,
                                kind: .manual,
                                bookmarkData: bookmarkData
                            )
                            if device.docs == nil {
                                device.docs = []
                            }
                            device.docs?.append(doc)
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                        .fullScreenCover(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.url.lastPathComponent
                            )
                        }
                    #else
                        .sheet(item: $manualViewerItem) { item in
                            ManualPDFViewer(
                                url: item.url,
                                title: item.url.lastPathComponent
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
                        description: "USB, Thunderbolt, Ethernet (two arrows)"
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
    
    private var links: [ConnectionLinkSummary] {
        connectionsStore.links(for: studio.id)
    }
    
    // Build a map of device pairs to their connection info
    private var connectionMap: [String: ConnectionInfo] {
        var map: [String: ConnectionInfo] = [:]
        
        for link in links {
            guard let bundle = connectionsStore.bundle(for: studio.id, linkId: link.id),
                  !bundle.edges.isEmpty else { continue }
            
            let key = "\(link.fromDeviceId)_\(link.toDeviceId)"
            
            // Analyze connection types and channel count
            var typeCounts: [ConnectionVisualType: Int] = [:]
            var uniqueChannels: Set<String> = []  // Track unique from.channelId (audio only)
            var hasWordClock = false
            
            for edge in bundle.edges {
                if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                   let port = device.ports?.first(where: { $0.id == edge.from.portId }) {
                    let visualType = ConnectionVisualType.from(portType: port.type)
                    typeCounts[visualType, default: 0] += 1
                    
                    // Word clock is sync only - don't count as audio channel
                    if port.type == .wordClockIn || port.type == .wordClockOut {
                        hasWordClock = true
                    } else {
                        // Count unique audio channels (avoid counting duplicates)
                        uniqueChannels.insert(edge.from.channelId.uuidString)
                    }
                } else if let device = studio.devices?.first(where: { $0.id == edge.from.deviceId }),
                          !device.computerInterfaceCounts.isEmpty {
                    // Computer interface virtual port
                    typeCounts[.computer, default: 0] += 1
                    uniqueChannels.insert(edge.from.channelId.uuidString)
                }
            }
            
            let types = typeCounts.sorted { $0.value > $1.value }.map { $0.key }
            // Use unique channel count if available, otherwise fall back to edge count
            let channelCount = uniqueChannels.isEmpty ? bundle.edges.count : uniqueChannels.count
            map[key] = ConnectionInfo(
                types: types.isEmpty ? [.unknown] : types,
                channelCount: channelCount,
                hasWordClock: hasWordClock
            )
        }
        
        return map
    }
    
    var body: some View {
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
                            ForEach(studio.devices ?? [], id: \.id) { device in
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
                        ForEach(studio.devices ?? [], id: \.id) { fromDevice in
                            HStack(spacing: 0) {
                                // Row header (source device)
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
                                
                                // Connection cells
                                ForEach(studio.devices ?? [], id: \.id) { toDevice in
                                    connectionCell(from: fromDevice, to: toDevice)
                                }
                            }
                        }
                    }
                    .padding()
                    .scaleEffect(canvasScale, anchor: .center)
                }
                .scrollDisabled(!isPanEnabled)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if !isPanEnabled {
                                canvasScale = lastScale * value
                            }
                        }
                        .onEnded { value in
                            if !isPanEnabled {
                                // Clamp scale between 0.5x and 5x
                                canvasScale = min(
                                    max(lastScale * value, 0.5),
                                    5.0
                                )
                                lastScale = canvasScale
                                
                                // Auto-enable pan mode when zoomed in
                                if canvasScale > 1.0 {
                                    isPanEnabled = true
                                }
                            }
                        }
                )
                
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
                    Button {
                        exportMatrixAsPDF()
                    } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .help("Export connection matrix as PDF")
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
                if info.hasWordClock {
                    Text("WC")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(3)
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
                    
                    ForEach(studio.devices ?? [], id: \.id) { device in
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
                ForEach(studio.devices ?? [], id: \.id) { fromDevice in
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
                        
                        ForEach(studio.devices ?? [], id: \.id) { toDevice in
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
}

// MARK: - Help View

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    private let helpItems: [(String, String)] = [
        ("1", "Add your devices and their manuals"),
        ("2", "Drag connections between devices"),
        ("3", "Click on the connections to define the details"),
        ("4", "Click on a device to review it, edit or delete"),
        ("5", "Long click on a device to see all its connection details"),
        ("6", "Hold or right click a connection to delete it"),
        ("7", "Press auto-arrange to tidy up the screen or drag devices manually"),
        ("8", "Select Matrix to view a structured from→to diagram")
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
