//
//  StoreManager.swift
//  Studio Guru
//
//  In-app purchase manager for Pro upgrade
//

import Foundation
import StoreKit
import SwiftUI
import Combine

@MainActor
class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs = Set<String>()
    @Published private(set) var isLoading = false

    #if DEBUG || targetEnvironment(simulator)
    // Debug mode for testing (only available in DEBUG builds and Simulator)
    @Published var debugSimulatePro: Bool = false
    #endif
    
    #if DEBUG
    @Published var debugForceFreeTier: Bool = false
    @Published private var refreshTrigger: Bool = false
    #endif

    // Product ID - this must match what you create in App Store Connect
    private let proProductID = "com.ianmiller.studioguru.pro.upgrade"

    private var updates: Task<Void, Never>? = nil

    // Computed property to check if user has Pro
    var isPro: Bool {
        #if DEBUG
        // Reference refreshTrigger to make SwiftUI re-evaluate when it changes
        _ = refreshTrigger
        
        // Force free tier overrides everything in debug mode
        if debugForceFreeTier {
            return false
        }
        #endif
        
        #if DEBUG || targetEnvironment(simulator)
        // Allow simulation of Pro tier (only in DEBUG builds and Simulator)
        if debugSimulatePro {
            return true
        }
        #endif
        
        // PRIORITY 1: Trust StoreKit transactions (most reliable)
        // Check for Pro upgrade IAP ONLY
        // NOTE: We do NOT check for bundle ID transactions because App Store
        // may return entitlements for free downloads of previously-paid apps
        if purchasedProductIDs.contains(proProductID) {
            return true
        }
        
        // PRIORITY 2: Check version upgrade (fallback for offline/edge cases)
        // This helps users who upgraded from paid version but StoreKit hasn't synced yet
        if didPurchaseOriginalApp {
            return true
        }
        
        // Default to free tier
        return false
    }
    
    // Check if user purchased the app before it went freemium
    // This is a FALLBACK check for users who upgraded but StoreKit hasn't synced
    // We trust StoreKit as primary source (checked FIRST in isPro), but this helps during offline/migration
    private var didPurchaseOriginalApp: Bool {
        // Check if user has the app installed from before freemium launch (v1.22)
        let lastVersionKey = "lastKnownVersion"
        let lastVersion = UserDefaults.standard.string(forKey: lastVersionKey)

        #if DEBUG
        print("🔍 Version check: lastKnownVersion = '\(lastVersion ?? "nil")'")
        #endif

        // If they had a previous version installed, check if it was a paid version
        if let previous = lastVersion, !previous.isEmpty {
            // Check if they upgraded from v1.21 or earlier (paid versions)
            let isEligible = isVersionEligibleForFreePro(previous)
            #if DEBUG
            print("🔍 Version check result: \(isEligible ? "ELIGIBLE" : "NOT ELIGIBLE") for Pro")
            #endif
            return isEligible
        }

        // Store current version for future reference
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.34"
        
        #if DEBUG
        print("🔍 First launch - saving version: '\(currentVersion)'")
        #endif
        
        // Validate version before saving
        if !currentVersion.isEmpty && currentVersion != "0.0" && currentVersion != "0" {
            UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)
        } else {
            #if DEBUG
            print("⚠️ WARNING: Current version is invalid ('\(currentVersion)'), not saving to UserDefaults")
            #endif
            // Don't save invalid version - this prevents the bug
        }

        // No previous version = fresh install = not eligible for legacy upgrade
        #if DEBUG
        print("🔍 Fresh install - DENYING Pro")
        #endif
        return false
    }

    // Helper function to check if a version is eligible for free Pro upgrade
    // Versions 1.21 and earlier were paid, so those users get Pro for free
    private func isVersionEligibleForFreePro(_ versionString: String) -> Bool {
        // Validate version string is not empty or default
        let trimmed = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "0.0", trimmed != "0" else {
            // Empty or default version strings are NOT eligible
            // This prevents fresh installs from getting Pro
            #if DEBUG
            print("⚠️ Version check: '\(versionString)' is invalid/empty - DENYING Pro")
            #endif
            return false
        }
        
        // Parse version string (e.g., "1.21" -> [1, 21])
        let components = trimmed.split(separator: ".").compactMap { Int($0) }

        guard components.count >= 2 else {
            // Invalid version format, deny Pro
            #if DEBUG
            print("⚠️ Version check: '\(versionString)' has invalid format - DENYING Pro")
            #endif
            return false
        }

        let major = components[0]
        let minor = components[1]

        // Freemium started at v1.22, so v1.21 and earlier get free Pro
        if major < 1 {
            // CRITICAL: v0.x versions should NOT exist in production
            // If we see v0.x, it's likely a build error - deny Pro
            #if DEBUG
            print("⚠️ Version check: v\(major).\(minor) is v0.x - DENYING Pro (suspicious)")
            #endif
            return false
        } else if major == 1 && minor <= 21 {
            #if DEBUG
            print("✅ Version check: v\(major).\(minor) is v1.21 or earlier - GRANTING Pro")
            #endif
            return true  // v1.0 through v1.21 get Pro
        } else {
            #if DEBUG
            print("⚠️ Version check: v\(major).\(minor) is v1.22+ - DENYING Pro")
            #endif
            return false  // v1.22+ do not get free Pro
        }
    }

    init() {
        // Start listening for transaction updates
        updates = observeTransactionUpdates()
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updates?.cancel()
    }
    
    #if DEBUG
    // Debug method to force refresh of Pro status after changing UserDefaults
    func refreshProStatus() {
        // Toggle a published property to force SwiftUI to re-evaluate isPro
        refreshTrigger.toggle()
    }
    #endif

    // Load available products from the App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedProducts = try await Product.products(for: [proProductID])
            products = loadedProducts
            #if DEBUG
            print("✅ Loaded \(loadedProducts.count) products")
            #endif
        } catch {
            #if DEBUG
            print("❌ Failed to load products: \(error)")
            #endif
        }
    }

    // Purchase the Pro upgrade
    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // Check verification
            let transaction = try checkVerified(verification)

            // Update purchased products
            await updatePurchasedProducts()

            // Finish the transaction
            await transaction.finish()

            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    // Restore previous purchases
    func restorePurchases() async throws {
        isLoading = true
        defer { isLoading = false }

        try await AppStore.sync()
        await updatePurchasedProducts()
    }

    // Update the set of purchased product IDs
    private func updatePurchasedProducts() async {
        var purchased = Set<String>()

        // Iterate through all transactions to check for ANY purchase
        // This includes the original paid app AND the Pro upgrade IAP
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                #if DEBUG
                if case .unverified(let transaction, let error) = result {
                    print("⚠️ Unverified transaction for \(transaction.productID): \(error)")
                }
                #endif
                continue
            }

            // Add to purchased set if not revoked
            if transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
                
                #if DEBUG
                print("📱 Found transaction: \(transaction.productID)")
                print("   Purchase date: \(transaction.purchaseDate)")
                print("   Transaction ID: \(transaction.id)")
                #endif
            }
        }

        purchasedProductIDs = purchased
        
        #if DEBUG
        print("✅ Updated purchased products: \(purchased)")
        if purchased.contains("com.ianmiller.studioguru") {
            print("⚠️  Found bundle ID transaction - this is IGNORED (free downloads may have this)")
        }
        #endif
        
        // IMPORTANT: Only the Pro IAP (proProductID) grants Pro access via StoreKit
        // Original paid app purchasers are detected via version check fallback
        // We do NOT trust bundle ID transactions as they may appear for free downloads
    }

    // Observe transaction updates
    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }

                if case .verified(let transaction) = result {
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                }
            }
        }
    }

    // Verify transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

// Store errors
enum StoreError: Error, LocalizedError {
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed"
        case .purchaseFailed:
            return "Purchase failed"
        }
    }
}

// Free tier limits
extension StoreManager {
    static let freeDeviceLimit = 6
    static let freeStudioLimit = 1

    // Check if user can add a device
    func canAddDevice(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < Self.freeDeviceLimit
    }

    // Check if user can add a studio
    func canAddStudio(currentCount: Int) -> Bool {
        if isPro { return true }
        return currentCount < Self.freeStudioLimit
    }

    // Check if user can use export/import
    var canExportImport: Bool {
        isPro
    }

    // Check if user can use iCloud sync
    var canUseICloudSync: Bool {
        isPro
    }
    
    // Check if user can access Gear Locker
    var canAccessGearLocker: Bool {
        isPro
    }
}
