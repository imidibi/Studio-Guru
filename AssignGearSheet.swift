//
//  AssignGearSheet.swift
//  Studio Guru
//
//  Sheet for assigning a device from Gear Locker to a studio
//

import SwiftUI
import SwiftData

struct AssignGearSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let deviceInfo: DeviceInfo
    let studioOptions: [StudioOption]
    let onAssign: (UUID) -> Void
    
    @State private var selectedStudioId: UUID?
    
    struct DeviceInfo {
        let id: UUID
        let nickname: String
    }
    
    struct StudioOption: Identifiable {
        let id: UUID
        let name: String
        let deviceCount: Int
    }
    
    var body: some View {
        #if os(macOS)
        macOSContent
        #else
        NavigationStack {
            contentView
                .navigationTitle("Assign Device")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Next") {
                            if let studioId = selectedStudioId {
                                onAssign(studioId)
                                dismiss()
                            }
                        }
                        .disabled(selectedStudioId == nil)
                    }
                }
        }
        #endif
    }
    
    #if os(macOS)
    private var macOSContent: some View {
        VStack(spacing: 0) {
            // Header bar with title and buttons
            HStack {
                Text("Assign Device")
                    .font(.headline)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Next") {
                    if let studioId = selectedStudioId {
                        onAssign(studioId)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedStudioId == nil)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            contentView
        }
        .frame(width: 500, height: 400)
    }
    #endif
    
    private var contentView: some View {
        VStack(spacing: 20) {
            headerView
            studioListView
            Spacer()
        }
        .onAppear {
            // Pre-select first studio if available
            selectedStudioId = studioOptions.first?.id
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            
            Text("Assign to Studio")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Assign \"\(deviceInfo.nickname)\" to a studio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var studioListView: some View {
        if studioOptions.isEmpty {
            emptyStateView
        } else {
            List(studioOptions) { studio in
                studioRow(studio)
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            
            Text("No Studios Available")
                .font(.headline)
            
            Text("Create a studio first before assigning devices from the Gear Locker.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
    
    private func studioRow(_ studio: StudioOption) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.headline)
                
                Text("\(studio.deviceCount) device\(studio.deviceCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if selectedStudioId == studio.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStudioId = studio.id
        }
    }
}
