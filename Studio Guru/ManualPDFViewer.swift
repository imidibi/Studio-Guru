//
//  Created by Ian Miller on 2/12/26.
//
//
//  ManualPDFViewer.swift
//  Studio Guru
//

import SwiftUI
import PDFKit

#if os(iOS)
import UIKit
private typealias UXViewRepresentable = UIViewRepresentable
private typealias UXView = UIView
#else
import AppKit
private typealias UXViewRepresentable = NSViewRepresentable
private typealias UXView = NSView
#endif

// MARK: - SwiftUI PDF Viewer

struct ManualPDFViewer: View {
    @Environment(\.dismiss) private var dismiss

    let url: URL
    let title: String

    @State private var searchText: String = ""
    @State private var matches: [PDFSelection] = []
    @State private var currentMatchIndex: Int = 0
    @State private var document: PDFDocument? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    TextField("Search manual…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { performSearch() }

                    Button("Find") {
                        performSearch()
                    }

                    Button("◀") {
                        goToPreviousMatch()
                    }
                    .disabled(matches.isEmpty)

                    Button("▶") {
                        goToNextMatch()
                    }
                    .disabled(matches.isEmpty)

                    if !matches.isEmpty {
                        Text("\(currentMatchIndex + 1)/\(matches.count)")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Close")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                PDFKitView(
                    url: url,
                    document: $document,
                    matches: $matches,
                    currentMatchIndex: $currentMatchIndex
                )
            }
            .onAppear {
                if document == nil {
                    document = PDFDocument(url: url)
                }
            }
            .navigationTitle(title)
        }
#if os(iOS)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.resizes)
#endif
#if os(macOS)
        .frame(minWidth: 900, idealWidth: 1100, maxWidth: .infinity, minHeight: 700, idealHeight: 900, maxHeight: .infinity)
#endif
    }

    private func performSearch() {
        guard let doc = document, !searchText.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }

        let results = doc.findString(searchText, withOptions: .caseInsensitive)
        matches = results
        currentMatchIndex = 0
    }

    private func goToNextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    private func goToPreviousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }
}

private struct PDFKitView: UXViewRepresentable {
    let url: URL
    @Binding var document: PDFDocument?
    @Binding var matches: [PDFSelection]
    @Binding var currentMatchIndex: Int

#if os(iOS)
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.usePageViewController(true, withViewOptions: nil)
        v.document = document ?? PDFDocument(url: url)
        return v
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if let doc = document {
            if view.document !== doc {
                view.document = doc
            }
        } else if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }

        highlightMatches(in: view)
    }
#else
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = document ?? PDFDocument(url: url)
        return v
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if let doc = document {
            if view.document !== doc {
                view.document = doc
            }
        } else if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }

        highlightMatches(in: view)
    }
#endif

    private func highlightMatches(in view: PDFView) {
        view.highlightedSelections = matches

        guard !matches.isEmpty,
              currentMatchIndex < matches.count else { return }

        let selection = matches[currentMatchIndex]
        view.go(to: selection)
        view.setCurrentSelection(selection, animate: true)
    }
}

// MARK: - Manual Storage Helper

enum ManualStorage {
    /// Copies a picked PDF into Application Support and returns the destination URL.
    static func copyPDFIntoAppSupport(pickedURL: URL, deviceId: UUID) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let manualsDir = appSupport
            .appendingPathComponent("Manuals", isDirectory: true)
            .appendingPathComponent(deviceId.uuidString, isDirectory: true)

        try fm.createDirectory(at: manualsDir, withIntermediateDirectories: true)

        let originalName = pickedURL.lastPathComponent
        let sanitized = sanitizeFileName(originalName.isEmpty ? "Manual.pdf" : originalName)

        var dest = manualsDir.appendingPathComponent(sanitized)

        // Avoid collisions
        if fm.fileExists(atPath: dest.path) {
            let base = dest.deletingPathExtension().lastPathComponent
            let ext = dest.pathExtension.isEmpty ? "pdf" : dest.pathExtension
            dest = manualsDir.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970)).\(ext)")
        }

        // If source is security-scoped (common on macOS/iOS), use scoped access.
        let needsScoped = pickedURL.startAccessingSecurityScopedResource()
        defer {
            if needsScoped { pickedURL.stopAccessingSecurityScopedResource() }
        }

        // Copy (or replace if needed)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: pickedURL, to: dest)

        return dest
    }

    private static func sanitizeFileName(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ()")
        let filtered = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let out = String(filtered).trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? "Manual.pdf" : out
    }
}
