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

    // MARK: - Explosion / occupancy helpers

    struct EndpointOccupancy: Hashable {
        let endpoint: IOEndpointRef
        let edge: ConnectionEdge
        let bundle: ConnectionBundle
        let isEndpointFromSide: Bool  // true if `endpoint` == edge.from, false if `endpoint` == edge.to

        var otherEndpoint: IOEndpointRef { isEndpointFromSide ? edge.to : edge.from }
        var otherNameFromEdge: String { isEndpointFromSide ? edge.toName : edge.fromName }
    }

    /// Returns the first edge that uses the given endpoint (either as from or to).
    func occupancyForEndpoint(studioId: UUID, endpoint: IOEndpointRef) -> EndpointOccupancy? {
        guard let studioBundles = bundlesByStudio[studioId] else { return nil }
        for (_, bundle) in studioBundles {
            if let e = bundle.edges.first(where: { $0.from == endpoint }) {
                return EndpointOccupancy(endpoint: endpoint, edge: e, bundle: bundle, isEndpointFromSide: true)
            }
            if let e = bundle.edges.first(where: { $0.to == endpoint }) {
                return EndpointOccupancy(endpoint: endpoint, edge: e, bundle: bundle, isEndpointFromSide: false)
            }
        }
        return nil
    }

    /// Resolve a human-friendly label for an endpoint.
    /// - Prefers per-endpoint naming stored in the bundle (user-entered names)
    /// - Falls back to device port + channel labels from the Studio models
    func endpointDisplayLabel(studio: Studio, bundle: ConnectionBundle?, endpoint: IOEndpointRef) -> String {
        // 1) Prefer bundle-provided endpoint name (typed by user in the overlay)
        if let bundle {
            let key = "\(endpoint.deviceId.uuidString):\(endpoint.portId.uuidString):\(endpoint.channelId.uuidString):\(endpoint.direction.rawValue)"
            if let named = bundle.endpointNames[key], !named.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return named
            }
        }

        // 2) Fall back to device port/channel labels
        guard let device = studio.devices.first(where: { $0.id == endpoint.deviceId }) else {
            return "(Unknown)"
        }

        // Regular device ports
        if let p = device.ports.first(where: { $0.id == endpoint.portId }) {
            let portName = p.name
            if let ch = p.channels.first(where: { $0.id == endpoint.channelId }) {
                let short = ch.nameShort.trimmingCharacters(in: .whitespacesAndNewlines)
                return short.isEmpty ? portName : "\(portName) \(short)"
            }
            return portName
        }

        // Computer interface endpoints (stable UUIDs)
        let counts = device.computerInterfaceCounts
        for iface in counts.keys {
            let n = max(0, counts[iface] ?? 0)
            if n == 0 { continue }
            for i in 1...n {
                let pid = stableUUID("computerPort|\(device.id.uuidString)|\(iface.rawValue)|\(i)")
                let cid = stableUUID("computerCh|\(device.id.uuidString)|\(iface.rawValue)|\(i)")
                if pid == endpoint.portId && cid == endpoint.channelId {
                    return (n > 1) ? "\(iface.rawValue) \(i)" : iface.rawValue
                }
            }
        }

        return "(Unknown)"
    }

    /// Returns a display string for what's connected to the given endpoint ("<Other Device> — <Other Endpoint>").
    func connectedToText(studio: Studio, studioId: UUID, endpoint: IOEndpointRef) -> String? {
        guard let occ = occupancyForEndpoint(studioId: studioId, endpoint: endpoint) else { return nil }

        let otherDeviceName = studio.devices.first(where: { $0.id == occ.otherEndpoint.deviceId })?.nickname ?? "(Unknown Device)"

        // Prefer other endpoint's user-entered name (from bundle.endpointNames), else edge-provided name, else model label.
        let otherLabelFromNames = endpointDisplayLabel(studio: studio, bundle: occ.bundle, endpoint: occ.otherEndpoint)
        let edgeName = occ.otherNameFromEdge.trimmingCharacters(in: .whitespacesAndNewlines)

        let rhs: String
        if !otherLabelFromNames.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && otherLabelFromNames != "(Unknown)" {
            rhs = otherLabelFromNames
        } else if !edgeName.isEmpty {
            rhs = edgeName
        } else {
            rhs = endpointDisplayLabel(studio: studio, bundle: nil, endpoint: occ.otherEndpoint)
        }

        return "\(otherDeviceName) — \(rhs)"
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

    // Delete mapping (edge) flow
    @State private var edgePendingDelete: ConnectionEdge? = nil
    @State private var isShowingEdgeDeleteAlert: Bool = false

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
                                if let fromDevice, !fromDevice.computerInterfaceCounts.isEmpty {
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
                                if let toDevice, !toDevice.computerInterfaceCounts.isEmpty {
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

                // Interactive hit targets for existing lines (needed for right-click / long-press / double-click)
                .overlayPreferenceValue(EndpointFramePreferenceKey.self) { anchors in
                    GeometryReader { proxy in
                        ZStack {
                            ForEach(workingBundle.edges) { edge in
                                let fromKey = endpointKey(for: edge.from)
                                let toKey = endpointKey(for: edge.to)

                                if let a1 = anchors[fromKey], let a2 = anchors[toKey] {
                                    let r1 = proxy[a1]
                                    let r2 = proxy[a2]

                                    let start = CGPoint(x: r1.maxX, y: r1.midY)
                                    let end = CGPoint(x: r2.minX, y: r2.midY)

                                    EdgeHitPathView(from: start, to: end)
                                        // Double-click (macOS) / double-tap (iOS) to delete
                                        .highPriorityGesture(
                                            TapGesture(count: 2)
                                                .onEnded {
                                                    edgePendingDelete = edge
                                                    isShowingEdgeDeleteAlert = true
                                                }
                                        )
                                        // Long-press on iPad/iPhone to delete
                                        .onLongPressGesture {
                                            edgePendingDelete = edge
                                            isShowingEdgeDeleteAlert = true
                                        }
                                        // Right-click / context menu
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                edgePendingDelete = edge
                                                isShowingEdgeDeleteAlert = true
                                            } label: {
                                                Label("Delete Mapping", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        // Give the overlay a real layout box
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            .alert("Delete mapping?", isPresented: $isShowingEdgeDeleteAlert) {
                Button("Delete", role: .destructive) {
                    guard let e = edgePendingDelete else { return }
                    workingBundle.edges.removeAll(where: { $0.id == e.id })
                    edgePendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    edgePendingDelete = nil
                }
            } message: {
                Text("This will remove the selected mapping.")
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
        if let (key, _) = endpointRects.first(where: { $0.value.contains(location) }),
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

        if let reason = validateEdge(output: output, input: input) {
            saveBlockedMessage = reason
            isShowingSaveBlockedAlert = true
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
                // If the "conflict" is coming from THIS bundle (i.e. existing mapping), allow Save.
                if c.existingBundle.id == workingBundle.id {
                    continue
                }

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
    // MARK: - Endpoint resolution and validation helpers

    private struct ResolvedEndpoint {
        enum Kind {
            case devicePort(type: PortType, portName: String)
            case computerInterface(ComputerInterface)
            case unknown
        }
        let kind: Kind
    }

    private func resolveEndpoint(_ e: IOEndpointRef) -> ResolvedEndpoint {
        guard let device = studio.devices.first(where: { $0.id == e.deviceId }) else {
            return ResolvedEndpoint(kind: .unknown)
        }

        // 1) Try resolve as a regular device port
        if let p = device.ports.first(where: { $0.id == e.portId }) {
            let t = p.type
            return ResolvedEndpoint(kind: .devicePort(type: t, portName: p.name))
        }

        // 2) Try resolve as a computer interface endpoint by matching stable UUIDs.
        let counts = device.computerInterfaceCounts
        for iface in counts.keys {
            let n = max(0, counts[iface] ?? 0)
            if n == 0 { continue }
            for i in 1...n {
                let pid = stableUUID("computerPort|\(device.id.uuidString)|\(iface.rawValue)|\(i)")
                if pid == e.portId {
                    return ResolvedEndpoint(kind: .computerInterface(iface))
                }
            }
        }

        return ResolvedEndpoint(kind: .unknown)
    }

    private func validateEdge(output: IOEndpointRef, input: IOEndpointRef) -> String? {
        let outR = resolveEndpoint(output)
        let inR = resolveEndpoint(input)

        // --- MADI: only MADI Out -> MADI In ---
        if case let .devicePort(type: outType, portName: _) = outR.kind,
           case let .devicePort(type: inType, portName: _) = inR.kind {
            let usesMadi = (outType == .madiOut || outType == .madiIn || inType == .madiOut || inType == .madiIn)
            if usesMadi && !(outType == .madiOut && inType == .madiIn) {
                return "MADI connections must go from a MADI output to a MADI input."
            }
        } else {
            if case let .devicePort(type: outType, portName: _) = outR.kind, (outType == .madiOut || outType == .madiIn) {
                return "MADI connections must go from a MADI output to a MADI input."
            }
            if case let .devicePort(type: inType, portName: _) = inR.kind, (inType == .madiOut || inType == .madiIn) {
                return "MADI connections must go from a MADI output to a MADI input."
            }
        }

        // --- Dante: only Dante (Ethernet) <-> Computer Ethernet ---
        func isDanteDevicePort(_ r: ResolvedEndpoint) -> Bool {
            if case let .devicePort(type: t, portName: n) = r.kind {
                return t == .ethernet && n.localizedCaseInsensitiveContains("dante")
            }
            return false
        }
        func isComputerEthernet(_ r: ResolvedEndpoint) -> Bool {
            if case let .computerInterface(iface) = r.kind { return iface == .ethernet }
            return false
        }

        let outIsDante = isDanteDevicePort(outR)
        let inIsDante = isDanteDevicePort(inR)
        if outIsDante || inIsDante {
            let ok = (outIsDante && isComputerEthernet(inR)) || (inIsDante && isComputerEthernet(outR))
            if !ok {
                return "Dante connections must connect between a Dante (Ethernet) port and a computer Ethernet interface."
            }
        }

        return nil
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
                let ports = device.ports
                    .filter { port in
                        (direction == .output && port.directionRaw == "output") ||
                        (direction == .input && port.directionRaw == "input")
                    }
                    .sorted(by: { connectionPortSortKey($0.name) < connectionPortSortKey($1.name) })

                ForEach(ports, id: \.id) { port in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(port.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let channels = port.channels.sorted(by: { connectionChannelSortKey($0.nameShort) < connectionChannelSortKey($1.nameShort) })
                        ForEach(channels, id: \.id) { ch in
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
            let counts = device.computerInterfaceCounts
            let keys = counts.keys.sorted(by: { $0.rawValue < $1.rawValue })

            ForEach(keys, id: \.self) { iface in
                let n = max(0, counts[iface] ?? 0)
                if n > 0 {
                    ForEach(1...n, id: \.self) { idx in
                        let portId = stableUUID("computerPort|\(device.id.uuidString)|\(iface.rawValue)|\(idx)")
                        let channelId = stableUUID("computerCh|\(device.id.uuidString)|\(iface.rawValue)|\(idx)")

                        let endpoint = IOEndpointRef(
                            deviceId: device.id,
                            portId: portId,
                            channelId: channelId,
                            direction: direction
                        )

                        let label = (n > 1) ? "\(iface.rawValue) \(idx)" : iface.rawValue

                        EndpointRowView(
                            studioId: studioId,
                            endpoint: endpoint,
                            portName: label,
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

// MARK: - Edge interactive overlay

fileprivate struct EdgeHitPathView: View {
    let from: CGPoint
    let to: CGPoint

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
        // Invisible but wide stroke to make it easy to hit
        path
            .stroke(Color.clear, style: StrokeStyle(lineWidth: 22, lineCap: .round))
            .contentShape(path.strokedPath(StrokeStyle(lineWidth: 22, lineCap: .round)))
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

// MARK: - Sorting helpers (Connections overlay)

fileprivate func connectionPortSortKey(_ name: String) -> (Int, Int, String) {
    // Goal: Analog 1, Analog 2, ... then ADAT, MADI, Dante, Ethernet, S/PDIF, AES, MIDI, etc.
    // We sort by a coarse type rank, then by extracted number, then by raw name.
    let lower = name.lowercased()

    let rank: Int
    if lower.contains("analog") { rank = 0 }
    else if lower.contains("adat") { rank = 1 }
    else if lower.contains("madi") { rank = 2 }
    else if lower.contains("dante") { rank = 3 }
    else if lower.contains("ethernet") { rank = 4 }
    else if lower.contains("spdif") || lower.contains("s/pdif") { rank = 5 }
    else if lower.contains("aes") { rank = 6 }
    else if lower.contains("midi") { rank = 7 }
    else { rank = 9 }

    return (rank, extractFirstInt(from: name) ?? Int.max, name)
}

fileprivate func connectionChannelSortKey(_ shortName: String) -> (Int, String) {
    // Typical channel labels are "1", "2", ... or "Ch 1" etc.
    return (extractFirstInt(from: shortName) ?? Int.max, shortName)
}

fileprivate func extractFirstInt(from s: String) -> Int? {
    var current = ""
    for ch in s {
        if ch.isNumber {
            current.append(ch)
        } else if !current.isEmpty {
            break
        }
    }
    return Int(current)
}

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



