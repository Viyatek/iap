//
//  SubscriptionManager.swift
//  Stella
//
//  Created by Ömer Karaca on 1.06.2024.
//

import Foundation
import StoreKit



// MARK: - PurchaseHandlerDelegate
protocol PurchaseHandlerDelegate: AnyObject {
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
protocol RestoreHandlerDelegate: AnyObject {
    func didRestorePurchase(isPro: Bool, expiryDate: Date?)
    func didFailRestore(with error: Error?)
}


// MARK: - SubscriptionHandler Class
final class SubscriptionManager: NSObject {
    
    static let shared = SubscriptionManager()
    weak var purchaseDelegate: PurchaseHandlerDelegate?
    weak var restoreDelegate: RestoreHandlerDelegate?
    
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

        let receiptURL = Bundle.main.appStoreReceiptURL
        guard let receiptData = try? Data(contentsOf: receiptURL!) else {
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

                print("Receipt JSON: \(json)")

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
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              let receiptData = try? Data(contentsOf: receiptURL) else {
            restoreDelegate?.didRestorePurchase(isPro: false, expiryDate: nil)
            return
        }

        verifyReceipt(receiptData: receiptData, storeURL: storeURL!) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let receiptInfo):
                    let (isSubscribed, expiryDate) = self?.parseSubscriptionInfo(receiptInfo) ?? (false, nil)
                    
                    if expiryDate ?? Date() > Calendar.current.date(byAdding: .year, value: 10, to: Date())! {
                        print("Restored lifetime product. Expiry date: \(expiryDate!)")
                    }

                    self?.restoreDelegate?.didRestorePurchase(isPro: isSubscribed, expiryDate: expiryDate)

                case .failure(let error):
                    self?.restoreDelegate?.didFailRestore(with: error)
                }
            }
        }
    }


}





//public class SubscriptionManager: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
//
//    public static let shared = SubscriptionManager()
//    public static var sharedSecret = ""
//    public static var endPoint = ""
//    
//    
//    // Products
//    public static var products: [SKProduct]?
//
//    //UI Update Delegate
//    public var purchaseSuccessDelegate: PurchaseSuccessDelegate?
//    
//    //Restore Delegate
//    public var restorePurchasesDelegate: RestorePurchasesDelegate?
//    
//    
//    private override init() {
//        super.init()
//        //Add it to purchase func to prevent unexpected purchase
//        //SKPaymentQueue.default().add(self)
//    }
//    
//    deinit {
//        SKPaymentQueue.default().remove(self)
//    }
//    
//    // MARK: - Product Request
//    var productsRequest: SKProductsRequest?
//    var availableProducts: [SKProduct] = []
//    var productRequestCompletion: ((Result<[SKProduct], Error>) -> Void)?
//    
//    public func fetchAvailableProducts(productIdentifiers: [String], completion: @escaping (Result<[SKProduct], Error>) -> Void) {
//        self.productRequestCompletion = completion
//        let productIdentifiers = Set(productIdentifiers)
//        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
//        productsRequest?.delegate = self
//        productsRequest?.start()
//    }
//
//    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
//        availableProducts = response.products
//        productRequestCompletion?(.success(response.products))
//        clearProductRequest()
//    }
//
//    public func request(_ request: SKRequest, didFailWithError error: Error) {
//        productRequestCompletion?(.failure(error))
//        clearProductRequest()
//    }
//
//    public func clearProductRequest() {
//        productsRequest = nil
//        productRequestCompletion = nil
//    }
//
//    // MARK: - Purchase
//    public func purchase(product: SKProduct) {
//        let payment = SKPayment(product: product)
//        SKPaymentQueue.default().add(self)
//        SKPaymentQueue.default().add(payment)
//    }
//    
//    public func  checkSubscriptionStatus(completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
//        print("inside checkSubscriptionStatus")
//        validateReceipt { isPro, subsExpiryDate in
//            print("in validate comp")
//            completion(isPro, subsExpiryDate)
//        }
//    }
//    
//    
//    public func fetchReceipt() -> Data? {
//        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
//           FileManager.default.fileExists(atPath: appStoreReceiptURL.path) {
//            do {
//                let receiptData = try Data(contentsOf: appStoreReceiptURL)
//                print("Fetched receipt data successfully: \(receiptData.count) bytes")
//                return receiptData
//            } catch {
//                print("Error fetching receipt data: \(error.localizedDescription)")
//            }
//        } else {
//            print("App Store receipt not found")
//        }
//        return nil
//    }
//    
//
//    public func fetchReceiptForFreeTrialCheck(completion: @escaping (Data?) -> Void) {
//        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
//            completion(nil)
//            return
//        }
//        
//        do {
//            let receiptData = try Data(contentsOf: receiptURL)
//            completion(receiptData)
//        } catch {
//            completion(nil)
//        }
//    }
//
//    
//    public func sendReceiptToServer(receiptData: Data, completion: @escaping (Bool) -> Void) {
//        // Your server URL
//        let url = URL(string: SubscriptionManager.endPoint)!
//        
//        var request = URLRequest(url: url)
//        request.httpMethod = "POST"
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        
//        let requestBody: [String: Any] = ["receipt-data": receiptData.base64EncodedString()]
//        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: [])
//        
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            guard let data = data, error == nil else {
//                completion(false)
//                return
//            }
//            
//            do {
//                // Parse the JSON response
//                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
//                    // Check for trial subscription in the receipt
//                    if let receiptInfo = jsonResponse["receipt"] as? [String: Any],
//                       let inApp = receiptInfo["in_app"] as? [[String: Any]] {
//                        
//                        for purchase in inApp {
//                            if let isTrialPeriod = purchase["is_trial_period"] as? String,
//                               isTrialPeriod == "true" {
//                                completion(true)
//                                return
//                            }
//                        }
//                    }
//                }
//                completion(false)
//            } catch {
//                completion(false)
//            }
//        }
//        
//        task.resume()
//    }
//
//    
//    public func checkFreeTrialStatus(completion: @escaping (Bool) -> Void) {
//        fetchReceiptForFreeTrialCheck { [self] receiptData in
//            guard let receiptData = receiptData else {
//                completion(false)
//                return
//            }
//            
//            sendReceiptToServer(receiptData: receiptData) { hasUsedFreeTrial in
//                completion(hasUsedFreeTrial)
//            }
//        }
//    }
//    
//    
//    public func validateReceipt(transaction: SKPaymentTransaction? = nil, completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
//        print("in validateReceipt")
//        guard let receiptData = fetchReceipt() else {
//            print("Receipt data is nill")
//            completion(false, Date())
//            return
//        }
//        let receiptString = receiptData.base64EncodedString(options: [])
//
//
//        // Prepare the request contents
//        let requestContents: [String: Any] = [
//            "receipt-data": receiptString,
//            "password": SubscriptionManager.sharedSecret // Replace with your actual shared secret
//        ]
//
//        // Convert the request contents to JSON
//        guard let requestData = try? JSONSerialization.data(withJSONObject: requestContents, options: []) else {
//            print("Failed to serialize request contents to JSON")
//            completion(false, Date())
//            return
//        }
//
//        // Debug: Log the JSON request data
////        if let requestString = String(data: requestData, encoding: .utf8) {
////            print("Request data: \(requestString)")
////        }
//
//        // Set up the validation URL (sandbox)
//        let storeURL = {
//            return URL(string: SubscriptionManager.endPoint)!
////            #if DEBUG
////                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
////            #else
////                return URL(string: SubscriptionManager.endPoint)!
////                //return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
////            #endif
//        }()
//
//        // Create the request
//        var request = URLRequest(url: storeURL)
//        request.httpMethod = "POST"
//        request.httpBody = requestData
//
//        // Debug: Log the request URL and method
//        print("Request URL: \(storeURL.absoluteString)")
//        print("Request method: \(request.httpMethod ?? "No method")")
//
//        // Perform the request
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            guard error == nil, let data = data else {
//                print("Error validating receipt: \(error?.localizedDescription ?? "No data")")
//                completion(false, Date())
//                return
//            }
//
//            // Debug: Log the response data
////            if let responseString = String(data: data, encoding: .utf8) {
////                print("Response data: \(responseString)")
////            }
//
//            do {
//                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
//                    //print("Receipt validation response: \(jsonResponse)")
//                    
//                    // Debug: Log the full response
////                    if let jsonResponseString = String(data: try JSONSerialization.data(withJSONObject: jsonResponse, options: .prettyPrinted), encoding: .utf8) {
////                        print("Full receipt validation response: \(jsonResponseString)")
////                    }
//
//                    // Parse jsonResponse to check subscription status
//                    let subscriptionStatus = self.checkSubscriptionStatus(receipt: jsonResponse)
//                    DispatchQueue.main.async {
//                        // Handle subscription status in the UI or app logic
//                        
//                        if subscriptionStatus.0 {
//                            print("Subscription is active")
//                        } else {
//                            print("Subscription is not active")
//                        }
//                        
//                        completion(subscriptionStatus.0, subscriptionStatus.1)
//                    }
//                }
//            } catch {
//                print("Error parsing receipt validation response: \(error.localizedDescription)")
//                completion(false, Date())
//            }
//        }
//        task.resume()
//    }
//
//    
//    public func checkSubscriptionStatus(receipt: [String: Any]) -> (Bool, Date) {
//        guard let receiptInfo = receipt["latest_receipt_info"] as? [[String: Any]] else {
//            print("No latest_receipt_info found in receipt")
//            return (false, Date())
//        }
//
//        var latestExpiryDate: Date?
//        var hasLifetimePurchase = false
//        var isInGracePeriod = false
//
//        for receiptItem in receiptInfo {
//            if let expiresDateMs = receiptItem["expires_date_ms"] as? String,
//               let expiresDate = Double(expiresDateMs) {
//                let expiryDate = Date(timeIntervalSince1970: expiresDate / 1000)
//
//                if expiryDate > Date() {
//                    if latestExpiryDate == nil || expiryDate > latestExpiryDate! {
//                        latestExpiryDate = expiryDate
//                    }
//                }
//            } else if let gracePeriodExpiresDateMs = receiptItem["grace_period_expires_date_ms"] as? String,
//                      let gracePeriodExpiresDate = Double(gracePeriodExpiresDateMs) {
//                let graceExpiryDate = Date(timeIntervalSince1970: gracePeriodExpiresDate / 1000)
//                if graceExpiryDate > Date() {
//                    isInGracePeriod = true
//                    latestExpiryDate = graceExpiryDate
//                }
//            } else if let purchaseDateMs = receiptItem["purchase_date_ms"] as? String,
//                      let productId = receiptItem["product_id"] as? String {
//                let purchaseDate = Date(timeIntervalSince1970: Double(purchaseDateMs)! / 1000)
//                if isLifetimePurchase(productId: productId) {
//                    hasLifetimePurchase = true
//                }
//            }
//        }
//
//        if hasLifetimePurchase {
//            return (true, Calendar.current.date(byAdding: .year, value: 100, to: Date())!)
//        } else if let latestExpiryDate = latestExpiryDate {
//            return (true, latestExpiryDate)
//        } else {
//            return (false, Date())
//        }
//    }
//
//
//    public func isLifetimePurchase(productId: String) -> Bool {
//        return productId.contains("lifetime")
//    }
//
//    //MARK: Check Refunds
//    public func checkForRefunds(completion: @escaping (Bool) -> Void) {
//        print("Checking for refunds")
//        guard let receiptData = fetchReceipt() else {
//            print("Receipt data is nil")
//            completion(false)
//            return
//        }
//        let receiptString = receiptData.base64EncodedString(options: [])
//
//        let requestContents: [String: Any] = [
//            "receipt-data": receiptString,
//            "password": SubscriptionManager.sharedSecret
//        ]
//
//        guard let requestData = try? JSONSerialization.data(withJSONObject: requestContents, options: []) else {
//            print("Failed to serialize request contents to JSON")
//            completion(false)
//            return
//        }
//
//        let storeURL = {
//            return URL(string: SubscriptionManager.endPoint)!
////            #if DEBUG
////                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
////            #else
////                return URL(string: SubscriptionManager.endPoint)!
////                //return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
////            #endif
//        }()
//
//        var request = URLRequest(url: storeURL)
//        request.httpMethod = "POST"
//        request.httpBody = requestData
//
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            guard error == nil, let data = data else {
//                print("Error validating receipt: \(error?.localizedDescription ?? "No data")")
//                completion(false)
//                return
//            }
//
//            do {
//                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
//                    let hasRefunds = self.checkForRefundsInReceipt(receipt: jsonResponse)
//                    DispatchQueue.main.async {
//                        completion(hasRefunds)
//                    }
//                }
//            } catch {
//                print("Error parsing receipt validation response: \(error.localizedDescription)")
//                completion(false)
//            }
//        }
//        task.resume()
//    }
//
//    public func checkForRefundsInReceipt(receipt: [String: Any]) -> Bool {
//        guard let receiptInfo = receipt["latest_receipt_info"] as? [[String: Any]] else {
//            print("No latest_receipt_info found in receipt")
//            return false
//        }
//
//        for receiptItem in receiptInfo {
//            if let cancellationDateMs = receiptItem["cancellation_date_ms"] as? String,
//               let _ = Double(cancellationDateMs) {
//                return true
//            }
//        }
//
//        return false
//    }
//    
//    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
//        print("in payment queue subs manager")
//        for transaction in transactions {
//            switch transaction.transactionState {
//            case .purchased:
//                validateReceipt(transaction: transaction) { [self] isPro, subsExpiryDate in
//                    
//                    if let purchasedProduct = getProduct(from: transaction) {
//                        
//                        purchaseSuccessDelegate?.purchaseSuccess(transaction: transaction, subscribedProduct: purchasedProduct, expireDate: subsExpiryDate)
//
//                    }
//                    
//                    SKPaymentQueue.default().finishTransaction(transaction)
//                    SKPaymentQueue.default().remove(self)
//                }
//            case .restored:
//                validateReceipt(transaction: transaction) { isPro, subsExpiryDate in
//
//                }
//                SKPaymentQueue.default().finishTransaction(transaction)
//                SKPaymentQueue.default().remove(self)
//
//            case .failed:
////                print("Failed to pay")
////                if let error = transaction.error as NSError?,
////                   error.code != SKError.paymentCancelled.rawValue {
////                    print("Transaction Failed: \(error.localizedDescription)")
////                }
//                
//                purchaseSuccessDelegate?.purchaseFailed(transaction: transaction, error: transaction.error)
//                SKPaymentQueue.default().finishTransaction(transaction)
//                
//                SKPaymentQueue.default().remove(self)
//            default:
//                break
//            }
//        }
//    }
//    
//    public  func getProduct(from transaction: SKPaymentTransaction) -> SKProduct? {
//        guard let productIdentifier = transaction.payment.productIdentifier as String?,
//              let product = availableProducts.first(where: { $0.productIdentifier == productIdentifier }) else {
//            return nil
//        }
//        return product
//    }
//    
//    // MARK: - Restore Purchases
//    public func restorePurchases() {
//        SKPaymentQueue.default().add(self)
//        SKPaymentQueue.default().restoreCompletedTransactions()
//    }
//
//    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
//        print("Restored completed transactions finished.")
//        validateReceipt { isPro, subsExpiryDate in
//            self.restorePurchasesDelegate?.restorePurchasesCompleted(isPro: isPro, expiryDate: subsExpiryDate)
//            SKPaymentQueue.default().remove(self)
//        }
//    }
//
//    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
//        print("Failed to restore completed transactions: \(error.localizedDescription)")
//        self.restorePurchasesDelegate?.restorePurchasesFailed(error: error)
//        SKPaymentQueue.default().remove(self)
//    }
//    
//}
//
//
//public protocol PurchaseSuccessDelegate {
//    func purchaseSuccess(transaction: SKPaymentTransaction, subscribedProduct: SKProduct, expireDate: Date)
//    func purchaseFailed(transaction: SKPaymentTransaction, error: Error?)
//}
//
//
//public protocol RestorePurchasesDelegate {
//    func restorePurchasesCompleted(isPro: Bool, expiryDate: Date)
//    func restorePurchasesFailed(error: Error)
//}

