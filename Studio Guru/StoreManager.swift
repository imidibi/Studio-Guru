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
        
        // Honor original app purchase - anyone who bought v1.21 or earlier gets Pro for free
        if didPurchaseOriginalApp {
            return true
        }
        
        return purchasedProductIDs.contains(proProductID)
    }
    
    // Check if user purchased the app before it went freemium
    private var didPurchaseOriginalApp: Bool {
        // SECURITY FIX: Track both granted AND denied states to prevent exploits
        // We need to remember if we already made a decision for this user
        let hasCheckedKey = "hasCheckedOriginalPurchaser"
        let wasGrantedKey = "wasGrantedOriginalPurchaserPro"
        
        // If we've already made a decision for this user, honor it
        if UserDefaults.standard.object(forKey: hasCheckedKey) != nil {
            let wasGranted = UserDefaults.standard.bool(forKey: wasGrantedKey)
            if wasGranted {
                print("ℹ️ User was previously granted Pro as original purchaser")
            }
            return wasGranted
        }

        // For backwards compatibility during transition:
        // Check if user has the app installed from before freemium launch (v1.22)
        // We'll use a version check - if they're upgrading from v1.21 or earlier, grant Pro
        let lastVersionKey = "lastKnownVersion"
        let lastVersion = UserDefaults.standard.string(forKey: lastVersionKey)

        // If this is their first launch of v1.22+ and they had a previous version, validate it
        if let previous = lastVersion, !previous.isEmpty {
            // SECURITY: Only grant Pro if they upgraded from v1.21 or earlier
            // This prevents users from getting Pro by reinstalling
            if isVersionEligibleForFreePro(previous) {
                // They upgraded from a paid version - mark as original purchaser
                UserDefaults.standard.set(true, forKey: hasCheckedKey)
                UserDefaults.standard.set(true, forKey: wasGrantedKey)
                print("✅ Granting Pro status to original app purchaser (upgraded from v\(previous))")
                return true
            } else {
                // They had a newer version installed (v1.22+), not eligible for free Pro
                UserDefaults.standard.set(true, forKey: hasCheckedKey)
                UserDefaults.standard.set(false, forKey: wasGrantedKey)
                print("ℹ️ User upgraded from v\(previous), not eligible for free Pro (freemium started at v1.22)")
                return false
            }
        }

        // First-time install - store current version and mark as checked/denied
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        UserDefaults.standard.set(currentVersion, forKey: lastVersionKey)
        UserDefaults.standard.set(true, forKey: hasCheckedKey)
        UserDefaults.standard.set(false, forKey: wasGrantedKey)
        print("ℹ️ First install at v\(currentVersion), not eligible for free Pro")

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
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            print("❌ Failed to restore purchases: \(error)")
        }
    }

    // Update the set of purchased product IDs
    private func updatePurchasedProducts() async {
        var purchased = Set<String>()

        // Iterate through all transactions
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            // Add to purchased set if not revoked
            if transaction.revocationDate == nil {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
        print("✅ Updated purchased products: \(purchased)")
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
