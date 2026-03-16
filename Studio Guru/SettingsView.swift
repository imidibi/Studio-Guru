//
//  SettingsView.swift
//  Studio Guru
//
//  Settings and preferences view
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundStyle(.green)
                            Text("iCloud Sync Active")
                                .font(.headline)
                        }
                        
                        Text("Your studios sync automatically across all your devices using iCloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Data Sync")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your studio data is stored securely in your personal iCloud account and syncs automatically between your iPad and Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Changes sync automatically when online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• No configuration needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("• Data never leaves your iCloud account")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How It Works")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To share studios with others or create backups, use the Export feature from the toolbar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                            Text("Export creates a .studioguru file")
                                .font(.caption)
                        }
                        
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(.blue)
                            Text("Import loads a .studioguru file")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Sharing & Backup")
                } footer: {
                    Text("Exported files can be shared via email, AirDrop, or cloud storage services.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
