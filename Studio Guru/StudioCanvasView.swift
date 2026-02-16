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

    @State private var draftDigitalInputs: Set<DigitalFormat> = []
    @State private var draftDigitalOutputs: Set<DigitalFormat> = []
    @State private var draftComputerInterfaces: Set<ComputerInterface> = []

    @State private var deviceEditorError: String? = nil

    // Delete device confirm
    @State private var isShowingDeleteDeviceConfirm: Bool = false
    @State private var deviceIdPendingDelete: UUID? = nil

    // Delete connection confirm
    @State private var isShowingDeleteConnectionConfirm: Bool = false
    @State private var connectionPendingDelete: Connection? = nil

    var body: some View {
        let sidebarView = AnyView(sidebar)
        let detailView = AnyView(detail)

        return NavigationSplitView {
            sidebarView
        } detail: {
            detailView
        }
        .onAppear {
            if selectedStudioId == nil {
                selectedStudioId = studios.first?.id
            }
            if let sid = selectedStudioId {
                connectionsStore.load(studioId: sid)
            }
        }
        .onChange(of: selectedStudioId) { _, _ in
            selectionState.selection = nil
        }
        if let sid = selectedStudioId {
            connectionsStore.load(studioId: sid)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedStudioId) {
            Section("Studios") {
                ForEach(studiosSortedByName, id: \.id) { studio in
                    Text(studio.name)
                        .tag(studio.id)
                        .contextMenu {
                            Button { duplicateStudio(from: studio) } label: {
                                Label("Duplicate Studio", systemImage: "plus.square.on.square")
                            }

                            Button { exportStudio(studio) } label: {
                                Label("Export Studio", systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                studioIdPendingDelete = studio.id
                                isShowingDeleteStudioConfirm = true
                            } label: {
                                Label("Delete Studio", systemImage: "trash")
                            }
                        }
#if os(iOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                studioIdPendingDelete = studio.id
                                isShowingDeleteStudioConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
#endif
                }
                .onDelete { indexSet in
                    let sorted = studiosSortedByName
                    if let first = indexSet.first, sorted.indices.contains(first) {
                        studioIdPendingDelete = sorted[first].id
                        isShowingDeleteStudioConfirm = true
                    }
                }
            }
        }
        .toolbar {
            Button {
                newStudioNameDraft = "My Studio"
                isShowingNewStudioPrompt = true
            } label: {
                Label("New Studio", systemImage: "plus")
            }

            Button {
                isShowingGuru = true
            } label: {
                Label("Guru", systemImage: "sparkles")
            }

            if let studio = currentStudio {
                Button { duplicateStudio(from: studio) } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }

                Button { exportStudio(studio) } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    studioIdPendingDelete = studio.id
                    isShowingDeleteStudioConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
#if os(macOS)
                .keyboardShortcut(.delete, modifiers: [])
#endif
            }
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
        .sheet(isPresented: $isShowingGuru) {
            GuruHomeView()
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let studio = currentStudio {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        TextField("Studio Name", text: Binding(
                            get: { studio.name },
                            set: { studio.name = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(minWidth: 240)

                        Spacer()

                        Button {
                            beginCreateDevice()
                        } label: {
                            Label("Add Device", systemImage: "plus.rectangle.on.rectangle")
                        }

                        Button { addExampleRig(to: studio) } label: {
                            Label("Example Rig", systemImage: "wand.and.stars")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)

                    Divider()

                    HStack(spacing: 0) {
                        CanvasSurfaceView(
                            studio: studio,
                            background: canvasBackground,
                            iconForDevice: { d in d.categorySymbolName },
                            subtitleForDevice: { d in ioSummary(from: d.ports) },
                            connectionsStore: connectionsStore,
                            onSelectLink: { link in
                                selectionState.selection = .connection(link.id)
                                connectionEditorLinkId = link.id
                                isShowingConnectionsEditor = true
                            },
                            onRequestDeleteLink: { link in
                                connectionEditorLinkId = link.id
                                isShowingDeleteConnectionConfirm = true
                            }
                        )
                        .environmentObject(selectionState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onPreferenceChange(CanvasSizePreferenceKey.self) { newSize in
                            if newSize != .zero {
                                canvasSize = newSize
                            }
                        }

                        Divider()

                        InspectorPanel(
                            studio: studio,
                            onEditDevice: { d in beginEditDevice(d) },
                            onRequestDeleteDevice: { d in
                                deviceIdPendingDelete = d.id
                                isShowingDeleteDeviceConfirm = true
                            }
                        )
                        .environmentObject(selectionState)
                        .frame(width: 360)
                    }
                }
                .sheet(isPresented: $isShowingDeviceEditor) {
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
                            digitalInputs: $draftDigitalInputs,
                            digitalOutputs: $draftDigitalOutputs,
                            computerInterfaces: $draftComputerInterfaces,
                            errorMessage: $deviceEditorError,
                            onCancel: { isShowingDeviceEditor = false },
                            onSave: { saveDeviceEdits(into: studio) }
                        )
                    } else {
                        Text("No studio")
                            .padding()
                    }
                }
                .sheet(isPresented: $isShowingConnectionsEditor) {
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
            } else {
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
        draftDigitalInputs = []
        draftDigitalOutputs = []
        draftComputerInterfaces = []

        isShowingDeviceEditor = true
    }

    private func beginEditDevice(_ d: DeviceInstance) {
        editingDeviceId = d.id
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

        draftDigitalInputs = Set(d.digitalInputs)
        draftDigitalOutputs = Set(d.digitalOutputs)
        draftComputerInterfaces = Set(d.computerInterfaces)

        isShowingDeviceEditor = true
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
                digitalInputs: Array(draftDigitalInputs),
                digitalOutputs: Array(draftDigitalOutputs),
                posX: pos.x,
                posY: pos.y
            )
            studio.devices.append(device)
            device.supportPageURLString = supportURL.isEmpty ? nil : supportURL
            device.downloadsPageURLString = downloadsURL.isEmpty ? nil : downloadsURL
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
        device.digitalInputs = Array(draftDigitalInputs)
        device.digitalOutputs = Array(draftDigitalOutputs)
        device.computerInterfaces = Array(draftComputerInterfaces)

        // Build ports from counts/formats for visualization and later connection tooling.
        device.ports = buildPorts(
            audioInputs: device.audioInputsCount,
            audioOutputs: device.audioOutputsCount,
            digitalInputs: device.digitalInputs,
            digitalOutputs: device.digitalOutputs
        )

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

    private func addExampleRig(to studio: Studio) {
        // Keep this as a convenient demo rig, but fully manual-editable.
        if studio.devices.isEmpty {
            let d = DeviceInstance(
                manufacturer: "Solid State Logic",
                model: "SSL 18",
                nickname: "SSL 18",
                category: .audioInterface,
                location: "Rack",
                audioInputsCount: 8,
                audioOutputsCount: 10,
                digitalInputs: [.adat, .spdif],
                digitalOutputs: [.adat, .spdif],
                posX: 320,
                posY: 240
            )
            d.ports = buildPorts(audioInputs: d.audioInputsCount, audioOutputs: d.audioOutputsCount, digitalInputs: d.digitalInputs, digitalOutputs: d.digitalOutputs)
            studio.devices.append(d)
            selectionState.selection = .device(d.id)
        }
    }

    private func buildPorts(audioInputs: Int, audioOutputs: Int, digitalInputs: [DigitalFormat], digitalOutputs: [DigitalFormat]) -> [Port] {
        var ports: [Port] = []

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
                ports.append(digitalPort(type: .adatIn, name: "Digital In (ADAT)", direction: .input, channels: 8))
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
                ports.append(digitalPort(type: .adatOut, name: "Digital Out (ADAT)", direction: .output, channels: 8))
            case .spdif:
                ports.append(digitalPort(type: .spdifOut, name: "Digital Out (S/PDIF)", direction: .output, channels: 2))
            default:
                ports.append(digitalPort(type: .analogOut, name: "Digital Out (\(f.rawValue))", direction: .output, channels: 2))
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

    private func ioSummary(from ports: [Port]) -> String {
        func chCount(_ type: PortType, _ dir: PortDirection) -> Int {
            ports.first(where: { $0.type == type && $0.direction == dir })?.channels.count ?? 0
        }

        let ain = chCount(.analogIn, .input)
        let aout = chCount(.analogOut, .output)
        let adatin = chCount(.adatIn, .input)
        let adatout = chCount(.adatOut, .output)
        let spdifin = chCount(.spdifIn, .input)
        let spdifout = chCount(.spdifOut, .output)

        var parts: [String] = []
        if ain > 0 || aout > 0 { parts.append("Analog \(ain) in / \(aout) out") }
        if adatin > 0 || adatout > 0 { parts.append("ADAT \(adatin)/\(adatout)") }
        if spdifin > 0 || spdifout > 0 { parts.append("S/PDIF \(spdifin)/\(spdifout)") }

        return parts.isEmpty ? "I/O: Unknown" : parts.joined(separator: " • ")
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
        exportResultMessage = "Export is a stub for now. Next: Pro Tools / Logic IO exports."
        isShowingExportResult = true
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
                    ConnectionLineRow(
                        link: link,
                        studio: studio,
                        isSelected: isSelectedConnection(linkId: link.id),
                        onSelect: {
                            onSelectLink(link)
                        },
                        onDelete: {
                            onRequestDeleteLink(link)
                        }
                    )
                }
                if let temp = activeConnectionDrag {
                    ConnectionLineView(
                        from: temp.start,
                        to: temp.location,
                        isSelected: true
                    )
                }
                ForEach(studio.devices, id: \.id) { d in
                    DeviceCardView(
                        device: d,
                        iconName: iconForDevice(d),
                        subtitle: subtitleForDevice(d),
                        studioId: studio.id,
                        connectionsStore: connectionsStore,
                        isSelected: isSelected(d.id),
                        isConnectionTarget: (hoveredConnectionTargetId == d.id) && (activeConnectionDrag?.fromId != d.id),
                        canvasSize: geo.size,
                        connectionHandleTip: connectionHandleTips[d.id],
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
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.selection = nil }
            .preference(key: CanvasSizePreferenceKey.self, value: geo.size)
            .coordinateSpace(name: "canvas")
            .onPreferenceChange(ConnectionHandleTipPreferenceKey.self) { connectionHandleTips = $0 }
        }
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
                        // The handle view includes padding; use the visible arrow tip at the right edge
                        // and vertically centered.
                        let frame = proxy.frame(in: .named("canvas"))
                        let tip = CGPoint(x: frame.maxX - 8, y: frame.midY)
                        Color.clear
                            .preference(key: ConnectionHandleTipPreferenceKey.self, value: [device.id: tip])
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = connectionHandleTip ?? CGPoint(x: device.posX, y: device.posY)
                            if !isDraggingConnection {
                                isDraggingConnection = true
                                onBeginConnectionDrag(device, start)
                            }
                            let end = CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                            onUpdateConnectionDrag(device, end)
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
    @EnvironmentObject var selection: SelectionState

    @State private var isImportingManual: Bool = false
    @State private var manualViewerURL: URL? = nil

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
                            ForEach(d.ports, id: \.id) { p in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    Text("\(p.typeRaw) • \(p.directionRaw) • \(p.channels.count) ch")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                                        if let urlString = doc.urlString,
                                           let url = URL(string: urlString) {
                                            manualViewerURL = url
                                        }
                                    }
                                }
                            }
                        }
                        Section {
                            HStack(spacing: 12) {
                                Button {
                                    onEditDevice(d)
                                } label: {
                                    Label("Edit Device", systemImage: "pencil")
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
                            let storedURL = try ManualStorage.copyPDFIntoAppSupport(
                                pickedURL: pickedURL,
                                deviceId: device.id
                            )

                            let doc = DocLink(
                                title: storedURL.lastPathComponent,
                                kind: .manual,
                                url: storedURL
                            )
                            device.docs.append(doc)
                        } catch {
                            print("Manual import failed: \(error)")
                        }
                    }
                    .sheet(item: Binding(
                        get: {
                            manualViewerURL.map { IdentifiableURL(url: $0) }
                        },
                        set: { newValue in
                            manualViewerURL = newValue?.url
                        }
                    )) { item in
                        ManualPDFViewer(url: item.url, title: item.url.lastPathComponent)
                    }
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

private struct ConnectionsDialogView: View {
    @Environment(\.dismiss) private var dismiss

    let studio: Studio
    let fromDeviceId: UUID
    let toDeviceId: UUID
    @ObservedObject var store: ConnectionsStore

    private var fromDevice: DeviceInstance? { studio.devices.first(where: { $0.id == fromDeviceId }) }
    private var toDevice: DeviceInstance? { studio.devices.first(where: { $0.id == toDeviceId }) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(fromDevice?.nickname ?? "Device")
                            .font(.title3).bold()
                        Text("Source")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.left.and.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(toDevice?.nickname ?? "Device")
                            .font(.title3).bold()
                        Text("Destination")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text("Patchbay mappings will appear here next.")
                    .foregroundStyle(.secondary)

                if let bundle = store.bundle(for: studio.id, fromId: fromDeviceId, toId: toDeviceId) {
                    Text("Current bundle has \(bundle.edges.count) mapping(s).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 860, idealWidth: 980, maxWidth: .infinity,
               minHeight: 560, idealHeight: 680, maxHeight: .infinity)
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
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if let a = studio.devices.first(where: { $0.id == link.fromDeviceId }),
           let b = studio.devices.first(where: { $0.id == link.toDeviceId }) {

            ConnectionLineView(
                from: CGPoint(x: a.posX, y: a.posY),
                to: CGPoint(x: b.posX, y: b.posY),
                isSelected: isSelected
            )
            .onTapGesture {
                onSelect()
            }
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
        .contentShape(Rectangle())
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

    @Binding var digitalInputs: Set<DigitalFormat>
    @Binding var digitalOutputs: Set<DigitalFormat>
    @Binding var computerInterfaces: Set<ComputerInterface>

    @Binding var errorMessage: String?

    let onCancel: () -> Void
    let onSave: () -> Void

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

                    GroupBox("Audio") {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper(value: $audioInputs, in: 0...128) {
                                HStack {
                                    Text("Audio Inputs")
                                    Spacer()
                                    Text("\(audioInputs)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Stepper(value: $audioOutputs, in: 0...128) {
                                HStack {
                                    Text("Audio Outputs")
                                    Spacer()
                                    Text("\(audioOutputs)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(8)
                    }

                    GroupBox("Digital Inputs") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(DigitalFormat.allCases, id: \.self) { f in
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
                            ForEach(DigitalFormat.allCases, id: \.self) { f in
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
                    
                    GroupBox("Computer Interface") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ComputerInterface.allCases, id: \.self) { f in
                                Toggle(f.rawValue, isOn: Binding(
                                    get: { computerInterfaces.contains(f) },
                                    set: { isOn in
                                        if isOn { computerInterfaces.insert(f) }
                                        else { computerInterfaces.remove(f) }
                                    }
                                ))
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

                Section("Audio") {
                    Stepper(value: $audioInputs, in: 0...128) {
                        HStack {
                            Text("Audio Inputs")
                            Spacer()
                            Text("\(audioInputs)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Stepper(value: $audioOutputs, in: 0...128) {
                        HStack {
                            Text("Audio Outputs")
                            Spacer()
                            Text("\(audioOutputs)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Digital Inputs") {
                    ForEach(DigitalFormat.allCases, id: \.self) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { digitalInputs.contains(f) },
                            set: { isOn in
                                if isOn { digitalInputs.insert(f) } else { digitalInputs.remove(f) }
                            }
                        ))
                    }
                }

                Section("Digital Outputs") {
                    ForEach(DigitalFormat.allCases, id: \.self) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { digitalOutputs.contains(f) },
                            set: { isOn in
                                if isOn { digitalOutputs.insert(f) } else { digitalOutputs.remove(f) }
                            }
                        ))
                    }
                }
                
                Section("Computer Interface") {
                    ForEach(ComputerInterface.allCases, id: \.self) { f in
                        Toggle(f.rawValue, isOn: Binding(
                            get: { computerInterfaces.contains(f) },
                            set: { isOn in
                                if isOn { computerInterfaces.insert(f) }
                                else { computerInterfaces.remove(f) }
                            }
                        ))
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
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
private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Guru Module (v1)

private enum GuruProcess: String, CaseIterable, Identifiable {
    case compressor = "Compressor"
    case equalizer = "Equalizer"
    case reverb = "Reverb"
    case delay = "Delay"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .compressor: return "waveform"
        case .equalizer: return "slider.horizontal.3"
        case .reverb: return "drop"
        case .delay: return "timer"
        }
    }
}

private enum GuruSource: String, CaseIterable, Identifiable {
    case vocalLead = "Vocal (Lead)"
    case bass = "Bass"
    case kick = "Kick"
    case snare = "Snare"
    case piano = "Piano"
    case drumBus = "Drum Bus"
    case mixBus = "Mix Bus"

    var id: String { rawValue }
}

private struct GuruHomeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSource: GuruSource = .vocalLead
    @State private var selectedProcess: GuruProcess = .compressor

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Choose") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Source", selection: $selectedSource) {
                                ForEach(GuruSource.allCases) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }

                            Picker("Process", selection: $selectedProcess) {
                                ForEach(GuruProcess.allCases) { p in
                                    Label(p.rawValue, systemImage: p.symbol).tag(p)
                                }
                            }
                        }
                        .padding(8)
                    }

                    GuruPluginPanel(source: selectedSource, process: selectedProcess)
                }
                .padding(16)
            }
            .navigationTitle("Guru")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 760, maxWidth: .infinity,
               minHeight: 640, idealHeight: 760, maxHeight: .infinity)
    }
}

private struct GuruPluginPanel: View {
    let source: GuruSource
    let process: GuruProcess

    var body: some View {
        Group {
            switch process {
            case .compressor:
                CompressorPluginView(source: source)
            case .equalizer:
                PlaceholderPluginView(title: "Equalizer", subtitle: "EQ starter settings coming next")
            case .reverb:
                PlaceholderPluginView(title: "Reverb", subtitle: "Reverb starter settings coming next")
            case .delay:
                PlaceholderPluginView(title: "Delay", subtitle: "Delay starter settings coming next")
            }
        }
    }
}

private struct PlaceholderPluginView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
            Text(subtitle)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
                .frame(height: 280)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Coming soon")
                            .foregroundStyle(.secondary)
                    }
                )
        }
    }
}

private struct CompressorPreset {
    var ratio: Double          // 1...10 (displayed as 1:1 ... 10:1)
    var attackMs: Double       // 0.1...100
    var releaseMs: Double      // 10...500
    var knee: Double           // 0...1 (soft..hard)
    var grDb: Double           // 0...12 (target gain reduction)

    static func forSource(_ s: GuruSource) -> CompressorPreset {
        switch s {
        case .vocalLead:
            return .init(ratio: 3.5, attackMs: 20, releaseMs: 90, knee: 0.2, grDb: 5)
        case .bass:
            return .init(ratio: 4.0, attackMs: 30, releaseMs: 120, knee: 0.35, grDb: 6)
        case .kick:
            return .init(ratio: 5.0, attackMs: 30, releaseMs: 80, knee: 0.5, grDb: 5)
        case .snare:
            return .init(ratio: 5.0, attackMs: 18, releaseMs: 90, knee: 0.5, grDb: 6)
        case .piano:
            return .init(ratio: 2.5, attackMs: 40, releaseMs: 160, knee: 0.25, grDb: 3)
        case .drumBus:
            return .init(ratio: 3.0, attackMs: 30, releaseMs: 100, knee: 0.35, grDb: 3)
        case .mixBus:
            return .init(ratio: 2.0, attackMs: 30, releaseMs: 120, knee: 0.3, grDb: 1.5)
        }
    }
}

private struct CompressorPluginView: View {
    let source: GuruSource

    private var preset: CompressorPreset { .forSource(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Compressor")
                    .font(.title2)
                    .bold()
                Spacer()
                Text(source.rawValue)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThickMaterial)
                .overlay(
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            GuruKnob(title: "Ratio", value01: ratio01(preset.ratio), valueText: String(format: "%.1f:1", preset.ratio))
                            GuruKnob(title: "Attack", value01: log01(preset.attackMs, min: 0.1, max: 100), valueText: "\(Int(preset.attackMs)) ms")
                            GuruKnob(title: "Release", value01: log01(preset.releaseMs, min: 10, max: 500), valueText: "\(Int(preset.releaseMs)) ms")
                            GuruKnob(title: "Knee", value01: preset.knee, valueText: preset.knee < 0.33 ? "Soft" : (preset.knee < 0.66 ? "Med" : "Hard"))
                            GuruKnob(title: "GR", value01: clamp01(preset.grDb / 12.0), valueText: String(format: "%.1f dB", preset.grDb))
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Starting point")
                                .font(.headline)
                            Text(startingPointNote(for: source))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                )
                .frame(height: 320)
        }
    }

    private func startingPointNote(for s: GuruSource) -> String {
        switch s {
        case .vocalLead:
            return "Aim for 3–6 dB gain reduction on peaks; adjust threshold to taste. Slightly slower attack keeps articulation intact."
        case .bass:
            return "Target 4–8 dB gain reduction for even sustain. If transients feel dull, slow the attack a touch."
        case .kick:
            return "Keep attack slow enough to preserve punch. Shorter release tightens the low end."
        case .snare:
            return "Shorter release increases snap; longer release smooths. Keep an eye on pumping."
        case .piano:
            return "Use light control (2–4 dB). Longer attack keeps dynamics natural."
        case .drumBus:
            return "Glue rather than slam: 2–4 dB is usually enough."
        case .mixBus:
            return "Very subtle: 1–2 dB gain reduction. If the mix narrows, back off."
        }
    }

    private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

    private func ratio01(_ ratio: Double) -> Double {
        // Map 1...10 to 0...1
        clamp01((ratio - 1.0) / 9.0)
    }

    private func log01(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        // Log-ish mapping for time constants so small values have more visual resolution.
        let v = Swift.max(minValue, Swift.min(value, maxValue))
        let a = log(minValue)
        let b = log(maxValue)
        let x = log(v)
        return clamp01((x - a) / (b - a))
    }
}

private struct GuruKnob: View {
    let title: String
    let value01: Double       // 0...1
    let valueText: String

    private var angle: Double {
        // From -135° to +135° like many plugins
        (-135.0) + (270.0 * min(max(value01, 0), 1))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)

                // Track
                Circle()
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 6)

                // Value arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(value01, 0), 1)))
                    .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(.primary)

                // Pointer
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2, height: 18)
                    .offset(y: -18)
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: 74, height: 74)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(valueText)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: 92)
    }
}

