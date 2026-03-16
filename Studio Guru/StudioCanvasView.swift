//
//  StudioCanvasView.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import SwiftUI
import Combine

import SwiftData
import UniformTypeIdentifiers
import CryptoKit


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
    @State private var draftSampleRate: SampleRate = SampleRate.allCases.first ?? SampleRate(rawValue: 0)!

    @State private var draftDigitalInputs: Set<DigitalFormat> = []
    @State private var draftDigitalOutputs: Set<DigitalFormat> = []
    /// Quantities for host interfaces (USB/Thunderbolt/Ethernet etc.).
    @State private var draftComputerInterfaceCounts: [ComputerInterface: Int] = [:]
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
                let trimmed = newStudioNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = trimmed.isEmpty ? "My Studio" : trimmed

                let s = Studio(name: name)
                // If the model has createdAt, ensure it’s set so @Query sorting works.
                // (This is safe even if Studio doesn’t use createdAt; the compiler will tell us and we can remove it.)
                // swiftlint:disable:next unused_optional_binding
                if let _ = Optional.some(s) as Studio? {
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
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Name your studio.")
        }
        .alert("Delete Studio", isPresented: $isShowingDeleteStudioConfirm) {
            Button("Delete", role: .destructive) { deletePendingStudio() }
            Button("Cancel", role: .cancel) { studioIdPendingDelete = nil }
        } message: {
            if let studio = studioPendingDelete, !studio.devices.isEmpty {
                Text("This studio has \(studio.devices.count) device(s). Deleting it will permanently delete the studio and all its devices and connections.")
            } else {
                Text("This studio will be permanently deleted.")
            }
        }
        .alert("Export", isPresented: $isShowingExportResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportResultMessage)
        }
        .alert("Studio Name Conflict", isPresented: $isShowingImportNameConflict) {
            Button("Replace Existing", role: .destructive) {
                // Delete existing studio with same name and import with original name
                if let existingStudio = studios.first(where: { $0.name == importConflictStudioName }) {
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
            Text("A studio named '\(importConflictStudioName)' already exists. Do you want to replace it or import with a different name?")
        }
        .sheet(isPresented: $isShowingGuru) {
            GuruHomeView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
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
            if selectedStudioId == nil {
                selectedStudioId = studios.first?.id
            }
            if let sid = selectedStudioId {
                connectionsStore.load(studioId: sid)
            }
        }
        .onChange(of: selectedStudioId) { _, newValue in
            selectionState.selection = nil
            if let sid = newValue {
                connectionsStore.load(studioId: sid)
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
            ToolbarItem(placement: .automatic) {
                Button {
                    newStudioNameDraft = "My Studio"
                    isShowingNewStudioPrompt = true
                } label: {
                    Label("New Studio", systemImage: "plus")
                }
                .help("Create a new studio")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingGuru = true
                } label: {
                    Label("Guru", systemImage: "sparkles")
                }
                .help("Open Guru assistant for device recommendations")
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingImportPicker = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a studio from file")
            }
            
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .help("App settings and sync information")
            }

            if let studio = currentStudio {
                ToolbarItem(placement: .automatic) {
                    Button { duplicateStudio(from: studio) } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .help("Duplicate this studio")
                }

                ToolbarItem(placement: .automatic) {
                    Button { exportStudio(studio) } label: {
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
            .sheet(isPresented: $isShowingConnectionExplosion, onDismiss: {
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
            }) {
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
                        guard let id = presentedInspectorDeviceId else { return nil }
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
            .alert("Delete Device", isPresented: $isShowingDeleteDeviceConfirm) {
                Button("Delete", role: .destructive) { deletePendingDevice() }
                Button("Cancel", role: .cancel) { deviceIdPendingDelete = nil }
            } message: {
                Text("This will permanently delete the device from the studio.")
            }
            .alert("Delete Connection?", isPresented: $isShowingDeleteConnectionConfirm) {
                Button("Delete", role: .destructive) {
                    guard let studio = currentStudio else { return }
                    guard let linkId = connectionEditorLinkId else { return }

                    _ = connectionsStore.deleteBundle(studioId: studio.id, linkId: linkId)

                    if case .connection(let selectedId) = selectionState.selection, selectedId == linkId {
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
                onAddExample: { addExampleRig(to: studio) }
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
                    if let until = explosionCooldownUntil, Date() < until { return }
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
        if isShowingConnectionExplosion || suppressExplosionReopen { return false }
        if let until = explosionCooldownUntil, Date() < until { return false }
        return true
    }

    @ViewBuilder
    private var explosionSheetContent: some View {
        if let studio = currentStudio,
           let center = explosionDeviceSnapshot ?? studio.devices.first(where: { $0.id == explosionDeviceId }) {
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
           let device = sourceStudio.devices.first(where: { $0.id == deviceId }) {
            NavigationStack {
                Form {
                    Section("Move To Studio") {
                        Picker("Destination", selection: Binding(
                            get: { moveTargetStudioId ?? studios.first?.id },
                            set: { moveTargetStudioId = $0 }
                        )) {
                            ForEach(studiosSortedByName.filter { $0.id != sourceStudio.id }, id: \.id) { s in
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
                            guard let destId = moveTargetStudioId ?? studios.first?.id,
                                  let destStudio = studios.first(where: { $0.id == destId }),
                                  destStudio.id != sourceStudio.id else {
                                moveErrorMessage = "Please choose a different destination studio."
                                return
                            }
                            moveDevice(device, from: sourceStudio, to: destStudio)
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
           let bundle = connectionsStore.bundle(for: studio.id, linkId: linkId) {
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

        draftNickname = "New Device"
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
        if let sr = SampleRate(rawValue: d.sampleRateRaw) { draftSampleRate = sr }

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

    private func expandComputerInterfaces(from counts: [ComputerInterface: Int]) -> [ComputerInterface] {
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
        let nickname = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let manufacturer = draftManufacturer.trimmingCharacters(in: .whitespacesAndNewlines)
        let productId = draftProductId.trimmingCharacters(in: .whitespacesAndNewlines)
        let serialNumber = draftSerialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = draftLocation.trimmingCharacters(in: .whitespacesAndNewlines)

        let supportURL = draftSupportPageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let downloadsURL = draftDownloadsPageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            deviceEditorError = "Nickname is required."
            return
        }

        // Warn if another device in this studio already uses the same serial number
        if !serialNumber.isEmpty {
            let duplicate = studio.devices.first { other in
                other.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(serialNumber) == .orderedSame
                && other.id != editingDeviceId
            }

            if duplicate != nil {
                deviceEditorError = "Another device in this studio already uses this serial number."
                return
            }
        }

        let device: DeviceInstance
        if let id = editingDeviceId, let existing = studio.devices.first(where: { $0.id == id }) {
            device = existing
        } else {
            let pos = findAvailableDevicePosition(in: studio, canvas: canvasSize)
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
                ethernetPortsCount: 0,                sampleRate: draftSampleRate,
                digitalInputs: Array(draftDigitalInputs),
                digitalOutputs: Array(draftDigitalOutputs),
                computerInterfaces: expandComputerInterfaces(from: draftComputerInterfaceCounts),
                posX: pos.x,
                posY: pos.y,
                scale: 1.0,
                zIndex: 0
            )
            studio.devices.append(device)
        }

        device.nickname = nickname
        if !manufacturer.isEmpty { device.manufacturer = manufacturer }
        device.model = productId
        device.category = draftCategory
        device.serialNumber = serialNumber
        device.location = location

        device.supportPageURLString = supportURL.isEmpty ? nil : supportURL
        device.downloadsPageURLString = downloadsURL.isEmpty ? nil : downloadsURL
        device.audioInputsCount = max(0, draftAudioInputs)
        device.audioOutputsCount = max(0, draftAudioOutputs)
        device.adatInputPortsCount = max(0, draftAdatInputPorts)
        device.adatOutputPortsCount = max(0, draftAdatOutputPorts)
        device.madiInputPortsCount = max(0, draftMadiInputPorts)
        device.madiOutputPortsCount = max(0, draftMadiOutputPorts)
        device.sampleRateRaw = draftSampleRate.rawValue
        device.digitalInputs = Array(draftDigitalInputs)
        device.digitalOutputs = Array(draftDigitalOutputs)
        device.computerInterfaces = expandComputerInterfaces(from: draftComputerInterfaceCounts)

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
        guard let idx = studio.devices.firstIndex(where: { $0.id == id }) else { return }

        studio.devices.remove(at: idx)
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
            sampleRate: SampleRate(rawValue: device.sampleRateRaw) ?? (SampleRate.allCases.first ?? SampleRate(rawValue: 0)!),
            digitalInputs: device.digitalInputs,
            digitalOutputs: device.digitalOutputs,
            computerInterfaces: device.computerInterfaces,
            posX: device.posX + 30,
            posY: device.posY + 30,
            scale: device.scale,
            zIndex: device.zIndex
        )
        newDevice.ports = device.ports.map { p in
            let np = Port(name: p.name, type: p.type, direction: p.direction)
            np.channels = p.channels.map { ch in
                Channel(index: ch.index, nameLong: ch.nameLong, nameShort: ch.nameShort, signal: ch.signal, grouping: ch.grouping)
            }
            return np
        }
        studio.devices.append(newDevice)
        selectionState.selection = .device(newDevice.id)
    }

    private func moveDevice(_ device: DeviceInstance, from source: Studio, to destination: Studio) {
        // Remove from source studio
        if let idx = source.devices.firstIndex(where: { $0.id == device.id }) {
            // Dismiss any presented inspector overlay during move
            presentedInspectorDeviceId = nil
            
            let removed = source.devices.remove(at: idx)
            // Append to destination studio
            let newPos = findAvailableDevicePosition(in: destination, canvas: canvasSize)
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
                sampleRate: SampleRate(rawValue: removed.sampleRateRaw) ?? (SampleRate.allCases.first ?? SampleRate(rawValue: 0)!),
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
            moved.ports = removed.ports.map { p in
                let np = Port(name: p.name, type: p.type, direction: p.direction)
                np.channels = p.channels.map { ch in
                    Channel(index: ch.index, nameLong: ch.nameLong, nameShort: ch.nameShort, signal: ch.signal, grouping: ch.grouping)
                }
                return np
            }
            destination.devices.append(moved)
            
            // Remove any connections involving the old device in the source studio
            let sourceLinks = connectionsStore.links(for: source.id)
            for link in sourceLinks where (link.fromDeviceId == device.id || link.toDeviceId == device.id) {
                _ = connectionsStore.deleteBundle(studioId: source.id, linkId: link.id)
            }
            // Ensure there are no connections in destination that reference the new device (should be none yet)
            let destLinks = connectionsStore.links(for: destination.id)
            for link in destLinks where (link.fromDeviceId == moved.id || link.toDeviceId == moved.id) {
                _ = connectionsStore.deleteBundle(studioId: destination.id, linkId: link.id)
            }
            
            // Update selection to moved device and switch selected studio
            selectedStudioId = destination.id
            selectionState.selection = .device(moved.id)
        }
    }

    private func addExampleRig(to studio: Studio) {
        // Keep this as a convenient demo rig, but fully manual-editable.
        if studio.devices.isEmpty {
            let defaultSR = SampleRate.allCases.first ?? SampleRate(rawValue: 0)!
            let d = DeviceInstance(
                manufacturer: "Solid State Logic",
                model: "SSL 18",
                nickname: "SSL 18",
                category: .audioInterface,
                serialNumber: "",
                location: "Rack",
                audioInputsCount: 8,
                audioOutputsCount: 10,
                adatInputPortsCount: 1,
                adatOutputPortsCount: 1,
                madiInputPortsCount: 0,
                madiOutputPortsCount: 0,
                ethernetPortsCount: 0,
                sampleRate: defaultSR,
                digitalInputs: [.adat, .spdif],
                digitalOutputs: [.adat, .spdif],
                computerInterfaces: [],
                posX: 320,
                posY: 240,
                scale: 1.0,
                zIndex: 0
            )
            d.ports = buildPorts(
                audioInputs: d.audioInputsCount,
                audioOutputs: d.audioOutputsCount,
                digitalInputs: d.digitalInputs,
                digitalOutputs: d.digitalOutputs,
                adatInputPorts: d.adatInputPortsCount,
                adatOutputPorts: d.adatOutputPortsCount,
                madiInputPorts: d.madiInputPortsCount,
                madiOutputPorts: d.madiOutputPortsCount,
                computerInterfaceCounts: d.computerInterfaceCounts,
                sampleRate: defaultSR
            )
            studio.devices.append(d)
            selectionState.selection = .device(d.id)
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
        let madiChannelsPerPort: Int = srHz >= 176_400 ? 16 : (srHz >= 88_200 ? 32 : 64)
        let danteChannelsPerLink: Int = 64

        func portLetter(_ i: Int) -> String {
            let scalar = UnicodeScalar(65 + max(0, i))!
            return String(Character(scalar)) // A, B, C...
        }

        if audioInputs > 0 {
            let p = Port(name: "Analog In", type: .analogIn, direction: .input)
            p.channels = (1...audioInputs).map { Channel(index: $0, nameLong: "Analog In \($0)", nameShort: "In\($0)") }
            ports.append(p)
        }

        if audioOutputs > 0 {
            let p = Port(name: "Analog Out", type: .analogOut, direction: .output)
            p.channels = (1...audioOutputs).map { Channel(index: $0, nameLong: "Analog Out \($0)", nameShort: "Out\($0)") }
            ports.append(p)
        }

        func digitalPort(type: PortType, name: String, direction: PortDirection, channels: Int) -> Port {
            let p = Port(name: name, type: type, direction: direction)
            p.channels = (1...channels).map { Channel(index: $0, nameLong: "\(name) \($0)", nameShort: "\($0)") }
            return p
        }

        for f in digitalInputs.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch f {
            case .adat:
                let count = max(1, max(0, adatInputPorts))
                for i in 0..<count {
                    let name = "ADAT In \(portLetter(i))"
                    ports.append(digitalPort(type: .adatIn, name: name, direction: .input, channels: adatChannelsPerPort))
                }
            case .madi:
                let count = max(1, max(0, madiInputPorts))
                for i in 0..<count {
                    let name = "MADI In \(portLetter(i))"
                    ports.append(digitalPort(type: .madiIn, name: name, direction: .input, channels: madiChannelsPerPort))
                }
            case .dante:
                // Represent Dante as an Ethernet-based digital input (one logical link = 64ch).
                ports.append(digitalPort(type: .ethernet, name: "Dante In (Ethernet)", direction: .input, channels: danteChannelsPerLink))
            case .spdif:
                ports.append(digitalPort(type: .spdifIn, name: "Digital In (S/PDIF)", direction: .input, channels: 2))
            default:
                // Fallback to analog types but preserve name
                ports.append(digitalPort(type: .analogIn, name: "Digital In (\(f.rawValue))", direction: .input, channels: 2))
            }
        }

        for f in digitalOutputs.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch f {
            case .adat:
                let count = max(1, max(0, adatOutputPorts))
                for i in 0..<count {
                    let name = "ADAT Out \(portLetter(i))"
                    ports.append(digitalPort(type: .adatOut, name: name, direction: .output, channels: adatChannelsPerPort))
                }
            case .madi:
                let count = max(1, max(0, madiOutputPorts))
                for i in 0..<count {
                    let name = "MADI Out \(portLetter(i))"
                    ports.append(digitalPort(type: .madiOut, name: name, direction: .output, channels: madiChannelsPerPort))
                }
            case .dante:
                ports.append(digitalPort(type: .ethernet, name: "Dante Out (Ethernet)", direction: .output, channels: danteChannelsPerLink))
            case .spdif:
                ports.append(digitalPort(type: .spdifOut, name: "Digital Out (S/PDIF)", direction: .output, channels: 2))
            default:
                ports.append(digitalPort(type: .analogOut, name: "Digital Out (\(f.rawValue))", direction: .output, channels: 2))
            }
        }

        // Computer Interfaces (USB / Thunderbolt / Ethernet, etc.)
        // These are *bidirectional* physical ports. We represent each physical port as a single
        // 1-channel logical port so they can show up in I/O lists and participate in occupancy.
        // IMPORTANT: Do NOT model these as separate "In" and "Out" ports.
        if !computerInterfaceCounts.isEmpty {
            let sortedIfaces = computerInterfaceCounts.keys.sorted(by: { $0.rawValue < $1.rawValue })
            for iface in sortedIfaces {
                let count = max(0, computerInterfaceCounts[iface] ?? 0)
                if count == 0 { continue }

                for i in 0..<count {
                    let suffix = count > 1 ? " \(i + 1)" : ""
                    let name = "\(iface.rawValue)\(suffix)"

                    // NOTE: PortDirection only supports input/output in the current model.
                    // We choose `.input` as a neutral placeholder; UI labels should rely on `name`
                    // (and not append "In"/"Out" for computer interfaces).
                    let p = Port(name: name, type: .ethernet, direction: .input)
                    p.channels = [Channel(index: 1, nameLong: "\(name) 1", nameShort: "1")]
                    ports.append(p)
                }
            }
        }

        return ports
    }

    private func findAvailableDevicePosition(in studio: Studio, canvas: CGSize) -> (x: Double, y: Double) {
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

            for d in studio.devices {
                let dx = d.posX
                let dy = d.posY
                let leftB = dx - halfW
                let rightB = dx + halfW
                let topB = dy - halfH
                let bottomB = dy + halfH

                let overlap = !(rightA < leftB || rightB < leftA || bottomA < topB || bottomB < topA)
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
                (centerX - r, centerY - r)
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
        let idx = Double(studio.devices.count)
        let (fx, fy) = clamped(centerX + (idx * 20).truncatingRemainder(dividingBy: 240) - 120,
                               centerY + (idx * 16).truncatingRemainder(dividingBy: 200) - 100)
        return (fx, fy)
    }

    private func defaultPortsGuess(forManufacturer manufacturer: String, model: String) -> [Port] {
        // Backward compatibility: used only by duplicateStudio if older devices exist.
        let analogIn = Port(name: "Analog In", type: .analogIn, direction: .input)
        analogIn.channels = (1...2).map { Channel(index: $0, nameLong: "Analog In \($0)", nameShort: "In\($0)") }

        let analogOut = Port(name: "Analog Out", type: .analogOut, direction: .output)
        analogOut.channels = (1...2).map { Channel(index: $0, nameLong: "Analog Out \($0)", nameShort: "Out\($0)") }

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
        for d in source.devices {
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

            for p in d.ports {
                let newPort = Port(name: p.name, type: p.type, direction: p.direction)
                for ch in p.channels {
                    newPort.channels.append(
                        Channel(index: ch.index, nameLong: ch.nameLong, nameShort: ch.nameShort, signal: ch.signal, grouping: ch.grouping)
                    )
                }
                newDevice.ports.append(newPort)
            }

            copy.devices.append(newDevice)
        }

        modelContext.insert(copy)
        selectedStudioId = copy.id
    }

    private func exportStudio(_ studio: Studio) {
        // Create exportable representation
        let exportable = ExportableStudio(from: studio)
        
        // Create document
        exportDocument = StudioDocument(exportableStudio: exportable)
        isShowingExportPicker = true
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
            let exportable = try decoder.decode(ExportableStudio.self, from: jsonData)
            
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
    
    private func completeImport(exportable: ExportableStudio, customName: String? = nil) {
        do {
            // Create new studio
            let studio = Studio(name: customName ?? exportable.name)
            
            // Import devices
            var deviceMap: [UUID: DeviceInstance] = [:]
            for exportableDevice in exportable.devices {
                let device = DeviceInstance(
                    manufacturer: exportableDevice.manufacturer,
                    model: exportableDevice.model,
                    nickname: exportableDevice.nickname,
                    category: DeviceCategory(rawValue: exportableDevice.categoryRaw) ?? .other,
                    serialNumber: exportableDevice.serialNumber,
                    location: exportableDevice.location,
                    audioInputsCount: exportableDevice.audioInputsCount,
                    audioOutputsCount: exportableDevice.audioOutputsCount,
                    adatInputPortsCount: exportableDevice.adatInputPortsCount,
                    adatOutputPortsCount: exportableDevice.adatOutputPortsCount,
                    madiInputPortsCount: exportableDevice.madiInputPortsCount,
                    madiOutputPortsCount: exportableDevice.madiOutputPortsCount,
                    ethernetPortsCount: exportableDevice.ethernetPortsCount,
                    sampleRate: SampleRate(rawValue: exportableDevice.sampleRateRaw) ?? .hz48000,
                    digitalInputs: exportableDevice.digitalInputsRaw.compactMap { DigitalFormat(rawValue: $0) },
                    digitalOutputs: exportableDevice.digitalOutputsRaw.compactMap { DigitalFormat(rawValue: $0) },
                    computerInterfaces: exportableDevice.computerInterfacesRaw.compactMap { ComputerInterface(rawValue: $0) },
                    posX: exportableDevice.posX,
                    posY: exportableDevice.posY,
                    scale: exportableDevice.scale,
                    zIndex: exportableDevice.zIndex
                )
                
                device.supportPageURLString = exportableDevice.supportPageURLString
                device.downloadsPageURLString = exportableDevice.downloadsPageURLString
                
                // Import ports
                var portMap: [UUID: Port] = [:]
                for exportablePort in exportableDevice.ports {
                    let port = Port(
                        name: exportablePort.name,
                        type: PortType(rawValue: exportablePort.typeRaw) ?? .usbAudio,
                        direction: PortDirection(rawValue: exportablePort.directionRaw) ?? .bidirectional
                    )
                    
                    // Import channels
                    for exportableChannel in exportablePort.channels {
                        let channel = Channel(
                            index: exportableChannel.index,
                            nameLong: exportableChannel.nameLong,
                            nameShort: exportableChannel.nameShort,
                            signal: SignalType(rawValue: exportableChannel.signalRaw) ?? .audio,
                            grouping: ChannelGrouping(rawValue: exportableChannel.groupingRaw) ?? .mono
                        )
                        port.channels.append(channel)
                    }
                    
                    device.ports.append(port)
                    portMap[exportablePort.id] = port
                }
                
                studio.devices.append(device)
                deviceMap[exportableDevice.id] = device
            }
            
            // Import connections
            for exportableConnection in exportable.connections {
                let connection = Connection(
                    fromDeviceId: exportableConnection.fromDeviceId,
                    fromPortId: exportableConnection.fromPortId,
                    fromChannelId: exportableConnection.fromChannelId,
                    toDeviceId: exportableConnection.toDeviceId,
                    toPortId: exportableConnection.toPortId,
                    toChannelId: exportableConnection.toChannelId,
                    cable: CableType(rawValue: exportableConnection.cableRaw) ?? .other,
                    label: exportableConnection.label,
                    notes: exportableConnection.notes
                )
                studio.connections.append(connection)
            }
            
            // Save to model context
            modelContext.insert(studio)
            try modelContext.save()
            
            // Select the imported studio
            selectedStudioId = studio.id
            
            exportResultMessage = "Studio '\(studio.name)' imported successfully!"
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
            exportResultMessage = "Import cancelled: \(error.localizedDescription)"
            isShowingExportResult = true
        }
    }



}

// MARK: - File-Level Helper Functions

private func ioSummary(from ports: [Port]) -> String {
    func chCount(_ type: PortType, _ dir: PortDirection) -> Int {
        ports
            .filter { $0.type == type && $0.direction == dir }
            .reduce(0) { $0 + $1.channels.count }
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
    if spdifin > 0 || spdifout > 0 { parts.append("S/PDIF \(spdifin)/\(spdifout)") }

    return parts.isEmpty ? "I/O: Unknown" : parts.joined(separator: " • ")
}

// MARK: - Detail Header Subview

private struct DetailHeader: View {
    @Bindable var studio: Studio
    let onCreateDevice: () -> Void
    let onAddExample: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Studio Name", text: .init(get: { studio.name }, set: { studio.name = $0 }))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .frame(minWidth: 240)

            Spacer()

            Button(action: onCreateDevice) {
                Label("Add Device", systemImage: "plus.rectangle.on.rectangle")
            }

            Button(action: onAddExample) {
                Label("Example Rig", systemImage: "wand.and.stars")
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
            iconForDevice: { (d: DeviceInstance) -> String in d.categorySymbolName },
            subtitleForDevice: { (d: DeviceInstance) -> String in ioSummary(from: d.ports) },
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
                            Button { onDuplicate(studio) } label: {
                                Label("Duplicate Studio", systemImage: "plus.square.on.square")
                            }
                            Button { onExport(studio) } label: {
                                Label("Export Studio", systemImage: "square.and.arrow.up")
                            }
                            Divider()
                            Button(role: .destructive) { onRequestDelete(studio) } label: {
                                Label("Delete Studio", systemImage: "trash")
                            }
                        }
#if os(iOS)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button { onDuplicate(studio) } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.blue)
                            
                            Button { onExport(studio) } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { onRequestDelete(studio) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
#endif
                }
                .onDelete { indexSet in
                    if let first = indexSet.first, studios.indices.contains(first) {
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
    static func reduce(value: inout [UUID: CGPoint], nextValue: () -> [UUID: CGPoint]) {
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
    @State private var activeConnectionDrag: (fromId: UUID, start: CGPoint, location: CGPoint)? = nil
    @State private var hoveredConnectionTargetId: UUID? = nil
    @State private var connectionHandleTips: [UUID: CGPoint] = [:]

    private var links: [ConnectionLinkSummary] {
        connectionsStore.links(for: studio.id)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(background)

                ForEach(links, id: \.id) { link in
                    linkRow(link)
                }

                ForEach(studio.devices, id: \.id) { d in
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
            .contentShape(Rectangle())
            .onTapGesture { selection.selection = nil }
            .preference(key: CanvasSizePreferenceKey.self, value: geo.size)
            .coordinateSpace(name: "canvas")
            .onPreferenceChange(ConnectionHandleTipPreferenceKey.self) { connectionHandleTips = $0 }
        }
    }

    @ViewBuilder
    private func linkRow(_ link: ConnectionLinkSummary) -> some View {
        ConnectionLineRow(
            link: link,
            studio: studio,
            handleTips: connectionHandleTips,
            isSelected: isSelectedConnection(linkId: link.id),
            onSelect: { onSelectLink(link) },
            onDelete: { onRequestDeleteLink(link) }
        )
    }

    @ViewBuilder
    private func deviceCard(_ d: DeviceInstance, canvasSize: CGSize) -> some View {
        let tip = connectionHandleTips[d.id]
        let isTarget = (hoveredConnectionTargetId == d.id) && (activeConnectionDrag?.fromId != d.id)
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
                activeConnectionDrag = (fromId: device.id, start: startPoint, location: startPoint)
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
                   let targetId = hoveredConnectionTargetId {
                    connectionsStore.ensureLinkSummary(studioId: studio.id, fromId: drag.fromId, toId: targetId)
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
    private func deviceId(at point: CGPoint, excluding excludedId: UUID) -> UUID? {
        // Must match the card frame used by DeviceCardView.
        let cardSize = CGSize(width: 260, height: 96)
        let halfW = Double(cardSize.width / 2)
        let halfH = Double(cardSize.height / 2)

        for d in studio.devices {
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
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            // Handle is visually anchored to the card corner.
            // We compute the drag line start point in the CANVAS coordinate space from the device position.
            DeviceConnectionHandle(deviceId: device.id)
                .offset(x: 18, y: -12)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named("canvas"))

                        // DeviceConnectionHandle is Triangle(16x14) + padding(8).
                        // Rotated to point right, the tip is at right edge, midY of the 16x14.
                        let tip = CGPoint(x: frame.minX + 24, y: frame.minY + 15)

                        Color.clear
                            .preference(key: ConnectionHandleTipPreferenceKey.self, value: [device.id: tip])
                    }
                )
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            let start = connectionHandleTip ?? CGPoint(x: device.posX, y: device.posY)
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
                    connectionsStore.ensureLinkSummary(studioId: studioId, fromId: fromId, toId: device.id)
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

                    guard let origin = dragOrigin, origin.id == device.id else { return }

                    // Approx label size; used for clamping so it stays on-screen.
                    let cardSize = CGSize(width: 260, height: 96)
                    let halfW = Double(cardSize.width / 2)
                    let halfH = Double(cardSize.height / 2)

                    let rawX = origin.x + Double(v.translation.width)
                    let rawY = origin.y + Double(v.translation.height)

                    let clampedX = min(max(rawX, halfW), Double(canvasSize.width) - halfW)
                    let clampedY = min(max(rawY, halfH), Double(canvasSize.height) - halfH)

                    device.posX = clampedX
                    device.posY = clampedY
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
                if let d = studio.devices.first(where: { $0.id == id }) {
                    Form {
                        Section("Device") {
                            LabeledContent("Nickname", value: d.nickname)

                            if !d.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Manufacturer", value: d.manufacturer)
                            }

                            if !d.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Product ID", value: d.model)
                            }

                            LabeledContent("Category", value: d.category.rawValue)

                            if !d.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Serial Number", value: d.serialNumber)
                            }

                            if !d.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Location", value: d.location)
                            }

                            if let url = d.supportPageURL {
                                LabeledContent("Support Page") {
                                    Link(url.absoluteString, destination: url).lineLimit(1)
                                }
                            }

                            if let url = d.downloadsPageURL {
                                LabeledContent("Downloads Page") {
                                    Link(url.absoluteString, destination: url).lineLimit(1)
                                }
                            }
                        }



                        Section("Ports") {
                            if d.ports.isEmpty {
                                Text("No ports defined yet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(d.ports.sorted(by: portSort), id: \.id) { p in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(p.name)
                                        Spacer()
                                        Text("\(p.channels.count) ch")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)

                                    if !p.channels.isEmpty {
                                        Text(
                                            p.channels
                                                .sorted(by: { $0.index < $1.index })
                                                .map { ch in
                                                    ch.nameShort.isEmpty ? "\(ch.index)" : ch.nameShort
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

                                ForEach(ifaceCounts.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { iface in
                                    Text("\(iface.rawValue) ×\(ifaceCounts[iface] ?? 0)")
                                }
                            }
                        }

                        Section("Manuals") {
                            Button {
                                isImportingManual = true
                            } label: {
                                Label("Add Manual", systemImage: "doc.badge.plus")
                            }

                            if d.docs.isEmpty {
                                Text("No manuals attached.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(d.docs, id: \.id) { doc in
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                            .foregroundStyle(.secondary)
                                        Text(doc.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(role: .destructive) {
                                            if let idx = d.docs.firstIndex(where: { $0.id == doc.id }) {
                                                d.docs.remove(at: idx)
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
                                        if let bookmarkData = doc.localBookmarkData {
                                            // print("📱 Attempting to resolve bookmark...")
                                            do {
                                                let url = try ManualStorage.resolveBookmark(bookmarkData)
                                                // print("📱 ✅ Bookmark resolved to: \(url.path)")
                                                manualViewerItem = IdentifiableURL(url: url)
                                            } catch {
                                                print("📱 ❌ Bookmark resolution failed: \(error)")
                                            }
                                        } else if let urlString = doc.urlString,
                                                  let url = URL(string: urlString) {
                                            // print("📱 Using legacy URL string: \(urlString)")
                                            manualViewerItem = IdentifiableURL(url: url)
                                        } else {
                                            print("📱 ❌ No bookmark or URL available")
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
                                        Label("Clone", systemImage: "plus.square.on.square")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        onRequestMoveDevice(d)
                                    } label: {
                                        Label("Move", systemImage: "arrowshape.turn.up.right")
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
                              let device = studio.devices.first(where: { $0.id == id })
                        else { return }

                        do {
                            let (storedURL, bookmarkData) = try ManualStorage.copyPDFIntoAppSupport(
                                pickedURL: pickedURL,
                                deviceId: device.id
                            )

                            let doc = DocLink(
                                title: storedURL.lastPathComponent,
                                kind: .manual,
                                bookmarkData: bookmarkData
                            )
                            device.docs.append(doc)
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                    .fullScreenCover(item: $manualViewerItem) { item in
                        ManualPDFViewer(url: item.url, title: item.url.lastPathComponent)
                    }
                    #else
                    .sheet(item: $manualViewerItem) { item in
                        ManualPDFViewer(url: item.url, title: item.url.lastPathComponent)
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
    let handleTips: [UUID: CGPoint]
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            if let fromDevice = studio.devices.first(where: { $0.id == link.fromDeviceId }),
               let toDevice = studio.devices.first(where: { $0.id == link.toDeviceId }) {

                // Must match DeviceCardView frame
                let cardSize = CGSize(width: 260, height: 96)
                let halfWidth = Double(cardSize.width) / 2.0

                // Start at measured arrow tip if available
                let fromPoint: CGPoint = handleTips[fromDevice.id]
                    ?? CGPoint(
                        x: CGFloat(fromDevice.posX + halfWidth),
                        y: CGFloat(fromDevice.posY)
                    )

                // End at left edge of destination card
                let toY: CGFloat = handleTips[toDevice.id]?.y ?? CGFloat(toDevice.posY)
                let toPoint = CGPoint(
                    x: CGFloat(toDevice.posX - halfWidth - 4.0),
                    y: toY
                )

                ConnectionLineView(
                    from: fromPoint,
                    to: toPoint,
                    isSelected: isSelected
                )
                // IMPORTANT: give the line a full-size layout box so macOS can attach a context menu
                // while hit-testing still remains constrained to the stroked curve via ConnectionLineView.contentShape.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct ConnectionLineView: View {
    let from: CGPoint
    let to: CGPoint
    let isSelected: Bool

    private var path: Path {
        var p = Path()
        p.move(to: from)
        let dx = to.x - from.x
        let c1 = CGPoint(x: from.x + dx * 0.35, y: from.y)
        let c2 = CGPoint(x: from.x + dx * 0.65, y: to.y)
        p.addCurve(to: to, control1: c1, control2: c2)
        return p
    }

    var body: some View {
        ZStack {
            // Wide invisible stroke for easy hit-testing
            path
                .stroke(Color.clear, style: StrokeStyle(lineWidth: 18, lineCap: .round))

            // Visible line
            path
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.55),
                    style: StrokeStyle(lineWidth: isSelected ? 3 : 2, lineCap: .round)
                )
        }
        // IMPORTANT: hit-test only the stroked curve, not the whole rectangular area.
        .contentShape(path.strokedPath(StrokeStyle(lineWidth: 18, lineCap: .round)))
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
        ZStack {
            Triangle()
                .fill(Color.accentColor.opacity(0.9))
                .frame(width: 16, height: 14)
                .rotationEffect(.degrees(90))
                .shadow(radius: 1.5)

            Triangle()
                .stroke(Color.primary.opacity(0.35), lineWidth: 1)
                .frame(width: 16, height: 14)
                .rotationEffect(.degrees(90))
        }
        .padding(8)
        .contentShape(Rectangle())
        .accessibilityLabel("Drag to connect")
    }
}
// MARK: - DeviceInstance UI Helpers

private extension DeviceInstance {
    var categorySymbolName: String {
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
        if adatInputPorts > 0 { digitalInputs.insert(.adat) } else { digitalInputs.remove(.adat) }
        if adatOutputPorts > 0 { digitalOutputs.insert(.adat) } else { digitalOutputs.remove(.adat) }

        // MADI is count-based
        if madiInputPorts > 0 { digitalInputs.insert(.madi) } else { digitalInputs.remove(.madi) }
        if madiOutputPorts > 0 { digitalOutputs.insert(.madi) } else { digitalOutputs.remove(.madi) }
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
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
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
                                    ForEach(DeviceCategory.allCases, id: \.self) { c in
                                        Text(c.rawValue).tag(c)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
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
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                            GridRow {
                                Text("Support Page")
                                TextField("https://…", text: $supportPageURL)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: .infinity)
                            }
                            GridRow {
                                Text("Downloads Page")
                                TextField("https://…", text: $downloadsPageURL)
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
                                    Text("\(audioInputs)").foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $audioOutputs, in: 0...128) {
                                HStack {
                                    Text("Analog Outputs")
                                    Spacer()
                                    Text("\(audioOutputs)").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Digital I/O") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Sample Rate", selection: $sampleRate) {
                                ForEach(SampleRate.allCases, id: \.self) { r in
                                    Text(r.displayName).tag(r)
                                }
                            }
                            .pickerStyle(.segmented)

                            Divider().padding(.vertical, 4)

                            Stepper(value: $adatInputPorts, in: 0...8) {
                                HStack {
                                    Text("ADAT Input Ports")
                                    Spacer()
                                    Text("\(adatInputPorts)").foregroundStyle(.secondary)
                                }
                            }

                            Stepper(value: $adatOutputPorts, in: 0...8) {
                                HStack {
                                    Text("ADAT Output Ports")
                                    Spacer()
                                    Text("\(adatOutputPorts)").foregroundStyle(.secondary)
                                }
                            }

                            Stepper(value: $madiInputPorts, in: 0...8) {
                                HStack {
                                    Text("MADI Input Ports")
                                    Spacer()
                                    Text("\(madiInputPorts)").foregroundStyle(.secondary)
                                }
                            }

                            Stepper(value: $madiOutputPorts, in: 0...8) {
                                HStack {
                                    Text("MADI Output Ports")
                                    Spacer()
                                    Text("\(madiOutputPorts)").foregroundStyle(.secondary)
                                }
                            }


                        }
                        .padding(8)
                    }

                    GroupBox("Digital Inputs") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(digitalInputFormatChoices, id: \.self) { f in
                                Toggle(f.rawValue, isOn: Binding(
                                    get: { digitalInputs.contains(f) },
                                    set: { isOn in
                                        if isOn { digitalInputs.insert(f) } else { digitalInputs.remove(f) }
                                    }
                                ))
                            }
                        }
                        .padding(8)
                    }

                    GroupBox("Digital Outputs") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(digitalOutputFormatChoices, id: \.self) { f in
                                Toggle(f.rawValue, isOn: Binding(
                                    get: { digitalOutputs.contains(f) },
                                    set: { isOn in
                                        if isOn { digitalOutputs.insert(f) } else { digitalOutputs.remove(f) }
                                    }
                                ))
                            }
                        }
                        .padding(8)
                    }
                    
                    GroupBox("Computer I/O"){
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(ComputerInterface.allCases, id: \.self) { f in
                                Stepper(value: Binding(
                                    get: { max(0, computerInterfaceCounts[f] ?? 0) },
                                    set: { newValue in
                                        let v = max(0, newValue)
                                        if v == 0 { computerInterfaceCounts.removeValue(forKey: f) }
                                        else { computerInterfaceCounts[f] = v }
                                    }
                                ), in: 0...8) {
                                    HStack {
                                        Text(f.rawValue)
                                        Spacer()
                                        Text("\(computerInterfaceCounts[f] ?? 0)")
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
            .onChange(of: adatInputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: adatOutputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: madiInputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: madiOutputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity,
                   minHeight: 640, idealHeight: 720, maxHeight: .infinity)
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

                    TextField("Downloads Page (URL)", text: $downloadsPageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Analog I/O") {
                    Stepper(value: $audioInputs, in: 0...128) {
                        HStack { Text("Analog Inputs"); Spacer(); Text("\(audioInputs)").foregroundStyle(.secondary) }
                    }
                    Stepper(value: $audioOutputs, in: 0...128) {
                        HStack { Text("Analog Outputs"); Spacer(); Text("\(audioOutputs)").foregroundStyle(.secondary) }
                    }
                }

                Section("Digital I/O") {
                    Picker("Sample Rate", selection: $sampleRate) {
                        ForEach(SampleRate.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }

                    Stepper(value: $adatInputPorts, in: 0...8) {
                        HStack { Text("ADAT Input Ports"); Spacer(); Text("\(adatInputPorts)").foregroundStyle(.secondary) }
                    }
                    Stepper(value: $adatOutputPorts, in: 0...8) {
                        HStack { Text("ADAT Output Ports"); Spacer(); Text("\(adatOutputPorts)").foregroundStyle(.secondary) }
                    }
                    Stepper(value: $madiInputPorts, in: 0...8) {
                        HStack { Text("MADI Input Ports"); Spacer(); Text("\(madiInputPorts)").foregroundStyle(.secondary) }
                    }
                    Stepper(value: $madiOutputPorts, in: 0...8) {
                        HStack { Text("MADI Output Ports"); Spacer(); Text("\(madiOutputPorts)").foregroundStyle(.secondary) }
                    }

                }

                Section("Digital Inputs") {
                    ForEach(digitalInputFormatChoices, id: \.self) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { digitalInputs.contains(f) },
                            set: { isOn in
                                if isOn { digitalInputs.insert(f) } else { digitalInputs.remove(f) }
                            }
                        ))
                    }
                }

                Section("Digital Outputs") {
                    ForEach(digitalOutputFormatChoices, id: \.self) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { digitalOutputs.contains(f) },
                            set: { isOn in
                                if isOn { digitalOutputs.insert(f) } else { digitalOutputs.remove(f) }
                            }
                        ))
                    }
                }
                
                Section("Computer I/O") {
                    ForEach(ComputerInterface.allCases, id: \.self) { f in
                        Stepper(value: Binding(
                            get: { max(0, computerInterfaceCounts[f] ?? 0) },
                            set: { newValue in
                                let v = max(0, newValue)
                                if v == 0 { computerInterfaceCounts.removeValue(forKey: f) }
                                else { computerInterfaceCounts[f] = v }
                            }
                        ), in: 0...8) {
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
            .onChange(of: adatInputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: adatOutputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: madiInputPorts) { _, _ in syncCountBasedDigitalFormats() }
            .onChange(of: madiOutputPorts) { _, _ in syncCountBasedDigitalFormats() }
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
                if let d = studio.devices.first(where: { $0.id == deviceId }) {
                    Form {
                        Section("Device") {
                            LabeledContent("Nickname", value: d.nickname)

                            if !d.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Manufacturer", value: d.manufacturer)
                            }

                            if !d.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Product ID", value: d.model)
                            }

                            LabeledContent("Category", value: d.category.rawValue)

                            if !d.serialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Serial Number", value: d.serialNumber)
                            }

                            if !d.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                LabeledContent("Location", value: d.location)
                            }

                            if let url = d.supportPageURL {
                                LabeledContent("Support Page") {
                                    Link(url.absoluteString, destination: url).lineLimit(1)
                                }
                            }

                            if let url = d.downloadsPageURL {
                                LabeledContent("Downloads Page") {
                                    Link(url.absoluteString, destination: url).lineLimit(1)
                                }
                            }
                        }

                        Section("Ports") {
                            if d.ports.isEmpty {
                                Text("No ports defined yet.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(d.ports.sorted(by: portSort), id: \.id) { p in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(p.name)
                                        Spacer()
                                        Text("\(p.channels.count) ch")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.subheadline)

                                    if !p.channels.isEmpty {
                                        Text(
                                            p.channels
                                                .sorted(by: { $0.index < $1.index })
                                                .map { ch in
                                                    ch.nameShort.isEmpty ? "\(ch.index)" : ch.nameShort
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

                                ForEach(d.computerInterfaces.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { iface in
                                    Text(iface.rawValue)
                                }
                            }
                        }

                        Section("Manuals") {
                            Button {
                                isImportingManual = true
                            } label: {
                                Label("Add Manual", systemImage: "doc.badge.plus")
                            }

                            if d.docs.isEmpty {
                                Text("No manuals attached.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(d.docs, id: \.id) { doc in
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                            .foregroundStyle(.secondary)
                                        Text(doc.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Button(role: .destructive) {
                                            if let idx = d.docs.firstIndex(where: { $0.id == doc.id }) {
                                                d.docs.remove(at: idx)
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
                                        if let bookmarkData = doc.localBookmarkData {
                                            // print("📱 Attempting to resolve bookmark...")
                                            do {
                                                let url = try ManualStorage.resolveBookmark(bookmarkData)
                                                // print("📱 ✅ Bookmark resolved to: \(url.path)")
                                                manualViewerItem = IdentifiableURL(url: url)
                                            } catch {
                                                print("📱 ❌ Bookmark resolution failed: \(error)")
                                            }
                                        } else if let urlString = doc.urlString,
                                                  let url = URL(string: urlString) {
                                            // print("📱 Using legacy URL string: \(urlString)")
                                            manualViewerItem = IdentifiableURL(url: url)
                                        } else {
                                            print("📱 ❌ No bookmark or URL available")
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
                                        Label("Clone", systemImage: "plus.square.on.square")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        onRequestMoveDevice(d)
                                    } label: {
                                        Label("Move", systemImage: "arrowshape.turn.up.right")
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
                              let device = studio.devices.first(where: { $0.id == deviceId })
                        else { return }

                        do {
                            let (storedURL, bookmarkData) = try ManualStorage.copyPDFIntoAppSupport(
                                pickedURL: pickedURL,
                                deviceId: device.id
                            )

                            let doc = DocLink(
                                title: storedURL.lastPathComponent,
                                kind: .manual,
                                bookmarkData: bookmarkData
                            )
                            device.docs.append(doc)
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    #if os(iOS)
                    .fullScreenCover(item: $manualViewerItem) { item in
                        ManualPDFViewer(url: item.url, title: item.url.lastPathComponent)
                    }
                    #else
                    .sheet(item: $manualViewerItem) { item in
                        ManualPDFViewer(url: item.url, title: item.url.lastPathComponent)
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
            }
        }
    }
}

// MARK: - DeviceExplosionDetailView

private struct DeviceExplosionDetailView: View {
    let studio: Studio
    let device: DeviceInstance
    let connectionsStore: ConnectionsStore

    private func endpoint(for port: Port, channel: Channel) -> IOEndpointRef {
        let dir: IOEndpointRef.Direction = (port.direction == .input) ? .input : .output
        return IOEndpointRef(deviceId: device.id, portId: port.id, channelId: channel.id, direction: dir)
    }

    private func rowLabel(port: Port, channel: Channel) -> String {
        let short = channel.nameShort.trimmingCharacters(in: .whitespacesAndNewlines)
        if short.isEmpty {
            return port.name
        }
        // Prefer the short label if it already implies index (e.g. "In1"), otherwise keep it readable.
        return "\(port.name) \(short)"
    }

    private func statusText(for endpoint: IOEndpointRef) -> String {
        connectionsStore.connectedToText(studio: studio, studioId: studio.id, endpoint: endpoint) ?? "open"
    }

    private func isOpen(_ endpoint: IOEndpointRef) -> Bool {
        connectionsStore.occupancyForEndpoint(studioId: studio.id, endpoint: endpoint) == nil
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
        device.ports
            .filter { $0.direction == .input && !isComputerInterfacePort($0) }
            .sorted(by: portSort)
    }

    private var outputPorts: [Port] {
        device.ports
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
                let label = (n > 1) ? "\(iface.rawValue) \(idx)" : iface.rawValue
                let portId = stableComputerPortId(deviceId: device.id, iface: iface, index: idx)
                let channelId = stableComputerChannelId(deviceId: device.id, iface: iface, index: idx)
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
                    let used = (inputPorts + outputPorts).flatMap { p in p.channels.map { endpoint(for: p, channel: $0) } }
                        .filter { !isOpen($0) }
                        .count
                    let total = (inputPorts + outputPorts).reduce(0) { $0 + $1.channels.count }
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
                        let connectedText = connectionsStore.connectedToText(
                            studio: studio,
                            studioId: studio.id,
                            endpoint: row.inputEndpoint
                        ) ?? connectionsStore.connectedToText(
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
                            Image(systemName: isOpen ? "circle" : "checkmark.circle.fill")
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
                        ForEach(p.channels.sorted(by: { $0.index < $1.index }), id: \.id) { ch in
                            let ep = endpoint(for: p, channel: ch)
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rowLabel(port: p, channel: ch))
                                    Text(statusText(for: ep))
                                        .font(.caption)
                                        .foregroundStyle(isOpen(ep) ? .secondary : .primary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: isOpen(ep) ? "circle" : "checkmark.circle.fill")
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
                        ForEach(p.channels.sorted(by: { $0.index < $1.index }), id: \.id) { ch in
                            let ep = endpoint(for: p, channel: ch)
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rowLabel(port: p, channel: ch))
                                    Text(statusText(for: ep))
                                        .font(.caption)
                                        .foregroundStyle(isOpen(ep) ? .secondary : .primary)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: isOpen(ep) ? "circle" : "checkmark.circle.fill")
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

private func stableComputerPortId(deviceId: UUID, iface: ComputerInterface, index: Int) -> UUID {
    stableUUID("computerPort|\(deviceId.uuidString)|\(iface.rawValue)|\(index)")
}

private func stableComputerChannelId(deviceId: UUID, iface: ComputerInterface, index: Int) -> UUID {
    stableUUID("computerCh|\(deviceId.uuidString)|\(iface.rawValue)|\(index)")
}
private func stableUUID(_ s: String) -> UUID {
    let digest = SHA256.hash(data: Data(s.utf8))
    let bytes = Array(digest)
    let uuidBytes = Array(bytes.prefix(16))
    return UUID(uuid: (
        uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
        uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
        uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
        uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
    ))
}
