//
//  SubscriptionManager.swift
//  Stella
//
//  Created by Ömer Karaca on 1.06.2024.
//

import Foundation
import StoreKit

public class SubscriptionManager: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {

    public static let shared = SubscriptionManager()
    public static var sharedSecret = ""
    public static var endPoint = ""
    
    
    // Products
    public static var products: [SKProduct]?

    //UI Update Delegate
    public var purchaseSuccessDelegate: PurchaseSuccessDelegate?
    
    //Restore Delegate
    public var restorePurchasesDelegate: RestorePurchasesDelegate?
    
    
    private override init() {
        super.init()
        //Add it to purchase func to prevent unexpected purchase
        //SKPaymentQueue.default().add(self)
    }
    
    deinit {
        SKPaymentQueue.default().remove(self)
    }
    
    // MARK: - Product Request
    var productsRequest: SKProductsRequest?
    var availableProducts: [SKProduct] = []
    var productRequestCompletion: ((Result<[SKProduct], Error>) -> Void)?
    
    public func fetchAvailableProducts(productIdentifiers: [String], completion: @escaping (Result<[SKProduct], Error>) -> Void) {
        self.productRequestCompletion = completion
        let productIdentifiers = Set(productIdentifiers)
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest?.delegate = self
        productsRequest?.start()
    }

    public func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        availableProducts = response.products
        productRequestCompletion?(.success(response.products))
        clearProductRequest()
    }

    public func request(_ request: SKRequest, didFailWithError error: Error) {
        productRequestCompletion?(.failure(error))
        clearProductRequest()
    }

    public func clearProductRequest() {
        productsRequest = nil
        productRequestCompletion = nil
    }

    // MARK: - Purchase
    public func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().add(payment)
    }
    
    public func  checkSubscriptionStatus(completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
        print("inside checkSubscriptionStatus")
        validateReceipt { isPro, subsExpiryDate in
            print("in validate comp")
            completion(isPro, subsExpiryDate)
        }
    }
    
    
    public func fetchReceipt() -> Data? {
        if let appStoreReceiptURL = Bundle.main.appStoreReceiptURL,
           FileManager.default.fileExists(atPath: appStoreReceiptURL.path) {
            do {
                let receiptData = try Data(contentsOf: appStoreReceiptURL)
                print("Fetched receipt data successfully: \(receiptData.count) bytes")
                return receiptData
            } catch {
                print("Error fetching receipt data: \(error.localizedDescription)")
            }
        } else {
            print("App Store receipt not found")
        }
        return nil
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
        let url = URL(string: SubscriptionManager.endPoint)!
        
        var request = URLRequest(url: url)
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
    
    
    public func validateReceipt(transaction: SKPaymentTransaction? = nil, completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
        print("in validateReceipt")
        guard let receiptData = fetchReceipt() else {
            print("Receipt data is nill")
            completion(false, Date())
            return
        }
        let receiptString = receiptData.base64EncodedString(options: [])


        // Prepare the request contents
        let requestContents: [String: Any] = [
            "receipt-data": receiptString,
            "password": SubscriptionManager.sharedSecret // Replace with your actual shared secret
        ]

        // Convert the request contents to JSON
        guard let requestData = try? JSONSerialization.data(withJSONObject: requestContents, options: []) else {
            print("Failed to serialize request contents to JSON")
            completion(false, Date())
            return
        }

        // Debug: Log the JSON request data
//        if let requestString = String(data: requestData, encoding: .utf8) {
//            print("Request data: \(requestString)")
//        }

        // Set up the validation URL (sandbox)
        let storeURL = {
            return URL(string: SubscriptionManager.endPoint)!
//            #if DEBUG
//                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
//            #else
//                return URL(string: SubscriptionManager.endPoint)!
//                //return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
//            #endif
        }()

        // Create the request
        var request = URLRequest(url: storeURL)
        request.httpMethod = "POST"
        request.httpBody = requestData

        // Debug: Log the request URL and method
        print("Request URL: \(storeURL.absoluteString)")
        print("Request method: \(request.httpMethod ?? "No method")")

        // Perform the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error validating receipt: \(error?.localizedDescription ?? "No data")")
                completion(false, Date())
                return
            }

            // Debug: Log the response data
//            if let responseString = String(data: data, encoding: .utf8) {
//                print("Response data: \(responseString)")
//            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    //print("Receipt validation response: \(jsonResponse)")
                    
                    // Debug: Log the full response
//                    if let jsonResponseString = String(data: try JSONSerialization.data(withJSONObject: jsonResponse, options: .prettyPrinted), encoding: .utf8) {
//                        print("Full receipt validation response: \(jsonResponseString)")
//                    }

                    // Parse jsonResponse to check subscription status
                    let subscriptionStatus = self.checkSubscriptionStatus(receipt: jsonResponse)
                    DispatchQueue.main.async {
                        // Handle subscription status in the UI or app logic
                        
                        if subscriptionStatus.0 {
                            print("Subscription is active")
                        } else {
                            print("Subscription is not active")
                        }
                        
                        completion(subscriptionStatus.0, subscriptionStatus.1)
                    }
                }
            } catch {
                print("Error parsing receipt validation response: \(error.localizedDescription)")
                completion(false, Date())
            }
        }
        task.resume()
    }

    
    public func checkSubscriptionStatus(receipt: [String: Any]) -> (Bool, Date) {
        guard let receiptInfo = receipt["latest_receipt_info"] as? [[String: Any]] else {
            print("No latest_receipt_info found in receipt")
            return (false, Date())
        }

        var latestExpiryDate: Date?
        var hasLifetimePurchase = false
        var isInGracePeriod = false

        for receiptItem in receiptInfo {
            if let expiresDateMs = receiptItem["expires_date_ms"] as? String,
               let expiresDate = Double(expiresDateMs) {
                let expiryDate = Date(timeIntervalSince1970: expiresDate / 1000)

                if expiryDate > Date() {
                    if latestExpiryDate == nil || expiryDate > latestExpiryDate! {
                        latestExpiryDate = expiryDate
                    }
                }
            } else if let gracePeriodExpiresDateMs = receiptItem["grace_period_expires_date_ms"] as? String,
                      let gracePeriodExpiresDate = Double(gracePeriodExpiresDateMs) {
                let graceExpiryDate = Date(timeIntervalSince1970: gracePeriodExpiresDate / 1000)
                if graceExpiryDate > Date() {
                    isInGracePeriod = true
                    latestExpiryDate = graceExpiryDate
                }
            } else if let purchaseDateMs = receiptItem["purchase_date_ms"] as? String,
                      let productId = receiptItem["product_id"] as? String {
                let purchaseDate = Date(timeIntervalSince1970: Double(purchaseDateMs)! / 1000)
                if isLifetimePurchase(productId: productId) {
                    hasLifetimePurchase = true
                }
            }
        }

        if hasLifetimePurchase {
            return (true, Calendar.current.date(byAdding: .year, value: 100, to: Date())!)
        } else if let latestExpiryDate = latestExpiryDate {
            return (true, latestExpiryDate)
        } else {
            return (false, Date())
        }
    }


    public func isLifetimePurchase(productId: String) -> Bool {
        return productId.contains("lifetime")
    }

    //MARK: Check Refunds
    public func checkForRefunds(completion: @escaping (Bool) -> Void) {
        print("Checking for refunds")
        guard let receiptData = fetchReceipt() else {
            print("Receipt data is nil")
            completion(false)
            return
        }
        let receiptString = receiptData.base64EncodedString(options: [])

        let requestContents: [String: Any] = [
            "receipt-data": receiptString,
            "password": SubscriptionManager.sharedSecret
        ]

        guard let requestData = try? JSONSerialization.data(withJSONObject: requestContents, options: []) else {
            print("Failed to serialize request contents to JSON")
            completion(false)
            return
        }

        let storeURL = {
            return URL(string: SubscriptionManager.endPoint)!
//            #if DEBUG
//                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
//            #else
//                return URL(string: SubscriptionManager.endPoint)!
//                //return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
//            #endif
        }()

        var request = URLRequest(url: storeURL)
        request.httpMethod = "POST"
        request.httpBody = requestData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, let data = data else {
                print("Error validating receipt: \(error?.localizedDescription ?? "No data")")
                completion(false)
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String: Any] {
                    let hasRefunds = self.checkForRefundsInReceipt(receipt: jsonResponse)
                    DispatchQueue.main.async {
                        completion(hasRefunds)
                    }
                }
            } catch {
                print("Error parsing receipt validation response: \(error.localizedDescription)")
                completion(false)
            }
        }
        task.resume()
    }

    public func checkForRefundsInReceipt(receipt: [String: Any]) -> Bool {
        guard let receiptInfo = receipt["latest_receipt_info"] as? [[String: Any]] else {
            print("No latest_receipt_info found in receipt")
            return false
        }

        for receiptItem in receiptInfo {
            if let cancellationDateMs = receiptItem["cancellation_date_ms"] as? String,
               let _ = Double(cancellationDateMs) {
                return true
            }
        }

        return false
    }
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        print("in payment queue subs manager")
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                validateReceipt(transaction: transaction) { [self] isPro, subsExpiryDate in
                    
                    if let purchasedProduct = getProduct(from: transaction) {
                        
                        purchaseSuccessDelegate?.purchaseSuccess(transaction: transaction, subscribedProduct: purchasedProduct, expireDate: subsExpiryDate)

                    }
                    
                    SKPaymentQueue.default().finishTransaction(transaction)
                    SKPaymentQueue.default().remove(self)
                }
            case .restored:
                validateReceipt(transaction: transaction) { isPro, subsExpiryDate in

                }
                SKPaymentQueue.default().finishTransaction(transaction)
                SKPaymentQueue.default().remove(self)

            case .failed:
//                print("Failed to pay")
//                if let error = transaction.error as NSError?,
//                   error.code != SKError.paymentCancelled.rawValue {
//                    print("Transaction Failed: \(error.localizedDescription)")
//                }
                
                purchaseSuccessDelegate?.purchaseFailed(transaction: transaction, error: transaction.error)
                SKPaymentQueue.default().finishTransaction(transaction)
                
                SKPaymentQueue.default().remove(self)
            default:
                break
            }
        }
    }
    
    public  func getProduct(from transaction: SKPaymentTransaction) -> SKProduct? {
        guard let productIdentifier = transaction.payment.productIdentifier as String?,
              let product = availableProducts.first(where: { $0.productIdentifier == productIdentifier }) else {
            return nil
        }
        return product
    }
    
    // MARK: - Restore Purchases
    public func restorePurchases() {
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    public func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        print("Restored completed transactions finished.")
        validateReceipt { isPro, subsExpiryDate in
            self.restorePurchasesDelegate?.restorePurchasesCompleted(isPro: isPro, expiryDate: subsExpiryDate)
            SKPaymentQueue.default().remove(self)
        }
    }

    public func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("Failed to restore completed transactions: \(error.localizedDescription)")
        self.restorePurchasesDelegate?.restorePurchasesFailed(error: error)
        SKPaymentQueue.default().remove(self)
    }
    
}


public protocol PurchaseSuccessDelegate {
    func purchaseSuccess(transaction: SKPaymentTransaction, subscribedProduct: SKProduct, expireDate: Date)
    func purchaseFailed(transaction: SKPaymentTransaction, error: Error?)
}


public protocol RestorePurchasesDelegate {
    func restorePurchasesCompleted(isPro: Bool, expiryDate: Date)
    func restorePurchasesFailed(error: Error)
}

