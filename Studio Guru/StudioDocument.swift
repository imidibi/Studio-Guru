//
//  StudioDocument.swift
//  Studio Guru
//
//  Created for export/import functionality
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    nonisolated static var studioGuru: UTType {
        UTType(exportedAs: "com.studioguru.studio")
    }
}

struct StudioDocument: FileDocument, @unchecked Sendable {
    nonisolated static var readableContentTypes: [UTType] { [.studioGuru, .json] }
    nonisolated static var writableContentTypes: [UTType] { [.studioGuru] }

    var exportableStudio: ExportableStudio

    init(exportableStudio: ExportableStudio) {
        self.exportableStudio = exportableStudio
    }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        exportableStudio = try decoder.decode(ExportableStudio.self, from: data)
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(exportableStudio)
        return FileWrapper(regularFileWithContents: data)
    }
}
