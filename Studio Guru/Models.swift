//
//  Models.swift
//  Studio Guru
//

import Foundation
import SwiftData

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
    case ethernet
    case headphoneOut
    case computerHost
}

enum PortDirection: String, Codable, CaseIterable { case input, output, bidirectional }

enum ChannelGrouping: String, Codable, CaseIterable { case mono, stereoPairable, fixedStereoPair }

enum CableType: String, Codable, CaseIterable { case trs, xlr, ts, opticalADAT, usb, thunderbolt, midiDIN, usbMIDI, wordClockBNC, ethernet, other }

enum DocKind: String, Codable, CaseIterable { case manual, driver, firmware, support, other }

// MARK: - Device Metadata Enums

enum DeviceCategory: String, Codable, CaseIterable {
    case adatExpander = "ADAT Expander"
    case audioInterface = "Audio Interface"
    case busCompressor = "Bus Compressor"
    case channelStrip = "Channel Strip"
    case compressor = "Compressor"
    case computer = "Computer"
    case digitalMixer = "Digital Mixer"
    case effectsUnit = "Effects Unit"
    case equalizer = "Equalizer"
    case keyboard = "Keyboard"
    case midiDevice = "MIDI Device"
    case mixer = "Mixer"
    case multi = "Multi"
    case patchbay = "Patchbay"
    case preamp = "Preamp"
    case usbHub = "USB Hub"
    case usbExpander = "USB Expander"
    case other = "Other"
}

enum DigitalFormat: String, Codable, CaseIterable {
    case adat = "ADAT"
    case aesebu = "AES/EBU"
    case dante = "Dante"
    case madi = "MADI"
    case midi = "MIDI"
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
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var devices: [DeviceInstance]
    @Relationship(deleteRule: .cascade) var connections: [Connection]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.devices = []
        self.connections = []
    }
}

// MARK: - Device

@Model
final class DeviceInstance {
    @Attribute(.unique) var id: UUID

    var manufacturer: String
    var model: String
    var nickname: String

    // Core metadata
    var categoryRaw: String
    var serialNumber: String
    var location: String

    // External resources
    var supportPageURLString: String?
    var downloadsPageURLString: String?

    // I/O summary (high-level counts)
    var audioInputsCount: Int
    var audioOutputsCount: Int

    // Digital audio port counts
    var adatInputPortsCount: Int
    var adatOutputPortsCount: Int
    var madiInputPortsCount: Int
    var madiOutputPortsCount: Int

    // Networking / control ports (used for Dante, remote control, etc.)
    var ethernetPortsCount: Int

    var sampleRateRaw: Int

    // Digital formats stored as raw strings
    var digitalInputsRaw: [String]
    var digitalOutputsRaw: [String]

    // Computer interfaces (bi-directional host connections).
    // NOTE: This array supports quantities by allowing duplicates (e.g. ["USB", "USB"] means 2x USB).
    var computerInterfacesRaw: [String]

    // Canvas placement
    var posX: Double
    var posY: Double
    var scale: Double
    var zIndex: Int

    // Optional image paths (sandbox)
    var frontImagePath: String?
    var rearImagePath: String?

    @Relationship(deleteRule: .cascade) var ports: [Port]
    @Relationship(deleteRule: .cascade) var docs: [DocLink]

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
        self.ports = []
        self.docs = []
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
}

// MARK: - Port

@Model
final class Port {
    @Attribute(.unique) var id: UUID
    var name: String

    var typeRaw: String
    var directionRaw: String

    @Relationship(deleteRule: .cascade) var channels: [Channel]

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
    @Attribute(.unique) var id: UUID
    var index: Int
    var nameLong: String
    var nameShort: String
    var signalRaw: String
    var groupingRaw: String

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
    @Attribute(.unique) var id: UUID

    var fromDeviceId: UUID
    var fromPortId: UUID
    var fromChannelId: UUID

    var toDeviceId: UUID
    var toPortId: UUID
    var toChannelId: UUID

    var cableRaw: String
    var label: String
    var notes: String?

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
    }

    var cable: CableType { CableType(rawValue: cableRaw) ?? .other }
}

// MARK: - DocLink

@Model
final class DocLink {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String

    var urlString: String?
    var localBookmarkData: Data?

    init(title: String, kind: DocKind, url: URL) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.urlString = url.absoluteString
        self.localBookmarkData = nil
    }

    init(title: String, kind: DocKind, bookmarkData: Data) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
        self.urlString = nil
        self.localBookmarkData = bookmarkData
    }

    var kind: DocKind { DocKind(rawValue: kindRaw) ?? .other }
}

// MARK: - Export/Import Data Structures

/// Codable representation of a studio for export/import
struct ExportableStudio: Codable {
    let name: String
    let devices: [ExportableDevice]
    let connections: [ExportableConnection]
    let exportDate: Date
    let appVersion: String
    
    init(from studio: Studio) {
        self.name = studio.name
        self.devices = studio.devices.map { ExportableDevice(from: $0) }
        self.connections = studio.connections.map { ExportableConnection(from: $0) }
        self.exportDate = Date()
        self.appVersion = "1.0"
    }
}

struct ExportableDevice: Codable {
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
        self.ethernetPortsCount = device.ethernetPortsCount
        self.sampleRateRaw = device.sampleRateRaw
        self.digitalInputsRaw = device.digitalInputsRaw
        self.digitalOutputsRaw = device.digitalOutputsRaw
        self.computerInterfacesRaw = device.computerInterfacesRaw
        self.posX = device.posX
        self.posY = device.posY
        self.scale = device.scale
        self.zIndex = device.zIndex
        self.ports = device.ports.map { ExportablePort(from: $0) }
    }
}

struct ExportablePort: Codable {
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
        self.channels = port.channels.map { ExportableChannel(from: $0) }
    }
}

struct ExportableChannel: Codable {
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

struct ExportableConnection: Codable {
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
}
