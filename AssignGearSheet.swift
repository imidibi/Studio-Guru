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
    
    @State private var selectedStudio: Studio?
    
    // Filter out system studios (like Gear Locker itself)
    private var availableStudios: [Studio] {
        studios.filter { !$0.isSystemStudio }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                headerView
                studioListView
                Spacer()
            }
            .navigationTitle("Assign Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
        .onAppear {
            // Pre-select first studio if available
            selectedStudio = availableStudios.first
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
            List(availableStudios, id: \.id, selection: $selectedStudio) { studio in
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
            
            if selectedStudio?.id == studio.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedStudio = studio
        }
    }
}
