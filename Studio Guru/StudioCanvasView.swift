//
//  StudioCanvasView.swift
//  Studio Guru
//
//  Created by Ian Miller on 2/7/26.
//

import SwiftUI

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

    // Canvas sizing (used to place new devices without overlap)
    @State private var canvasSize: CGSize = CGSize(width: 1200, height: 800)


    // Device CRUD
    @State private var isShowingDeviceEditor: Bool = false
    @State private var editingDeviceId: UUID? = nil

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
        }
        .onChange(of: selectedStudioId) { _, _ in
            selectionState.selection = nil
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
                            iconForDevice: { d in
                                d.categorySymbolName
                            },
                            subtitleForDevice: { d in
                                ioSummary(from: d.ports)
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
                .alert("Delete Device", isPresented: $isShowingDeleteDeviceConfirm) {
                    Button("Delete", role: .destructive) { deletePendingDevice() }
                    Button("Cancel", role: .cancel) { deviceIdPendingDelete = nil }
                } message: {
                    Text("This will permanently delete the device from the studio.")
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

// MARK: - Canvas

private struct CanvasSurfaceView: View {
    let studio: Studio
    let background: Color
    let iconForDevice: (DeviceInstance) -> String
    let subtitleForDevice: (DeviceInstance) -> String
    @EnvironmentObject var selection: SelectionState

    @State private var dragOrigin: (id: UUID, x: Double, y: Double)?

    private func beginDragIfNeeded(for device: DeviceInstance) {
        if dragOrigin?.id != device.id {
            dragOrigin = (device.id, device.posX, device.posY)
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(background)

                ForEach(studio.devices, id: \.id) { d in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: iconForDevice(d))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text(d.nickname)
                                .font(.headline)
                        }

                        Text(subtitleForDevice(d))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(width: 260, alignment: .leading)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected(d.id) ? Color.accentColor : Color.secondary.opacity(0.25),
                                    lineWidth: isSelected(d.id) ? 3 : 1)
                    )
                    .position(x: d.posX, y: d.posY)
                    .onTapGesture { selection.selection = .device(d.id) }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { v in
                                beginDragIfNeeded(for: d)
                                guard let origin = dragOrigin, origin.id == d.id else { return }

                                // Approx label size; used for clamping so it stays on-screen.
                                let cardSize = CGSize(width: 260, height: 96)
                                let halfW = Double(cardSize.width / 2)
                                let halfH = Double(cardSize.height / 2)

                                let rawX = origin.x + Double(v.translation.width)
                                let rawY = origin.y + Double(v.translation.height)

                                let clampedX = min(max(rawX, halfW), Double(geo.size.width) - halfW)
                                let clampedY = min(max(rawY, halfH), Double(geo.size.height) - halfH)

                                d.posX = clampedX
                                d.posY = clampedY
                            }
                            .onEnded { _ in
                                dragOrigin = nil
                            }
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.selection = nil }
            .preference(key: CanvasSizePreferenceKey.self, value: geo.size)
        }
    }

    private func isSelected(_ id: UUID) -> Bool {
        if case .device(let did) = selection.selection { return did == id }
        return false
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

            case .connection:
                Text("Connections next")
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
