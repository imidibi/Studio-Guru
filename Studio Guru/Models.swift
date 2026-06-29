//
//  Models.swift
//  Studio Guru
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums stored as raw strings (SwiftData-friendly)

enum SignalType: String, Codable, CaseIterable { case audio, midi, clock }

enum PortType: String, Codable, CaseIterable {
    case analogIn, analogOut
    case adatIn, adatOut
    case madiIn, madiOut
    case spdifIn, spdifOut
    case aesIn, aesOut
    case usbAudio, thunderboltAudio
    case midiIn, midiOut
    case wordClockIn, wordClockOut
    case cvIn, cvOut
    case ethernet
    case headphoneOut
    case computerHost
}

enum PortDirection: String, Codable, CaseIterable { case input, output, bidirectional }

enum ChannelGrouping: String, Codable, CaseIterable { case mono, stereoPairable, fixedStereoPair }

enum CableType: String, Codable, CaseIterable { case trs, xlr, ts, opticalADAT, usb, thunderbolt, midiDIN, usbMIDI, wordClockBNC, cv, ethernet, other }

enum DocKind: String, Codable, CaseIterable { case manual, driver, firmware, support, other }

// MARK: - Device Metadata Enums

enum DeviceCategory: String, Codable, CaseIterable {
    case adatExpander = "ADAT Expander"
    case audioInterface = "Audio Interface"
    case busCompressor = "Bus Compressor"
    case channelStrip = "Channel Strip"
    case compressor = "Compressor"
    case computer = "Computer"
    case controlSurface = "Control Surface"
    case digitalMixer = "Digital Mixer"
    case effectsUnit = "Effects Unit"
    case equalizer = "Equalizer"
    case headphoneAmp = "Headphone Amp"
    case headphones = "Headphones"
    case keyboard = "Keyboard"
    case microphone = "Microphone"
    case midiDevice = "MIDI Device"
    case midiInterface = "MIDI Interface"
    case mixer = "Mixer"
    case monitor = "Studio Monitor"
    case multi = "Multi"
    case patchbay = "Patchbay"
    case preamp = "Preamp"
    case synth = "Synth"
    case usbHub = "USB Hub"
    case usbExpander = "USB Expander"
    case videoMonitor = "Video Monitor"
    case other = "Other"
}

enum DigitalFormat: String, Codable, CaseIterable {
    case adat = "ADAT"
    case aesebu = "AES/EBU"
    case dante = "Dante"
    case madi = "MADI"
    case midi = "MIDI over USB"
    case spdif = "S/PDIF"
    case wordClock = "Word Clock"
}

enum ComputerInterface: String, Codable, CaseIterable {
    case firewire = "FireWire"
    case thunderbolt = "Thunderbolt"
    case usb = "USB"
    case usbc = "USB-C"
    case ethernet = "Ethernet"
}

enum SampleRate: Int, Codable, CaseIterable {
    case hz44100 = 44100
    case hz48000 = 48000
    case hz88200 = 88200
    case hz96000 = 96000
    case hz176400 = 176400
    case hz192000 = 192000

    var displayName: String {
        switch self {
        case .hz44100: return "44.1 kHz"
        case .hz48000: return "48 kHz"
        case .hz88200: return "88.2 kHz"
        case .hz96000: return "96 kHz"
        case .hz176400: return "176.4 kHz"
        case .hz192000: return "192 kHz"
        }
    }

    var adatChannelsPerPort: Int {
        switch self {
        case .hz44100, .hz48000: return 8
        default: return 4
        }
    }
}

// MARK: - Studio

@Model
final class Studio {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    
    // Layout settings
    var layoutMode: String = "freeform"  // "freeform" or "snapToGrid"
    var gridSize: Double = 24.0
    var showGridOverlay: Bool = false
    
    // Canvas annotations (PencilKit drawing data)
    @Attribute(.externalStorage) var canvasDrawingData: Data?
    
    // Gear Locker system studio support
    var isSystemStudio: Bool = false
    var systemStudioType: String? = nil  // "gear_locker" for the Gear Locker

    @Relationship(deleteRule: .cascade, inverse: \DeviceInstance.studio) var devices: [DeviceInstance]? = []
    @Relationship(deleteRule: .cascade, inverse: \Connection.studio) var connections: [Connection]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.devices = []
        self.connections = []
    }
    
    func markAsModified() {
        self.modifiedAt = Date()
    }
}

// MARK: - Device

@Model
final class DeviceInstance {
    var id: UUID = UUID()

    var manufacturer: String = ""
    var model: String = ""
    var nickname: String = ""

    // Core metadata
    var categoryRaw: String = DeviceCategory.other.rawValue
    var serialNumber: String = ""
    var location: String = ""

    // External resources
    var supportPageURLString: String?
    var downloadsPageURLString: String?

    // I/O summary (high-level counts)
    var audioInputsCount: Int = 0
    var audioOutputsCount: Int = 0

    // Digital audio port counts
    var adatInputPortsCount: Int = 0
    var adatOutputPortsCount: Int = 0
    var madiInputPortsCount: Int = 0
    var madiOutputPortsCount: Int = 0
    
    // MIDI DIN 5-pin port counts (physical connectors)
    var midiInputPortsCount: Int = 0
    var midiOutputPortsCount: Int = 0
    
    // CV (Control Voltage) port counts
    var cvInputPortsCount: Int = 0
    var cvOutputPortsCount: Int = 0

    // Networking / control ports (used for Dante, remote control, etc.)
    var ethernetPortsCount: Int = 0

    var sampleRateRaw: Int = SampleRate.hz48000.rawValue

    // Digital formats stored as raw strings
    var digitalInputsRaw: [String] = []
    var digitalOutputsRaw: [String] = []

    // Computer interfaces (bi-directional host connections).
    // NOTE: This array supports quantities by allowing duplicates (e.g. ["USB", "USB"] means 2x USB).
    var computerInterfacesRaw: [String] = []

    // Canvas placement
    var posX: Double = 200
    var posY: Double = 200
    var scale: Double = 1.0
    var zIndex: Int = 0
    
    // Layout settings
    var isPinned: Bool = false  // Pinned devices don't move during auto-arrange
    
    // Custom color override (optional - stored as hex string for SwiftData compatibility)
    var customColorHex: String?

    // Optional image paths (sandbox)
    var frontImagePath: String?
    var rearImagePath: String?
    
    // Modification tracking for iCloud sync
    var modifiedAt: Date = Date()
    
    // Gear Locker support
    var isInGearLocker: Bool = false              // Device lives in Gear Locker
    var isAssignedFromLocker: Bool = false        // Device was assigned from locker to a studio
    var lockerSourceDeviceId: UUID? = nil         // Reference to original locker device
    var isGhostDevice: Bool = false               // Documentation placeholder (returned to locker)
    var ghostOfDeviceId: UUID? = nil              // Reference to the locker device this is a ghost of
    
    // Asset Inventory tracking
    var purchasePrice: Double = 0.0               // Original purchase price
    var purchaseDate: Date? = nil                 // Date of purchase
    var purchaseLocation: String = ""             // Where device was purchased
    var receiptImagePath: String? = nil           // Path to receipt image
    var warrantyExpirationDate: Date? = nil       // When warranty expires
    var insurancePolicyNumber: String = ""        // Insurance policy number
    var currentEstimatedValue: Double = 0.0       // Current depreciated value
    var assetNotes: String = ""                   // General notes about the asset

    @Relationship(deleteRule: .cascade, inverse: \Port.device) var ports: [Port]? = []
    @Relationship(deleteRule: .cascade, inverse: \DocLink.device) var docs: [DocLink]? = []
    
    var studio: Studio?

    init(manufacturer: String,
         model: String,
         nickname: String? = nil,
         category: DeviceCategory = .other,
         serialNumber: String = "",
         location: String = "",
         audioInputsCount: Int = 0,
         audioOutputsCount: Int = 0,
         adatInputPortsCount: Int = 0,
         adatOutputPortsCount: Int = 0,
         madiInputPortsCount: Int = 0,
         madiOutputPortsCount: Int = 0,
         midiInputPortsCount: Int = 0,
         midiOutputPortsCount: Int = 0,
         cvInputPortsCount: Int = 0,
         cvOutputPortsCount: Int = 0,
         ethernetPortsCount: Int = 0,
         sampleRate: SampleRate = .hz48000,
         digitalInputs: [DigitalFormat] = [],
         digitalOutputs: [DigitalFormat] = [],
         computerInterfaces: [ComputerInterface] = [],
         posX: Double = 200,
         posY: Double = 200,
         scale: Double = 1.0,
         zIndex: Int = 0) {

        self.id = UUID()
        self.manufacturer = manufacturer
        self.model = model
        self.nickname = nickname ?? model

        self.categoryRaw = category.rawValue
        self.serialNumber = serialNumber
        self.location = location

        self.supportPageURLString = nil
        self.downloadsPageURLString = nil

        self.audioInputsCount = audioInputsCount
        self.audioOutputsCount = audioOutputsCount

        self.adatInputPortsCount = adatInputPortsCount
        self.adatOutputPortsCount = adatOutputPortsCount
        self.madiInputPortsCount = madiInputPortsCount
        self.madiOutputPortsCount = madiOutputPortsCount
        self.midiInputPortsCount = midiInputPortsCount
        self.midiOutputPortsCount = midiOutputPortsCount
        self.cvInputPortsCount = cvInputPortsCount
        self.cvOutputPortsCount = cvOutputPortsCount

        self.ethernetPortsCount = ethernetPortsCount

        self.sampleRateRaw = sampleRate.rawValue

        self.digitalInputsRaw = digitalInputs.map { $0.rawValue }
        self.digitalOutputsRaw = digitalOutputs.map { $0.rawValue }
        self.computerInterfacesRaw = computerInterfaces.map { $0.rawValue }

        self.posX = posX
        self.posY = posY
        self.scale = scale
        self.zIndex = zIndex

        self.frontImagePath = nil
        self.rearImagePath = nil
        self.modifiedAt = Date()
        self.ports = []
        self.docs = []
    }
    
    func markAsModified() {
        self.modifiedAt = Date()
    }

    var category: DeviceCategory {
        get { DeviceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var digitalInputs: [DigitalFormat] {
        get { digitalInputsRaw.compactMap { DigitalFormat(rawValue: $0) } }
        set { digitalInputsRaw = newValue.map { $0.rawValue } }
    }

    var digitalOutputs: [DigitalFormat] {
        get { digitalOutputsRaw.compactMap { DigitalFormat(rawValue: $0) } }
        set { digitalOutputsRaw = newValue.map { $0.rawValue } }
    }

    var computerInterfaces: [ComputerInterface] {
        get { computerInterfacesRaw.compactMap { ComputerInterface(rawValue: $0) } }
        set { computerInterfacesRaw = newValue.map { $0.rawValue } }
    }

    /// Quantities for host interfaces. This is derived from `computerInterfacesRaw` by counting duplicates.
    var computerInterfaceCounts: [ComputerInterface: Int] {
        var counts: [ComputerInterface: Int] = [:]
        for raw in computerInterfacesRaw {
            if let iface = ComputerInterface(rawValue: raw) {
                counts[iface, default: 0] += 1
            }
        }
        return counts
    }

    var sampleRate: SampleRate {
        get { SampleRate(rawValue: sampleRateRaw) ?? .hz48000 }
        set { sampleRateRaw = newValue.rawValue }
    }

    var supportPageURL: URL? {
        guard let supportPageURLString, !supportPageURLString.isEmpty else { return nil }
        return URL(string: supportPageURLString)
    }

    var downloadsPageURL: URL? {
        guard let downloadsPageURLString, !downloadsPageURLString.isEmpty else { return nil }
        return URL(string: downloadsPageURLString)
    }
    
    /// Custom color for this device (overrides category default)
    var customColor: Color? {
        get {
            guard let hex = customColorHex else { return nil }
            return Color(hex: hex)
        }
        set {
            customColorHex = newValue?.toHex()
        }
    }
}

// MARK: - Port

@Model
final class Port {
    var id: UUID = UUID()
    var name: String = ""

    var typeRaw: String = PortType.usbAudio.rawValue
    var directionRaw: String = PortDirection.bidirectional.rawValue

    @Relationship(deleteRule: .cascade, inverse: \Channel.port) var channels: [Channel]? = []
    
    var device: DeviceInstance?

    init(name: String, type: PortType, direction: PortDirection) {
        self.id = UUID()
        self.name = name
        self.typeRaw = type.rawValue
        self.directionRaw = direction.rawValue
        self.channels = []
    }

    var type: PortType {
        PortType(rawValue: typeRaw) ?? .usbAudio
    }

    var direction: PortDirection {
        PortDirection(rawValue: directionRaw) ?? .bidirectional
    }
}

// MARK: - Channel

@Model
final class Channel {
    var id: UUID = UUID()
    var index: Int = 0
    var nameLong: String = ""
    var nameShort: String = ""
    var signalRaw: String = SignalType.audio.rawValue
    var groupingRaw: String = ChannelGrouping.mono.rawValue
    
    var port: Port?

    init(index: Int,
         nameLong: String,
         nameShort: String,
         signal: SignalType = .audio,
         grouping: ChannelGrouping = .mono) {
        self.id = UUID()
        self.index = index
        self.nameLong = nameLong
        self.nameShort = nameShort
        self.signalRaw = signal.rawValue
        self.groupingRaw = grouping.rawValue
    }

    var signal: SignalType { SignalType(rawValue: signalRaw) ?? .audio }
    var grouping: ChannelGrouping { ChannelGrouping(rawValue: groupingRaw) ?? .mono }
}

// MARK: - Connection

@Model
final class Connection {
    var id: UUID = UUID()

    var fromDeviceId: UUID = UUID()
    var fromPortId: UUID = UUID()
    var fromChannelId: UUID = UUID()

    var toDeviceId: UUID = UUID()
    var toPortId: UUID = UUID()
    var toChannelId: UUID = UUID()

    var cableRaw: String = CableType.other.rawValue
    var label: String = ""
    var notes: String?
    
    // Modification tracking for iCloud sync
    var modifiedAt: Date = Date()
    
    var studio: Studio?

    init(fromDeviceId: UUID,
         fromPortId: UUID,
         fromChannelId: UUID,
         toDeviceId: UUID,
         toPortId: UUID,
         toChannelId: UUID,
         cable: CableType = .other,
         label: String = "",
         notes: String? = nil) {
        self.id = UUID()
        self.fromDeviceId = fromDeviceId
        self.fromPortId = fromPortId
        self.fromChannelId = fromChannelId
        self.toDeviceId = toDeviceId
        self.toPortId = toPortId
        self.toChannelId = toChannelId
        self.cableRaw = cable.rawValue
        self.label = label
        self.notes = notes
        self.modifiedAt = Date()
    }

    func markAsModified() {
        self.modifiedAt = Date()
    }

    var cable: CableType { CableType(rawValue: cableRaw) ?? .other }
}

// MARK: - DocLink

@Model
final class DocLink {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = DocKind.other.rawValue

    var urlString: String?
    var localBookmarkData: Data?
    
    // iCloud-stored document path (relative to app's iCloud container)
    var iCloudDocumentPath: String?
    
    // Modification tracking for iCloud sync
    var modifiedAt: Date = Date()
    
    var device: DeviceInstance?

    init(title: String, kind: DocKind, url: URL) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.urlString = url.absoluteString
        self.localBookmarkData = nil
        self.iCloudDocumentPath = nil
        self.modifiedAt = Date()
    }

    init(title: String, kind: DocKind, bookmarkData: Data) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.urlString = nil
        self.localBookmarkData = bookmarkData
        self.iCloudDocumentPath = nil
        self.modifiedAt = Date()
    }
    
    init(title: String, kind: DocKind, iCloudPath: String) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.urlString = nil
        self.localBookmarkData = nil
        self.iCloudDocumentPath = iCloudPath
        self.modifiedAt = Date()
    }
    
    func markAsModified() {
        self.modifiedAt = Date()
    }

    var kind: DocKind { DocKind(rawValue: kindRaw) ?? .other }
}

// MARK: - Export/Import Data Structures

/// Codable representation of a studio for export/import
struct ExportableStudio: Sendable {
    let name: String
    let devices: [ExportableDevice]
    let connections: [ExportableConnection]
    let canvasDrawingData: Data?
    let exportDate: Date
    let appVersion: String

    init(from studio: Studio) {
        self.name = studio.name
        self.devices = (studio.devices ?? []).map { ExportableDevice(from: $0) }
        self.connections = (studio.connections ?? []).map { ExportableConnection(from: $0) }
        self.canvasDrawingData = studio.canvasDrawingData
        self.exportDate = Date()
        self.appVersion = "1.0"
    }
    
    /// Initialize from Studio, building connections from ConnectionsStore instead of studio.connections
    /// This avoids modifying SwiftData during export (which would trigger CloudKit sync)
    init(from studio: Studio, connectionsStore: ConnectionsStore) {
        self.name = studio.name
        self.devices = (studio.devices ?? []).map { ExportableDevice(from: $0) }
        
        // Build connections from ConnectionsStore without modifying SwiftData
        var exportableConnections: [ExportableConnection] = []
        let bundles = connectionsStore.links(for: studio.id)
            .compactMap { connectionsStore.bundle(for: studio.id, linkId: $0.id) }
        
        for bundle in bundles {
            for edge in bundle.edges {
                let connection = ExportableConnection(
                    id: edge.id,
                    fromDeviceId: edge.from.deviceId,
                    fromPortId: edge.from.portId,
                    fromChannelId: edge.from.channelId,
                    toDeviceId: edge.to.deviceId,
                    toPortId: edge.to.portId,
                    toChannelId: edge.to.channelId,
                    cableRaw: CableType.other.rawValue,
                    label: edge.fromName,
                    notes: nil
                )
                exportableConnections.append(connection)
            }
        }
        
        self.connections = exportableConnections
        self.canvasDrawingData = studio.canvasDrawingData
        self.exportDate = Date()
        self.appVersion = "1.0"
    }
}

// Manual Codable conformance to avoid Swift 6 concurrency warnings
extension ExportableStudio: Codable {
    enum CodingKeys: String, CodingKey {
        case name, devices, connections, canvasDrawingData, exportDate, appVersion
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        devices = try container.decode([ExportableDevice].self, forKey: .devices)
        connections = try container.decode([ExportableConnection].self, forKey: .connections)
        canvasDrawingData = try container.decodeIfPresent(Data.self, forKey: .canvasDrawingData)
        exportDate = try container.decode(Date.self, forKey: .exportDate)
        appVersion = try container.decode(String.self, forKey: .appVersion)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(devices, forKey: .devices)
        try container.encode(connections, forKey: .connections)
        try container.encodeIfPresent(canvasDrawingData, forKey: .canvasDrawingData)
        try container.encode(exportDate, forKey: .exportDate)
        try container.encode(appVersion, forKey: .appVersion)
    }
}

struct ExportableDevice: Codable, Sendable {
    let id: UUID
    let manufacturer: String
    let model: String
    let nickname: String
    let categoryRaw: String
    let serialNumber: String
    let location: String
    let supportPageURLString: String?
    let downloadsPageURLString: String?
    let audioInputsCount: Int
    let audioOutputsCount: Int
    let adatInputPortsCount: Int
    let adatOutputPortsCount: Int
    let madiInputPortsCount: Int
    let madiOutputPortsCount: Int
    let midiInputPortsCount: Int
    let midiOutputPortsCount: Int
    let cvInputPortsCount: Int
    let cvOutputPortsCount: Int
    let ethernetPortsCount: Int
    let sampleRateRaw: Int
    let digitalInputsRaw: [String]
    let digitalOutputsRaw: [String]
    let computerInterfacesRaw: [String]
    let posX: Double
    let posY: Double
    let scale: Double
    let zIndex: Int
    let ports: [ExportablePort]
    let docs: [ExportableDocLink]
    
    init(from device: DeviceInstance) {
        self.id = device.id
        self.manufacturer = device.manufacturer
        self.model = device.model
        self.nickname = device.nickname
        self.categoryRaw = device.categoryRaw
        self.serialNumber = device.serialNumber
        self.location = device.location
        self.supportPageURLString = device.supportPageURLString
        self.downloadsPageURLString = device.downloadsPageURLString
        self.audioInputsCount = device.audioInputsCount
        self.audioOutputsCount = device.audioOutputsCount
        self.adatInputPortsCount = device.adatInputPortsCount
        self.adatOutputPortsCount = device.adatOutputPortsCount
        self.madiInputPortsCount = device.madiInputPortsCount
        self.madiOutputPortsCount = device.madiOutputPortsCount
        self.midiInputPortsCount = device.midiInputPortsCount
        self.midiOutputPortsCount = device.midiOutputPortsCount
        self.cvInputPortsCount = device.cvInputPortsCount
        self.cvOutputPortsCount = device.cvOutputPortsCount
        self.ethernetPortsCount = device.ethernetPortsCount
        self.sampleRateRaw = device.sampleRateRaw
        self.digitalInputsRaw = device.digitalInputsRaw
        self.digitalOutputsRaw = device.digitalOutputsRaw
        self.computerInterfacesRaw = device.computerInterfacesRaw
        self.posX = device.posX
        self.posY = device.posY
        self.scale = device.scale
        self.zIndex = device.zIndex
        self.ports = (device.ports ?? []).map { ExportablePort(from: $0) }
        self.docs = (device.docs ?? []).map { ExportableDocLink(from: $0) }
    }
}

struct ExportablePort: Codable, Sendable {
    let id: UUID
    let name: String
    let typeRaw: String
    let directionRaw: String
    let channels: [ExportableChannel]
    
    init(from port: Port) {
        self.id = port.id
        self.name = port.name
        self.typeRaw = port.typeRaw
        self.directionRaw = port.directionRaw
        self.channels = (port.channels ?? []).map { ExportableChannel(from: $0) }
    }
}

struct ExportableChannel: Codable, Sendable {
    let id: UUID
    let index: Int
    let nameLong: String
    let nameShort: String
    let signalRaw: String
    let groupingRaw: String
    
    init(from channel: Channel) {
        self.id = channel.id
        self.index = channel.index
        self.nameLong = channel.nameLong
        self.nameShort = channel.nameShort
        self.signalRaw = channel.signalRaw
        self.groupingRaw = channel.groupingRaw
    }
}

struct ExportableConnection: Codable, Sendable {
    let id: UUID
    let fromDeviceId: UUID
    let fromPortId: UUID
    let fromChannelId: UUID
    let toDeviceId: UUID
    let toPortId: UUID
    let toChannelId: UUID
    let cableRaw: String
    let label: String
    let notes: String?
    
    init(from connection: Connection) {
        self.id = connection.id
        self.fromDeviceId = connection.fromDeviceId
        self.fromPortId = connection.fromPortId
        self.fromChannelId = connection.fromChannelId
        self.toDeviceId = connection.toDeviceId
        self.toPortId = connection.toPortId
        self.toChannelId = connection.toChannelId
        self.cableRaw = connection.cableRaw
        self.label = connection.label
        self.notes = connection.notes
    }
    
    init(id: UUID, fromDeviceId: UUID, fromPortId: UUID, fromChannelId: UUID,
         toDeviceId: UUID, toPortId: UUID, toChannelId: UUID,
         cableRaw: String, label: String, notes: String?) {
        self.id = id
        self.fromDeviceId = fromDeviceId
        self.fromPortId = fromPortId
        self.fromChannelId = fromChannelId
        self.toDeviceId = toDeviceId
        self.toPortId = toPortId
        self.toChannelId = toChannelId
        self.cableRaw = cableRaw
        self.label = label
        self.notes = notes
    }
}

struct ExportableDocLink: Codable, Sendable {
    let id: UUID
    let title: String
    let kindRaw: String
    let urlString: String?
    let localBookmarkData: Data?
    
    init(from docLink: DocLink) {
        self.id = docLink.id
        self.title = docLink.title
        self.kindRaw = docLink.kindRaw
        self.urlString = docLink.urlString
        self.localBookmarkData = docLink.localBookmarkData
    }
}

// MARK: - New Connection Bundle Models (replaces UserDefaults-based storage)

@Model
final class ConnectionBundleModel {
    var id: UUID = UUID()
    var studioId: UUID = UUID()
    var fromDeviceId: UUID = UUID()
    var toDeviceId: UUID = UUID()
    var modifiedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ConnectionEdgeModel.bundle) var edges: [ConnectionEdgeModel]? = []
    @Relationship(deleteRule: .cascade, inverse: \EndpointNameModel.bundle) var endpointNames: [EndpointNameModel]? = []

    init(id: UUID = UUID(), studioId: UUID, fromDeviceId: UUID, toDeviceId: UUID) {
        self.id = id
        self.studioId = studioId
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.modifiedAt = Date()
        self.edges = []
        self.endpointNames = []
    }

    func markAsModified() {
        self.modifiedAt = Date()
    }
}

@Model
final class ConnectionEdgeModel {
    var id: UUID = UUID()
    var modifiedAt: Date = Date()

    // From endpoint
    var fromDeviceId: UUID = UUID()
    var fromPortId: UUID = UUID()
    var fromChannelId: UUID = UUID()
    var fromDirection: String = "output"

    // To endpoint
    var toDeviceId: UUID = UUID()
    var toPortId: UUID = UUID()
    var toChannelId: UUID = UUID()
    var toDirection: String = "input"

    // Labels
    var fromName: String = ""
    var toName: String = ""

    var bundle: ConnectionBundleModel?

    init(id: UUID = UUID(),
         fromDeviceId: UUID, fromPortId: UUID, fromChannelId: UUID, fromDirection: String,
         toDeviceId: UUID, toPortId: UUID, toChannelId: UUID, toDirection: String,
         fromName: String = "", toName: String = "") {
        self.id = id
        self.modifiedAt = Date()
        self.fromDeviceId = fromDeviceId
        self.fromPortId = fromPortId
        self.fromChannelId = fromChannelId
        self.fromDirection = fromDirection
        self.toDeviceId = toDeviceId
        self.toPortId = toPortId
        self.toChannelId = toChannelId
        self.toDirection = toDirection
        self.fromName = fromName
        self.toName = toName
    }

    func markAsModified() {
        self.modifiedAt = Date()
    }
}

@Model
final class EndpointNameModel {
    var id: UUID = UUID()
    var modifiedAt: Date = Date()
    var endpointKey: String = ""
    var name: String = ""

    var bundle: ConnectionBundleModel?

    init(id: UUID = UUID(), endpointKey: String, name: String) {
        self.id = id
        self.modifiedAt = Date()
        self.endpointKey = endpointKey
        self.name = name
    }

    func markAsModified() {
        self.modifiedAt = Date()
    }
}

// MARK: - Device Color Resolution

extension DeviceInstance {
    /// Get the resolved color for this device (custom color > category color > default grey)
    func resolvedColor(categoryColors: [DeviceCategory: Color]) -> Color {
        // Priority 1: Custom color override
        if let customColor = self.customColor {
            return customColor
        }
        
        // Priority 2: Category default color
        if let categoryColor = categoryColors[self.category] {
            return categoryColor
        }
        
        // Priority 3: Fallback to grey
        return .gray
    }
}

/// Helper to load category colors from UserDefaults
struct CategoryColorSettings {
    static func loadCategoryColors() -> [DeviceCategory: Color] {
        var colors: [DeviceCategory: Color] = [:]
        
        for category in DeviceCategory.allCases {
            let key = "categoryColor_\(category.rawValue.replacingOccurrences(of: " ", with: ""))"
            if let hex = UserDefaults.standard.string(forKey: key),
               let color = Color(hex: hex) {
                colors[category] = color
            } else {
                // Use default colors if not set
                colors[category] = defaultColorFor(category)
            }
        }
        
        return colors
    }
    
    private static func defaultColorFor(_ category: DeviceCategory) -> Color {
        switch category {
        case .adatExpander: return Color(hex: "#9B59B6") ?? .purple
        case .audioInterface: return Color(hex: "#3498DB") ?? .blue
        case .busCompressor: return Color(hex: "#E74C3C") ?? .red
        case .channelStrip: return Color(hex: "#F39C12") ?? .orange
        case .compressor: return Color(hex: "#E67E22") ?? .orange
        case .computer: return Color(hex: "#95A5A6") ?? .gray
        case .controlSurface: return Color(hex: "#1ABC9C") ?? .teal
        case .digitalMixer: return Color(hex: "#16A085") ?? .teal
        case .effectsUnit: return Color(hex: "#8E44AD") ?? .purple
        case .equalizer: return Color(hex: "#D35400") ?? .orange
        case .headphoneAmp: return Color(hex: "#2C3E50") ?? .gray
        case .headphones: return Color(hex: "#34495E") ?? .gray
        case .keyboard: return Color(hex: "#C0392B") ?? .red
        case .microphone: return Color(hex: "#16A085") ?? .teal
        case .midiDevice: return Color(hex: "#2980B9") ?? .blue
        case .midiInterface: return Color(hex: "#5DADE2") ?? .blue
        case .mixer: return Color(hex: "#27AE60") ?? .green
        case .monitor: return Color(hex: "#F1C40F") ?? .yellow
        case .multi: return Color(hex: "#34495E") ?? .gray
        case .patchbay: return Color(hex: "#7F8C8D") ?? .gray
        case .preamp: return Color(hex: "#E74C3C") ?? .red
        case .synth: return Color(hex: "#9B59B6") ?? .purple
        case .usbHub: return Color(hex: "#BDC3C7") ?? .gray
        case .usbExpander: return Color(hex: "#95A5A6") ?? .gray
        case .videoMonitor: return Color(hex: "#ECF0F1") ?? .gray
        case .other: return Color(hex: "#7F8C8D") ?? .gray
        }
    }
}

// MARK: - Color Extensions for Hex Conversion

extension Color {
    /// Initialize Color from hex string (supports #RRGGBB or RRGGBB format)
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        
        let r, g, b: Double
        switch hex.count {
        case 6: // RGB
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            return nil
        }
        
        self.init(red: r, green: g, blue: b)
    }
    
    /// Convert Color to hex string (returns #RRGGBB format)
    func toHex() -> String? {
        #if os(macOS)
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        #else
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        #endif
        
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
