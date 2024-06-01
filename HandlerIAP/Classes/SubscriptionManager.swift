//
//  SubscriptionManager.swift
//  Stella
//
//  Created by Ömer Karaca on 1.06.2024.
//

import Foundation
import StoreKit
import SVProgressHUD
import Adjust

public class SubscriptionManager: NSObject, SKPaymentTransactionObserver, SKProductsRequestDelegate {
    
    public static let shared = SubscriptionManager()
    public static var sharedSecret = ""
    
    // Products
    public static var products: [SKProduct]?
    //UI Update Delegate
    public var purchaseSuccessDelegate: PurchaseSuccessDelegate?
    
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
    
    func fetchAvailableProducts(productIdentifiers: [String], completion: @escaping (Result<[SKProduct], Error>) -> Void) {
        self.productRequestCompletion = completion
        let productIdentifiers = Set(productIdentifiers)
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest?.delegate = self
        productsRequest?.start()
    }

    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        availableProducts = response.products
        productRequestCompletion?(.success(response.products))
        clearProductRequest()
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        productRequestCompletion?(.failure(error))
        clearProductRequest()
    }

    private func clearProductRequest() {
        productsRequest = nil
        productRequestCompletion = nil
    }

    // MARK: - Purchase
    func purchase(product: SKProduct) {
        SVProgressHUD.show()
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(self)
        SKPaymentQueue.default().add(payment)
    }
    
    func checkSubscriptionStatus(completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
        print("innnnnn checkSubscriptionStatus")
        validateReceipt { isPro, subsExpiryDate in
            print("in validate comp")
            completion(isPro, subsExpiryDate)
        }
    }
    
    
    func fetchReceipt() -> Data? {
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

    
    func validateReceipt(transaction: SKPaymentTransaction? = nil, completion: @escaping(_ isPro: Bool, _ expiryDate: Date) -> Void) {
        print("in validateReceipt")
        guard let receiptData = fetchReceipt() else {
            print("Receipt data is nil")
            return
        }
        let receiptString = receiptData.base64EncodedString(options: [])

        // Debug: Log the receipt string length and content
        //print("Receipt string length: \(receiptString.count)")
        //print("Receipt string: \(receiptString)")

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
            #if DEBUG
                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
            #else
                return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
            #endif
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

    
    func checkSubscriptionStatus(receipt: [String: Any]) -> (Bool, Date) {
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


    func isLifetimePurchase(productId: String) -> Bool {
        return productId.contains("lifetime")
    }

    //MARK: Check Refunds
    func checkForRefunds(completion: @escaping (Bool) -> Void) {
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
            #if DEBUG
                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
            #else
                return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
            #endif
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

    func checkForRefundsInReceipt(receipt: [String: Any]) -> Bool {
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
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        print("in payment queue subs manager")
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased, .restored:
                validateReceipt(transaction: transaction) { isPro, subsExpiryDate in

                }
                SKPaymentQueue.default().finishTransaction(transaction)
                print("identifier isss: \(transaction.payment.productIdentifier)")
                
                if let purchasedProduct = getProduct(from: transaction) {
                    
                    purchaseSuccessDelegate?.purchaseSuccess(transaction: transaction, subscribedProduct: purchasedProduct)
                    
                    if isLifetimePurchase(productId: transaction.payment.productIdentifier) {
                        sendLifetimeReportToAdjust(price: Float(truncating: purchasedProduct.price), currency: purchasedProduct.priceLocale.currencyCode!, transaction: transaction, lifeTimeEventToken: "adjustLifetimePurchaseToken")
                    } else {
                        sendSubscriptionToAdjust(price: purchasedProduct.price, currency: purchasedProduct.priceLocale.currencyCode!, transaction: transaction)
                    }
                    
                    

                    if let introductoryPrice = purchasedProduct.introductoryPrice, introductoryPrice.paymentMode == .freeTrial {
                        //print("\(selectedProduct.localizedTitle) offers a free trial.")
                        reportEventToAdjust(eventCode: "pxtw9x")
                    } else {
                        //print("\(selectedProduct.localizedTitle) does not offer a free trial.")
                        reportEventToAdjust(eventCode: "1iyz2t")
                    }

                }
                
                if SVProgressHUD.isVisible() {
                    SVProgressHUD.dismiss()
                }
                SKPaymentQueue.default().remove(self)
            case .failed:
                print("Failed to pay")
                if let error = transaction.error as NSError?,
                   error.code != SKError.paymentCancelled.rawValue {
                    print("Transaction Failed: \(error.localizedDescription)")
                }
                SKPaymentQueue.default().finishTransaction(transaction)
                if SVProgressHUD.isVisible() {
                    SVProgressHUD.dismiss()
                }
                
                SKPaymentQueue.default().remove(self)
            default:
                break
            }
        }
    }
    
    private func getProduct(from transaction: SKPaymentTransaction) -> SKProduct? {
        guard let productIdentifier = transaction.payment.productIdentifier as String?,
              let product = availableProducts.first(where: { $0.productIdentifier == productIdentifier }) else {
            return nil
        }
        return product
    }
    
    // MARK: - Restore Purchases
    func restorePurchases() {
        SVProgressHUD.show()
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        print("Restored completed transactions finished.")
        validateReceipt { isPro, subsExpiryDate in
            
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        print("Failed to restore completed transactions: \(error.localizedDescription)")
    }
    
    //MARK: Adjust
    func reportEventToAdjust(eventCode: String) {
        let event = ADJEvent(eventToken: eventCode)
        Adjust.trackEvent(event)
    }
    
    func sendSubscriptionToAdjust(price: NSDecimalNumber, currency: String, transaction: SKPaymentTransaction) {
        print("sending SubscriptionToAdjust")
        guard let transactionId = transaction.transactionIdentifier, let receiptUrl = Bundle.main.appStoreReceiptURL, let receipt = try? Data(contentsOf: receiptUrl) else{
            print("Adjust subscription report error. Parameters are nil");return}
        
        guard let subscription = ADJSubscription(
            price: price,
            currency: currency,
            transactionId: transactionId,
            andReceipt: receipt) else {
                print("Adjust subscription report error. Subscription object is nil.")
                return
            }
        
        if let date = transaction.transactionDate, let region = Locale.current.regionCode{
            subscription.setTransactionDate(date)
            subscription.setSalesRegion(region)
        }

        Adjust.trackSubscription(subscription)
        print("Adjust subscription successfully tracked. ID: \(subscription.transactionId)")
    }
    
    //Lifetime
    func sendLifetimeReportToAdjust(price: Float, currency: String, transaction: SKPaymentTransaction, lifeTimeEventToken: String = "adjustLifetimePurchaseToken") {
            print("Reporting lifetime purchase to Adjust. Transaction Identifier: \(String(describing: transaction.transactionIdentifier)), price: \(price), currency: \(currency)")
            let event = ADJEvent(eventToken: lifeTimeEventToken)//TODO
            event?.setRevenue(Double(price), currency: currency)
            if let transactionId = transaction.transactionIdentifier{
                event?.setTransactionId(transactionId)
            }
            Adjust.trackEvent(event)
    }
    
}


public protocol PurchaseSuccessDelegate {
    func purchaseSuccess(transaction: SKPaymentTransaction, subscribedProduct: SKProduct)
}

extension SKProductSubscriptionPeriod {
    func asString() -> String {
        let unitCount = self.numberOfUnits
        let unitType = self.unit
        
        switch unitType {
        case .day:
            print("\(unitCount) day\(unitCount > 1 ? "s" : "")")
            return "daily"
        case .week:
            print("\(unitCount) week\(unitCount > 1 ? "s" : "")")
            return "weekly"
        case .month:
            print("\(unitCount) month\(unitCount > 1 ? "s" : "")")
            if unitCount == 3 {
                return "quarterly"
            } else {
                return "monthly"
            }
        case .year:
            print("\(unitCount) year\(unitCount > 1 ? "s" : "")")
            return "yearly"
        @unknown default:
            print("\(unitCount) unit(s)")
            return "lifetime"
        }
    }
}




