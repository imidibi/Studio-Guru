//
//  CloudKitSyncManager.swift
//  Studio Guru
//
//  Manual CloudKit sync implementation for deterministic, reliable syncing
//

import Foundation
import CloudKit
import SwiftData
import Combine

@MainActor
class CloudKitSyncManager: ObservableObject {
    // MARK: - Published State

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?
    @Published var syncStatus: SyncStatus = .idle

    enum SyncStatus: Equatable {
        case idle
        case syncing(progress: String)
        case success
        case error(String)
    }

    // MARK: - CloudKit Setup

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private var modelContext: ModelContext?

    // Record type names
    private let studioRecordType = "Studio"
    private let deviceRecordType = "Device"
    private let connectionBundleRecordType = "ConnectionBundle"
    private let connectionEdgeRecordType = "ConnectionEdge"

    // Zone for custom sync
    private let customZone = CKRecordZone(zoneName: "StudioGuruZone")

    init() {
        self.container = CKContainer(identifier: "iCloud.com.ianmiller.studioguru")
        self.privateDatabase = container.privateCloudDatabase
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        
        // Check if we need to do initial migration from SwiftData to manual CloudKit
        Task {
            await checkAndPerformInitialMigration()
        }
    }
    
    /// Check if initial migration is needed and perform it
    private func checkAndPerformInitialMigration() async {
        // Check if migration has already been done
        let migrationKey = "hasPerformedManualCloudKitMigration"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("✅ Manual CloudKit migration already completed")
            return
        }
        
        // Check if iCloud sync is enabled
        let iCloudSyncEnabled = UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool ?? false
        guard iCloudSyncEnabled else {
            print("ℹ️ iCloud sync disabled - skipping migration")
            return
        }
        
        print("🔄 Starting initial migration to manual CloudKit sync...")
        
        do {
            // Perform full sync to upload all local data
            try await performFullSync()
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("✅ Initial migration to manual CloudKit completed successfully")
        } catch {
            print("❌ Initial migration failed: \(error)")
            // Don't mark as complete so it will retry next time
        }
    }

    // MARK: - Zone Setup

    /// Ensure custom zone exists (call once on first sync)
    func ensureZoneExists() async throws {
        do {
            let zone = try await privateDatabase.recordZone(for: customZone.zoneID)
            print("📱 CloudKit zone exists: \(zone.zoneID.zoneName)")
        } catch {
            // Zone doesn't exist, create it
            print("📱 Creating CloudKit zone: \(customZone.zoneID.zoneName)")
            do {
                let savedZone = try await privateDatabase.save(customZone)
                print("✅ CloudKit zone created successfully: \(savedZone.zoneID.zoneName)")
            } catch {
                print("❌ Failed to create CloudKit zone: \(error)")
                throw error
            }
        }
    }

    // MARK: - Public Sync Methods

    /// Full sync: push local changes, then pull remote changes
    func performFullSync() async throws {
        guard let context = modelContext else {
            throw SyncError.noModelContext
        }

        await MainActor.run {
            isSyncing = true
            syncStatus = .syncing(progress: "Starting sync...")
            syncError = nil
        }

        do {
            // Ensure zone exists
            try await ensureZoneExists()

            // Phase 1: Push local changes to CloudKit
            await updateStatus(.syncing(progress: "Uploading changes..."))
            try await pushLocalChanges(context: context)

            // Phase 2: Pull remote changes from CloudKit
            await updateStatus(.syncing(progress: "Downloading changes..."))
            try await pullRemoteChanges(context: context)

            // Success
            await MainActor.run {
                lastSyncDate = Date()
                syncStatus = .success
                isSyncing = false
            }

            print("✅ Full sync completed successfully")

        } catch {
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
                syncError = error.localizedDescription
                isSyncing = false
            }
            throw error
        }
    }

    /// Push a single studio immediately (call after user makes changes)
    func pushStudio(_ studio: Studio) async throws {
        await updateStatus(.syncing(progress: "Saving studio..."))

        // Ensure zone exists before saving
        try await ensureZoneExists()
        
        let record = try createStudioRecord(from: studio)
        let _ = try await privateDatabase.save(record)

        print("✅ Pushed studio: \(studio.name)")
    }

    /// Push a single device immediately
    func pushDevice(_ device: DeviceInstance, studioId: UUID) async throws {
        await updateStatus(.syncing(progress: "Saving device..."))

        // Ensure zone exists before saving
        try await ensureZoneExists()
        
        let record = try createDeviceRecord(from: device, studioId: studioId)
        let _ = try await privateDatabase.save(record)

        print("✅ Pushed device: \(device.nickname)")
    }

    // MARK: - Push Local Changes

    private func pushLocalChanges(context: ModelContext) async throws {
        // Get all studios
        let studioDescriptor = FetchDescriptor<Studio>()
        let studios = try context.fetch(studioDescriptor)

        print("📤 Pushing \(studios.count) studios to CloudKit")

        var recordsToSave: [CKRecord] = []

        // Create records for each studio
        for studio in studios {
            let record = try createStudioRecord(from: studio)
            recordsToSave.append(record)

            // Create records for devices in this studio
            for device in studio.devices ?? [] {
                let deviceRecord = try createDeviceRecord(from: device, studioId: studio.id)
                recordsToSave.append(deviceRecord)
            }

            // Create records for connection bundles
            let currentStudioId = studio.id
            let bundleDescriptor = FetchDescriptor<ConnectionBundleModel>(
                predicate: #Predicate { $0.studioId == currentStudioId }
            )
            let bundles = try context.fetch(bundleDescriptor)

            for bundle in bundles {
                let bundleRecord = try createConnectionBundleRecord(from: bundle)
                recordsToSave.append(bundleRecord)

                // Create records for edges
                for edge in bundle.edges ?? [] {
                    let edgeRecord = try createConnectionEdgeRecord(from: edge, bundleId: bundle.id)
                    recordsToSave.append(edgeRecord)
                }
            }
        }

        // Batch save all records
        if !recordsToSave.isEmpty {
            try await batchSaveRecords(recordsToSave)
            print("✅ Pushed \(recordsToSave.count) records to CloudKit")
        }
    }

    // MARK: - Pull Remote Changes

    private func pullRemoteChanges(context: ModelContext) async throws {
        print("📥 Pulling changes from CloudKit")

        // Fetch all studios from CloudKit
        let studioQuery = CKQuery(recordType: studioRecordType, predicate: NSPredicate(value: true))
        let studioRecords = try await fetchAllRecords(query: studioQuery)

        print("📥 Found \(studioRecords.count) studios in CloudKit")

        for record in studioRecords {
            try await processStudioRecord(record, context: context)
        }

        try context.save()
    }

    private func processStudioRecord(_ record: CKRecord, context: ModelContext) async throws {
        guard let studioIdString = record["id"] as? String,
              let studioId = UUID(uuidString: studioIdString),
              let name = record["name"] as? String else {
            print("⚠️ Invalid studio record")
            return
        }

        let modifiedAt = record["modifiedAt"] as? Date ?? Date()

        // Check if studio exists locally
        let descriptor = FetchDescriptor<Studio>(
            predicate: #Predicate { $0.id == studioId }
        )
        let existingStudios = try context.fetch(descriptor)

        if let existing = existingStudios.first {
            // Check if remote is newer (conflict resolution: last-write-wins)
            if modifiedAt > existing.modifiedAt {
                print("📥 Updating studio: \(name) (remote is newer)")
                updateStudio(existing, from: record)
            } else {
                print("⏭️ Skipping studio: \(name) (local is newer)")
            }
        } else {
            // Create new studio from CloudKit
            print("📥 Creating new studio: \(name)")
            let studio = createStudio(from: record)
            context.insert(studio)
        }

        // Fetch ALL devices and filter locally (CloudKit fields aren't queryable by default)
        let allDevicesQuery = CKQuery(recordType: deviceRecordType, predicate: NSPredicate(value: true))
        let allDeviceRecords = try await fetchAllRecords(query: allDevicesQuery)
        
        // Filter devices for this studio
        let deviceRecords = allDeviceRecords.filter { record in
            (record["studioId"] as? String) == studioIdString
        }

        for deviceRecord in deviceRecords {
            try processDeviceRecord(deviceRecord, studioId: studioId, context: context)
        }

        // Fetch ALL connection bundles and filter locally
        let allBundlesQuery = CKQuery(recordType: connectionBundleRecordType, predicate: NSPredicate(value: true))
        let allBundleRecords = try await fetchAllRecords(query: allBundlesQuery)
        
        // Filter bundles for this studio
        let bundleRecords = allBundleRecords.filter { record in
            (record["studioId"] as? String) == studioIdString
        }

        for bundleRecord in bundleRecords {
            try await processConnectionBundleRecord(bundleRecord, context: context)
        }
    }

    private func processDeviceRecord(_ record: CKRecord, studioId: UUID, context: ModelContext) throws {
        guard let deviceIdString = record["id"] as? String,
              let deviceId = UUID(uuidString: deviceIdString) else {
            print("⚠️ Invalid device record")
            return
        }

        let modifiedAt = record["modifiedAt"] as? Date ?? Date()

        // Check if device exists locally
        let descriptor = FetchDescriptor<DeviceInstance>(
            predicate: #Predicate { $0.id == deviceId }
        )
        let existingDevices = try context.fetch(descriptor)

        if let existing = existingDevices.first {
            if modifiedAt > existing.modifiedAt {
                print("📥 Updating device: \(existing.nickname)")
                updateDevice(existing, from: record)
            }
        } else {
            print("📥 Creating new device from CloudKit")
            let device = createDevice(from: record, studioId: studioId, context: context)
            context.insert(device)
        }
    }

    private func processConnectionBundleRecord(_ record: CKRecord, context: ModelContext) async throws {
        guard let bundleIdString = record["id"] as? String,
              let bundleId = UUID(uuidString: bundleIdString),
              let studioIdString = record["studioId"] as? String,
              let _ = UUID(uuidString: studioIdString) else {
            return
        }

        let descriptor = FetchDescriptor<ConnectionBundleModel>(
            predicate: #Predicate { $0.id == bundleId }
        )
        let existing = try context.fetch(descriptor).first

        if existing == nil {
            // Create new bundle
            let bundle = createConnectionBundle(from: record)
            context.insert(bundle)

            // Fetch ALL edges and filter locally (CloudKit fields aren't queryable by default)
            let allEdgesQuery = CKQuery(recordType: connectionEdgeRecordType, predicate: NSPredicate(value: true))
            let allEdgeRecords = try await fetchAllRecords(query: allEdgesQuery)
            
            // Filter edges for this bundle
            let edgeRecords = allEdgeRecords.filter { record in
                (record["bundleId"] as? String) == bundleIdString
            }

            for edgeRecord in edgeRecords {
                let edge = createConnectionEdge(from: edgeRecord)
                bundle.edges?.append(edge)
                context.insert(edge)
            }
        }
    }

    // MARK: - Record Creation (SwiftData → CloudKit)

    private func createStudioRecord(from studio: Studio) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: studio.id.uuidString,
            zoneID: customZone.zoneID
        )
        let record = CKRecord(recordType: studioRecordType, recordID: recordID)

        record["id"] = studio.id.uuidString
        record["name"] = studio.name
        record["createdAt"] = studio.createdAt
        record["modifiedAt"] = studio.modifiedAt
        record["layoutMode"] = studio.layoutMode
        record["gridSize"] = studio.gridSize
        record["showGridOverlay"] = studio.showGridOverlay ? 1 : 0
        record["isSystemStudio"] = studio.isSystemStudio ? 1 : 0
        record["systemStudioType"] = studio.systemStudioType

        if let canvasData = studio.canvasDrawingData {
            record["canvasDrawingData"] = canvasData
        }

        return record
    }

    private func createDeviceRecord(from device: DeviceInstance, studioId: UUID) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: device.id.uuidString,
            zoneID: customZone.zoneID
        )
        let record = CKRecord(recordType: deviceRecordType, recordID: recordID)

        // Core fields
        record["id"] = device.id.uuidString
        record["studioId"] = studioId.uuidString
        record["manufacturer"] = device.manufacturer
        record["model"] = device.model
        record["nickname"] = device.nickname
        record["categoryRaw"] = device.categoryRaw
        record["serialNumber"] = device.serialNumber
        record["location"] = device.location
        record["modifiedAt"] = device.modifiedAt

        // Position
        record["posX"] = device.posX
        record["posY"] = device.posY
        record["scale"] = device.scale
        record["zIndex"] = device.zIndex
        record["isPinned"] = device.isPinned ? 1 : 0

        // Port counts
        record["audioInputsCount"] = device.audioInputsCount
        record["audioOutputsCount"] = device.audioOutputsCount
        record["adatInputPortsCount"] = device.adatInputPortsCount
        record["adatOutputPortsCount"] = device.adatOutputPortsCount
        record["madiInputPortsCount"] = device.madiInputPortsCount
        record["madiOutputPortsCount"] = device.madiOutputPortsCount
        record["midiInputPortsCount"] = device.midiInputPortsCount
        record["midiOutputPortsCount"] = device.midiOutputPortsCount
        record["cvInputPortsCount"] = device.cvInputPortsCount
        record["cvOutputPortsCount"] = device.cvOutputPortsCount
        record["ethernetPortsCount"] = device.ethernetPortsCount

        // Digital formats
        record["digitalInputsRaw"] = device.digitalInputsRaw
        record["digitalOutputsRaw"] = device.digitalOutputsRaw
        record["computerInterfacesRaw"] = device.computerInterfacesRaw
        record["sampleRateRaw"] = device.sampleRateRaw

        // Gear Locker
        record["isInGearLocker"] = device.isInGearLocker ? 1 : 0
        record["isAssignedFromLocker"] = device.isAssignedFromLocker ? 1 : 0
        record["lockerSourceDeviceId"] = device.lockerSourceDeviceId?.uuidString
        record["isGhostDevice"] = device.isGhostDevice ? 1 : 0
        record["ghostOfDeviceId"] = device.ghostOfDeviceId?.uuidString

        // Optional fields
        if let color = device.customColorHex {
            record["customColorHex"] = color
        }
        
        // Serialize ports array as JSON
        if let ports = device.ports, !ports.isEmpty {
            do {
                let portsData = try JSONEncoder().encode(ports.map { port in
                    PortData(
                        id: port.id,
                        name: port.name,
                        typeRaw: port.typeRaw,
                        directionRaw: port.directionRaw,
                        channels: port.channels?.map { channel in
                            ChannelData(
                                id: channel.id,
                                index: channel.index,
                                nameLong: channel.nameLong,
                                nameShort: channel.nameShort,
                                groupingRaw: channel.groupingRaw
                            )
                        } ?? []
                    )
                })
                record["portsJSON"] = String(data: portsData, encoding: .utf8)
            } catch {
                print("⚠️ Failed to serialize ports: \(error)")
            }
        }
        
        // Serialize docs array as JSON
        if let docs = device.docs, !docs.isEmpty {
            do {
                let docsData = try JSONEncoder().encode(docs.map { doc in
                    DocData(
                        id: doc.id,
                        title: doc.title,
                        kindRaw: doc.kindRaw,
                        iCloudDocumentPath: doc.iCloudDocumentPath,
                        localBookmarkData: doc.localBookmarkData,
                        urlString: doc.urlString,
                        modifiedAt: doc.modifiedAt
                    )
                })
                record["docsJSON"] = String(data: docsData, encoding: .utf8)
            } catch {
                print("⚠️ Failed to serialize docs: \(error)")
            }
        } else {
            // Explicitly set empty array to sync deletions
            record["docsJSON"] = "[]"
        }

        return record
    }
    
    // Helper structures for JSON serialization
    private struct PortData: Codable {
        let id: UUID
        let name: String
        let typeRaw: String
        let directionRaw: String
        let channels: [ChannelData]
    }
    
    private struct ChannelData: Codable {
        let id: UUID
        let index: Int
        let nameLong: String
        let nameShort: String
        let groupingRaw: String
    }
    
    private struct DocData: Codable {
        let id: UUID
        let title: String
        let kindRaw: String
        let iCloudDocumentPath: String?
        let localBookmarkData: Data?
        let urlString: String?
        let modifiedAt: Date
    }

    private func createConnectionBundleRecord(from bundle: ConnectionBundleModel) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: bundle.id.uuidString,
            zoneID: customZone.zoneID
        )
        let record = CKRecord(recordType: connectionBundleRecordType, recordID: recordID)

        record["id"] = bundle.id.uuidString
        record["studioId"] = bundle.studioId.uuidString
        record["fromDeviceId"] = bundle.fromDeviceId.uuidString
        record["toDeviceId"] = bundle.toDeviceId.uuidString
        record["modifiedAt"] = bundle.modifiedAt

        return record
    }

    private func createConnectionEdgeRecord(from edge: ConnectionEdgeModel, bundleId: UUID) throws -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: edge.id.uuidString,
            zoneID: customZone.zoneID
        )
        let record = CKRecord(recordType: connectionEdgeRecordType, recordID: recordID)

        record["id"] = edge.id.uuidString
        record["bundleId"] = bundleId.uuidString
        record["modifiedAt"] = edge.modifiedAt

        record["fromDeviceId"] = edge.fromDeviceId.uuidString
        record["fromPortId"] = edge.fromPortId.uuidString
        record["fromChannelId"] = edge.fromChannelId.uuidString
        record["fromDirection"] = edge.fromDirection
        record["fromName"] = edge.fromName

        record["toDeviceId"] = edge.toDeviceId.uuidString
        record["toPortId"] = edge.toPortId.uuidString
        record["toChannelId"] = edge.toChannelId.uuidString
        record["toDirection"] = edge.toDirection
        record["toName"] = edge.toName

        return record
    }

    // MARK: - Object Creation (CloudKit → SwiftData)

    private func createStudio(from record: CKRecord) -> Studio {
        let name = record["name"] as? String ?? "Untitled"
        let studio = Studio(name: name)

        if let idString = record["id"] as? String,
           let id = UUID(uuidString: idString) {
            studio.id = id
        }

        studio.createdAt = record["createdAt"] as? Date ?? Date()
        studio.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        studio.layoutMode = record["layoutMode"] as? String ?? "freeform"
        studio.gridSize = record["gridSize"] as? Double ?? 24.0
        studio.showGridOverlay = (record["showGridOverlay"] as? Int ?? 0) == 1
        studio.isSystemStudio = (record["isSystemStudio"] as? Int ?? 0) == 1
        studio.systemStudioType = record["systemStudioType"] as? String
        studio.canvasDrawingData = record["canvasDrawingData"] as? Data

        return studio
    }

    private func updateStudio(_ studio: Studio, from record: CKRecord) {
        studio.name = record["name"] as? String ?? studio.name
        studio.modifiedAt = record["modifiedAt"] as? Date ?? Date()
        studio.layoutMode = record["layoutMode"] as? String ?? studio.layoutMode
        studio.gridSize = record["gridSize"] as? Double ?? studio.gridSize
        studio.showGridOverlay = (record["showGridOverlay"] as? Int ?? 0) == 1
        studio.canvasDrawingData = record["canvasDrawingData"] as? Data
    }

    private func createDevice(from record: CKRecord, studioId: UUID, context: ModelContext) -> DeviceInstance {
        let manufacturer = record["manufacturer"] as? String ?? ""
        let model = record["model"] as? String ?? ""
        let nickname = record["nickname"] as? String ?? model

        let device = DeviceInstance(
            manufacturer: manufacturer,
            model: model,
            nickname: nickname
        )

        if let idString = record["id"] as? String,
           let id = UUID(uuidString: idString) {
            device.id = id
        }

        updateDevice(device, from: record)

        // Link to studio
        let studioDescriptor = FetchDescriptor<Studio>(
            predicate: #Predicate { $0.id == studioId }
        )
        if let studio = try? context.fetch(studioDescriptor).first {
            device.studio = studio
        }

        return device
    }

    private func updateDevice(_ device: DeviceInstance, from record: CKRecord) {
        device.manufacturer = record["manufacturer"] as? String ?? device.manufacturer
        device.model = record["model"] as? String ?? device.model
        device.nickname = record["nickname"] as? String ?? device.nickname
        device.categoryRaw = record["categoryRaw"] as? String ?? device.categoryRaw
        device.serialNumber = record["serialNumber"] as? String ?? device.serialNumber
        device.location = record["location"] as? String ?? device.location
        device.modifiedAt = record["modifiedAt"] as? Date ?? Date()

        device.posX = record["posX"] as? Double ?? device.posX
        device.posY = record["posY"] as? Double ?? device.posY
        device.scale = record["scale"] as? Double ?? device.scale
        device.zIndex = record["zIndex"] as? Int ?? device.zIndex
        device.isPinned = (record["isPinned"] as? Int ?? 0) == 1

        device.audioInputsCount = record["audioInputsCount"] as? Int ?? device.audioInputsCount
        device.audioOutputsCount = record["audioOutputsCount"] as? Int ?? device.audioOutputsCount
        device.adatInputPortsCount = record["adatInputPortsCount"] as? Int ?? device.adatInputPortsCount
        device.adatOutputPortsCount = record["adatOutputPortsCount"] as? Int ?? device.adatOutputPortsCount
        device.madiInputPortsCount = record["madiInputPortsCount"] as? Int ?? device.madiInputPortsCount
        device.madiOutputPortsCount = record["madiOutputPortsCount"] as? Int ?? device.madiOutputPortsCount
        device.midiInputPortsCount = record["midiInputPortsCount"] as? Int ?? device.midiInputPortsCount
        device.midiOutputPortsCount = record["midiOutputPortsCount"] as? Int ?? device.midiOutputPortsCount
        device.cvInputPortsCount = record["cvInputPortsCount"] as? Int ?? device.cvInputPortsCount
        device.cvOutputPortsCount = record["cvOutputPortsCount"] as? Int ?? device.cvOutputPortsCount
        device.ethernetPortsCount = record["ethernetPortsCount"] as? Int ?? device.ethernetPortsCount

        device.digitalInputsRaw = record["digitalInputsRaw"] as? [String] ?? device.digitalInputsRaw
        device.digitalOutputsRaw = record["digitalOutputsRaw"] as? [String] ?? device.digitalOutputsRaw
        device.computerInterfacesRaw = record["computerInterfacesRaw"] as? [String] ?? device.computerInterfacesRaw
        device.sampleRateRaw = record["sampleRateRaw"] as? Int ?? device.sampleRateRaw

        device.isInGearLocker = (record["isInGearLocker"] as? Int ?? 0) == 1
        device.isAssignedFromLocker = (record["isAssignedFromLocker"] as? Int ?? 0) == 1
        device.isGhostDevice = (record["isGhostDevice"] as? Int ?? 0) == 1

        if let lockerIdString = record["lockerSourceDeviceId"] as? String {
            device.lockerSourceDeviceId = UUID(uuidString: lockerIdString)
        }
        if let ghostIdString = record["ghostOfDeviceId"] as? String {
            device.ghostOfDeviceId = UUID(uuidString: ghostIdString)
        }

        device.customColorHex = record["customColorHex"] as? String
        
        // Deserialize ports from JSON
        if let portsJSON = record["portsJSON"] as? String,
           let portsData = portsJSON.data(using: .utf8) {
            do {
                let portDataArray = try JSONDecoder().decode([PortData].self, from: portsData)
                
                // Clear existing ports
                device.ports?.removeAll()
                if device.ports == nil {
                    device.ports = []
                }
                
                // Recreate ports from data
                for portData in portDataArray {
                    let port = Port(
                        name: portData.name,
                        type: PortType(rawValue: portData.typeRaw) ?? .usbAudio,
                        direction: PortDirection(rawValue: portData.directionRaw) ?? .bidirectional
                    )
                    port.id = portData.id
                    
                    // Recreate channels
                    for channelData in portData.channels {
                        let channel = Channel(
                            index: channelData.index,
                            nameLong: channelData.nameLong,
                            nameShort: channelData.nameShort,
                            grouping: ChannelGrouping(rawValue: channelData.groupingRaw) ?? .mono
                        )
                        channel.id = channelData.id
                        port.channels?.append(channel)
                    }
                    
                    device.ports?.append(port)
                }
            } catch {
                print("⚠️ Failed to deserialize ports: \(error)")
            }
        }
        
        // Deserialize docs from JSON
        if let docsJSON = record["docsJSON"] as? String,
           let docsData = docsJSON.data(using: .utf8) {
            do {
                let docDataArray = try JSONDecoder().decode([DocData].self, from: docsData)
                
                // Merge docs using modifiedAt timestamps for conflict resolution
                // This preserves newer changes while removing deleted docs
                var existingDocsMap: [UUID: DocLink] = [:]
                if let existingDocs = device.docs {
                    for doc in existingDocs {
                        existingDocsMap[doc.id] = doc
                    }
                }
                
                // Clear and rebuild docs array
                device.docs?.removeAll()
                if device.docs == nil {
                    device.docs = []
                }
                
                // Process incoming docs
                for docData in docDataArray {
                    // Check if we have this doc locally
                    if let existingDoc = existingDocsMap[docData.id] {
                        // Keep the newer version based on modifiedAt
                        if docData.modifiedAt > existingDoc.modifiedAt {
                            // Remote is newer, use remote data
                            existingDoc.title = docData.title
                            existingDoc.kindRaw = docData.kindRaw
                            existingDoc.iCloudDocumentPath = docData.iCloudDocumentPath
                            existingDoc.localBookmarkData = docData.localBookmarkData
                            existingDoc.urlString = docData.urlString
                            existingDoc.modifiedAt = docData.modifiedAt
                        }
                        // Keep the existing doc (with potentially updated data)
                        device.docs?.append(existingDoc)
                    } else {
                        // New doc from remote, create it based on what type of storage it uses
                        let newDoc: DocLink
                        let kind = DocKind(rawValue: docData.kindRaw) ?? .other
                        
                        if let iCloudPath = docData.iCloudDocumentPath {
                            newDoc = DocLink(title: docData.title, kind: kind, iCloudPath: iCloudPath)
                        } else if let bookmarkData = docData.localBookmarkData {
                            newDoc = DocLink(title: docData.title, kind: kind, bookmarkData: bookmarkData)
                        } else if let urlString = docData.urlString, let url = URL(string: urlString) {
                            newDoc = DocLink(title: docData.title, kind: kind, url: url)
                        } else {
                            // Invalid doc data, skip it
                            print("⚠️ Skipping doc with no valid storage: \(docData.title)")
                            continue
                        }
                        
                        newDoc.id = docData.id
                        newDoc.modifiedAt = docData.modifiedAt
                        device.docs?.append(newDoc)
                    }
                }
                
                // Note: Docs that exist locally but not in remote have been deleted remotely
                // They are automatically removed by not adding them back to the array
                
            } catch {
                print("⚠️ Failed to deserialize docs: \(error)")
            }
        }
    }

    private func createConnectionBundle(from record: CKRecord) -> ConnectionBundleModel {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let studioIdString = record["studioId"] as? String,
              let studioId = UUID(uuidString: studioIdString),
              let fromIdString = record["fromDeviceId"] as? String,
              let fromId = UUID(uuidString: fromIdString),
              let toIdString = record["toDeviceId"] as? String,
              let toId = UUID(uuidString: toIdString) else {
            fatalError("Invalid connection bundle record")
        }

        let bundle = ConnectionBundleModel(
            id: id,
            studioId: studioId,
            fromDeviceId: fromId,
            toDeviceId: toId
        )
        bundle.modifiedAt = record["modifiedAt"] as? Date ?? Date()

        return bundle
    }

    private func createConnectionEdge(from record: CKRecord) -> ConnectionEdgeModel {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let fromDeviceIdString = record["fromDeviceId"] as? String,
              let fromDeviceId = UUID(uuidString: fromDeviceIdString),
              let fromPortIdString = record["fromPortId"] as? String,
              let fromPortId = UUID(uuidString: fromPortIdString),
              let fromChannelIdString = record["fromChannelId"] as? String,
              let fromChannelId = UUID(uuidString: fromChannelIdString),
              let toDeviceIdString = record["toDeviceId"] as? String,
              let toDeviceId = UUID(uuidString: toDeviceIdString),
              let toPortIdString = record["toPortId"] as? String,
              let toPortId = UUID(uuidString: toPortIdString),
              let toChannelIdString = record["toChannelId"] as? String,
              let toChannelId = UUID(uuidString: toChannelIdString) else {
            fatalError("Invalid connection edge record")
        }

        let edge = ConnectionEdgeModel(
            id: id,
            fromDeviceId: fromDeviceId,
            fromPortId: fromPortId,
            fromChannelId: fromChannelId,
            fromDirection: record["fromDirection"] as? String ?? "output",
            toDeviceId: toDeviceId,
            toPortId: toPortId,
            toChannelId: toChannelId,
            toDirection: record["toDirection"] as? String ?? "input",
            fromName: record["fromName"] as? String ?? "",
            toName: record["toName"] as? String ?? ""
        )
        edge.modifiedAt = record["modifiedAt"] as? Date ?? Date()

        return edge
    }

    // MARK: - Utilities

    private func updateStatus(_ status: SyncStatus) async {
        await MainActor.run {
            self.syncStatus = status
        }
    }

    private func batchSaveRecords(_ records: [CKRecord]) async throws {
        // CloudKit allows max 400 records per batch
        let batchSize = 400
        let batches = stride(from: 0, to: records.count, by: batchSize).map {
            Array(records[$0..<min($0 + batchSize, records.count)])
        }

        for batch in batches {
            let _ = try await privateDatabase.modifyRecords(saving: batch, deleting: [])
        }
    }

    private func fetchAllRecords(query: CKQuery) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        
        // Use CKFetchRecordZoneChangesOperation to fetch all records without requiring queryable fields
        // Create configuration for the zone
        let zoneID = customZone.zoneID
        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = nil // Fetch all records
        
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zoneID], configurationsByRecordZoneID: [zoneID: configuration])
        
        // Collect records that match the query's record type
        let recordType = query.recordType
        operation.recordWasChangedBlock = { recordID, result in
            switch result {
            case .success(let record):
                // Only include records of the requested type
                if record.recordType == recordType {
                    allRecords.append(record)
                }
            case .failure(let error):
                print("⚠️ Failed to fetch record \(recordID): \(error)")
            }
        }
        
        // Handle completion
        await withCheckedContinuation { continuation in
            operation.fetchRecordZoneChangesResultBlock = { result in
                continuation.resume()
            }
            
            privateDatabase.add(operation)
        }
        
        return allRecords
    }

    // MARK: - Errors

    enum SyncError: LocalizedError {
        case noModelContext
        case invalidRecord
        case uploadFailed(String)
        case downloadFailed(String)

        var errorDescription: String? {
            switch self {
            case .noModelContext:
                return "Model context not set"
            case .invalidRecord:
                return "Invalid CloudKit record"
            case .uploadFailed(let message):
                return "Upload failed: \(message)"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            }
        }
    }
}
