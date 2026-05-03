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
    @Published var debugSimulateFree: Bool = false
    #endif

    // Product ID - this must match what you create in App Store Connect
    private let proProductID = "com.ianmiller.studioguru.pro"

    private var updates: Task<Void, Never>? = nil

    // Computed property to check if user has Pro
    var isPro: Bool {
        #if DEBUG
        // In debug mode, allow simulation of free tier
        if debugSimulateFree {
            return false
        }
        #endif
        return purchasedProductIDs.contains(proProductID)
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
}
