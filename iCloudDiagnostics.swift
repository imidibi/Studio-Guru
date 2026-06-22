//
//  iCloudDiagnostics.swift
//  Studio Guru
//
//  CloudKit diagnostics and migration helper
//

import Foundation
import CloudKit
import SwiftUI
import Combine

@MainActor
class iCloudDiagnostics: ObservableObject {
    @Published var accountStatus: CKAccountStatus?
    @Published var containerStatus: String = "Checking..."
    @Published var hasOldContainerData: Bool = false
    @Published var diagnosticResults: [String] = []
    @Published var showMigrationAlert: Bool = false
    
    private let containerIdentifier = "iCloud.com.ianmiller.studioguru"
    private let currentTeamID = "BSUPN2VUX7"
    
    /// Run comprehensive iCloud diagnostics
    func runDiagnostics() async {
        diagnosticResults.removeAll()
        
        // 1. Check iCloud account status
        await checkAccountStatus()
        
        // 2. Check container accessibility
        await checkContainerStatus()
        
        // 3. Check for potential Team ID migration issues
        await checkForMigrationIssues()
        
        // 4. Check CloudKit permissions
        await checkPermissions()
    }
    
    /// Check if user is signed into iCloud
    private func checkAccountStatus() async {
        let container = CKContainer(identifier: containerIdentifier)
        
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            
            switch status {
            case .available:
                diagnosticResults.append("✅ iCloud account is available and signed in")
            case .noAccount:
                diagnosticResults.append("❌ No iCloud account signed in")
                diagnosticResults.append("   → Go to System Settings > Apple Account to sign in")
            case .restricted:
                diagnosticResults.append("❌ iCloud account is restricted (parental controls or MDM)")
            case .couldNotDetermine:
                diagnosticResults.append("⚠️ Could not determine iCloud account status")
            case .temporarilyUnavailable:
                diagnosticResults.append("⚠️ iCloud is temporarily unavailable")
            @unknown default:
                diagnosticResults.append("⚠️ Unknown iCloud account status")
            }
        } catch {
            diagnosticResults.append("❌ Error checking iCloud account: \(error.localizedDescription)")
        }
    }
    
    /// Check if the CloudKit container is accessible
    private func checkContainerStatus() async {
        let container = CKContainer(identifier: containerIdentifier)
        
        do {
            // Try to fetch user record to verify container access
            _ = try await container.userRecordID()
            containerStatus = "Accessible"
            diagnosticResults.append("✅ CloudKit container is accessible")
            diagnosticResults.append("   Container: \(containerIdentifier)")
            diagnosticResults.append("   Team ID: \(currentTeamID)")
        } catch let error as CKError {
            containerStatus = "Error: \(error.localizedDescription)"
            
            switch error.code {
            case .notAuthenticated:
                diagnosticResults.append("❌ Not authenticated to CloudKit")
                diagnosticResults.append("   → Sign in to iCloud in System Settings")
            case .networkUnavailable, .networkFailure:
                diagnosticResults.append("❌ Network error accessing CloudKit")
                diagnosticResults.append("   → Check your internet connection")
            case .permissionFailure:
                diagnosticResults.append("❌ Permission denied for CloudKit")
                diagnosticResults.append("   → Check iCloud Drive is enabled in System Settings")
            case .incompatibleVersion:
                diagnosticResults.append("⚠️ CloudKit container version mismatch")
                diagnosticResults.append("   → This may indicate a Team ID change issue")
                hasOldContainerData = true
            default:
                diagnosticResults.append("❌ CloudKit error: \(error.localizedDescription)")
                diagnosticResults.append("   Error code: \(error.code.rawValue)")
            }
        } catch {
            containerStatus = "Error: \(error.localizedDescription)"
            diagnosticResults.append("❌ Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Check for signs of container configuration issues
    private func checkForMigrationIssues() async {
        // Check if container might be in Development mode (not Production)
        // This can happen if CloudKit schema wasn't deployed to Production
        let iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
        
        if iCloudSyncEnabled && accountStatus == .available && containerStatus.hasPrefix("Error") {
            diagnosticResults.append("⚠️ CloudKit container may not be in Production mode")
            diagnosticResults.append("   If you're an App Store user and sync isn't working,")
            diagnosticResults.append("   the developer may need to deploy the CloudKit schema")
            diagnosticResults.append("   to Production in the CloudKit Console.")
        }
    }
    
    /// Check CloudKit database permissions
    private func checkPermissions() async {
        guard accountStatus == .available else {
            return // Skip if account not available
        }
        
        let container = CKContainer(identifier: containerIdentifier)
        
        // Check if we can access the database by fetching user record
        // This is safer than querying records which may not be queryable
        do {
            let database = container.privateCloudDatabase
            
            // Try to access the database by getting the user record
            // This verifies permissions without querying potentially non-indexed fields
            _ = try await container.userRecordID()
            
            // Try a simple fetch operation (not a query)
            // This checks database access without requiring queryable indexes
            let recordID = CKRecord.ID(recordName: "test-permission-check")
            do {
                _ = try await database.record(for: recordID)
            } catch let fetchError as CKError {
                // Expected - record doesn't exist, but we verified database access
                if fetchError.code == .unknownItem {
                    diagnosticResults.append("✅ Private database is accessible")
                } else {
                    diagnosticResults.append("⚠️ Database access issue: \(fetchError.localizedDescription)")
                }
            }
        } catch let error as CKError {
            diagnosticResults.append("⚠️ Database access issue: \(error.localizedDescription)")
        } catch {
            diagnosticResults.append("⚠️ Database check failed: \(error.localizedDescription)")
        }
    }
    
    /// Get a user-friendly summary of the diagnostics
    var summary: String {
        if diagnosticResults.isEmpty {
            return "No diagnostics run yet"
        }
        
        let hasError = diagnosticResults.contains { $0.hasPrefix("❌") }
        let hasWarning = diagnosticResults.contains { $0.hasPrefix("⚠️") }
        
        if hasError {
            return "iCloud sync has issues that need attention"
        } else if hasWarning {
            return "iCloud sync may have minor issues"
        } else {
            return "iCloud sync is configured correctly"
        }
    }
    
    /// Check if this device appears to be in System Settings > iCloud
    func checkSystemSettingsVisibility() {
        // This is a best-effort check - there's no direct API to verify
        // if the app appears in System Settings > iCloud
        
        let ubiquityIdentityToken = FileManager.default.ubiquityIdentityToken
        
        if ubiquityIdentityToken != nil {
            diagnosticResults.append("✅ App has iCloud identity token")
            diagnosticResults.append("   (Should appear in System Settings > iCloud)")
        } else {
            diagnosticResults.append("❌ No iCloud identity token")
            diagnosticResults.append("   App may not appear in System Settings > iCloud")
            diagnosticResults.append("   → Try reinstalling the app")
        }
    }
}

/// Diagnostics results view
struct iCloudDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var diagnostics: iCloudDiagnostics
    @State private var isRunning = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Running diagnostics...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else if diagnostics.diagnosticResults.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 50))
                                .foregroundStyle(.secondary)
                            
                            Text("iCloud Diagnostics")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Run diagnostics to check your iCloud sync configuration and identify any issues.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button {
                                runDiagnostics()
                            } label: {
                                Text("Run Diagnostics")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                            .padding()
                        }
                        .padding()
                    } else {
                        // Summary
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.headline)
                            
                            Text(diagnostics.summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        
                        // Results
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Diagnostic Results")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(diagnostics.diagnosticResults, id: \.self) { result in
                                Text(result)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal)
                            }
                        }
                        

                        
                        // Re-run button
                        Button {
                            runDiagnostics()
                        } label: {
                            Label("Run Again", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .padding()
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("iCloud Diagnostics")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func runDiagnostics() {
        isRunning = true
        Task {
            await diagnostics.runDiagnostics()
            diagnostics.checkSystemSettingsVisibility()
            isRunning = false
        }
    }
}
