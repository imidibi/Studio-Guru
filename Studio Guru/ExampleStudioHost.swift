//
//  ExampleStudioHost.swift
//  Studio Guru
//
//  Shows a bundled example studio in its own window (a sheet on iOS).
//
//  The example lives in a temporary in-memory store that is completely separate from the
//  user's studios and devices: it is never synced, backed up, or counted against the free
//  tier, and it is discarded when the window closes. The user can freely experiment, and can
//  copy the example into their real studios with "Use as My Studio".
//

import SwiftData
import SwiftUI

struct ExampleStudioHost: View {
    static let windowId = "example-studio"

    let example: ExampleStudio

    // The user's real store. This window's content below swaps in the example store.
    @Environment(\.modelContext) private var realContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var storeManager: StoreManager

    @State private var exampleContainer: ModelContainer?
    @State private var isShowingPaywall = false
    @State private var paywallReason: PaywallReason = .general
    @State private var resultMessage: String?
    @State private var shouldDismissAfterResult = false

    var body: some View {
        VStack(spacing: 0) {
            banner
            Divider()
            if let exampleContainer {
                StudioCanvasView(example: example)
                    .modelContainer(exampleContainer)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .onAppear {
            if exampleContainer == nil {
                exampleContainer = Self.makeContainer()
            }
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView(reason: paywallReason)
                .environmentObject(storeManager)
        }
        .alert(
            "Example Studio",
            isPresented: Binding(
                get: { resultMessage != nil },
                set: { if !$0 { resultMessage = nil } }
            )
        ) {
            Button("OK") {
                if shouldDismissAfterResult { dismiss() }
            }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(example.title) — try it out")
                    .font(.headline)
                Text("Changes here aren't saved and don't affect your own studios.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use as My Studio") { useAsMyStudio() }
                .buttonStyle(.borderedProminent)
            #if os(iOS)
            Button("Close") { dismiss() }
            #endif
        }
        .padding(12)
    }

    /// A temporary store with the full app schema, never synced to iCloud.
    private static func makeContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(
            schema: AppSchema.schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try? ModelContainer(for: AppSchema.schema, configurations: configuration)
    }

    /// Copies the pristine example into the user's real studios, subject to the usual limits.
    @MainActor
    private func useAsMyStudio() {
        if example.requiresPro && !storeManager.isPro {
            paywallReason = .general
            isShowingPaywall = true
            return
        }

        let existing = (try? realContext.fetch(FetchDescriptor<Studio>())) ?? []
        let regularCount = existing.filter { !$0.isSystemStudio }.count
        guard storeManager.canAddStudio(currentCount: regularCount) else {
            paywallReason = .studioLimit
            isShowingPaywall = true
            return
        }

        do {
            // Make the name unique among the user's studios
            var name = example.studioName
            var counter = 2
            while existing.contains(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                name = "\(example.studioName) \(counter)"
                counter += 1
            }

            let connectionsStore = ConnectionsStore()
            connectionsStore.setModelContext(realContext, migrateLegacy: false)
            let studio = try StudioImporter.insertStudio(
                from: try example.load(),
                name: name,
                into: realContext,
                connectionsStore: connectionsStore
            )

            // Pro users get a Gear Locker alongside their first regular studio
            if storeManager.isPro {
                StudioSeed.ensureGearLockerExists(modelContext: realContext, studios: existing + [studio])
            }

            shouldDismissAfterResult = true
            resultMessage = "“\(studio.name)” was added to your studios."
        } catch {
            shouldDismissAfterResult = false
            resultMessage = "Could not add the example: \(error.localizedDescription)"
        }
    }
}

#if os(macOS)
/// "View Example Studio" submenu in the File menu.
struct ExampleStudioCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Menu("View Example Studio") {
                ForEach(ExampleStudio.allCases) { example in
                    Button(example.title) {
                        openWindow(id: ExampleStudioHost.windowId, value: example)
                    }
                }
            }
        }
    }
}
#endif
