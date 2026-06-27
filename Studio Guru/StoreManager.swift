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

    // Debug mode for testing (only available in DEBUG builds)
    #if DEBUG
    @Published var debugSimulatePro: Bool = false
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
        
        // In debug mode, allow simulation of Pro tier
        if debugSimulatePro {
            return true
        }
        #endif
        
        // PRIORITY 1: Trust StoreKit transactions (most reliable)
        // Check for Pro upgrade IAP
        if purchasedProductIDs.contains(proProductID) {
            print("✅ User has Pro IAP purchase")
            return true
        }
        
        // Check if user bought the original paid app
        // When the app was paid, the transaction product ID was the bundle ID
        if purchasedProductIDs.contains("com.ianmiller.studioguru") {
            print("✅ User has paid app purchase - granting Pro")
            return true
        }
        
        // PRIORITY 2: Check version upgrade (fallback for offline/edge cases)
        // This helps users who upgraded from paid version but StoreKit hasn't synced yet
        if didPurchaseOriginalApp {
            print("✅ User upgraded from paid version - granting Pro")
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

        // If they had a previous version installed, check if it was a paid version
        if let previous = lastVersion, !previous.isEmpty {
            // Check if they upgraded from v1.21 or earlier (paid versions)
            if isVersionEligibleForFreePro(previous) {
                print("ℹ️ User upgraded from paid version v\(previous)")
                return true
            } else {
                print("ℹ️ User upgraded from v\(previous) (freemium era)")
                return false
            }
        }

        // Store current version for future reference
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)

        // No previous version = fresh install = not eligible for legacy upgrade
        return false
    }

    // Helper function to check if a version is eligible for free Pro upgrade
    // Versions 1.21 and earlier were paid, so those users get Pro for free
    private func isVersionEligibleForFreePro(_ versionString: String) -> Bool {
        // Parse version string (e.g., "1.21" -> [1, 21])
        let components = versionString.split(separator: ".").compactMap { Int($0) }

        guard components.count >= 2 else {
            // Invalid version format, deny Pro
            return false
        }

        let major = components[0]
        let minor = components[1]

        // Freemium started at v1.22, so v1.21 and earlier get free Pro
        if major < 1 {
            return true  // v0.x versions get Pro
        } else if major == 1 && minor <= 21 {
            return true  // v1.0 through v1.21 get Pro
        } else {
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
            print("✅ Loaded \(loadedProducts.count) products")
        } catch {
            print("❌ Failed to load products: \(error)")
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
        print("🔄 restorePurchases() called - Starting restore process...")
        isLoading = true
        defer { 
            isLoading = false 
            print("🔄 restorePurchases() completed - isLoading set to false")
        }

        print("🔄 Calling AppStore.sync()...")
        try await AppStore.sync()
        print("✅ AppStore.sync() completed successfully")
        
        print("🔄 Calling updatePurchasedProducts()...")
        await updatePurchasedProducts()
        print("✅ updatePurchasedProducts() completed")
    }

    // Update the set of purchased product IDs
    private func updatePurchasedProducts() async {
        print("🔍 updatePurchasedProducts() started")
        var purchased = Set<String>()
        var transactionCount = 0
        var unverifiedCount = 0

        // Iterate through all transactions to check for ANY purchase
        // This includes the original paid app AND the Pro upgrade IAP
        print("🔍 Checking Transaction.currentEntitlements...")
        for await result in Transaction.currentEntitlements {
            transactionCount += 1
            print("🔍 Found transaction #\(transactionCount): \(result)")
            
            switch result {
            case .verified(let transaction):
                print("✅ Transaction #\(transactionCount) is VERIFIED")
                print("   Product ID: \(transaction.productID)")
                print("   Purchase date: \(transaction.purchaseDate)")
                print("   Transaction ID: \(transaction.id)")
                print("   Revocation date: \(transaction.revocationDate?.description ?? "nil")")
                
                // Add to purchased set if not revoked
                if transaction.revocationDate == nil {
                    purchased.insert(transaction.productID)
                    print("   ✅ Added to purchased set")
                } else {
                    print("   ⚠️ Transaction was revoked - not adding")
                }
                
            case .unverified(let transaction, let verificationError):
                unverifiedCount += 1
                print("⚠️ Transaction #\(transactionCount) is UNVERIFIED")
                print("   Product ID: \(transaction.productID)")
                print("   Purchase date: \(transaction.purchaseDate)")
                print("   Verification error: \(verificationError)")
                print("   ⚠️ SKIPPING unverified transaction")
            }
        }

        print("📊 Transaction scan complete:")
        print("   Total transactions found: \(transactionCount)")
        print("   Verified: \(transactionCount - unverifiedCount)")
        print("   Unverified: \(unverifiedCount)")
        print("   Purchased product IDs: \(purchased)")

        purchasedProductIDs = purchased
        print("✅ Updated purchased products: \(purchased)")
        
        // IMPORTANT: If user has ANY purchase (paid app OR Pro IAP), they should have Pro
        // The paid app transaction will have the bundle ID as product ID
        if !purchased.isEmpty {
            print("ℹ️ User has at least one purchase - checking for Pro eligibility")
        } else {
            print("⚠️ No purchases found - user will be on free tier")
        }
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
