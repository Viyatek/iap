//
//  SubscriptionManager.swift
//  Stella
//
//  Created by Ömer Karaca on 1.06.2024.
//

import Foundation
import StoreKit


// MARK: - PurchaseHandlerDelegate
protocol PurchaseHandlerDelegate {
    func didCompletePurchase(
        transaction: SKPaymentTransaction,
        subscribedProduct: SKProduct,
        expireDate: Date,
        isConsumableProduct: Bool
    )
    func didFailPurchase(with error: Error?)
    func didUpdateProducts(_ products: [SKProduct])
}

// MARK: - RestoreHandlerDelegate
protocol RestoreHandlerDelegate {
    func didRestorePurchase(isPro: Bool, expiryDate: Date?)
    func didFailRestore(with error: Error?)
}


// MARK: - SubscriptionHandler Class
final class SubscriptionManager: NSObject {
    
    static let shared = SubscriptionManager()
    var purchaseDelegate: PurchaseHandlerDelegate?
    var restoreDelegate: RestoreHandlerDelegate?
    
    private var products = [SKProduct]()
    private var sharedSecret: String = ""
    private var storeURL: URL?
    var endPoint: String?
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    // MARK: - Configuration
    func configure(sharedSecret: String, storeURL: URL?, endPoint: String?) {
        self.sharedSecret = sharedSecret
        self.storeURL = storeURL
        self.endPoint = endPoint
    }
    
    // MARK: - Fetch Products
    func fetchAvailableProducts(with productIdentifiers: [String]) {
        let request = SKProductsRequest(productIdentifiers: Set(productIdentifiers))
        request.delegate = self
        request.start()
    }
    
    // MARK: - Purchase Product
    func purchase(_ product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    // MARK: - Restore Purchases
    func restorePurchases() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    func checkSubscriptionStatus(completion: @escaping (Result<(isSubscribed: Bool, subExpiryDate: Date?), Error>) -> Void) {
        guard let storeURL = storeURL else {
            print("Store URL not configured.")
            return
        }

        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return
        }
        
        guard let receiptData = try? Data(contentsOf: receiptURL) else {
            print("Receipt not found.")
            completion(.failure(NSError(domain: "ReceiptVerification", code: -1, userInfo: [NSLocalizedDescriptionKey: "Receipt not found."])))
            return
        }

        verifyReceipt(receiptData: receiptData, storeURL: storeURL) { [weak self] result in
            switch result {
            case .success(let receiptInfo):
                print("Receipt info: \(receiptInfo)")
                let (isSubscribed, expiryDate) = self?.parseSubscriptionInfo(receiptInfo) ?? (false, nil)
                completion(.success((isSubscribed, expiryDate)))
            case .failure(let error):
                print("Receipt verification failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    // MARK: - Verify Receipt with Enhanced Error Handling
    private func verifyReceipt(
        receiptData: Data,
        storeURL: URL,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        var request = URLRequest(url: storeURL)
        request.httpMethod = "POST"
        let body = [
            "receipt-data": receiptData.base64EncodedString(),
            "password": sharedSecret,
            "exclude-old-transactions": true
        ] as [String : Any]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(.failure(error ?? NSError(domain: "ReceiptVerification", code: -2, userInfo: [NSLocalizedDescriptionKey: "No response from server."])))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    completion(.failure(NSError(domain: "ReceiptVerification", code: -3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response."])))
                    return
                }

                //print("Receipt JSON: \(json)")

                if let status = json["status"] as? Int {
                    if status == 21007 {
                        // Switch to sandbox URL and retry verification
                        let sandboxURL = URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
                        self.verifyReceipt(receiptData: receiptData, storeURL: sandboxURL, completion: completion)
                    } else if status != 0 {
                        let errorMessage = self.getErrorMessage(for: status)
                        completion(.failure(NSError(domain: "ReceiptVerification", code: status, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                    } else {
                        completion(.success(json))
                    }
                } else {
                    completion(.failure(NSError(domain: "ReceiptVerification", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown status."])))
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }


    // MARK: - Helper to Handle Status Codes
    private func getErrorMessage(for status: Int) -> String {
        switch status {
        case 21000: return "The App Store could not read the JSON object."
        case 21002: return "The receipt data is malformed or missing."
        case 21003: return "The receipt could not be authenticated."
        case 21004: return "The shared secret does not match the account’s shared secret."
        case 21005: return "The receipt server is temporarily unavailable."
        case 21006: return "The subscription has expired."
        case 21007: return "Sandbox receipt sent to production URL."
        case 21008: return "Production receipt sent to sandbox URL."
        default: return "Unknown error. Status code: \(status)"
        }
    }

    // MARK: - Parse Subscription Info
//    private func parseSubscriptionInfo(_ receiptInfo: [String: Any]) -> (Bool, Date?) {
//        guard let latestReceiptInfo = receiptInfo["latest_receipt_info"] as? [[String: Any]] else {
//            return (false, nil)
//        }
//
//        // Assuming the most recent subscription is the last item in the array
//        let lastTransaction = latestReceiptInfo.last
//
//        if let expiresDateMs = lastTransaction?["expires_date_ms"] as? String
//            {
//            let expiresDate = Date(timeIntervalSince1970: Double(expiresDateMs)! / 1000)
//            let isSubscribed = expiresDate > Date() // Check if subscription is active
//            return (isSubscribed, expiresDate)
//        }
//
//        return (false, nil)
//    }
    
    // MARK: - Parse Subscription Info
    private func parseSubscriptionInfo(_ receiptInfo: [String: Any]) -> (Bool, Date?) {
        guard let latestReceiptInfo = receiptInfo["latest_receipt_info"] as? [[String: Any]] else {
            return (false, nil)
        }

        // Check for a lifetime product and return a 100-year expiry date if found
        if latestReceiptInfo.contains(where: { transaction in
            if let productId = transaction["product_id"] as? String {
                return productId.contains("lifetime")
            }
            return false
        }) {
            let lifetimeExpiryDate = Calendar.current.date(byAdding: .year, value: 100, to: Date())!
            print("Lifetime product found. Expiry date set to \(lifetimeExpiryDate)")
            return (true, lifetimeExpiryDate)
        }

        // Find the latest transaction with the highest expiry date
        let latestTransaction = latestReceiptInfo
            .compactMap { transaction -> (Date, Bool)? in
                if let expiresDateMs = transaction["expires_date_ms"] as? String {
                    let expiresDate = Date(timeIntervalSince1970: Double(expiresDateMs)! / 1000)
                    let isActive = expiresDate > Date()
                    return (expiresDate, isActive)
                }
                return nil
            }
            .max(by: { $0.0 < $1.0 }) // Get the latest expiry date

        guard let latest = latestTransaction else { return (false, nil) }
        return (latest.1, latest.0) // Return (isSubscribed, latestExpiryDate)
    }
    
    
        static func formattedPrice(for product: SKProduct) -> String {
            print("Format Price: \(product.price)")
    
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceLocale
            return formatter.string(from: product.price) ?? "\(product.price)"
        }
    
        static func subscriptionType(for product: SKProduct) -> String {
            print("subscribeType: \(product.productIdentifier)")
            let productId = product.productIdentifier.lowercased()
            if productId.contains("yearly") {
                return "Yearly"
            } else if productId.contains("monthly") {
                return "Monthly"
            } else if productId.contains("weekly") {
                return "Weekly"
            } else if productId.contains("lifetime") {
                return "Lifetime"
            } else {
                return "Subscription"
            }
        }
    
        static func calculateDailyPrice(for product: SKProduct) -> String {
            print("calculateDailyPrice: \(product.price)")
    
            let price = product.price.doubleValue
            var period: Double = 1 // Default value
    
            if let subscriptionPeriod = product.subscriptionPeriod {
                switch subscriptionPeriod.unit {
                case .day:
                    period = Double(subscriptionPeriod.numberOfUnits)
                case .week:
                    period = Double(subscriptionPeriod.numberOfUnits * 7)
                case .month:
                    period = Double(subscriptionPeriod.numberOfUnits * 30)
                case .year:
                    period = Double(subscriptionPeriod.numberOfUnits * 365)
                @unknown default:
                    period = 1
                }
            }
    
            let dailyPrice = price / period
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = product.priceLocale
            if let formattedPrice = formatter.string(from: NSNumber(value: dailyPrice)) {
                return "\(formattedPrice)/day"
            } else {
                return "\(dailyPrice)/day"
            }
        }
    
        func getFreeTrialDaysNumber(product: SKProduct) -> Int {
            print("getFreeTrialDaysNumber: \(product.productIdentifier)")
            if let introductoryPrice = product.introductoryPrice {
                let trialPeriod = introductoryPrice.subscriptionPeriod
                if trialPeriod.unit == .day {
                    print("Trial duration: \(trialPeriod.numberOfUnits) days")
                    return Int(trialPeriod.numberOfUnits)
                } else if trialPeriod.unit == .week {
                    print("Trial duration: \(trialPeriod.numberOfUnits * 7) days")
                    return Int(trialPeriod.numberOfUnits * 7)
                } else if trialPeriod.unit == .month {
                    print("Trial duration: \(trialPeriod.numberOfUnits * 30) days")
                    return Int(trialPeriod.numberOfUnits * 30)
                } else if trialPeriod.unit == .year {
                    print("Trial duration: \(trialPeriod.numberOfUnits * 365) days")
                    return Int(trialPeriod.numberOfUnits * 365)
                } else {
                    return 0
                }
            } else {
                print("No free trial available for this product.")
                return 0
            }
        }




}

// MARK: - SKProductsRequestDelegate
extension SubscriptionManager: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.products = response.products
        purchaseDelegate?.didUpdateProducts(products)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        purchaseDelegate?.didFailPurchase(with: error)
    }
}

// MARK: - SKPaymentTransactionObserver
extension SubscriptionManager: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                handlePurchased(transaction)
            case .failed:
                purchaseDelegate?.didFailPurchase(with: transaction.error)
                queue.finishTransaction(transaction)
            case .restored:
                handleRestored(transaction)
                queue.finishTransaction(transaction)
            default:
                break
            }
        }
    }
    
    private func handlePurchased(_ transaction: SKPaymentTransaction) {
        guard let product = products.first(where: { $0.productIdentifier == transaction.payment.productIdentifier }) else { return }
        let expiryDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())! // Simulate expiry date
        
        purchaseDelegate?.didCompletePurchase(
            transaction: transaction,
            subscribedProduct: product,
            expireDate: expiryDate,
            isConsumableProduct: false
        )
        
        SKPaymentQueue.default().finishTransaction(transaction)
    }
    
    public func fetchReceiptForFreeTrialCheck(completion: @escaping (Data?) -> Void) {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            completion(nil)
            return
        }
        
        do {
            let receiptData = try Data(contentsOf: receiptURL)
            completion(receiptData)
        } catch {
            completion(nil)
        }
    }

    
    public func sendReceiptToServer(receiptData: Data, completion: @escaping (Bool) -> Void) {
        // Your server URL
        //let url = URL(string: endPoint ?? "https://buy.itunes.apple.com/verifyReceipt")!
        
        var request = URLRequest(url: (storeURL ?? URL(string: "https://buy.itunes.apple.com/verifyReceipt"))!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = ["receipt-data": receiptData.base64EncodedString()]
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(false)
                return
            }
            
            do {
                // Parse the JSON response
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    // Check for trial subscription in the receipt
                    if let receiptInfo = jsonResponse["receipt"] as? [String: Any],
                       let inApp = receiptInfo["in_app"] as? [[String: Any]] {
                        
                        for purchase in inApp {
                            if let isTrialPeriod = purchase["is_trial_period"] as? String,
                               isTrialPeriod == "true" {
                                completion(true)
                                return
                            }
                        }
                    }
                }
                completion(false)
            } catch {
                completion(false)
            }
        }
        
        task.resume()
    }
    
    public func checkFreeTrialStatus(completion: @escaping (Bool) -> Void) {
        fetchReceiptForFreeTrialCheck { [self] receiptData in
            guard let receiptData = receiptData else {
                completion(false)
                return
            }
            
            sendReceiptToServer(receiptData: receiptData) { hasUsedFreeTrial in
                completion(hasUsedFreeTrial)
            }
        }
    }
    
    private func handleRestored(_ transaction: SKPaymentTransaction) {
        guard let receiptURL = Bundle.main.appStoreReceiptURL, let storeURL = storeURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            restoreDelegate?.didRestorePurchase(isPro: false, expiryDate: nil)
            return
        }

        verifyReceipt(receiptData: receiptData, storeURL: storeURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let receiptInfo):
                    let (isSubscribed, expiryDate) = self?.parseSubscriptionInfo(receiptInfo) ?? (false, nil)
                    
//                    if expiryDate ?? Date() > Calendar.current.date(byAdding: .year, value: 10, to: Date())! {
//                        print("Restored lifetime product. Expiry date: \(expiryDate!)")
//                    }

                    self?.restoreDelegate?.didRestorePurchase(isPro: isSubscribed, expiryDate: expiryDate)

                case .failure(let error):
                    self?.restoreDelegate?.didFailRestore(with: error)
                }
            }
        }
    }
    
}
