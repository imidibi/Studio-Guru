//
//  ExampleStudios.swift
//  Studio Guru
//
//  Bundled example studios shown to new users instead of a blank canvas.
//  The examples are ordinary exported studios (see ExportableStudio) shipped as
//  JSON resources. They are viewed in a temporary in-memory store (see ExampleStudioHost);
//  they only reach the user's real studios if the user chooses "Use as My Studio".
//

import Foundation

enum ExampleStudio: String, CaseIterable, Identifiable, Codable, Hashable {
    case simple
    case pro

    var id: String { rawValue }

    /// Name given to the studio created from this example.
    var studioName: String {
        switch self {
        case .simple: return "Example Studio"
        case .pro: return "Example Studio (Pro)"
        }
    }

    var title: String {
        switch self {
        case .simple: return "Simple Example"
        case .pro: return "Advanced Example"
        }
    }

    var summary: String {
        switch self {
        case .simple: return "A computer, audio interface, two monitors and a keyboard."
        case .pro: return "A fuller studio with synths, effects, drums and a microphone."
        }
    }

    /// Examples larger than the free device limit need a Pro license to copy into your studios
    /// (viewing is always free).
    var requiresPro: Bool { self == .pro }

    private var resourceName: String {
        switch self {
        case .simple: return "ExampleStudioSimple"
        case .pro: return "ExampleStudioPro"
        }
    }

    func load() throws -> ExportableStudio {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportableStudio.self, from: Data(contentsOf: url))
    }
}
