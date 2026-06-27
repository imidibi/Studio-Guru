//
//  PaywallView.swift
//  Studio Guru
//
//  Paywall and upgrade prompts for Pro features
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var storeManager: StoreManager
    @State private var isPurchasing = false
    @State private var errorMessage: String?

    let reason: PaywallReason

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)

                        Text("Upgrade to Pro")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text(reason.message)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // Pro Features
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Pro Features")
                            .font(.title2)
                            .fontWeight(.semibold)

                        FeatureRow(
                            icon: "square.stack.3d.up.fill",
                            title: "Unlimited Studios/Sessions",
                            description: "Create as many studios/sessions as you need"
                        )

                        FeatureRow(
                            icon: "mic.fill",
                            title: "Unlimited Devices",
                            description: "Add as many devices as your studio has"
                        )

                        FeatureRow(
                            icon: "arrow.up.arrow.down.circle.fill",
                            title: "Export & Import",
                            description: "Share studio configurations with others"
                        )

                        FeatureRow(
                            icon: "icloud.fill",
                            title: "iCloud Sync",
                            description: "Keep your studios in sync across all devices"
                        )
                        
                        FeatureRow(
                            icon: "archivebox.fill",
                            title: "Gear Locker",
                            description: "Track equipment inventory and assign gear to studios"
                        )
                        
                        Divider()
                            .padding(.vertical, 8)
                        
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("One-time purchase · No subscription")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(12)

                    // Purchase button
                    if let product = storeManager.products.first {
                        VStack(spacing: 12) {
                            Button {
                                Task {
                                    await purchaseProduct(product)
                                }
                            } label: {
                                HStack {
                                    if isPurchasing {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Text("Upgrade to Pro - \(product.displayPrice)")
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                            }
                            .disabled(isPurchasing)

                            Button {
                                Task {
                                    await restorePurchases()
                                }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .disabled(isPurchasing)
                        }
                    } else if storeManager.isLoading {
                        ProgressView("Loading...")
                    } else {
                        VStack(spacing: 16) {
                            Text("Unable to load product from App Store")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .font(.subheadline)

                            #if DEBUG
                            VStack(spacing: 8) {
                                Text("⚠️ Debug Info")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text("Product ID: com.ianmiller.studioguru.pro.upgrade")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Make sure this product exists in App Store Connect")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                            #endif

                            Button {
                                Task {
                                    await storeManager.loadProducts()
                                }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    // Free tier info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Free Version Includes:")
                            .font(.headline)
                        Text("• Up to \(StoreManager.freeDeviceLimit) devices")
                        Text("• \(StoreManager.freeStudioLimit) studio")
                        Text("• All basic features")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
                .padding(24)
            }
            .navigationTitle("Studio Guru Pro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue with Free")
                            .font(.subheadline)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    private func purchaseProduct(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil

        do {
            let success = try await storeManager.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }

        isPurchasing = false
    }
    
    private func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        
        do {
            NSLog("🔄 STUDIOGURU: PaywallView: Calling storeManager.restorePurchases()...")
            try await storeManager.restorePurchases()
            NSLog("✅ STUDIOGURU: PaywallView: restorePurchases() completed")
            
            if storeManager.isPro {
                NSLog("✅ STUDIOGURU: PaywallView: User is now Pro - dismissing paywall")
                errorMessage = "Purchases restored successfully!"
                // Give user a moment to see the success message
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                dismiss()
            } else {
                NSLog("⚠️ STUDIOGURU: PaywallView: User is NOT Pro after restore")
                errorMessage = "No previous purchases found. Please check that you're signed in with the correct Apple ID and try again."
            }
        } catch {
            NSLog("❌ STUDIOGURU: PaywallView: restorePurchases() failed with error: %@", error.localizedDescription)
            errorMessage = "Failed to restore purchases: \(error.localizedDescription). Please check your internet connection and try again."
        }
        
        isPurchasing = false
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum PaywallReason {
    case deviceLimit
    case studioLimit
    case exportImport
    case iCloudSync
    case gearLocker
    case general

    var message: String {
        switch self {
        case .deviceLimit:
            return "You've reached the free limit of \(StoreManager.freeDeviceLimit) devices"
        case .studioLimit:
            return "You've reached the free limit of \(StoreManager.freeStudioLimit) studio"
        case .exportImport:
            return "Export and import features require Pro"
        case .iCloudSync:
            return "iCloud sync requires Pro"
        case .gearLocker:
            return "Gear Locker requires Pro"
        case .general:
            return "Unlock unlimited studios and devices"
        }
    }
}

#Preview {
    PaywallView(reason: .general)
        .environmentObject(StoreManager())
}
