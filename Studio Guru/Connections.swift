//
//  Connections.swift
//  Studio Guru
//
//  Connections patchbay overlay + supporting UI types.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Combine


// MARK: - Connections Data Models + Store

struct ConnectionLinkSummary: Identifiable, Hashable, Codable {
    let id: UUID
    let fromDeviceId: UUID
    let toDeviceId: UUID

    init(id: UUID = UUID(), fromDeviceId: UUID, toDeviceId: UUID) {
        self.id = id
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
    }

    var normalizedPairKey: String {
        let a = fromDeviceId.uuidString
        let b = toDeviceId.uuidString
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

struct ActiveLinkDrag: Equatable {
    let fromDeviceId: UUID
    var currentPoint: CGPoint

    init(fromDeviceId: UUID, currentPoint: CGPoint) {
        self.fromDeviceId = fromDeviceId
        self.currentPoint = currentPoint
    }
}

struct IOEndpointRef: Hashable, Codable {
    enum Direction: String, Codable {
        case input
        case output
    }

    var deviceId: UUID
    var portId: UUID
    var channelId: UUID
    var direction: Direction

    init(deviceId: UUID, portId: UUID, channelId: UUID, direction: Direction) {
        self.deviceId = deviceId
        self.portId = portId
        self.channelId = channelId
        self.direction = direction
    }
}

struct ConnectionEdge: Identifiable, Hashable, Codable {
    var id: UUID
    var from: IOEndpointRef
    var to: IOEndpointRef
    var fromName: String
    var toName: String

    init(
        id: UUID = UUID(),
        from: IOEndpointRef,
        to: IOEndpointRef,
        fromName: String = "",
        toName: String = ""
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.fromName = fromName
        self.toName = toName
    }
}

struct ConnectionBundle: Identifiable, Hashable, Codable {
    var id: UUID
    var fromDeviceId: UUID
    var toDeviceId: UUID
    var endpointNames: [String: String]
    var edges: [ConnectionEdge]

    init(
        id: UUID = UUID(),
        fromDeviceId: UUID,
        toDeviceId: UUID,
        endpointNames: [String: String] = [:],
        edges: [ConnectionEdge] = []
    ) {
        self.id = id
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.endpointNames = endpointNames
        self.edges = edges
    }

    var normalizedPairKey: String {
        let a = fromDeviceId.uuidString
        let b = toDeviceId.uuidString
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

@MainActor
final class ConnectionsStore: ObservableObject {
    @Published private(set) var bundlesByStudio: [UUID: [String: ConnectionBundle]] = [:]

    init() {}

    /// Ensure a bundle exists for the device pair so the main canvas can render a link.
    func ensureLinkSummary(studioId: UUID, fromId: UUID, toId: UUID) {
        _ = ensureBundle(studioId: studioId, fromId: fromId, toId: toId)
    }

    public func links(for studioId: UUID) -> [ConnectionLinkSummary] {
        let bundles: [ConnectionBundle] = bundlesByStudio[studioId].map { Array($0.values) } ?? []
        return bundles.map { ConnectionLinkSummary(id: $0.id, fromDeviceId: $0.fromDeviceId, toDeviceId: $0.toDeviceId) }
    }
    
    /// Find a bundle by its bundle id (the UI selects a link by id).
    public func bundle(for studioId: UUID, linkId: UUID) -> ConnectionBundle? {
        let bundles: [ConnectionBundle] = bundlesByStudio[studioId].map { Array($0.values) } ?? []
        return bundles.first(where: { $0.id == linkId })
    }

    /// Delete a bundle by its bundle id.
    @discardableResult
    public func deleteBundle(studioId: UUID, linkId: UUID) -> Bool {
        guard var studioBundles = bundlesByStudio[studioId] else { return false }
        guard let key = studioBundles.first(where: { $0.value.id == linkId })?.key else { return false }

        let removed = (studioBundles.removeValue(forKey: key) != nil)
        bundlesByStudio[studioId] = studioBundles
        if removed { persist(studioId: studioId) }
        return removed
    }

    func ensureBundle(studioId: UUID, fromId: UUID, toId: UUID) -> ConnectionBundle {
        let key = normalizedPairKey(fromId, toId)
        if let existing = bundlesByStudio[studioId]?[key] { return existing }

        var studioBundles = bundlesByStudio[studioId] ?? [:]
        let created = ConnectionBundle(fromDeviceId: fromId, toDeviceId: toId)
        studioBundles[key] = created
        bundlesByStudio[studioId] = studioBundles
        persist(studioId: studioId)
        return created
    }

    func upsertBundle(studioId: UUID, bundle: ConnectionBundle) {
        var studioBundles = bundlesByStudio[studioId] ?? [:]
        studioBundles[bundle.normalizedPairKey] = bundle
        bundlesByStudio[studioId] = studioBundles
        persist(studioId: studioId)
    }

    struct ConnectionConflict: Hashable {
        let existingEdge: ConnectionEdge
        let existingBundle: ConnectionBundle

        var message: String {
            let lhs = existingEdge.toName.isEmpty ? "This input" : existingEdge.toName
            let rhs = existingEdge.fromName.isEmpty ? "an existing output" : existingEdge.fromName
            return "\(lhs) is already connected to \(rhs)."
        }
    }

    func conflictForDestinationInput(studioId: UUID, destination: IOEndpointRef) -> ConnectionConflict? {
        guard destination.direction == .input else { return nil }
        guard let studioBundles = bundlesByStudio[studioId] else { return nil }
        for (_, bundle) in studioBundles {
            if let edge = bundle.edges.first(where: { $0.to == destination }) {
                return ConnectionConflict(existingEdge: edge, existingBundle: bundle)
            }
        }
        return nil
    }

    func isInputUsed(studioId: UUID, input: IOEndpointRef) -> Bool {
        conflictForDestinationInput(studioId: studioId, destination: input) != nil
    }

    func replaceEdge(
        studioId: UUID,
        fromDeviceId: UUID,
        toDeviceId: UUID,
        from: IOEndpointRef,
        to: IOEndpointRef,
        fromName: String = "",
        toName: String = ""
    ) {
        removeEdgesTargetingInput(studioId: studioId, input: to)
        var b = ensureBundle(studioId: studioId, fromId: fromDeviceId, toId: toDeviceId)
        b.edges.append(ConnectionEdge(from: from, to: to, fromName: fromName, toName: toName))
        upsertBundle(studioId: studioId, bundle: b)
    }

    private func removeEdgesTargetingInput(studioId: UUID, input: IOEndpointRef) {
        guard var studioBundles = bundlesByStudio[studioId] else { return }
        var changed = false
        for (key, var bundle) in studioBundles {
            let original = bundle.edges.count
            bundle.edges.removeAll(where: { $0.to == input })
            if bundle.edges.count != original {
                studioBundles[key] = bundle
                changed = true
            }
        }
        if changed {
            bundlesByStudio[studioId] = studioBundles
            persist(studioId: studioId)
        }
    }

    func load(studioId: UUID) {
        let key = persistenceKey(studioId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: ConnectionBundle].self, from: data)
            bundlesByStudio[studioId] = decoded
        } catch {
            print("ConnectionsStore.load decode error:", error)
        }
    }

    func persist(studioId: UUID) {
        let key = persistenceKey(studioId)
        let bundles = bundlesByStudio[studioId] ?? [:]
        DispatchQueue.global(qos: .utility).async {
            do {
                let data = try JSONEncoder().encode(bundles)
                UserDefaults.standard.set(data, forKey: key)
            } catch {
                print("ConnectionsStore.persist encode error:", error)
            }
        }
    }

    private func normalizedPairKey(_ a: UUID, _ b: UUID) -> String {
        let aa = a.uuidString
        let bb = b.uuidString
        return aa < bb ? "\(aa)|\(bb)" : "\(bb)|\(aa)"
    }

    private func persistenceKey(_ studioId: UUID) -> String {
        "studio-guru.connections.\(studioId.uuidString)"
    }
}

extension IOEndpointRef {
    static func input(deviceId: UUID, portId: UUID, channelId: UUID) -> IOEndpointRef {
        IOEndpointRef(deviceId: deviceId, portId: portId, channelId: channelId, direction: .input)
    }

    static func output(deviceId: UUID, portId: UUID, channelId: UUID) -> IOEndpointRef {
        IOEndpointRef(deviceId: deviceId, portId: portId, channelId: channelId, direction: .output)
    }
}

// MARK: - Patchbay Overlay

struct ConnectionsDialogView: View {
    @Environment(\.dismiss) private var dismiss

    let studio: Studio
    let fromDeviceId: UUID
    let toDeviceId: UUID
    @ObservedObject var store: ConnectionsStore


    // Conflict / replace flow
    @State private var pendingEdge: (from: IOEndpointRef, to: IOEndpointRef)? = nil
    @State private var replaceTargets: Set<String> = [] // endpointKey(for: input)
    @State private var isShowingReplaceAlert: Bool = false
    @State private var replaceMessage: String = ""

    // Save validation
    @State private var isShowingSaveBlockedAlert: Bool = false
    @State private var saveBlockedMessage: String = ""

    // Live drag line while connecting inside the overlay
    @State private var tempDrag: (from: IOEndpointRef, start: CGPoint, location: CGPoint)? = nil
    @State private var endpointRects: [String: CGRect] = [:]

    // Staged edits (one Save)
    @State private var workingBundle: ConnectionBundle

    init(studio: Studio, fromDeviceId: UUID, toDeviceId: UUID, store: ConnectionsStore) {
        self.studio = studio
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.store = store

        let b = store.ensureBundle(studioId: studio.id, fromId: fromDeviceId, toId: toDeviceId)
        _workingBundle = State(initialValue: b)
    }

    private var fromDevice: DeviceInstance? { studio.devices.first(where: { $0.id == fromDeviceId }) }
    private var toDevice: DeviceInstance? { studio.devices.first(where: { $0.id == toDeviceId }) }

    var body: some View {
        NavigationStack {
            ZStack {
                HStack(spacing: 0) {
                    // LEFT: source (outputs)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(fromDevice?.nickname ?? "Source")
                            .font(.title3).bold()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if let fromDevice, !fromDevice.computerInterfaces.isEmpty {
                                    Text("Computer")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    ComputerEndpointsColumnView(
                                        studioId: studio.id,
                                        device: fromDevice,
                                        direction: .output,
                                        side: .left,
                                        bundle: $workingBundle,
                                        store: store,
                                        onCreateEdge: stageEdge,
                                        onBeginDrag: beginTempDrag,
                                        onUpdateDrag: updateTempDrag,
                                        onEndDrag: endTempDrag
                                    )
                                    .padding(.bottom, 6)
                                }

                                Text("Outputs")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                EndpointsColumnView(
                                    studioId: studio.id,
                                    device: fromDevice,
                                    direction: .output,
                                    side: .left,
                                    bundle: $workingBundle,
                                    store: store,
                                    onCreateEdge: stageEdge,
                                    onBeginDrag: beginTempDrag,
                                    onUpdateDrag: updateTempDrag,
                                    onEndDrag: endTempDrag
                                )

                                Spacer(minLength: 0)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
                    .padding(16)

                    Divider()

                    // CENTER: lines gutter (grey zone)
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .frame(width: 120)
                    .padding(.vertical, 16)

                    Divider()

                    // RIGHT: destination (inputs)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(toDevice?.nickname ?? "Destination")
                            .font(.title3).bold()

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                if let toDevice, !toDevice.computerInterfaces.isEmpty {
                                    Text("Computer")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)

                                    ComputerEndpointsColumnView(
                                        studioId: studio.id,
                                        device: toDevice,
                                        direction: .input,
                                        side: .right,
                                        bundle: $workingBundle,
                                        store: store,
                                        onCreateEdge: stageEdge,
                                        onBeginDrag: beginTempDrag,
                                        onUpdateDrag: updateTempDrag,
                                        onEndDrag: endTempDrag
                                    )
                                    .padding(.bottom, 6)
                                }

                                Text("Inputs")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)

                                EndpointsColumnView(
                                    studioId: studio.id,
                                    device: toDevice,
                                    direction: .input,
                                    side: .right,
                                    bundle: $workingBundle,
                                    store: store,
                                    onCreateEdge: stageEdge,
                                    onBeginDrag: beginTempDrag,
                                    onUpdateDrag: updateTempDrag,
                                    onEndDrag: endTempDrag
                                )

                                Spacer(minLength: 0)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity)
                    .padding(16)
                }
                .coordinateSpace(name: "connections")
                .onPreferenceChange(EndpointRectPreferenceKey.self) { endpointRects = $0 }
                // Draw lines across both columns, into the grey center gutter
                .overlayPreferenceValue(EndpointFramePreferenceKey.self) { anchors in
                    GeometryReader { proxy in
                        Canvas { context, _ in
                            for e in workingBundle.edges {
                                let fromKey = endpointKey(for: e.from)
                                let toKey = endpointKey(for: e.to)
                                guard let a1 = anchors[fromKey], let a2 = anchors[toKey] else { continue }

                                let r1 = proxy[a1]
                                let r2 = proxy[a2]

                                // Start at right edge of output row; end at left edge of input row
                                let start = CGPoint(x: r1.maxX, y: r1.midY)
                                let end = CGPoint(x: r2.minX, y: r2.midY)

                                var path = Path()
                                path.move(to: start)
                                let dx = end.x - start.x
                                let c1 = CGPoint(x: start.x + dx * 0.35, y: start.y)
                                let c2 = CGPoint(x: start.x + dx * 0.65, y: end.y)
                                path.addCurve(to: end, control1: c1, control2: c2)

                                context.stroke(path, with: .color(Color.accentColor.opacity(0.75)), lineWidth: 2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }

                if let d = tempDrag {
                    Canvas { context, _ in
                        var path = Path()
                        path.move(to: d.start)
                        let dx = d.location.x - d.start.x
                        let c1 = CGPoint(x: d.start.x + dx * 0.35, y: d.start.y)
                        let c2 = CGPoint(x: d.start.x + dx * 0.65, y: d.location.y)
                        path.addCurve(to: d.location, control1: c1, control2: c2)
                        context.stroke(path, with: .color(Color.accentColor.opacity(0.75)), lineWidth: 2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationTitle("Connections")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAll() }
                }
            }
            .alert("Replace existing connection?", isPresented: $isShowingReplaceAlert) {
                Button("Replace", role: .destructive) {
                    guard let pendingEdge else { return }
                    replaceTargets.insert(endpointKey(for: pendingEdge.to))
                    applyEdgeToWorkingBundle(pendingEdge.from, pendingEdge.to)
                    self.pendingEdge = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingEdge = nil
                }
            } message: {
                Text(replaceMessage)
            }
            .alert("Can’t Save Yet", isPresented: $isShowingSaveBlockedAlert) {
                Button("OK") {}
            } message: {
                Text(saveBlockedMessage)
            }
        }
        .frame(minWidth: 860, idealWidth: 980, maxWidth: .infinity,
               minHeight: 560, idealHeight: 680, maxHeight: .infinity)
    }
    // MARK: - Live drag helpers (overlay)

    private func beginTempDrag(_ endpoint: IOEndpointRef) {
        let key = endpointKey(for: endpoint)
        guard let rect = endpointRects[key] else { return }
        // Start at the arrow side of the row: right edge for outputs, left edge for inputs.
        let startX: CGFloat = (endpoint.direction == .output) ? rect.maxX : rect.minX
        let start = CGPoint(x: startX, y: rect.midY)
        tempDrag = (from: endpoint, start: start, location: start)
    }

    private func updateTempDrag(location: CGPoint) {
        guard tempDrag != nil else { return }
        tempDrag!.location = location
    }

    private func endTempDrag(location: CGPoint) {
        defer { tempDrag = nil }
        guard let d = tempDrag else { return }

        // Find which endpoint row the drag ended over.
        if let (key, rect) = endpointRects.first(where: { $0.value.contains(location) }),
           let target = parseEndpointKey(key) {
            stageEdge(d.from, target)
        }
    }

    // MARK: - Staging

    private func stageEdge(_ a: IOEndpointRef, _ b: IOEndpointRef) {
        // Normalize so from=output, to=input regardless of drag direction.
        let output: IOEndpointRef
        let input: IOEndpointRef

        switch (a.direction, b.direction) {
        case (.output, .input):
            output = a
            input = b
        case (.input, .output):
            output = b
            input = a
        default:
            return
        }

        // Bundle-local conflict
        if workingBundle.edges.contains(where: { $0.to == input }) {
            pendingEdge = (from: output, to: input)
            replaceMessage = "That input is already connected in this connection bundle. Replace it?"
            isShowingReplaceAlert = true
            return
        }

        // Studio-wide conflict
        if let c = store.conflictForDestinationInput(studioId: studio.id, destination: input) {
            pendingEdge = (from: output, to: input)
            replaceMessage = c.message + "\n\nReplace it with this new connection?"
            isShowingReplaceAlert = true
            return
        }

        applyEdgeToWorkingBundle(output, input)
    }

    private func applyEdgeToWorkingBundle(_ output: IOEndpointRef, _ input: IOEndpointRef) {
        // Replace any existing mapping to this input (within this working bundle)
        workingBundle.edges.removeAll(where: { $0.to == input })

        let fromName = workingBundle.endpointNames[endpointKey(for: output)] ?? ""
        let toName = workingBundle.endpointNames[endpointKey(for: input)] ?? ""
        workingBundle.edges.append(ConnectionEdge(from: output, to: input, fromName: fromName, toName: toName))
    }

    // MARK: - Save

    private func saveAll() {
        // Validate: any input used elsewhere must be explicitly approved for replacement.
        for edge in workingBundle.edges {
            let input = edge.to
            if let c = store.conflictForDestinationInput(studioId: studio.id, destination: input) {
                let key = endpointKey(for: input)
                if !replaceTargets.contains(key) {
                    saveBlockedMessage = c.message + "\n\nResolve this by re-dragging to that input and choosing Replace, or pick a free input."
                    isShowingSaveBlockedAlert = true
                    return
                }
            }
        }

        // Apply approved replacements (clears other bundles targeting those inputs)
        for edge in workingBundle.edges {
            let inputKey = endpointKey(for: edge.to)
            if replaceTargets.contains(inputKey) {
                store.replaceEdge(
                    studioId: studio.id,
                    fromDeviceId: edge.from.deviceId,
                    toDeviceId: edge.to.deviceId,
                    from: edge.from,
                    to: edge.to,
                    fromName: workingBundle.endpointNames[endpointKey(for: edge.from)] ?? edge.fromName,
                    toName: workingBundle.endpointNames[endpointKey(for: edge.to)] ?? edge.toName
                )
            }
        }

        // Persist this bundle (names + staged edges)
        store.upsertBundle(studioId: studio.id, bundle: workingBundle)
        dismiss()
    }

    // Key format must match ConnectionBundle.endpointNames.
    private func endpointKey(for endpoint: IOEndpointRef) -> String {
        "\(endpoint.deviceId.uuidString):\(endpoint.portId.uuidString):\(endpoint.channelId.uuidString):\(endpoint.direction.rawValue)"
    }
}

// MARK: - Columns / Rows

fileprivate enum ConnectionsColumnSide {
    case left
    case right
}

fileprivate struct EndpointsColumnView: View {
    let studioId: UUID
    let device: DeviceInstance?
    let direction: IOEndpointRef.Direction
    let side: ConnectionsColumnSide

    @Binding var bundle: ConnectionBundle
    @ObservedObject var store: ConnectionsStore

    let onCreateEdge: (IOEndpointRef, IOEndpointRef) -> Void
    let onBeginDrag: (IOEndpointRef) -> Void
    let onUpdateDrag: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let device {
                ForEach(device.ports.filter { port in
                    (direction == .output && port.directionRaw == "output") ||
                    (direction == .input && port.directionRaw == "input")
                }, id: \.id) { port in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(port.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ForEach(port.channels, id: \.id) { ch in
                            let endpoint = IOEndpointRef(
                                deviceId: device.id,
                                portId: port.id,
                                channelId: ch.id,
                                direction: direction
                            )

                            EndpointRowView(
                                studioId: studioId,
                                endpoint: endpoint,
                                portName: port.name,
                                channelName: ch.nameShort,
                                allowsNaming: true,       // audio/digital allowed
                                side: side,
                                direction: direction,
                                bundle: $bundle,
                                store: store,
                                onCreateEdge: onCreateEdge,
                                onBeginDrag: onBeginDrag,
                                onUpdateDrag: onUpdateDrag,
                                onEndDrag: onEndDrag
                            )
                        }
                    }
                    .padding(.bottom, 4)
                }
            } else {
                Text("No device")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

fileprivate struct ComputerEndpointsColumnView: View {
    let studioId: UUID
    let device: DeviceInstance
    let direction: IOEndpointRef.Direction
    let side: ConnectionsColumnSide

    @Binding var bundle: ConnectionBundle
    @ObservedObject var store: ConnectionsStore

    let onCreateEdge: (IOEndpointRef, IOEndpointRef) -> Void
    let onBeginDrag: (IOEndpointRef) -> Void
    let onUpdateDrag: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(device.computerInterfaces.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { iface in
                let portId = stableUUID("computerPort|\(device.id.uuidString)|\(iface.rawValue)")
                let channelId = stableUUID("computerCh|\(device.id.uuidString)|\(iface.rawValue)")

                let endpoint = IOEndpointRef(
                    deviceId: device.id,
                    portId: portId,
                    channelId: channelId,
                    direction: direction
                )

                EndpointRowView(
                    studioId: studioId,
                    endpoint: endpoint,
                    portName: iface.rawValue,
                    channelName: "",
                    allowsNaming: false, // computer endpoints NOT nameable
                    side: side,
                    direction: direction,
                    bundle: $bundle,
                    store: store,
                    onCreateEdge: onCreateEdge,
                    onBeginDrag: onBeginDrag,
                    onUpdateDrag: onUpdateDrag,
                    onEndDrag: onEndDrag
                )
            }
        }
    }
}

fileprivate struct EndpointRowView: View {
    let studioId: UUID
    let endpoint: IOEndpointRef
    let portName: String
    let channelName: String
    let allowsNaming: Bool
    let side: ConnectionsColumnSide
    let direction: IOEndpointRef.Direction

    @Binding var bundle: ConnectionBundle
    @ObservedObject var store: ConnectionsStore

    let onCreateEdge: (IOEndpointRef, IOEndpointRef) -> Void
    let onBeginDrag: (IOEndpointRef) -> Void
    let onUpdateDrag: (CGPoint) -> Void
    let onEndDrag: (CGPoint) -> Void

    @State private var tempDragStartNeeded: Bool = true

    private var labelText: String {
        channelName.isEmpty ? portName : "\(portName) \(channelName)"
    }

    private var endpointKey: String {
        "\(endpoint.deviceId.uuidString):\(endpoint.portId.uuidString):\(endpoint.channelId.uuidString):\(endpoint.direction.rawValue)"
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { bundle.endpointNames[endpointKey] ?? "" },
            set: { bundle.endpointNames[endpointKey] = $0 }
        )
    }

    private var isInputUsedElsewhere: Bool {
        guard direction == .input else { return false }
        let used = store.isInputUsed(studioId: studioId, input: endpoint)
        if !used { return false }
        return !bundle.edges.contains(where: { $0.to == endpoint })
    }

    var body: some View {
        HStack(spacing: 10) {
            if side == .right {
                // Right side: arrow is on the LEFT, accepts drops.
                dropHandle
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(labelText)
                    .font(.body)
                    .lineLimit(1)

                if allowsNaming {
                    TextField("Name", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 120, idealWidth: 180, maxWidth: 220)
                }
            }
            .foregroundStyle(isInputUsedElsewhere ? .orange : .primary)

            Spacer(minLength: 0)

            if side == .left {
                // Left side: arrow is on the RIGHT, starts drags.
                dragHandle
            }

            if isInputUsedElsewhere {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .anchorPreference(key: EndpointFramePreferenceKey.self, value: .bounds) { anchor in
            [endpointKey: anchor]
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: EndpointRectPreferenceKey.self,
                        value: [endpointKey: proxy.frame(in: .named("connections"))]
                    )
            }
        )
    }

    private var dragHandle: some View {
        Triangle()
            .fill(Color.accentColor.opacity(0.9))
            .frame(width: 14, height: 12)
            .rotationEffect(.degrees(90))
            .padding(8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("connections"))
                    .onChanged { value in
                        // Start the temp line on first movement
                        if tempDragStartNeeded {
                            onBeginDrag(endpoint)
                            tempDragStartNeeded = false
                        }
                        onUpdateDrag(value.location)
                    }
                    .onEnded { value in
                        onEndDrag(value.location)
                        tempDragStartNeeded = true
                    }
            )
            .accessibilityLabel("Drag to connect")
    }

    private var dropHandle: some View {
        Triangle()
            .fill(isInputUsedElsewhere ? Color.orange.opacity(0.75) : Color.accentColor.opacity(0.35))
            .frame(width: 14, height: 12)
            .rotationEffect(.degrees(-90))
            .padding(8)
            .contentShape(Rectangle())
            .onDrop(of: [UTType.text.identifier], isTargeted: nil) { providers in
                guard !isInputUsedElsewhere else { return false }
                guard let item = providers.first else { return false }
                item.loadObject(ofClass: NSString.self) { obj, _ in
                    guard let ns = obj as? NSString else { return }
                    let key = String(ns)
                    guard let from = parseEndpointKey(key) else { return }
                    DispatchQueue.main.async {
                        onCreateEdge(from, endpoint)
                    }
                }
                return true
            }
            .accessibilityLabel("Drop to connect")
    }
}

// MARK: - Anchors for drawing lines

fileprivate struct EndpointFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

fileprivate struct EndpointRectPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Utilities

fileprivate func parseEndpointKey(_ key: String) -> IOEndpointRef? {
    // "deviceId:portId:channelId:direction"
    let parts = key.split(separator: ":")
    guard parts.count == 4 else { return nil }
    guard let did = UUID(uuidString: String(parts[0])) else { return nil }
    guard let pid = UUID(uuidString: String(parts[1])) else { return nil }
    guard let cid = UUID(uuidString: String(parts[2])) else { return nil }
    guard let dir = IOEndpointRef.Direction(rawValue: String(parts[3])) else { return nil }
    return IOEndpointRef(deviceId: did, portId: pid, channelId: cid, direction: dir)
}

fileprivate func stableUUID(_ s: String) -> UUID {
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

// Local triangle (file-scoped) so it won’t collide with your canvas Triangle
fileprivate struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
