//
//  Connections.swift
//  Studio Guru
//
//  Connections data models + store (persisted per studio)
//  Phase 1: device-to-device bundles + placeholder edges
//

import Foundation
import SwiftUI
import Combine

// MARK: - Public Models

public struct ConnectionLinkSummary: Identifiable, Hashable, Codable {
    public let id: UUID
    public let fromDeviceId: UUID
    public let toDeviceId: UUID

    public init(id: UUID = UUID(), fromDeviceId: UUID, toDeviceId: UUID) {
        self.id = id
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
    }

    public var normalizedPairKey: String {
        let a = fromDeviceId.uuidString
        let b = toDeviceId.uuidString
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

public struct ActiveLinkDrag: Equatable {
    public let fromDeviceId: UUID
    public var currentPoint: CGPoint

    public init(fromDeviceId: UUID, currentPoint: CGPoint) {
        self.fromDeviceId = fromDeviceId
        self.currentPoint = currentPoint
    }
}

public struct IOEndpointRef: Hashable, Codable {
    public enum Direction: String, Codable { case input, output }

    public var deviceId: UUID
    public var portId: UUID
    public var channelId: UUID
    public var direction: Direction

    public init(deviceId: UUID, portId: UUID, channelId: UUID, direction: Direction) {
        self.deviceId = deviceId
        self.portId = portId
        self.channelId = channelId
        self.direction = direction
    }
}

public struct ConnectionEdge: Identifiable, Hashable, Codable {
    public var id: UUID
    public var from: IOEndpointRef
    public var to: IOEndpointRef
    public var fromName: String
    public var toName: String

    public init(
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

public struct ConnectionBundle: Identifiable, Hashable, Codable {
    public var id: UUID
    public var fromDeviceId: UUID
    public var toDeviceId: UUID
    public var endpointNames: [String: String]
    public var edges: [ConnectionEdge]

    public init(
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

    public var normalizedPairKey: String {
        let a = fromDeviceId.uuidString
        let b = toDeviceId.uuidString
        return a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }
}

// MARK: - Store

@MainActor
public final class ConnectionsStore: ObservableObject {
    @Published private(set) var bundlesByStudio: [UUID: [String: ConnectionBundle]] = [:]

    public init() {}

    public func links(for studioId: UUID) -> [ConnectionLinkSummary] {
        let bundles: [ConnectionBundle] = bundlesByStudio[studioId].map { Array($0.values) } ?? []
        return bundles.map { ConnectionLinkSummary(id: $0.id, fromDeviceId: $0.fromDeviceId, toDeviceId: $0.toDeviceId) }
    }

    public func ensureLinkSummary(studioId: UUID, fromId: UUID, toId: UUID) {
        _ = ensureBundle(studioId: studioId, fromId: fromId, toId: toId)
    }

    public func ensureBundle(studioId: UUID, fromId: UUID, toId: UUID) -> ConnectionBundle {
        let key = normalizedPairKey(fromId, toId)
        if let existing = bundlesByStudio[studioId]?[key] { return existing }

        var studioBundles = bundlesByStudio[studioId] ?? [:]
        let created = ConnectionBundle(fromDeviceId: fromId, toDeviceId: toId)
        studioBundles[key] = created
        bundlesByStudio[studioId] = studioBundles
        persist(studioId: studioId)
        return created
    }

    public func bundle(for studioId: UUID, linkId: UUID) -> ConnectionBundle? {
        bundlesByStudio[studioId]?.values.first(where: { $0.id == linkId })
    }

    public func bundle(for studioId: UUID, fromId: UUID, toId: UUID) -> ConnectionBundle? {
        bundlesByStudio[studioId]?[normalizedPairKey(fromId, toId)]
    }

    public func upsertBundle(studioId: UUID, bundle: ConnectionBundle) {
        var studioBundles = bundlesByStudio[studioId] ?? [:]
        studioBundles[bundle.normalizedPairKey] = bundle
        bundlesByStudio[studioId] = studioBundles
        persist(studioId: studioId)
    }

    @discardableResult
    public func deleteBundle(studioId: UUID, linkId: UUID) -> Bool {
        guard var studioBundles = bundlesByStudio[studioId] else { return false }
        if let (key, _) = studioBundles.first(where: { $0.value.id == linkId }) {
            studioBundles.removeValue(forKey: key)
            bundlesByStudio[studioId] = studioBundles
            persist(studioId: studioId)
            return true
        }
        return false
    }

    public func load(studioId: UUID) {
        let key = persistenceKey(studioId)
        guard let data = UserDefaults.standard.data(forKey: key) else {
            if bundlesByStudio[studioId] == nil { bundlesByStudio[studioId] = [:] }
            return
        }
        do {
            let decoded = try JSONDecoder().decode([String: ConnectionBundle].self, from: data)
            bundlesByStudio[studioId] = decoded
        } catch {
            print("ConnectionsStore.load decode error:", error)
            if bundlesByStudio[studioId] == nil { bundlesByStudio[studioId] = [:] }
        }
    }

    public func persist(studioId: UUID) {
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

public extension IOEndpointRef {
    static func input(deviceId: UUID, portId: UUID, channelId: UUID) -> IOEndpointRef {
        IOEndpointRef(deviceId: deviceId, portId: portId, channelId: channelId, direction: .input)
    }

    static func output(deviceId: UUID, portId: UUID, channelId: UUID) -> IOEndpointRef {
        IOEndpointRef(deviceId: deviceId, portId: portId, channelId: channelId, direction: .output)
    }
}
