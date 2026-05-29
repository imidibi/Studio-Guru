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
    let device: DeviceInstance
    let studios: [Studio]
    let onAssign: (Studio) -> Void
    
    @State private var selectedStudioId: UUID?
    
    // Filter out system studios (like Gear Locker itself)
    private var availableStudios: [Studio] {
        studios.filter { !$0.isSystemStudio }
    }
    
    private var selectedStudio: Studio? {
        availableStudios.first(where: { $0.id == selectedStudioId })
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
                            if let studio = selectedStudio {
                                onAssign(studio)
                                dismiss()
                            }
                        }
                        .disabled(selectedStudio == nil)
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
                    if let studio = selectedStudio {
                        onAssign(studio)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedStudio == nil)
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
            selectedStudioId = availableStudios.first?.id
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
            
            Text("Assign \"\(device.nickname)\" to a studio")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var studioListView: some View {
        if availableStudios.isEmpty {
            emptyStateView
        } else {
            List(availableStudios, id: \.id) { studio in
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
    
    private func studioRow(_ studio: Studio) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.headline)
                
                if let deviceCount = studio.devices?.count {
                    Text("\(deviceCount) device\(deviceCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
